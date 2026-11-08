import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// Shape operations on the Ring: `transformRotate` around its centroid,
/// `polygonSmooth` (Chaikin), `explode` into vertices, `envelope`, and
/// `booleanIntersects` / `booleanContains` against the original.
class TransformTab extends StatefulWidget {
  final SampleData data;

  const TransformTab({super.key, required this.data});

  @override
  State<TransformTab> createState() => _TransformTabState();
}

class _Transformed {
  final Feature<Polygon> shape;
  final FeatureCollection<Point> vertices;
  final Feature<Polygon> envelope;
  final bool intersects, contains;

  _Transformed(
    this.shape,
    this.vertices,
    this.envelope,
    this.intersects,
    this.contains,
  );
}

class _TransformTabState extends State<TransformTab> {
  double angle = 30;
  double iterations = 2;
  bool showVertices = true;

  _Transformed _compute() {
    final ring = widget.data.ring;
    final rotated = Feature<Polygon>(
      geometry: transformRotate(ring.geometry!, angle) as Polygon,
    );
    var shape = rotated;
    if (iterations > 0) {
      final smoothed = polygonSmooth(rotated, iterations: iterations.round());
      shape = Feature<Polygon>(
        geometry: smoothed.features.first.geometry as Polygon,
      );
    }
    return _Transformed(
      shape,
      explode(shape),
      envelope(shape),
      booleanIntersects(shape, ring),
      booleanContains(ring, shape),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (t, ms) = timed(_compute);
    return DemoMap(
      stats: OpStats(
        ms,
        vertexCount(t.shape),
        'booleanIntersects(ring): ${t.intersects} · '
        'booleanContains(ring, shape): ${t.contains}',
      ),
      onBenchmark: () => showBenchmark(
        context,
        'rotate + smooth + explode + envelope',
        benchmarkMedian(_compute),
      ),
      controls: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          LabeledSlider(
            label: 'rotate ${angle.round()}°',
            value: angle,
            min: -180,
            max: 180,
            onChanged: (v) => setState(() => angle = v),
          ),
          LabeledSlider(
            label: 'smooth ×${iterations.round()}',
            value: iterations,
            min: 0,
            max: 5,
            divisions: 5,
            onChanged: (v) => setState(() => iterations = v),
          ),
          LabeledSwitch(
            label: 'explode (vertices)',
            value: showVertices,
            onChanged: (v) => setState(() => showVertices = v),
          ),
          const LegendDot(Colors.grey, 'original'),
          const LegendDot(Colors.deepPurple, 'transformed'),
          const LegendDot(Colors.blueGrey, 'envelope'),
        ],
      ),
      layers: [
        fm.PolygonLayer(
          polygons: [
            ...toMapPolygons(
              t.envelope,
              border: Colors.blueGrey,
              borderWidth: 1,
            ),
            ...toMapPolygons(
              widget.data.ring,
              fill: Colors.grey.withValues(alpha: 0.15),
              border: Colors.grey,
            ),
            ...toMapPolygons(
              t.shape,
              fill: Colors.deepPurple.withValues(alpha: 0.2),
              border: Colors.deepPurple,
              borderWidth: 2,
            ),
          ],
        ),
        if (showVertices)
          fm.CircleLayer(
            circles: [
              for (final v in t.vertices.features)
                fm.CircleMarker(
                  point: toLatLng(v.geometry!.coordinates),
                  radius: 2.5,
                  color: Colors.deepPurple,
                ),
            ],
          ),
      ],
    );
  }
}
