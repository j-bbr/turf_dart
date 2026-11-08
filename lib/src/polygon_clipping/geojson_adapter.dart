// Conversion between GeoJSON objects and the clipper's coordinate arrays.
import 'package:geotypes/geotypes.dart';

import '../meta/geom.dart';
import 'polygon_clipping.dart';

/// Collects the coordinates of every Polygon and MultiPolygon in [geoJSON]
/// (a geometry, Feature or FeatureCollection), each as MultiPolygon
/// coordinates, in input order.
///
/// Throws an [ArgumentError] for any other geometry type.
List<MultiPolygonCoords> polygonalCoordsOf(GeoJSONObject geoJSON) {
  final geoms = <MultiPolygonCoords>[];
  geomEach(geoJSON, (geom, featureIndex, _, __, ___) {
    if (geom is Polygon) {
      geoms.add([geom.coordinates]);
    } else if (geom is MultiPolygon) {
      geoms.add(geom.coordinates);
    } else if (geom != null) {
      throw ArgumentError(
          '${geom.type.name} is not supported, only Polygon and MultiPolygon');
    }
  });
  return geoms;
}

/// Wraps a clipping result in a Feature: `null` for an empty result, a
/// [Polygon] for a single polygon and a [MultiPolygon] otherwise.
Feature<GeometryObject>? clipResultToFeature(
  MultiPolygonCoords result,
  Map<String, dynamic>? properties,
) {
  if (result.isEmpty) return null;
  final GeometryObject geometry = result.length == 1
      ? Polygon(coordinates: result[0])
      : MultiPolygon(coordinates: result);
  return Feature<GeometryObject>(
    geometry: geometry,
    properties: properties ?? {},
  );
}
