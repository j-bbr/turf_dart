import 'package:geotypes/geotypes.dart';

import 'polygon_clipping/geojson_adapter.dart';
import 'polygon_clipping/polygon_clipping.dart';

const List<List<num>> _world = [
  [180, 90],
  [-180, 90],
  [-180, -90],
  [180, -90],
  [180, 90],
];

/// Takes polygons and returns a mask: the [mask] polygon (by default the
/// whole world) with the polygons cut out as holes.
///
/// [polygons] is a [Polygon] or [MultiPolygon], a [Feature] of one, or a
/// [FeatureCollection] of them; they are unioned first.
///
/// With the default `keepHoles: false` the result is exactly turf.js'
/// `mask`: a [Polygon] whose rings are the mask's rings followed by the
/// outer ring of each unioned polygon. Holes in the input are dropped, so
/// they end up unshaded.
///
/// With `keepHoles: true` the result is the [mask] minus the polygons,
/// computed with [difference]-style clipping, so holes in the input are
/// shaded too. It is a [Polygon], or a [MultiPolygon] when a hole contains
/// shaded islands, with GeoJSON ring orientation; when the polygons cover
/// the whole mask it is an empty [MultiPolygon]. The result is never
/// `null`.
///
/// Throws an [ArgumentError] if [polygons] contains other geometry types or
/// [mask] is not a Polygon.
///
/// ```dart
/// // Shade everything outside the polygon, including its holes:
/// final shading = mask(polygon, mask: frame, keepHoles: true);
/// ```
Feature<GeometryObject> mask(
  GeoJSONObject polygons, {
  GeoJSONObject? mask,
  bool keepHoles = false,
}) {
  final maskRings = _maskRings(mask);
  final geoms = polygonalCoordsOf(polygons);

  if (keepHoles) {
    final result = clipDifference([maskRings], geoms);
    return clipResultToFeature(result, {}) ??
        Feature<GeometryObject>(
          geometry: MultiPolygon(coordinates: []),
          properties: {},
        );
  }

  final unioned = geoms.isEmpty
      ? <List<List<Position>>>[]
      : clipUnion(geoms[0], geoms.sublist(1));
  return Feature<GeometryObject>(
    geometry: Polygon(coordinates: [
      ...maskRings,
      for (final poly in unioned) poly[0],
    ]),
    properties: {},
  );
}

List<List<Position>> _maskRings(GeoJSONObject? mask) {
  if (mask == null) {
    return [
      [for (final p in _world) Position(p[0], p[1])]
    ];
  }
  final geom = mask is Feature ? mask.geometry : mask;
  if (geom is! Polygon) {
    throw ArgumentError('mask must be a Polygon or a Feature<Polygon>');
  }
  // copy, so the result never shares lists with the input
  return [
    for (final ring in geom.coordinates) [for (final p in ring) p.clone()]
  ];
}
