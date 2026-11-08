import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/clip_fixture_runner.dart';
import '../context/geometry_matcher.dart';
import '../fixtures/union_fixtures.g.dart';

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

void main() {
  group('union', () {
    group('turf.js fixtures', () {
      runClipFixtures(unionFixtures, (fc) => union(fc));
    });

    test('squares sharing an edge merge into one polygon', () {
      final result = union(
          FeatureCollection(features: [_square(0, 0, 1), _square(1, 0, 1)]))!;
      expect(result.geometry, isA<Polygon>());
      expect(
          polygonalCoords(result),
          matchesCoords([
            [
              [
                Position(0, 0),
                Position(2, 0),
                Position(2, 1),
                Position(0, 1),
                Position(0, 0),
              ]
            ]
          ], checkOrientation: true));
    });

    test('disjoint squares give a MultiPolygon', () {
      final result = union(
          FeatureCollection(features: [_square(0, 0, 1), _square(5, 5, 1)]))!;
      expect(result.geometry, isA<MultiPolygon>());
      expect(polygonalCoords(result), hasLength(2));
    });

    test('properties are passed through', () {
      final result = union(
          FeatureCollection(features: [_square(0, 0, 1), _square(1, 0, 1)]),
          properties: {'a': 1})!;
      expect(result.properties, {'a': 1});
    });

    test('throws for fewer than two geometries', () {
      expect(() => union(FeatureCollection(features: [_square(0, 0, 1)])),
          throwsArgumentError);
    });
  });
}
