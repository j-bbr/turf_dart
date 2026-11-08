import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/clip_fixture_runner.dart';
import '../context/geometry_matcher.dart';
import '../fixtures/difference_fixtures.g.dart';

Feature<Polygon> _square(num x, num y, num size,
        [Map<String, dynamic>? properties]) =>
    Feature(
      properties: properties,
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
  group('difference', () {
    group('turf.js fixtures', () {
      runClipFixtures(differenceFixtures, (fc) => difference(fc));
    });

    // turf.js: "turf-difference - support specific polygons"
    test('support specific polygons', () {
      final poly1 = Feature(
          geometry: Polygon(coordinates: [
        [
          Position(121, -31),
          Position(144, -31),
          Position(144, -15),
          Position(121, -15),
          Position(121, -31),
        ]
      ]));
      final poly2 = Feature(
          geometry: Polygon(coordinates: [
        [
          Position(126, -28),
          Position(140, -28),
          Position(140, -20),
          Position(126, -20),
          Position(126, -28),
        ]
      ]));
      final result = difference(FeatureCollection(features: [poly1, poly2]));
      expect(result, isNotNull);
      expect(result!.geometry, isA<Polygon>());
      expect((result.geometry as Polygon).coordinates, hasLength(2));
    });

    test('a hole fully inside creates a polygon with a hole', () {
      final result = difference(
          FeatureCollection(features: [_square(0, 0, 4), _square(1, 1, 1)]))!;
      final coords = polygonalCoords(result);
      expect(coords, hasLength(1));
      expect(coords[0], hasLength(2));
      expectGeoJsonOrientation(coords);
    });

    test('completely covered returns null', () {
      expect(
          difference(FeatureCollection(
              features: [_square(1, 1, 1), _square(0, 0, 4)])),
          isNull);
    });

    test('keeps the properties of the first feature', () {
      final result = difference(FeatureCollection(features: [
        _square(0, 0, 4, {'name': 'first'}),
        _square(1, 1, 1, {'name': 'second'}),
      ]))!;
      expect(result.properties, {'name': 'first'});
    });

    test('properties argument overrides', () {
      final result = difference(
          FeatureCollection(features: [
            _square(0, 0, 4, {'name': 'first'}),
            _square(1, 1, 1),
          ]),
          properties: {'name': 'given'})!;
      expect(result.properties, {'name': 'given'});
    });

    test('subtracting several features', () {
      final result = difference(FeatureCollection(features: [
        _square(0, 0, 4),
        _square(-1, -1, 2),
        _square(3, 3, 2),
      ]))!;
      expect(polygonalCoords(result), hasLength(1));
    });
  });
}
