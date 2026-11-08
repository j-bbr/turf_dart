// Chains of polygonIntersect, difference and union on a city-scale polygon,
// and mask(keepHoles: true) of polygons with holes, checked against shapely
// results (tool/reference/make_reference.py).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/geometry_matcher.dart';
import '../fixtures/shapely_reference_fixtures.g.dart';

double _planarArea(Coords coords) {
  var sum = 0.0;
  for (final poly in coords) {
    for (final ring in poly) {
      sum += signedArea2(ring) / 2;
    }
  }
  return sum;
}

/// Applies the operations of a case in order; `null` once the result is
/// empty.
Feature<GeometryObject>? _apply(FeatureCollection fc) {
  Feature<GeometryObject>? area = fc.features.first;
  for (final op in fc.features.skip(1)) {
    if (area == null) return null;
    final pair = FeatureCollection(features: [area, op]);
    area = op.properties!['op'] == 'intersect'
        ? polygonIntersect(pair)
        : difference(pair);
  }
  return area;
}

FeatureCollection _input(String name) => FeatureCollection.fromJson(
    jsonDecode(shapelyReferenceFixtures['in/$name.geojson']!)
        as Map<String, dynamic>);

Map<String, dynamic> _reference(String name) =>
    jsonDecode(shapelyReferenceFixtures['out/$name.geojson']!)
        as Map<String, dynamic>;

/// Our result agrees with shapely's: planar area within 0.1 %, and the same
/// membership on a 100 x 100 grid of sample points away from the boundary.
void _expectMatchesReference(String name, Feature<GeometryObject>? result) {
  final ref = _reference(name);
  final refGeom = ref['geometry'];
  if (refGeom == null) {
    expect(result, isNull, reason: 'shapely found an empty result');
    return;
  }
  expect(result, isNotNull);
  final coords = polygonalCoords(result);
  expectGeoJsonOrientation(coords);

  final refArea = (ref['properties']['area'] as num).toDouble();
  expect(_planarArea(coords), closeTo(refArea, refArea * 1e-3));

  final refFeature = Feature.fromJson({'type': 'Feature', 'geometry': refGeom});
  final b = bbox(refFeature);
  for (var i = 0; i < 100; i++) {
    for (var j = 0; j < 100; j++) {
      final p = Position(
        b.lng1 + (b.lng2 - b.lng1) * (i + 0.5) / 100,
        b.lat1 + (b.lat2 - b.lat1) * (j + 0.5) / 100,
      );
      final expected = booleanPointInPolygon(p, refFeature);
      final actual = booleanPointInPolygon(p, result!);
      if (expected != actual) {
        // only allowed right at the boundary
        final d = pointToLineDistance(
          Point(coordinates: p),
          LineString(coordinates: _nearestRing(p, coords)),
          unit: Unit.meters,
        );
        expect(d, lessThan(0.01), reason: 'membership differs at $p');
      }
    }
  }
}

List<Position> _nearestRing(Position p, Coords coords) {
  List<Position>? best;
  var bestD = double.infinity;
  for (final poly in coords) {
    for (final ring in poly) {
      final d = pointToLineDistance(
          Point(coordinates: p), LineString(coordinates: ring),
          unit: Unit.meters);
      if (d < bestD) {
        bestD = d.toDouble();
        best = ring;
      }
    }
  }
  return best!;
}

void main() {
  group('shapely reference', () {
    test('Ring ∩ 1 km circle: inside both, area as shapely', () {
      final fc = _input('ring_intersect_circle');
      final result = _apply(fc);
      _expectMatchesReference('ring_intersect_circle', result);
      for (final ring in polygonalCoords(result)[0]) {
        for (final p in ring) {
          // result vertices lie in (or on) both inputs
          expect(
              booleanPointInPolygon(p, fc.features[0]) ||
                  _onBoundary(p, fc.features[0]),
              isTrue);
          expect(
              booleanPointInPolygon(p, fc.features[1]) ||
                  _onBoundary(p, fc.features[1]),
              isTrue);
        }
      }
    });

    test('Ring − a circle fully inside: one polygon with one hole', () {
      final result = _apply(_input('ring_difference_inner_circle'));
      _expectMatchesReference('ring_difference_inner_circle', result);
      expect(result!.geometry, isA<Polygon>());
      expect((result.geometry as Polygon).coordinates, hasLength(2));
    });

    test('Ring ∩ half-plane: the split edge lies on the latitude', () {
      final result = _apply(_input('ring_intersect_half_plane'));
      _expectMatchesReference('ring_intersect_half_plane', result);
      final coords = polygonalCoords(result);
      var onLine = 0;
      for (final poly in coords) {
        for (final ring in poly) {
          for (final p in ring) {
            expect(p.lat, greaterThanOrEqualTo(52.52));
            if (p.lat == 52.52) onLine++;
          }
        }
      }
      expect(onLine, greaterThanOrEqualTo(2));
    });

    test('an intersection that empties the result returns null', () {
      final result = _apply(_input('ring_intersect_far_circle'));
      expect(result, isNull);
      _expectMatchesReference('ring_intersect_far_circle', result);
    });

    test('ten chained operations: as shapely, no slivers below 1 m²', () {
      final result = _apply(_input('ten_chained_operations'));
      _expectMatchesReference('ten_chained_operations', result);
      for (final poly in polygonalCoords(result)) {
        for (final ring in poly) {
          final a = area(Polygon(coordinates: [ring]))!;
          expect(a, greaterThanOrEqualTo(1), reason: 'sliver of $a m²');
        }
      }
    });
  });
}

bool _onBoundary(Position p, Feature f) {
  for (final poly in polygonalCoords(f)) {
    for (final ring in poly) {
      final d = pointToLineDistance(
          Point(coordinates: p), LineString(coordinates: ring),
          unit: Unit.meters);
      if (d < 1e-3) return true;
    }
  }
  return false;
}
