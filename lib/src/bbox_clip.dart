import 'package:geotypes/geotypes.dart';

import 'lineclip.dart';

/// Clips a [LineString], [MultiLineString], [Polygon] or [MultiPolygon] to
/// a rectangular [bbox], as turf.js' `bboxClip`.
///
/// [feature] is a [Feature] or a bare geometry; the result is a [Feature]
/// carrying the feature's properties.
///
/// * Lines are clipped with Cohen–Sutherland ([lineclip]). A LineString
///   becomes a [LineString] when one part remains, otherwise a
///   [MultiLineString] (possibly with no lines).
/// * Polygons are clipped ring by ring with Sutherland–Hodgman
///   ([polygonclip]): holes are kept, rings that vanish are dropped. The
///   result keeps the input type; as in turf.js, a polygon of a
///   [MultiPolygon] whose rings all vanish stays as an empty polygon.
///
/// Sutherland–Hodgman can leave zero-width slivers along the box edges
/// when a polygon leaves and re-enters the box; turf.js does the same. Use
/// `polygonIntersect` with a box polygon when you need a clean result.
///
/// Throws an [ArgumentError] for other geometry types.
///
/// ```dart
/// final bbox = BBox(0, 0, 10, 10);
/// final poly = Feature(geometry: Polygon(coordinates: [[Position(2, 2),
///   Position(8, 4), Position(12, 8), Position(3, 7), Position(2, 2)]]));
///
/// final clipped = bboxClip(poly, bbox);
/// ```
Feature<GeometryObject> bboxClip(GeoJSONObject feature, BBox bbox) {
  final GeometryObject? geom;
  final Map<String, dynamic> properties;
  if (feature is Feature) {
    geom = feature.geometry;
    properties = Map.of(feature.properties ?? {});
  } else if (feature is GeometryObject) {
    geom = feature;
    properties = {};
  } else {
    throw ArgumentError('bboxClip takes a Feature or a geometry');
  }

  if (geom is LineString || geom is MultiLineString) {
    final lines = geom is LineString
        ? [geom.coordinates]
        : (geom as MultiLineString).coordinates;
    final clipped = <List<Position>>[];
    for (final line in lines) {
      if (line.isNotEmpty) lineclip(line, bbox, clipped);
    }
    if (clipped.length == 1) {
      return Feature<GeometryObject>(
        geometry: LineString(coordinates: clipped[0]),
        properties: properties,
      );
    }
    return Feature<GeometryObject>(
      geometry: MultiLineString(coordinates: clipped),
      properties: properties,
    );
  }
  if (geom is Polygon) {
    return Feature<GeometryObject>(
      geometry: Polygon(coordinates: _clipPolygon(geom.coordinates, bbox)),
      properties: properties,
    );
  }
  if (geom is MultiPolygon) {
    return Feature<GeometryObject>(
      geometry: MultiPolygon(coordinates: [
        for (final poly in geom.coordinates) _clipPolygon(poly, bbox),
      ]),
      properties: properties,
    );
  }
  throw ArgumentError('geometry ${geom?.type.name} not supported');
}

List<List<Position>> _clipPolygon(List<List<Position>> rings, BBox bbox) {
  final outRings = <List<Position>>[];
  for (final ring in rings) {
    if (ring.isEmpty) continue;
    final clipped = polygonclip(ring, bbox);
    if (clipped.isNotEmpty) {
      final first = clipped.first, last = clipped.last;
      if (first.lng != last.lng || first.lat != last.lat) {
        clipped.add(first);
      }
      if (clipped.length >= 4) outRings.add(clipped);
    }
  }
  return outRings;
}
