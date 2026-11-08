import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// `voronoi`: tap to add points (tap a point to remove it); cells computed in
/// Web Mercator and clipped to the view. A draggable probe finds its
/// `nearestPoint`, whose cell always contains the probe; with "clip to
/// circle", that cell is intersected with a circle around the probe.
class VoronoiTab extends StatefulWidget {
  final SampleData data;

  const VoronoiTab({super.key, required this.data});

  @override
  State<VoronoiTab> createState() => _VoronoiTabState();
}

class _VoronoiTabState extends State<VoronoiTab> {
  final controller = fm.MapController();
  late List<LatLng> points = [
    for (final m in widget.data.museums) toLatLng(m.geometry!.coordinates),
  ];
  bool clipToCircle = false;
  LatLng probe = const LatLng(52.517, 13.392);
  double radiusKm = 1;
  BBox? view;

  BBox get _view =>
      view ??
      BBox(13.30, 52.47, 13.48, 52.56); // until the map reports its bounds

  /// Cells in Web Mercator for metric accuracy, back in WGS84.
  FeatureCollection<Polygon> _cells() {
    final v = _view;
    final sw =
        geoToMercator(Point(coordinates: Position(v.lng1, v.lat1))) as Point;
    final ne =
        geoToMercator(Point(coordinates: Position(v.lng2, v.lat2))) as Point;
    final cells = voronoi(
      FeatureCollection<Point>(
        features: [
          for (final p in points)
            Feature<Point>(
              geometry:
                  geoToMercator(Point(coordinates: toPosition(p))) as Point,
            ),
        ],
      ),
      bbox: BBox(
        sw.coordinates.lng,
        sw.coordinates.lat,
        ne.coordinates.lng,
        ne.coordinates.lat,
      ),
    );
    return FeatureCollection<Polygon>(
      features: [
        for (final f in (geoToWgs84(cells) as FeatureCollection).features)
          f as Feature<Polygon>,
      ],
    );
  }

  void _tap(LatLng p) {
    final camera = controller.camera;
    final tapped = camera.latLngToScreenOffset(p);
    for (var i = 0; i < points.length; i++) {
      if ((camera.latLngToScreenOffset(points[i]) - tapped).distance < 14) {
        setState(() => points.removeAt(i));
        return;
      }
    }
    setState(() => points.add(p));
  }

  @override
  Widget build(BuildContext context) {
    final (cells, ms) = timed(_cells);
    final sites = FeatureCollection<Point>(
      features: [for (final p in points) pointFeature(p)],
    );
    final nearest = points.isEmpty
        ? null
        : nearestPoint(pointFeature(probe), sites);
    final nearestIndex = nearest?.properties!['featureIndex'] as int?;
    final disc = circle(pointFeature(probe), radiusKm, steps: 64);
    final highlight = nearestIndex == null
        ? null
        : clipToCircle
        ? polygonIntersect(
            FeatureCollection(features: [cells.features[nearestIndex], disc]),
          )
        : cells.features[nearestIndex];
    var vertices = 0;
    for (final c in cells.features) {
      vertices += vertexCount(c);
    }
    return DemoMap(
      controller: controller,
      onTap: (_, p) => _tap(p),
      onPositionChanged: (camera, _) {
        final b = camera.visibleBounds;
        final next = BBox(b.west, b.south, b.east, b.north);
        if (view == null ||
            view!.lng1 != next.lng1 ||
            view!.lat1 != next.lat1 ||
            view!.lng2 != next.lng2 ||
            view!.lat2 != next.lat2) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => view = next),
          );
        }
      },
      stats: OpStats(ms, vertices, '${points.length} points'),
      onBenchmark: () =>
          showBenchmark(context, 'voronoi', benchmarkMedian(_cells)),
      controls: Wrap(
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Tap to add a point, tap a point to remove it.'),
          const LegendDot(Colors.red, 'probe (drag)'),
          if (nearest != null)
            Text(
              'nearestPoint: ${(nearest.properties!['distanceToPoint'] as num).toStringAsFixed(2)} km',
            ),
          LabeledSwitch(
            label: 'clip to circle (polygonIntersect)',
            value: clipToCircle,
            onChanged: (v) => setState(() => clipToCircle = v),
          ),
          if (clipToCircle)
            LabeledSlider(
              label: 'radius ${radiusKm.toStringAsFixed(1)} km',
              value: radiusKm,
              min: 0.2,
              max: 4,
              onChanged: (v) => setState(() => radiusKm = v),
            ),
        ],
      ),
      layers: [
        fm.PolygonLayer(
          polygons: [
            for (final c in cells.features)
              ...toMapPolygons(c, border: Colors.indigo, borderWidth: 1),
            if (clipToCircle)
              ...toMapPolygons(disc, border: Colors.orange, borderWidth: 1.5),
            if (highlight != null)
              ...toMapPolygons(
                highlight,
                fill: Colors.green.withValues(alpha: 0.35),
                border: Colors.green.shade800,
                borderWidth: 2,
              ),
          ],
        ),
        if (nearest != null)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: [probe, toLatLng(nearest.geometry!.coordinates)],
                color: Colors.red,
                strokeWidth: 1.5,
                pattern: fm.StrokePattern.dashed(segments: const [6, 4]),
              ),
            ],
          ),
        fm.CircleLayer(
          circles: [
            for (var i = 0; i < points.length; i++)
              fm.CircleMarker(
                point: points[i],
                radius: i == nearestIndex ? 7 : 4,
                color: i == nearestIndex
                    ? Colors.green.shade800
                    : Colors.indigo,
              ),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            dragHandle(
              probe,
              (p) => setState(() => probe = p),
              color: Colors.red,
            ),
          ],
        ),
      ],
    );
  }
}
