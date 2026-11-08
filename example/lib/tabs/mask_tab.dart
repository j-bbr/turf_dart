import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// `mask`: a polygon with a hole (the Ring minus a circle) inside the frame,
/// with and without `keepHoles`.
class MaskTab extends StatefulWidget {
  final SampleData data;

  const MaskTab({super.key, required this.data});

  @override
  State<MaskTab> createState() => _MaskTabState();
}

class _MaskTabState extends State<MaskTab> {
  bool keepHoles = true;
  LatLng hole = const LatLng(52.5219, 13.4132);
  double radiusKm = 1;

  Feature<GeometryObject> get polygon => difference(
    FeatureCollection(
      features: [
        widget.data.ring,
        circle(pointFeature(hole), radiusKm, steps: 64),
      ],
    ),
  )!;

  Feature<GeometryObject> _compute(Feature<GeometryObject> shape) =>
      mask(shape, mask: SampleData.frame, keepHoles: keepHoles);

  @override
  Widget build(BuildContext context) {
    final shape = polygon;
    final (shading, ms) = timed(() => _compute(shape));
    return DemoMap(
      stats: OpStats(ms, vertexCount(shading), shading.geometry!.type.name),
      onBenchmark: () => showBenchmark(
        context,
        'mask',
        benchmarkMedian(() => _compute(shape)),
      ),
      controls: Wrap(
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: keepHoles,
                onChanged: (v) => setState(() => keepHoles = v),
              ),
              const Text('keepHoles'),
            ],
          ),
          Text(
            keepHoles
                ? 'The hole is shaded too.'
                : 'turf.js behaviour: the hole stays unshaded.',
          ),
          const Text('Drag the hole.'),
        ],
      ),
      layers: [
        fm.PolygonLayer(
          polygons: [
            ...toMapPolygons(
              shading,
              fill: Colors.black.withValues(alpha: 0.35),
              border: Colors.transparent,
              borderWidth: 0,
            ),
            ...toMapPolygons(shape, border: Colors.green.shade800),
          ],
        ),
        fm.MarkerLayer(
          markers: [dragHandle(hole, (p) => setState(() => hole = p))],
        ),
      ],
    );
  }
}
