// Conversions between turf_dart's geotypes and flutter_map / latlong2.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

/// The LatLng of [p], with the longitude wrapped into [-180, 180).
LatLng toLatLng(Position p) {
  var lng = p.lng.toDouble();
  if (lng < -180 || lng >= 180) lng = ((lng + 180) % 360 + 360) % 360 - 180;
  return LatLng(p.lat.toDouble(), lng);
}

Position toPosition(LatLng p) => Position(p.longitude, p.latitude);

List<LatLng> ringToLatLngs(List<Position> ring) => [
  for (final p in ring) toLatLng(p),
];

/// The polygons (outer ring, holes) of a Polygon or MultiPolygon geometry,
/// or of a Feature of one.
List<List<List<Position>>> polygonsOf(GeoJSONObject? geo) {
  if (geo == null) return [];
  if (geo is Feature) return polygonsOf(geo.geometry);
  if (geo is Polygon) return geo.coordinates.isEmpty ? [] : [geo.coordinates];
  if (geo is MultiPolygon) {
    return [
      for (final p in geo.coordinates)
        if (p.isNotEmpty) p,
    ];
  }
  return [];
}

/// flutter_map polygons for a Polygon or MultiPolygon (or a Feature of one).
List<fm.Polygon> toMapPolygons(
  GeoJSONObject? geo, {
  Color? fill,
  Color border = Colors.black,
  double borderWidth = 1.5,
}) => [
  for (final poly in polygonsOf(geo))
    fm.Polygon(
      points: ringToLatLngs(poly[0]),
      holePointsList: [for (final hole in poly.skip(1)) ringToLatLngs(hole)],
      color: fill,
      borderColor: border,
      borderStrokeWidth: borderWidth,
    ),
];

/// flutter_map polylines for a LineString or MultiLineString (or a Feature
/// of one).
List<fm.Polyline> toMapPolylines(
  GeoJSONObject? geo, {
  Color color = Colors.black,
  double width = 3,
}) {
  final g = geo is Feature ? geo.geometry : geo;
  final lines = g is LineString
      ? [g.coordinates]
      : g is MultiLineString
      ? g.coordinates
      : const <List<Position>>[];
  return [
    for (final line in lines)
      if (line.length > 1)
        fm.Polyline(
          points: ringToLatLngs(line),
          color: color,
          strokeWidth: width,
        ),
  ];
}

/// Number of positions in a geometry (rings counted with their closing
/// position).
int vertexCount(GeoJSONObject? geo) {
  if (geo == null) return 0;
  var n = 0;
  coordEach(geo, (_, _, _, _, _) {
    n++;
    return null;
  });
  return n;
}

Feature<Point> pointFeature(LatLng p, [Map<String, dynamic>? properties]) =>
    Feature<Point>(
      geometry: Point(coordinates: toPosition(p)),
      properties: properties ?? {},
    );

Feature<Polygon> boxPolygon(LatLng sw, LatLng ne) => Feature<Polygon>(
  geometry: Polygon(
    coordinates: [
      [
        Position(sw.longitude, sw.latitude),
        Position(ne.longitude, sw.latitude),
        Position(ne.longitude, ne.latitude),
        Position(sw.longitude, ne.latitude),
        Position(sw.longitude, sw.latitude),
      ],
    ],
  ),
);
