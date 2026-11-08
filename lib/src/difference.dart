import 'package:geotypes/geotypes.dart';

import 'polygon_clipping/geojson_adapter.dart';
import 'polygon_clipping/polygon_clipping.dart';

/// Takes a [FeatureCollection] of [Polygon]s and [MultiPolygon]s and returns
/// the first one minus all the others.
///
/// Returns a [Feature] with a [Polygon] when the difference is a single
/// polygon, a [MultiPolygon] when it consists of several, and `null` when
/// nothing remains. The result carries [properties] if given, otherwise the
/// properties of the first feature, as in turf.js. Coordinates are treated
/// as planar (lng/lat). Outer rings of the result are counter-clockwise,
/// holes clockwise.
///
/// Throws an [ArgumentError] if fewer than two polygonal geometries are
/// given, or if any geometry is not a Polygon or MultiPolygon.
///
/// ```dart
/// final area = Feature(geometry: Polygon(coordinates: [[Position(0, 0),
///   Position(4, 0), Position(4, 4), Position(0, 4), Position(0, 0)]]));
/// final hole = Feature(geometry: Polygon(coordinates: [[Position(1, 1),
///   Position(2, 1), Position(2, 2), Position(1, 2), Position(1, 1)]]));
///
/// // A polygon with one hole.
/// final result = difference(FeatureCollection(features: [area, hole]));
/// ```
Feature<GeometryObject>? difference(
  FeatureCollection features, {
  Map<String, dynamic>? properties,
}) {
  final geoms = polygonalCoordsOf(features);
  if (geoms.length < 2) {
    throw ArgumentError('Must have at least two features');
  }
  final props = properties ??
      (features.features.isNotEmpty ? features.features[0].properties : null);
  final result = clipDifference(geoms[0], geoms.sublist(1));
  return clipResultToFeature(result, props == null ? {} : Map.of(props));
}
