import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libcompress/libcompress.dart';
import 'package:fladder/sushi/sushi_assignment_pb.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';

void main() {
  test('SushiAssignmentPb round-trip fields 1-5', () {
    final token = utf8.encode('tok-bytes');
    final encoded = SushiAssignmentPb.encode(
      apiBotUsername: 'exampleStreamer31Bot',
      pool: const ['exampleStreamer31Bot', 'exampleStreamer32Bot'],
      providerId: 7,
      bindingToken: token,
      epoch: 3,
    );
    final pb = SushiAssignmentPb.decode(encoded);
    expect(pb.apiBotUsername, 'exampleStreamer31Bot');
    expect(pb.pool, ['exampleStreamer31Bot', 'exampleStreamer32Bot']);
    expect(pb.providerId, 7);
    expect(pb.bindingToken, token);
    expect(pb.epoch, 3);
    expect(pb.deliveryBots, isEmpty);
  });

  test('SushiAssignmentPb round-trips field 6 delivery_bots', () {
    final encoded = SushiAssignmentPb.encode(
      apiBotUsername: 'exampleStreamer31Bot',
      deliveryBots: const ['exampleStreamer36Bot', 'exampleStreamer35Bot', 'exampleStreamer33Bot'],
    );
    final pb = SushiAssignmentPb.decode(encoded);
    expect(pb.deliveryBots, ['exampleStreamer36Bot', 'exampleStreamer35Bot', 'exampleStreamer33Bot']);
  });

  test('sushiParseInitbotReply decodes Assignment protobuf', () {
    final payload = SushiAssignmentPb.encode(
      apiBotUsername: 'apiBotOne',
      pool: const ['apiBotOne', 'apiBotTwo'],
      providerId: 42,
      bindingToken: utf8.encode('bind-secret'),
      epoch: 9,
    );
    final envelope = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(1))
      ..add(_uvarint(15))
      ..add(_uvarint(0))
      ..add(payload);
    final reply = '!${base64Url.encode(envelope.toBytes()).replaceAll('=', '')}';

    final a = sushiParseInitbotReply(reply);
    expect(a.msgType, SushiAssignment.msgTypeAssignment);
    expect(a.pending, isFalse);
    expect(a.isError, isFalse);
    expect(a.apiBotUsername, 'apiBotOne');
    expect(a.pool, ['apiBotOne', 'apiBotTwo']);
    expect(a.providerId, 42);
    expect(a.epoch, 9);
    expect(a.bindingToken, isNotEmpty);
    expect(utf8.decode(base64Url.decode(_pad(a.bindingToken))), 'bind-secret');
    expect(a.payloadBase64, isNotEmpty);
  });

  test('sushiParseInitbotReply recognises ERR_CODE_NOT_PUBLIC', () {
    final bytes = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(2))
      ..add(_uvarint(14))
      ..add(_uvarint(0))
      ..add(const [0x08, SushiAssignment.errCodeNotPublic]);
    final reply = '!${base64Url.encode(bytes.toBytes()).replaceAll('=', '')}';

    final a = sushiParseInitbotReply(reply);
    expect(a.isError, isTrue);
    expect(a.notPublic, isTrue);
    expect(() => sushiEnsureAssignmentReady(a), throwsA(isA<StateError>()
        .having((e) => e.message, 'message', contains('not open for public use'))));
  });

  test('ERR_CODE_AUTH is not mistaken for a public-access refusal', () {
    final bytes = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(2))
      ..add(_uvarint(14))
      ..add(_uvarint(0))
      ..add(const [0x08, 3]);
    final reply = '!${base64Url.encode(bytes.toBytes()).replaceAll('=', '')}';

    expect(sushiParseInitbotReply(reply).notPublic, isFalse);
  });

  test('sushiParseInitbotReply reads ERR type 14 as pending', () {
    final bytes = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(2))
      ..add(_uvarint(14))
      ..add(_uvarint(0));
    final reply = '!${base64Url.encode(bytes.toBytes()).replaceAll('=', '')}';
    final a = sushiParseInitbotReply(reply);
    expect(a.msgType, SushiAssignment.msgTypeErr);
    expect(a.isError, isTrue);
    expect(a.pending, isTrue);
    expect(a.apiBotUsername, isEmpty);
  });

  test('sushiParseInitbotReply decompresses FlagCompressed Assignment', () {
    final bigPool = List.generate(40, (i) => 'pool-bot-$i-${'x' * 8}');
    final fatPlain = SushiAssignmentPb.encode(
      apiBotUsername: 'compressedBot',
      pool: bigPool,
      providerId: 1,
      bindingToken: utf8.encode('tok'),
      epoch: 2,
    );
    final compressed = ZstdCodec(level: 3).compress(fatPlain);
    expect(compressed.length, lessThan(fatPlain.length));

    final envelope = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(1))
      ..add(_uvarint(15))
      ..add(_uvarint(SushiAssignment.flagCompressed))
      ..add(compressed);
    final reply = '!${base64Url.encode(envelope.toBytes()).replaceAll('=', '')}';

    final a = sushiParseInitbotReply(reply);
    expect(a.pending, isFalse);
    expect(a.apiBotUsername, 'compressedBot');
    expect(a.pool.length, 40);
    expect(a.providerId, 1);
    expect(a.epoch, 2);
  });

  test('sushiEnsureAssignmentReady accepts a live pool', () {
    sushiEnsureAssignmentReady(
      const SushiAssignment(
        apiBotUsername: 'exampleStreamer31Bot',
        pool: ['exampleStreamer31Bot'],
        providerId: 1,
        bindingToken: 'tok',
        epoch: 1,
      ),
    );
  });

  test('sushiEnsureAssignmentReady rejects pending', () {
    expect(
      () => sushiEnsureAssignmentReady(SushiAssignment.stubPending(reason: 'no pool')),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('Finish setup in Telegram'),
      )),
    );
  });

  test('sushiEnsureAssignmentReady distinguishes timeout', () {
    expect(
      () => sushiEnsureAssignmentReady(SushiAssignment.stubPending(reason: 'timeout')),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('timed out talking to Telegram'),
      )),
    );
  });

  test('sushiCoalesceAssignment keeps a live assignment over ERR', () {
    const live = SushiAssignment(
      apiBotUsername: 'exampleStreamer31Bot',
      pool: ['exampleStreamer31Bot'],
      providerId: 1,
      bindingToken: 'tok',
      epoch: 4,
    );
    final err = SushiAssignment.stubPending(reason: 'type 14');
    final kept = sushiCoalesceAssignment(err, live);
    expect(kept.usable, isTrue);
    expect(kept.epoch, 4);
    expect(kept.apiBotUsername, 'exampleStreamer31Bot');
  });

  test('sushiCoalesceAssignment keeps first-install pending', () {
    final err = SushiAssignment.stubPending(reason: 'type 14');
    expect(sushiCoalesceAssignment(err, null).pending, isTrue);
  });
}

List<int> _uvarint(int n) {
  final out = <int>[];
  var x = n;
  while (x >= 0x80) {
    out.add((x & 0x7f) | 0x80);
    x >>= 7;
  }
  out.add(x);
  return out;
}

String _pad(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s.padRight(s.length + (4 - mod), '=');
}
