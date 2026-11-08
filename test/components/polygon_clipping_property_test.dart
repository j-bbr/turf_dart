// Property tests for polygonIntersect, union and difference: on a 50 x 50
// grid of sample points, a point is inside the result exactly when the
// set operation of its membership in the inputs says so.
//
// TURF_FUZZ_RUNS sets the number of random pairs per shape kind on the VM.
import 'dart:math';

import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/fuzz_runs.dart';
import '../context/geometry_matcher.dart';
import '../context/random_shapes.dart';

const _grid = 50;

double _segmentDistance(Position p, Position a, Position b) {
  final dx = b.lng - a.lng, dy = b.lat - a.lat;
  final len2 = dx * dx + dy * dy;
  var t =
      len2 == 0 ? 0.0 : ((p.lng - a.lng) * dx + (p.lat - a.lat) * dy) / len2;
  t = t.clamp(0.0, 1.0).toDouble();
  final x = a.lng + t * dx - p.lng, y = a.lat + t * dy - p.lat;
  return sqrt(x * x + y * y);
}

bool _nearBoundary(Position p, Coords coords, double tolerance) {
  for (final poly in coords) {
    for (final ring in poly) {
      for (var i = 0; i + 1 < ring.length; i++) {
        if (_segmentDistance(p, ring[i], ring[i + 1]) <= tolerance) {
          return true;
        }
      }
    }
  }
  return false;
}

bool _inside(Position p, Feature<GeometryObject>? f) =>
    f != null && booleanPointInPolygon(p, f);

void _checkPair(Feature<Polygon> a, Feature<Polygon> b, String label) {
  final fc = FeatureCollection(features: [a, b]);
  final inter = polygonIntersect(fc);
  final uni = union(fc);
  final diff = difference(fc);
  for (final r in [inter, uni, diff]) {
    if (r != null) expectGeoJsonOrientation(polygonalCoords(r));
  }

  final ca = polygonalCoords(a), cb = polygonalCoords(b);
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final c in [...ca, ...cb]) {
    for (final p in c[0]) {
      minX = min(minX, p.lng.toDouble());
      minY = min(minY, p.lat.toDouble());
      maxX = max(maxX, p.lng.toDouble());
      maxY = max(maxY, p.lat.toDouble());
    }
  }
  final size = max(maxX - minX, maxY - minY);
  final tolerance = size * 1e-6;

  for (var i = 0; i < _grid; i++) {
    for (var j = 0; j < _grid; j++) {
      final p = Position(
        minX + (maxX - minX) * (i + 0.5) / _grid,
        minY + (maxY - minY) * (j + 0.5) / _grid,
      );
      if (_nearBoundary(p, ca, tolerance) || _nearBoundary(p, cb, tolerance)) {
        continue;
      }
      final inA = _inside(p, a), inB = _inside(p, b);
      expect(_inside(p, inter), inA && inB,
          reason: '$label: intersect at $p (inA $inA, inB $inB)');
      expect(_inside(p, uni), inA || inB,
          reason: '$label: union at $p (inA $inA, inB $inB)');
      expect(_inside(p, diff), inA && !inB,
          reason: '$label: difference at $p (inA $inA, inB $inB)');
    }
  }
}

void main() {
  final runs = fuzzRuns();
  group('polygon clipping properties', () {
    for (final kind in ShapeKind.values) {
      test('${kind.name} ($runs pairs)', () {
        for (var run = 0; run < runs; run++) {
          final seed = kind.index * 1000003 + run;
          final rnd = Random(seed);
          final a = randomPolygon(rnd, kind);
          final b = randomPolygon(rnd, kind);
          _checkPair(a, b, '${kind.name} seed $seed');
        }
      }, timeout: const Timeout.factor(20));
    }
  });
}
