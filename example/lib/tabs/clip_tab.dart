import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

enum ClipOp { intersect, difference, union }

enum ClipPreset { ringAndCircle, overlappingSquares, shapeWithHole }

/// `polygonIntersect` / `difference` / `union` of two shapes with draggable
/// vertices.
class ClipTab extends StatefulWidget {
  final SampleData data;

  const ClipTab({super.key, required this.data});

  @override
  State<ClipTab> createState() => _ClipTabState();
}

class _ClipTabState extends State<ClipTab> {
  ClipOp op = ClipOp.intersect;
  ClipPreset preset = ClipPreset.ringAndCircle;

  /// Rings of shape A and shape B, without the closing position.
  late List<List<LatLng>> a;
  late List<List<LatLng>> b;
  LatLng circleCenter = const LatLng(52.5486, 13.3886);

  @override
  void initState() {
    super.initState();
    _loadPreset();
  }

  List<LatLng> _open(List<Position> ring) =>
      ringToLatLngs(ring.sublist(0, ring.length - 1));

  List<LatLng> _square(double lat, double lng, double size) => [
    LatLng(lat, lng),
    LatLng(lat, lng + size * 1.6),
    LatLng(lat + size, lng + size * 1.6),
    LatLng(lat + size, lng),
  ];

  void _loadPreset() {
    switch (preset) {
      case ClipPreset.ringAndCircle:
        a = [_open(widget.data.ring.geometry!.coordinates[0])];
        b = [];
        break;
      case ClipPreset.overlappingSquares:
        a = [_square(52.49, 13.33, 0.04)];
        b = [_square(52.51, 13.37, 0.04)];
        break;
      case ClipPreset.shapeWithHole:
        a = [
          _square(52.48, 13.32, 0.07),
          _square(52.50, 13.35, 0.03).reversed.toList(),
        ];
        b = [_square(52.52, 13.39, 0.05)];
        break;
    }
  }

  Feature<Polygon> _shape(List<List<LatLng>> rings) => Feature(
    geometry: Polygon(
      coordinates: [
        for (final r in rings) [...r.map(toPosition), toPosition(r.first)],
      ],
    ),
  );

  Feature<Polygon> get shapeA => _shape(a);

  Feature<Polygon> get shapeB => preset == ClipPreset.ringAndCircle
      ? circle(pointFeature(circleCenter), 1, steps: 64)
      : _shape(b);

  Feature<GeometryObject>? _compute() {
    final fc = FeatureCollection(features: [shapeA, shapeB]);
    switch (op) {
      case ClipOp.intersect:
        return polygonIntersect(fc);
      case ClipOp.difference:
        return difference(fc);
      case ClipOp.union:
        return union(fc);
    }
  }

  List<fm.Marker> _handles(List<List<LatLng>> rings, Color color) => [
    for (var r = 0; r < rings.length; r++)
      for (var i = 0; i < rings[r].length; i++)
        dragHandle(
          rings[r][i],
          (p) => setState(() => rings[r][i] = p),
          color: color,
          size: 12,
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final (result, ms) = timed(_compute);
    return DemoMap(
      stats: OpStats(
        ms,
        vertexCount(result),
        result == null ? 'empty (null)' : result.geometry!.type.name,
      ),
      onBenchmark: () =>
          showBenchmark(context, op.name, benchmarkMedian(_compute)),
      controls: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<ClipOp>(
            segments: const [
              ButtonSegment(value: ClipOp.intersect, label: Text('intersect')),
              ButtonSegment(
                value: ClipOp.difference,
                label: Text('difference'),
              ),
              ButtonSegment(value: ClipOp.union, label: Text('union')),
            ],
            selected: {op},
            onSelectionChanged: (s) => setState(() => op = s.first),
          ),
          DropdownButton<ClipPreset>(
            value: preset,
            items: const [
              DropdownMenuItem(
                value: ClipPreset.ringAndCircle,
                child: Text('Ring + circle'),
              ),
              DropdownMenuItem(
                value: ClipPreset.overlappingSquares,
                child: Text('Overlapping squares'),
              ),
              DropdownMenuItem(
                value: ClipPreset.shapeWithHole,
                child: Text('Shape with a hole'),
              ),
            ],
            onChanged: (p) => setState(() {
              preset = p!;
              _loadPreset();
            }),
          ),
          const Text('Drag the vertices.'),
        ],
      ),
      layers: [
        fm.PolygonLayer(
          polygons: [
            ...toMapPolygons(
              result,
              fill: Colors.green.withValues(alpha: 0.45),
              border: Colors.green.shade800,
              borderWidth: 2.5,
            ),
            ...toMapPolygons(shapeA, border: Colors.red, borderWidth: 1),
            ...toMapPolygons(shapeB, border: Colors.blue, borderWidth: 1),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            ..._handles(a, Colors.red),
            if (preset == ClipPreset.ringAndCircle)
              dragHandle(
                circleCenter,
                (p) => setState(() => circleCenter = p),
                color: Colors.blue,
              )
            else
              ..._handles(b, Colors.blue),
          ],
        ),
      ],
    );
  }
}
