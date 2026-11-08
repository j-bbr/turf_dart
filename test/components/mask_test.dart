import 'dart:convert';

import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/geometry_matcher.dart';
import '../fixtures/mask_fixtures.g.dart';

Feature<Polygon> _square(num x, num y, num size) => Feature(
      geometry: Polygon(coordinates: [
        [
          Position(x, y),
          Position(x + size, y),
          Position(x + size, y + size),
          Position(x, y + size),
          Position(x, y),
        ]
      ]),
    );

/// A square with a square hole.
Feature<Polygon> _donut() => Feature(
      geometry: Polygon(coordinates: [
        _square(2, 2, 6).geometry!.coordinates[0],
        [
          Position(4, 4),
          Position(4, 6),
          Position(6, 6),
          Position(6, 4),
          Position(4, 4),
        ],
      ]),
    );

/// Skipped in turf.js 7.4.0's own test too: their out files do not match
/// turf.js' current output.
const _turfSkip = ['multi-polygon.geojson', 'overlapping.geojson'];

void main() {
  group('mask', () {
    group('turf.js fixtures', () {
      final names = maskFixtures.keys
          .where((k) => k.startsWith('in/'))
          .map((k) => k.substring(3))
          .toList()
        ..sort();
      for (final name in names) {
        test(name, () {
          final input = FeatureCollection.fromJson(
              jsonDecode(maskFixtures['in/$name']!) as Map<String, dynamic>);
          final expected = Feature.fromJson(
              jsonDecode(maskFixtures['out/$name']!) as Map<String, dynamic>);
          final result = mask(input.features[0],
              mask: input.features.length > 1 ? input.features[1] : null);
          expect(result.geometry, isA<Polygon>());
          // turf.js' own ring order and orientation, exactly
          final actualRings = (result.geometry as Polygon).coordinates;
          final expectedRings = (expected.geometry as Polygon).coordinates;
          expect(actualRings, hasLength(expectedRings.length));
          for (var i = 0; i < actualRings.length; i++) {
            expect(
                [
                  [actualRings[i]]
                ],
                matchesCoords([
                  [expectedRings[i]]
                ], checkOrientation: true));
          }
        },
            skip: _turfSkip.contains(name)
                ? 'skipped in turf.js 7.4.0 as well'
                : false);
      }
    });

    test('defaults to the world', () {
      final result = mask(_square(0, 0, 1));
      final rings = (result.geometry as Polygon).coordinates;
      expect(rings, hasLength(2));
      expect(rings[0].first, Position(180, 90));
    });

    test('accepts a FeatureCollection and unions it', () {
      final result = mask(
          FeatureCollection(features: [_square(0, 0, 2), _square(1, 1, 2)]),
          mask: _square(-10, -10, 20));
      expect((result.geometry as Polygon).coordinates, hasLength(2));
    });

    test('accepts a bare geometry and a Polygon mask', () {
      final result = mask(_square(0, 0, 2).geometry!,
          mask: _square(-10, -10, 20).geometry);
      expect((result.geometry as Polygon).coordinates, hasLength(2));
    });

    test('does not mutate the mask', () {
      final frame = _square(0, 0, 10);
      final before = jsonEncode(frame.toJson());
      mask(_square(2, 2, 2), mask: frame);
      mask(_square(2, 2, 2), mask: frame, keepHoles: true);
      expect(jsonEncode(frame.toJson()), before);
    });

    group('keepHoles', () {
      final frame = _square(0, 0, 10);

      test('false: holes of the input are not shaded (turf.js)', () {
        final shading = mask(_donut(), mask: frame);
        expect(booleanPointInPolygon(Position(5, 5), shading), isFalse);
        expect(booleanPointInPolygon(Position(3, 3), shading), isFalse);
        expect(booleanPointInPolygon(Position(1, 1), shading), isTrue);
      });

      test('true: holes of the input are shaded as islands', () {
        final shading = mask(_donut(), mask: frame, keepHoles: true);
        expect(shading.geometry, isA<MultiPolygon>());
        expectGeoJsonOrientation(polygonalCoords(shading));
        expect(booleanPointInPolygon(Position(5, 5), shading), isTrue);
        expect(booleanPointInPolygon(Position(3, 3), shading), isFalse);
        expect(booleanPointInPolygon(Position(1, 1), shading), isTrue);
      });

      test('true: without holes the result is a Polygon', () {
        final shading = mask(_square(2, 2, 2), mask: frame, keepHoles: true);
        expect(shading.geometry, isA<Polygon>());
        expect((shading.geometry as Polygon).coordinates, hasLength(2));
      });

      test('true: an input covering the mask gives an empty MultiPolygon', () {
        final shading = mask(_square(-1, -1, 12), mask: frame, keepHoles: true);
        expect(shading.geometry, isA<MultiPolygon>());
        expect((shading.geometry as MultiPolygon).coordinates, isEmpty);
      });
    });

    test('throws for a non-polygon mask', () {
      expect(
          () => mask(_square(0, 0, 1),
              mask: Feature(geometry: Point(coordinates: Position(0, 0)))),
          throwsArgumentError);
    });
  });
}
