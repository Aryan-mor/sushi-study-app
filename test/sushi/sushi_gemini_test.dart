import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fladder/sushi/subtitles/sushi_gemini.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';

http.Response _geminiJson(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('sushiLooksLikeGeminiKey', () {
    expect(sushiLooksLikeGeminiKey('AIzaSyDummyKeyForTestsOnly1234567890AB'), isTrue);
    expect(sushiLooksLikeGeminiKey('AQ.Ab8RN6DummyKeyForTestsOnly1234567890ABCD'), isTrue);
    expect(sushiLooksLikeGeminiKey('123456789:AAThisLooksLikeATelegramTok'), isFalse);
    expect(sushiLooksLikeGeminiKey('AQ.short'), isFalse);
    expect(sushiLooksLikeGeminiKey('AIza short'), isFalse);
    expect(sushiLooksLikeGeminiKey('hello'), isFalse);
  });

  test('sushiGeminiExtractText reads candidates.parts', () {
    final body = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': '1. سلام'},
              {'text': '\n2. خداحافظ'},
            ],
          },
        },
      ],
    });
    expect(sushiGeminiExtractText(body), '1. سلام\n2. خداحافظ');
    expect(sushiGeminiExtractText('{}'), isEmpty);
    expect(sushiGeminiExtractText('{"candidates":[]}'), isEmpty);
  });

  test('generateContent posts to Gemini and returns model text', () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'generativelanguage.googleapis.com');
      expect(req.url.path, contains('gemini-3.1-flash-lite'));
      expect(req.url.queryParameters['key'], 'AIzaSyDummyKeyForTestsOnly1234567890AB');
      return _geminiJson('1. سلام');
    });
    final gemini = SushiGeminiClient(client: client);
    final text = await gemini.generateContent(
      apiKey: 'AIzaSyDummyKeyForTestsOnly1234567890AB',
      prompt: 'hi',
    );
    expect(text, '1. سلام');
  });

  test('generateContent falls back when first model 404s', () async {
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add(req.url.path);
      if (req.url.path.contains('gemini-3.5-flash-lite')) {
        return _geminiJson('1. سلام');
      }
      return http.Response(
        '{"error":{"code":404,"message":"This model models/gemini-3.1-flash-lite is no longer available to new users. Please update your code to use models/gemini-3.5-flash-lite"}}',
        404,
      );
    });
    final gemini = SushiGeminiClient(client: client);
    final text = await gemini.generateContent(
      apiKey: 'AIzaSyDummyKeyForTestsOnly1234567890AB',
      prompt: 'hi',
    );
    expect(text, '1. سلام');
    expect(seen.first, contains('gemini-3.1-flash-lite:'));
    expect(seen, contains(contains('gemini-3.5-flash-lite:')));
  });

  test('sushiGeminiSuggestedModel reads Google replacement id', () {
    expect(
      sushiGeminiSuggestedModel(
        'Please update your code to use models/gemini-3.5-flash',
      ),
      'gemini-3.5-flash',
    );
    expect(sushiGeminiSuggestedModel('not found'), isNull);
  });

  test('translateCuesToPersian rebuilds SRT from numbered reply', () async {
    final client = MockClient((req) async {
      return _geminiJson('1. سلام');
    });
    final gemini = SushiGeminiClient(client: client);
    final srt = await gemini.translateCuesToPersian(
      [
        const SushiSrtCue(
          index: 1,
          timing: '00:00:01,000 --> 00:00:02,000',
          text: 'Hello',
        ),
      ],
      'AIzaSyDummyKeyForTestsOnly1234567890AB',
    );
    expect(srt, contains('00:00:01,000 --> 00:00:02,000'));
    expect(srt, contains('سلام'));
  });

  test('sushiGeminiSubtitlePrompt uses Persian path for fa, general for others', () {
    final fa = sushiGeminiSubtitlePrompt('1. Hi', 'fa');
    expect(fa, contains('spoken Persian'));
    expect(fa, isNot(contains('into natural, idiomatic Spanish')));

    final es = sushiGeminiSubtitlePrompt('1. Hi', 'es');
    expect(es, contains('Spanish'));
    expect(es, contains('natural, idiomatic Spanish'));
    expect(es, isNot(contains('spoken Persian')));
  });
}
