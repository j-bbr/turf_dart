import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// Line operations on one tram line: `length`, `simplify`, `along`,
/// `lineSliceAlong`, and `nearestPointOnLine` and `pointToLineDistance` for a
/// draggable probe.
class LinesTab extends StatefulWidget {
  final SampleData data;

  const LinesTab({super.key, required this.data});

  @override
  State<LinesTab> createState() => _LinesTabState();
}

class _LineResult {
  final num length;
  final Feature<LineString> simplified;
  final Feature<LineString> slice;
  final Feature<Point> along;
  final Feature<Point> nearest;
  final num distance;

  _LineResult(
    this.length,
    this.simplified,
    this.slice,
    this.along,
    this.nearest,
    this.distance,
  );
}

class _LinesTabState extends State<LinesTab> {
  double tolerance = 0;
  RangeValues sliceRange = const RangeValues(0.2, 0.6);
  double alongFraction = 0.4;
  LatLng probe = const LatLng(52.527, 13.40);

  late final Feature<LineString> line = widget.data.tramLines.first;

  _LineResult _compute() {
    final len = length(line);
    final simplified = tolerance == 0
        ? line
        : simplify(line, tolerance: tolerance, highestQuality: true);
    final slice = lineSliceAlong(
      line,
      len * sliceRange.start,
      len * sliceRange.end,
    );
    final at = along(line, len * alongFraction);
    final probePoint = Point(coordinates: toPosition(probe));
    final nearest = nearestPointOnLine(line.geometry!, probePoint);
    final distance = pointToLineDistance(probePoint, line.geometry!);
    return _LineResult(len, simplified, slice, at, nearest, distance);
  }

  @override
  Widget build(BuildContext context) {
    final (r, ms) = timed(_compute);
    final original = line.geometry!.coordinates.length;
    return DemoMap(
      stats: OpStats(
        ms,
        r.simplified.geometry!.coordinates.length,
        '${r.length.toStringAsFixed(2)} km long · '
        'simplify kept ${r.simplified.geometry!.coordinates.length} of '
        '$original vertices',
      ),
      onBenchmark: () => showBenchmark(
        context,
        'all line operations',
        benchmarkMedian(_compute),
      ),
      controls: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${line.properties?['name'] ?? 'line'}'),
          LabeledSlider(
            label: 'simplify ${(tolerance * 1e4).toStringAsFixed(0)}e-4°',
            value: tolerance,
            min: 0,
            max: 0.005,
            labelWidth: 120,
            onChanged: (v) => setState(() => tolerance = v),
          ),
          LabeledSlider(
            label: 'along ${(alongFraction * 100).round()} %',
            value: alongFraction,
            min: 0,
            max: 1,
            onChanged: (v) => setState(() => alongFraction = v),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 110, child: Text('lineSliceAlong')),
              SizedBox(
                width: 180,
                child: RangeSlider(
                  values: sliceRange,
                  onChanged: (v) => setState(() => sliceRange = v),
                ),
              ),
            ],
          ),
          Text(
            'probe: ${(r.distance * 1000).round()} m from the line '
            '(pointToLineDistance)',
          ),
          const LegendDot(Colors.indigo, 'simplify'),
          const LegendDot(Colors.orange, 'lineSliceAlong'),
          const LegendDot(Colors.green, 'along'),
          const LegendDot(Colors.red, 'nearestPointOnLine (drag the probe)'),
        ],
      ),
      layers: [
        fm.PolylineLayer(
          polylines: [
            ...toMapPolylines(line, color: Colors.blueGrey.shade200, width: 7),
            ...toMapPolylines(r.slice, color: Colors.orange, width: 7),
            ...toMapPolylines(r.simplified, color: Colors.indigo, width: 2.5),
            fm.Polyline(
              points: [probe, toLatLng(r.nearest.geometry!.coordinates)],
              color: Colors.red,
              strokeWidth: 1.5,
              pattern: fm.StrokePattern.dashed(segments: const [6, 4]),
            ),
          ],
        ),
        fm.CircleLayer(
          circles: [
            for (final p in r.simplified.geometry!.coordinates)
              fm.CircleMarker(
                point: toLatLng(p),
                radius: 3,
                color: Colors.indigo,
              ),
            fm.CircleMarker(
              point: toLatLng(r.along.geometry!.coordinates),
              radius: 7,
              color: Colors.green.shade700,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
            fm.CircleMarker(
              point: toLatLng(r.nearest.geometry!.coordinates),
              radius: 5,
              color: Colors.red,
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
