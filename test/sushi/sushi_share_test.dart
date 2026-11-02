import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/sushi_share.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/deep_link_helper.dart';

void main() {
  group('sushiBuildShareUrl', () {
    test('catalog id only', () {
      expect(
        sushiBuildShareUrl('abc-123'),
        'https://sushi.app/share/abc-123',
      );
    });

    test('includes mediaSourceId query param', () {
      expect(
        sushiBuildShareUrl('abc-123', mediaSourceId: 'ms_variant_1'),
        'https://sushi.app/share/abc-123?mediaSourceId=ms_variant_1',
      );
    });
  });

  group('sushiCatalogIdFromShareUri', () {
    test('parses https share path', () {
      final uri = Uri.parse('https://sushi.app/share/catalog-id-1');
      expect(sushiCatalogIdFromShareUri(uri), 'catalog-id-1');
    });

    test('parses custom scheme share path', () {
      final uri = Uri.parse('sushi:///share/catalog-id-2');
      expect(sushiCatalogIdFromShareUri(uri), 'catalog-id-2');
    });
  });

  group('sushiMediaSourceIdFromShareUri', () {
    test('reads mediaSourceId from query', () {
      final uri = Uri.parse(
        'https://sushi.app/share/catalog-id-1?mediaSourceId=ms_1080p',
      );
      expect(sushiMediaSourceIdFromShareUri(uri), 'ms_1080p');
    });

    test('reads mediaSourceId from custom scheme query', () {
      final uri = Uri.parse(
        'sushi:///share/catalog-id-2?mediaSourceId=ms_720p',
      );
      expect(sushiMediaSourceIdFromShareUri(uri), 'ms_720p');
    });
  });

  group('payloadToRoute share links', () {
    test('https production share url', () {
      final route = payloadToRoute(Uri.parse(
        'https://sushi.app/share/f55d713c-2392-4de4-87c3-d0595587b717',
      ));
      expect(route, isA<DetailsRoute>());
      expect((route as DetailsRoute).queryParams.getString('id', ''), 'f55d713c-2392-4de4-87c3-d0595587b717');
    });

    test('custom scheme share url', () {
      final route = payloadToRoute(Uri.parse(
        'sushi:///share/f55d713c-2392-4de4-87c3-d0595587b717',
      ));
      expect(route, isA<DetailsRoute>());
    });

    test('path-only share url', () {
      final route = payloadToRoute(Uri.parse(
        '/share/f55d713c-2392-4de4-87c3-d0595587b717',
      ));
      expect(route, isA<DetailsRoute>());
    });
  });
}
