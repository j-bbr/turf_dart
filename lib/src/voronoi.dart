import 'dart:math';
import 'dart:typed_data';

import 'package:geotypes/geotypes.dart';

import 'voronoi/voronoi_cells.dart';

/// Takes a [FeatureCollection] of [Point]s and a [bbox] and returns the
/// Voronoi diagram: one [Polygon] cell per point, in input order, clipped to
/// [bbox] (by default `[-180, -85, 180, 85]`, as in turf.js).
///
/// Each cell holds the part of the box that is closer to its point than to
/// any other point, and carries a copy of the point's properties. The cells
/// tile the box.
///
/// Coordinates are treated as planar, as in turf.js. For metric accuracy,
/// project the points first (for example with `geoToMercator`), compute the
/// diagram, and project the cells back with `geoToWgs84`.
///
/// Differences to turf.js, which uses d3-voronoi:
/// * the diagram is computed with a port of Delaunator and d3-delaunay;
/// * rings are counter-clockwise (RFC 7946);
/// * a point that occurs more than once gets the cell of its first
///   occurrence, and a point whose cell is empty (it lies outside the box)
///   gets a polygon without coordinates.
///
/// ```dart
/// final points = FeatureCollection<Point>(features: [
///   Feature(geometry: Point(coordinates: Position(13.40, 52.52))),
///   Feature(geometry: Point(coordinates: Position(13.45, 52.50))),
///   Feature(geometry: Point(coordinates: Position(13.38, 52.49))),
/// ]);
/// final cells = voronoi(points, bbox: BBox(13.3, 52.45, 13.5, 52.55));
/// ```
FeatureCollection<Polygon> voronoi(
  FeatureCollection<Point> points, {
  BBox? bbox,
}) {
  final box = bbox ?? BBox(-180, -85, 180, 85);
  final features = points.features;
  final n = features.length;
  if (n == 0) return FeatureCollection<Polygon>(features: []);

  // d3-delaunay's tolerances (degenerate triangles, collinearity, "infinite"
  // circumcenters) assume pixel-scale coordinates. Compute the diagram in a
  // copy of the box translated to the origin and scaled uniformly to about
  // 1000 units - a similarity, so the diagram is the same - and map back.
  final xmin = box.lng1.toDouble(), ymin = box.lat1.toDouble();
  final xmax = box.lng2.toDouble(), ymax = box.lat2.toDouble();
  final extent = max(xmax - xmin, ymax - ymin);
  final scale = extent > 0 && extent.isFinite ? 1000 / extent : 1.0;

  final coords = Float64List(n * 2);
  final original = Float64List(n * 2);
  for (var i = 0; i < n; i++) {
    final geom = features[i].geometry;
    if (geom == null) {
      throw ArgumentError('Feature $i has no geometry');
    }
    original[2 * i] = geom.coordinates.lng.toDouble();
    original[2 * i + 1] = geom.coordinates.lat.toDouble();
    coords[2 * i] = (original[2 * i] - xmin) * scale;
    coords[2 * i + 1] = (original[2 * i + 1] - ymin) * scale;
  }

  final nxmax = (xmax - xmin) * scale, nymax = (ymax - ymin) * scale;
  final diagram = Voronoi(Delaunay(coords), 0, 0, nxmax, nymax);

  // back to input coordinates; box edges map exactly onto the box
  double backX(double x) => x == 0
      ? xmin
      : x == nxmax
          ? xmax
          : xmin + x / scale;
  double backY(double y) => y == 0
      ? ymin
      : y == nymax
          ? ymax
          : ymin + y / scale;

  final firstIndex = <String, int>{};
  final cells = <Feature<Polygon>>[];
  for (var i = 0; i < n; i++) {
    final key = '${original[2 * i]},${original[2 * i + 1]}';
    final first = firstIndex.putIfAbsent(key, () => i);

    var ring = diagram.cellPolygon(i);
    if (ring == null && first != i) ring = diagram.cellPolygon(first);

    final properties = Map<String, dynamic>.of(features[i].properties ?? {});
    cells.add(Feature<Polygon>(
      geometry: Polygon(
        coordinates: ring == null
            ? []
            : [
                _counterClockwise([
                  for (final p in ring) [backX(p[0]), backY(p[1])]
                ])
              ],
      ),
      properties: properties,
    ));
  }
  return FeatureCollection<Polygon>(features: cells);
}

List<Position> _counterClockwise(List<List<double>> ring) {
  var area2 = 0.0;
  for (var i = 0; i + 1 < ring.length; i++) {
    area2 += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
  }
  final ordered = area2 < 0 ? ring.reversed : ring;
  return [for (final p in ordered) Position(p[0], p[1])];
}
