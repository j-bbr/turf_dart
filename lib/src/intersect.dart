import 'package:geotypes/geotypes.dart';

import 'polygon_clipping/geojson_adapter.dart';
import 'polygon_clipping/polygon_clipping.dart';

/// Takes a [FeatureCollection] of [Polygon]s and [MultiPolygon]s and returns
/// their intersection, the area shared by all of them.
///
/// Returns a [Feature] with a [Polygon] when the intersection is a single
/// polygon, a [MultiPolygon] when it consists of several, and `null` when
/// the features do not share any area. Coordinates are treated as planar
/// (lng/lat), as in turf.js. Outer rings of the result are
/// counter-clockwise, holes clockwise.
///
/// This is turf.js' `intersect`; it is named `polygonIntersect` in Dart
/// because the `lineclip` module already exports an `intersect` function.
///
/// Throws an [ArgumentError] if fewer than two polygonal geometries are
/// given, or if any geometry is not a Polygon or MultiPolygon.
///
/// ```dart
/// final poly1 = polygon([[[-122.801742, 45.48565], [-122.801742, 45.60491],
///   [-122.584762, 45.60491], [-122.584762, 45.48565],
///   [-122.801742, 45.48565]]]);
/// final poly2 = polygon([[[-122.520217, 45.535693], [-122.64038, 45.553967],
///   [-122.720031, 45.526554], [-122.669906, 45.507309],
///   [-122.723464, 45.446643], [-122.532577, 45.408574],
///   [-122.487258, 45.477466], [-122.520217, 45.535693]]]);
///
/// final result = polygonIntersect(FeatureCollection(features: [poly1, poly2]));
/// ```
Feature<GeometryObject>? polygonIntersect(
  FeatureCollection features, {
  Map<String, dynamic>? properties,
}) {
  final geoms = polygonalCoordsOf(features);
  if (geoms.length < 2) {
    throw ArgumentError('Must specify at least 2 geometries');
  }
  final result = clipIntersection(geoms[0], geoms.sublist(1));
  return clipResultToFeature(result, properties);
}
