import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/clip_fixture_runner.dart';
import '../context/geometry_matcher.dart';
import '../fixtures/intersect_fixtures.g.dart';

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
  group('polygonIntersect', () {
    group('turf.js fixtures', () {
      runClipFixtures(intersectFixtures, (fc) => polygonIntersect(fc));
    });

    test('overlapping squares', () {
      final result = polygonIntersect(
          FeatureCollection(features: [_square(0, 0, 2), _square(1, 1, 2)]))!;
      expect(result.geometry, isA<Polygon>());
      expect(
          polygonalCoords(result),
          matchesCoords([
            [
              [
                Position(1, 1),
                Position(2, 1),
                Position(2, 2),
                Position(1, 2),
                Position(1, 1),
              ]
            ]
          ], checkOrientation: true));
    });

    test('no overlap returns null', () {
      expect(
          polygonIntersect(FeatureCollection(
              features: [_square(0, 0, 1), _square(5, 5, 1)])),
          isNull);
    });

    test('touching squares return null', () {
      expect(
          polygonIntersect(FeatureCollection(
              features: [_square(0, 0, 1), _square(1, 0, 1)])),
          isNull);
    });

    test('properties are passed through', () {
      final result = polygonIntersect(
          FeatureCollection(features: [_square(0, 0, 2), _square(1, 1, 2)]),
          properties: {'foo': 'bar'})!;
      expect(result.properties, {'foo': 'bar'});
    });

    test('more than two features', () {
      final result = polygonIntersect(FeatureCollection(features: [
        _square(0, 0, 3),
        _square(1, 1, 3),
        _square(2, 2, 3),
      ]))!;
      expect(
          polygonalCoords(result),
          matchesCoords([
            [
              [
                Position(2, 2),
                Position(3, 2),
                Position(3, 3),
                Position(2, 3),
                Position(2, 2),
              ]
            ]
          ]));
    });

    test('throws for fewer than two geometries', () {
      expect(
          () =>
              polygonIntersect(FeatureCollection(features: [_square(0, 0, 1)])),
          throwsArgumentError);
    });

    test('throws for non-polygonal geometries', () {
      final line = Feature(
          geometry: LineString(coordinates: [Position(0, 0), Position(1, 1)]));
      expect(
          () => polygonIntersect(
              FeatureCollection(features: [_square(0, 0, 1), line])),
          throwsArgumentError);
    });
  });
}
