import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// Line operations on a tram line or the Ring's boundary: `length`,
/// `simplify`, `along`, `lineSliceAlong`, `nearestPointOnLine` and
/// `pointToLineDistance` for a draggable probe, and `lineIntersect` with the
/// other lines.
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
  final List<Feature<Point>> crossings;

  _LineResult(
    this.length,
    this.simplified,
    this.slice,
    this.along,
    this.nearest,
    this.distance,
    this.crossings,
  );
}

class _LinesTabState extends State<LinesTab> {
  int selected = 0;
  double tolerance = 0;
  RangeValues sliceRange = const RangeValues(0.2, 0.6);
  double alongFraction = 0.4;
  LatLng probe = const LatLng(52.527, 13.40);

  /// The tram lines, then the Ring's boundary as a line.
  late final List<Feature<LineString>> lines = [
    ...widget.data.tramLines,
    Feature<LineString>(
      geometry: LineString(
        coordinates: widget.data.ring.geometry!.coordinates[0],
      ),
      properties: {'name': 'Ring'},
    ),
  ];

  String _name(int i) => '${lines[i].properties?['name'] ?? 'line ${i + 1}'}';

  _LineResult _compute() {
    final line = lines[selected];
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
    final crossings = <Feature<Point>>[
      for (var i = 0; i < lines.length; i++)
        if (i != selected) ...lineIntersect(line, lines[i]).features,
    ];
    return _LineResult(
      len,
      simplified,
      slice,
      at,
      nearest,
      distance,
      crossings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (r, ms) = timed(_compute);
    final original = lines[selected].geometry!.coordinates.length;
    return DemoMap(
      stats: OpStats(
        ms,
        r.simplified.geometry!.coordinates.length,
        '${r.length.toStringAsFixed(2)} km long · '
        'simplify kept ${r.simplified.geometry!.coordinates.length} of '
        '$original vertices · ${r.crossings.length} crossings',
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
          DropdownButton<int>(
            value: selected,
            items: [
              for (var i = 0; i < lines.length; i++)
                DropdownMenuItem(value: i, child: Text(_name(i))),
            ],
            onChanged: (v) => setState(() => selected = v ?? selected),
          ),
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
          const LegendDot(Colors.black, 'lineIntersect'),
        ],
      ),
      layers: [
        fm.PolylineLayer(
          polylines: [
            for (var i = 0; i < lines.length; i++)
              if (i != selected)
                ...toMapPolylines(
                  lines[i],
                  color: Colors.grey.shade500,
                  width: 2,
                ),
            ...toMapPolylines(
              lines[selected],
              color: Colors.blueGrey.shade200,
              width: 7,
            ),
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
            for (final c in r.crossings)
              fm.CircleMarker(
                point: toLatLng(c.geometry!.coordinates),
                radius: 6,
                color: Colors.transparent,
                borderColor: Colors.black,
                borderStrokeWidth: 2,
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
