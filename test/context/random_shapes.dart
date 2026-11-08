// Random polygon generators for property tests.
import 'dart:math';

import 'package:turf/turf.dart';

/// A closed ring around ([cx], [cy]) whose vertices lie at random angles and
/// radii between [rMin] and [rMax]: a star-shaped, simple polygon.
List<Position> randomStarRing(
  Random rnd,
  double cx,
  double cy,
  double rMin,
  double rMax, {
  int minVertices = 3,
  int maxVertices = 16,
  bool clockwise = false,
  double? snap,
}) {
  final n = minVertices + rnd.nextInt(maxVertices - minVertices + 1);
  final angles = [for (var i = 0; i < n; i++) rnd.nextDouble() * 2 * pi]
    ..sort();
  double s(double v) => snap == null ? v : (v / snap).roundToDouble() * snap;
  final ring = <Position>[];
  Position? last;
  for (final a in angles) {
    final r = rMin + rnd.nextDouble() * (rMax - rMin);
    final p = Position(s(cx + r * cos(a)), s(cy + r * sin(a)));
    if (last != null && last.lng == p.lng && last.lat == p.lat) continue;
    ring.add(p);
    last = p;
  }
  if (ring.length > 1 &&
      ring.first.lng == ring.last.lng &&
      ring.first.lat == ring.last.lat) {
    ring.removeLast();
  }
  final pts = clockwise ? ring.reversed.toList() : ring;
  return [...pts, pts.first];
}

/// The kinds of random input the property tests draw from.
enum ShapeKind {
  /// Star-shaped polygons, sometimes with a hole, in a unit-sized region.
  star,

  /// Star-shaped polygons with coordinates snapped to a 0.25 grid: shared
  /// vertices, collinear and overlapping edges.
  snapped,

  /// Thin, nearly collinear polygons.
  nearlyCollinear,

  /// Polygons a few metres across near Berlin (52.5°N).
  metreScale,
}

/// A random polygon of [kind] in the region of [kind]'s scale.
Feature<Polygon> randomPolygon(Random rnd, ShapeKind kind) {
  switch (kind) {
    case ShapeKind.star:
      final cx = rnd.nextDouble() * 2, cy = rnd.nextDouble() * 2;
      final outer = randomStarRing(rnd, cx, cy, 0.5, 1.5);
      // a hole must stay inside the outer ring: keep it within the
      // distance from the centre to the nearest outer edge
      final inner = _distanceToRing(Position(cx, cy), outer);
      if (rnd.nextBool() &&
          inner > 0.1 &&
          _strictlyContainsCentre(outer, cx, cy)) {
        final hole = randomStarRing(rnd, cx, cy, inner * 0.2, inner * 0.8,
            clockwise: true);
        return Feature(geometry: Polygon(coordinates: [outer, hole]));
      }
      return Feature(geometry: Polygon(coordinates: [outer]));
    case ShapeKind.snapped:
      final cx = (rnd.nextInt(8)) * 0.25, cy = (rnd.nextInt(8)) * 0.25;
      // snapping can make a ring degenerate or self-intersecting; retry
      while (true) {
        final ring = randomStarRing(rnd, cx, cy, 0.5, 1.5, snap: 0.25);
        if (ring.length >= 4 && isSimpleRing(ring)) {
          return Feature(geometry: Polygon(coordinates: [ring]));
        }
      }
    case ShapeKind.nearlyCollinear:
      // a sliver along a random direction, with vertices off the line by
      // a tiny amount
      final a = rnd.nextDouble() * pi;
      final dx = cos(a), dy = sin(a);
      final ox = rnd.nextDouble(), oy = rnd.nextDouble();
      final n = 3 + rnd.nextInt(5);
      final top = <Position>[];
      final bottom = <Position>[];
      for (var i = 0; i <= n; i++) {
        final t = i / n * 2;
        final off = 1e-9 + rnd.nextDouble() * 1e-6;
        top.add(Position(ox + t * dx - off * dy, oy + t * dy + off * dx));
        bottom.add(Position(ox + t * dx + off * dy, oy + t * dy - off * dx));
      }
      final ring = [...bottom, ...top.reversed.skip(1).take(n - 1)];
      return Feature(
          geometry: Polygon(coordinates: [
        [...ring, ring.first]
      ]));
    case ShapeKind.metreScale:
      // ~1e-5 degrees is about a metre at Berlin's latitude
      final cx = 13.4 + rnd.nextDouble() * 4e-5;
      final cy = 52.5 + rnd.nextDouble() * 4e-5;
      return Feature(
          geometry:
              Polygon(coordinates: [randomStarRing(rnd, cx, cy, 1e-5, 4e-5)]));
  }
}

double _distanceToRing(Position p, List<Position> ring) {
  var best = double.infinity;
  for (var i = 0; i + 1 < ring.length; i++) {
    final a = ring[i], b = ring[i + 1];
    final dx = (b.lng - a.lng).toDouble(), dy = (b.lat - a.lat).toDouble();
    final len2 = dx * dx + dy * dy;
    var t =
        len2 == 0 ? 0.0 : ((p.lng - a.lng) * dx + (p.lat - a.lat) * dy) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final x = a.lng + t * dx - p.lng, y = a.lat + t * dy - p.lat;
    best = min(best, sqrt(x * x + y * y));
  }
  return best;
}

int _orientation(Position a, Position b, Position c) {
  final v =
      (b.lng - a.lng) * (c.lat - a.lat) - (b.lat - a.lat) * (c.lng - a.lng);
  return v > 0 ? 1 : (v < 0 ? -1 : 0);
}

bool _onSegment(Position a, Position b, Position p) =>
    min(a.lng, b.lng) <= p.lng &&
    p.lng <= max(a.lng, b.lng) &&
    min(a.lat, b.lat) <= p.lat &&
    p.lat <= max(a.lat, b.lat);

bool _segmentsTouch(Position a, Position b, Position c, Position d) {
  final o1 = _orientation(a, b, c), o2 = _orientation(a, b, d);
  final o3 = _orientation(c, d, a), o4 = _orientation(c, d, b);
  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && _onSegment(a, b, c)) return true;
  if (o2 == 0 && _onSegment(a, b, d)) return true;
  if (o3 == 0 && _onSegment(c, d, a)) return true;
  if (o4 == 0 && _onSegment(c, d, b)) return true;
  return false;
}

/// Whether the closed [ring] is simple: non-adjacent edges don't touch and
/// adjacent edges only share their common vertex.
bool isSimpleRing(List<Position> ring) {
  final n = ring.length - 1;
  if (n < 3) return false;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final adjacent = j == i + 1 || (i == 0 && j == n - 1);
      final a = ring[i], b = ring[i + 1], c = ring[j], d = ring[j + 1];
      if (adjacent) {
        // adjacent edges must not fold back onto each other
        final shared = j == i + 1 ? b : a;
        final p = j == i + 1 ? a : b;
        final q = j == i + 1 ? d : c;
        if (_orientation(p, shared, q) == 0 &&
            ((p.lng - shared.lng) * (q.lng - shared.lng) +
                    (p.lat - shared.lat) * (q.lat - shared.lat)) >
                0) {
          return false;
        }
        continue;
      }
      if (_segmentsTouch(a, b, c, d)) return false;
    }
  }
  return true;
}

/// For a star-shaped ring around (cx, cy) with counter-clockwise sorted
/// vertices: whether the centre lies strictly inside (every angular gap is
/// below half a turn).
bool _strictlyContainsCentre(List<Position> ring, double cx, double cy) {
  for (var i = 0; i + 1 < ring.length; i++) {
    final ax = ring[i].lng - cx, ay = ring[i].lat - cy;
    final bx = ring[i + 1].lng - cx, by = ring[i + 1].lat - cy;
    if (ax * by - ay * bx <= 0) return false;
  }
  return true;
}
