import 'package:geotypes/geotypes.dart';

import 'polygon_clipping/geojson_adapter.dart';
import 'polygon_clipping/polygon_clipping.dart';

/// Takes a [FeatureCollection] of [Polygon]s and [MultiPolygon]s and returns
/// their union, the area covered by any of them.
///
/// Returns a [Feature] with a [Polygon] when the union is a single polygon,
/// a [MultiPolygon] when it consists of several unconnected parts, and
/// `null` for an empty result. Coordinates are treated as planar (lng/lat),
/// as in turf.js. Outer rings of the result are counter-clockwise, holes
/// clockwise.
///
/// Throws an [ArgumentError] if fewer than two polygonal geometries are
/// given, or if any geometry is not a Polygon or MultiPolygon.
///
/// ```dart
/// final poly1 = Feature(geometry: Polygon(coordinates: [[Position(0, 0),
///   Position(2, 0), Position(2, 2), Position(0, 2), Position(0, 0)]]));
/// final poly2 = Feature(geometry: Polygon(coordinates: [[Position(1, 1),
///   Position(3, 1), Position(3, 3), Position(1, 3), Position(1, 1)]]));
///
/// final result = union(FeatureCollection(features: [poly1, poly2]));
/// ```
Feature<GeometryObject>? union(
  FeatureCollection features, {
  Map<String, dynamic>? properties,
}) {
  final geoms = polygonalCoordsOf(features);
  if (geoms.length < 2) {
    throw ArgumentError('Must have at least 2 geometries');
  }
  final result = clipUnion(geoms[0], geoms.sublist(1));
  return clipResultToFeature(result, properties);
}
