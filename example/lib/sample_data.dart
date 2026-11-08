// The demo's sample data from assets/ (approximate, hand-made shapes around
// Berlin) and the fixed frame of the map.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

class SampleData {
  final Feature<Polygon> ring;
  final List<Feature<LineString>> tramLines;
  final List<Feature<Point>> museums;

  SampleData(this.ring, this.tramLines, this.museums);

  /// The frame of the city-scale tabs: the region around the Ring.
  static final BBox frameBox = BBox(13.20, 52.43, 13.60, 52.60);

  static final Feature<Polygon> frame = Feature<Polygon>(
    geometry: Polygon(
      coordinates: [
        [
          Position(frameBox.lng1, frameBox.lat1),
          Position(frameBox.lng2, frameBox.lat1),
          Position(frameBox.lng2, frameBox.lat2),
          Position(frameBox.lng1, frameBox.lat2),
          Position(frameBox.lng1, frameBox.lat1),
        ],
      ],
    ),
  );

  static const LatLng center = LatLng(52.515, 13.40);

  static Future<SampleData> load() async {
    Future<FeatureCollection> read(String name) async =>
        FeatureCollection.fromJson(
          jsonDecode(await rootBundle.loadString('assets/$name'))
              as Map<String, dynamic>,
        );
    final ring = await read('sbahn_ring.geojson');
    final trams = await read('tram_lines.geojson');
    final museums = await read('museums.geojson');
    return SampleData(
      Feature<Polygon>(
        geometry: ring.features.first.geometry as Polygon,
        properties: ring.features.first.properties,
      ),
      [
        for (final f in trams.features)
          Feature<LineString>(
            geometry: f.geometry as LineString,
            properties: f.properties,
          ),
      ],
      [
        for (final f in museums.features)
          Feature<Point>(
            geometry: f.geometry as Point,
            properties: f.properties,
          ),
      ],
    );
  }
}
