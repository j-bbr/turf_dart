// Tolerant comparison of polygonal geometries for the clipping tests.
//
// Rings are compared without their closing position, with rotation
// normalised (they start at their lexicographically smallest position) and,
// unless `checkOrientation` is set, with orientation normalised. Polygons of
// a MultiPolygon and the holes of a polygon are matched regardless of their
// order. Coordinates match within `tolerance`.
import 'package:test/test.dart';
import 'package:turf/turf.dart';

typedef Coords = List<List<List<Position>>>;

/// MultiPolygon coordinates of a Polygon, MultiPolygon or Feature of them;
/// an empty list for `null`.
Coords polygonalCoords(GeoJSONObject? geo) {
  if (geo == null) return [];
  if (geo is Feature) return polygonalCoords(geo.geometry);
  if (geo is Polygon) return [geo.coordinates];
  if (geo is MultiPolygon) return geo.coordinates;
  throw ArgumentError('Not polygonal: ${geo.type}');
}

/// Parses raw JSON coordinates of a Polygon or MultiPolygon.
Coords coordsFromJson(List<dynamic> json) {
  List<Position> ring(List<dynamic> r) => [
        for (final p in r)
          Position.of([for (final n in (p as List)) (n as num)])
      ];
  if (json.isEmpty) return [];
  // Polygon: [[[x, y], ...]]
  if (json[0] is List && (json[0] as List).isNotEmpty) {
    final first = (json[0] as List)[0];
    if (first is List && first.isNotEmpty && first[0] is num) {
      return [
        [for (final r in json) ring(r as List)]
      ];
    }
  }
  return [
    for (final poly in json) [for (final r in (poly as List)) ring(r as List)]
  ];
}

/// Twice the signed area of [ring] (positive = counter-clockwise).
double signedArea2(List<Position> ring) {
  var sum = 0.0;
  for (var i = 0; i + 1 < ring.length; i++) {
    sum += ring[i].lng * ring[i + 1].lat - ring[i + 1].lng * ring[i].lat;
  }
  return sum;
}

List<Position> _normaliseRing(List<Position> ring, bool keepOrientation) {
  var pts = List<Position>.of(ring);
  if (pts.length > 1 &&
      pts.first.lng == pts.last.lng &&
      pts.first.lat == pts.last.lat) {
    pts.removeLast();
  }
  if (!keepOrientation && signedArea2([...pts, pts.first]) < 0) {
    pts = pts.reversed.toList();
  }
  var start = 0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i], b = pts[start];
    if (a.lng < b.lng || (a.lng == b.lng && a.lat < b.lat)) start = i;
  }
  return [...pts.sublist(start), ...pts.sublist(0, start)];
}

bool _ringsMatch(
  List<Position> a,
  List<Position> b,
  double tolerance,
  bool keepOrientation,
) {
  final na = _normaliseRing(a, keepOrientation);
  final nb = _normaliseRing(b, keepOrientation);
  if (na.length != nb.length) return false;
  // The start can differ when two positions are equal within tolerance;
  // try every rotation.
  for (var shift = 0; shift < na.length; shift++) {
    var ok = true;
    for (var i = 0; i < na.length && ok; i++) {
      final p = na[(i + shift) % na.length], q = nb[i];
      ok = (p.lng - q.lng).abs() <= tolerance &&
          (p.lat - q.lat).abs() <= tolerance;
    }
    if (ok) return true;
  }
  return false;
}

bool _unorderedMatch<T>(List<T> a, List<T> b, bool Function(T, T) eq) {
  if (a.length != b.length) return false;
  final used = List<bool>.filled(b.length, false);
  for (final x in a) {
    var found = false;
    for (var j = 0; j < b.length; j++) {
      if (!used[j] && eq(x, b[j])) {
        used[j] = true;
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

bool _polysMatch(
  List<List<Position>> a,
  List<List<Position>> b,
  double tolerance,
  bool keepOrientation,
) {
  if (a.isEmpty || b.isEmpty) return a.isEmpty && b.isEmpty;
  if (!_ringsMatch(a[0], b[0], tolerance, keepOrientation)) return false;
  return _unorderedMatch<List<Position>>(
    a.sublist(1),
    b.sublist(1),
    (x, y) => _ringsMatch(x, y, tolerance, keepOrientation),
  );
}

/// Whether two MultiPolygon coordinate lists describe the same geometry.
bool coordsMatch(
  Coords actual,
  Coords expected, {
  double tolerance = 1e-9,
  bool checkOrientation = false,
}) =>
    _unorderedMatch<List<List<Position>>>(
      actual,
      expected,
      (x, y) => _polysMatch(x, y, tolerance, checkOrientation),
    );

String _describe(Coords c) => c
    .map((p) => p
        .map((r) => '[${r.map((pos) => '(${pos.lng}, ${pos.lat})').join(' ')}]')
        .join(', '))
    .join('\n');

/// Matches polygonal coordinates against [expected]; see [coordsMatch].
Matcher matchesCoords(
  Coords expected, {
  double tolerance = 1e-9,
  bool checkOrientation = false,
}) =>
    _CoordsMatcher(expected, tolerance, checkOrientation);

class _CoordsMatcher extends Matcher {
  final Coords expected;
  final double tolerance;
  final bool checkOrientation;

  _CoordsMatcher(this.expected, this.tolerance, this.checkOrientation);

  @override
  bool matches(dynamic item, Map matchState) =>
      item is List &&
      coordsMatch(item.cast<List<List<Position>>>(), expected,
          tolerance: tolerance, checkOrientation: checkOrientation);

  @override
  Description describe(Description description) => description
      .add('polygonal coordinates within $tolerance of\n')
      .add(_describe(expected));

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
          Map matchState, bool verbose) =>
      item is List
          ? mismatchDescription
              .add('was\n')
              .add(_describe(item.cast<List<List<Position>>>()))
          : mismatchDescription.add('is not a coordinate list');
}

/// Checks the GeoJSON ring orientation of [coords]: counter-clockwise outer
/// rings, clockwise holes, every ring closed. Rings whose area rounds to
/// zero in double precision (slivers from exact intersection points) have no
/// measurable orientation and are accepted.
void expectGeoJsonOrientation(Coords coords) {
  for (final poly in coords) {
    for (var i = 0; i < poly.length; i++) {
      final ring = poly[i];
      expect(ring.length, greaterThanOrEqualTo(4), reason: 'ring too short');
      expect(ring.first.lng, ring.last.lng, reason: 'ring not closed');
      expect(ring.first.lat, ring.last.lat, reason: 'ring not closed');
      final area = signedArea2(ring);
      // shoelace roundoff grows with the coordinate magnitude
      var scale = 0.0;
      for (var j = 0; j + 1 < ring.length; j++) {
        scale += (ring[j].lng * ring[j + 1].lat).abs() +
            (ring[j + 1].lng * ring[j].lat).abs();
      }
      final eps = scale * 1e-12;
      if (i == 0) {
        expect(area, greaterThanOrEqualTo(-eps),
            reason: 'outer ring must be CCW');
      } else {
        expect(area, lessThanOrEqualTo(eps), reason: 'hole must be CW');
      }
    }
  }
}
