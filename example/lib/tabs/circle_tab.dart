import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// `circle`: tap a centre; sliders for radius and steps.
class CircleTab extends StatefulWidget {
  const CircleTab({super.key});

  @override
  State<CircleTab> createState() => _CircleTabState();
}

class _CircleTabState extends State<CircleTab> {
  LatLng center = SampleData.center;
  double radiusM = 1000;
  double steps = 64;

  Feature<Polygon> _compute() => circle(
    pointFeature(center),
    radiusM,
    steps: steps.round(),
    unit: Unit.meters,
  );

  @override
  Widget build(BuildContext context) {
    final (result, ms) = timed(_compute);
    return DemoMap(
      onTap: (_, p) => setState(() => center = p),
      stats: OpStats(ms, vertexCount(result)),
      onBenchmark: () =>
          showBenchmark(context, 'circle', benchmarkMedian(_compute)),
      controls: Wrap(
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Tap to set the centre.'),
          LabeledSlider(
            label: 'radius ${radiusM.round()} m',
            value: radiusM,
            min: 100,
            max: 5000,
            onChanged: (v) => setState(() => radiusM = v),
          ),
          LabeledSlider(
            label: 'steps ${steps.round()}',
            value: steps,
            min: 8,
            max: 128,
            divisions: 120,
            onChanged: (v) => setState(() => steps = v),
          ),
        ],
      ),
      layers: [
        fm.PolygonLayer(
          polygons: toMapPolygons(
            result,
            fill: Colors.blue.withValues(alpha: 0.25),
            border: Colors.blue,
          ),
        ),
        fm.CircleLayer(
          circles: [
            for (final p in result.geometry!.coordinates[0])
              fm.CircleMarker(
                point: toLatLng(p),
                radius: 3,
                color: Colors.blue,
              ),
          ],
        ),
        fm.MarkerLayer(
          markers: [dragHandle(center, (p) => setState(() => center = p))],
        ),
      ],
    );
  }
}
