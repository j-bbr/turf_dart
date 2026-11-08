import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';
import '../sample_data.dart';

/// `bboxClip`: a draggable, resizable rectangle over the Ring and the tram
/// lines.
class BboxClipTab extends StatefulWidget {
  final SampleData data;

  const BboxClipTab({super.key, required this.data});

  @override
  State<BboxClipTab> createState() => _BboxClipTabState();
}

class _BboxClipTabState extends State<BboxClipTab> {
  LatLng sw = const LatLng(52.49, 13.36);
  LatLng ne = const LatLng(52.535, 13.43);

  BBox get box => BBox(
    sw.longitude < ne.longitude ? sw.longitude : ne.longitude,
    sw.latitude < ne.latitude ? sw.latitude : ne.latitude,
    sw.longitude < ne.longitude ? ne.longitude : sw.longitude,
    sw.latitude < ne.latitude ? ne.latitude : sw.latitude,
  );

  List<Feature<GeometryObject>> _compute() => [
    bboxClip(widget.data.ring, box),
    for (final line in widget.data.tramLines) bboxClip(line, box),
  ];

  LatLng get center => LatLng(
    (sw.latitude + ne.latitude) / 2,
    (sw.longitude + ne.longitude) / 2,
  );

  void _move(LatLng p) {
    final c = center;
    final dLat = p.latitude - c.latitude, dLng = p.longitude - c.longitude;
    setState(() {
      sw = LatLng(sw.latitude + dLat, sw.longitude + dLng);
      ne = LatLng(ne.latitude + dLat, ne.longitude + dLng);
    });
  }

  @override
  Widget build(BuildContext context) {
    final (clipped, ms) = timed(_compute);
    var vertices = 0;
    for (final f in clipped) {
      vertices += vertexCount(f);
    }
    return DemoMap(
      stats: OpStats(ms, vertices),
      onBenchmark: () =>
          showBenchmark(context, 'bboxClip', benchmarkMedian(_compute)),
      controls: const Text(
        'Drag the corners to resize and the centre to move the rectangle.',
      ),
      layers: [
        fm.PolygonLayer(
          polygons: [
            ...toMapPolygons(
              widget.data.ring,
              border: Colors.grey,
              borderWidth: 1,
            ),
            ...toMapPolygons(
              boxPolygon(sw, ne),
              border: Colors.deepOrange,
              borderWidth: 1,
            ),
            ...toMapPolygons(
              clipped.first,
              fill: Colors.green.withValues(alpha: 0.35),
              border: Colors.green.shade800,
              borderWidth: 2,
            ),
          ],
        ),
        fm.PolylineLayer(
          polylines: [
            for (final line in widget.data.tramLines)
              ...toMapPolylines(line, color: Colors.grey, width: 2),
            for (final line in clipped.skip(1))
              ...toMapPolylines(line, color: Colors.red.shade700, width: 4),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            dragHandle(sw, (p) => setState(() => sw = p)),
            dragHandle(ne, (p) => setState(() => ne = p)),
            dragHandle(center, _move, color: Colors.deepPurple),
          ],
        ),
      ],
    );
  }
}
