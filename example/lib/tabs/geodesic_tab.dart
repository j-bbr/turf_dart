import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';

/// Measurements on the sphere at world scale, for two draggable points:
/// `distance`, `bearing` and `midpoint` along the great circle, compared
/// with the rhumb line (`rhumbDistance`, `rhumbBearing`); and `destination`
/// versus `rhumbDestination` for a bearing and distance from A.
///
/// The paths are drawn by stepping with `destination` / `rhumbDestination`
/// (turf_dart's `greatCircle` takes `[lat, lng]` positions and returns
/// radians, so it does not fit a map directly).
class GeodesicTab extends StatefulWidget {
  const GeodesicTab({super.key});

  @override
  State<GeodesicTab> createState() => _GeodesicTabState();
}

class _Geodesic {
  final num distance, rhumbDistanceKm, bearing, rhumbBearingDeg;
  final Point midpoint;
  final List<List<LatLng>> greatCircle;
  final List<List<LatLng>> rhumbLine;
  final Point destination;
  final Feature<Point> rhumbDestination;
  final List<List<LatLng>> destinationPath;
  final List<List<LatLng>> rhumbDestinationPath;

  _Geodesic(
    this.distance,
    this.rhumbDistanceKm,
    this.bearing,
    this.rhumbBearingDeg,
    this.midpoint,
    this.greatCircle,
    this.rhumbLine,
    this.destination,
    this.rhumbDestination,
    this.destinationPath,
    this.rhumbDestinationPath,
  );
}

final List<fm.Polyline> _worldGrid = graticule(BBox(-180, -80, 180, 80), 10);

class _GeodesicTabState extends State<GeodesicTab> {
  LatLng a = const LatLng(52.52, 13.40); // Berlin
  LatLng b = const LatLng(40.71, -74.01); // New York
  double travelBearing = 60;
  double travelKm = 6000;

  _Geodesic _compute() {
    final pa = Point(coordinates: toPosition(a));
    final pb = Point(coordinates: toPosition(b));
    final d = distance(pa, pb);
    final brg = bearing(pa, pb);
    final rd = rhumbDistance(pa, pb);
    final rbrg = rhumbBearing(pa, pb);
    final dest = destination(pa, travelKm, travelBearing);
    final rdest = rhumbDestination(pa, travelKm, travelBearing);
    return _Geodesic(
      d,
      rd,
      brg,
      rbrg,
      midpoint(pa, pb),
      _path((t) => destination(pa, d * t, brg).coordinates),
      _path((t) => rhumbDestination(pa, rd * t, rbrg).geometry!.coordinates),
      dest,
      rdest,
      _path((t) => destination(pa, travelKm * t, travelBearing).coordinates),
      _path(
        (t) => rhumbDestination(
          pa,
          travelKm * t,
          travelBearing,
        ).geometry!.coordinates,
      ),
    );
  }

  /// 128 steps of [at] for t in [0, 1], split where the path crosses the
  /// antimeridian.
  static List<List<LatLng>> _path(Position Function(double t) at) {
    final parts = <List<LatLng>>[[]];
    double? lastLng;
    for (var i = 0; i <= 128; i++) {
      final p = at(i / 128);
      var lng = p.lng.toDouble();
      lng = ((lng + 180) % 360 + 360) % 360 - 180;
      final lat = p.lat.toDouble().clamp(-90.0, 90.0);
      if (lastLng != null && (lng - lastLng).abs() > 180) parts.add([]);
      parts.last.add(LatLng(lat, lng));
      lastLng = lng;
    }
    return parts;
  }

  static List<fm.Polyline> _lines(
    List<List<LatLng>> parts,
    Color color,
    double width, {
    bool dashed = false,
  }) => [
    for (final part in parts)
      if (part.length > 1)
        fm.Polyline(
          points: part,
          color: color,
          strokeWidth: width,
          pattern: dashed
              ? fm.StrokePattern.dashed(segments: const [6, 4])
              : const fm.StrokePattern.solid(),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final (g, ms) = timed(_compute);
    return DemoMap(
      initialCenter: const LatLng(45, -30),
      initialZoom: 2.5,
      minZoom: 1,
      grid: _worldGrid,
      stats: OpStats(
        ms,
        g.greatCircle.fold(0, (n, part) => n + part.length),
        'great circle ${g.distance.round()} km, bearing '
        '${g.bearing.toStringAsFixed(1)}° · rhumb line '
        '${g.rhumbDistanceKm.round()} km, bearing '
        '${g.rhumbBearingDeg.toStringAsFixed(1)}°',
      ),
      onBenchmark: () => showBenchmark(
        context,
        'all geodesic operations',
        benchmarkMedian(_compute),
      ),
      controls: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Drag A (blue) and B (red).'),
          const LegendDot(Colors.indigo, 'great circle'),
          const LegendDot(Colors.orange, 'rhumb line'),
          const LegendDot(Colors.green, 'midpoint'),
          LabeledSlider(
            label: 'bearing ${travelBearing.round()}°',
            value: travelBearing,
            min: -180,
            max: 180,
            onChanged: (v) => setState(() => travelBearing = v),
          ),
          LabeledSlider(
            label: '${travelKm.round()} km',
            value: travelKm,
            min: 100,
            max: 15000,
            onChanged: (v) => setState(() => travelKm = v),
          ),
          const LegendDot(Colors.purple, 'destination'),
          const LegendDot(Colors.deepOrange, 'rhumbDestination'),
        ],
      ),
      layers: [
        fm.PolylineLayer(
          polylines: [
            ..._lines(g.greatCircle, Colors.indigo, 3),
            ..._lines(g.rhumbLine, Colors.orange, 2.5),
            ..._lines(
              g.destinationPath,
              Colors.purple.withValues(alpha: 0.6),
              2,
            ),
            ..._lines(
              g.rhumbDestinationPath,
              Colors.deepOrange.withValues(alpha: 0.6),
              2,
              dashed: true,
            ),
          ],
        ),
        fm.CircleLayer(
          circles: [
            fm.CircleMarker(
              point: toLatLng(g.midpoint.coordinates),
              radius: 6,
              color: Colors.green,
            ),
            fm.CircleMarker(
              point: toLatLng(g.destination.coordinates),
              radius: 6,
              color: Colors.purple,
            ),
            fm.CircleMarker(
              point: toLatLng(g.rhumbDestination.geometry!.coordinates),
              radius: 6,
              color: Colors.deepOrange,
            ),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            dragHandle(a, (p) => setState(() => a = p), color: Colors.blue),
            dragHandle(b, (p) => setState(() => b = p), color: Colors.red),
          ],
        ),
      ],
    );
  }
}
