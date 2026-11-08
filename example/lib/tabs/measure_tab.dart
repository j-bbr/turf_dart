import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart';

import '../convert.dart';
import '../demo_map.dart';

/// Measurements of a polygon with draggable vertices: `area`, `length` of
/// its boundary, `bbox` / `bboxPolygon`, `centroid`, `center`,
/// `centerOfMass`, `pointOnFeature`; and for a draggable probe:
/// `booleanPointInPolygon`, `pointToLineDistance` to the boundary and
/// `polygonTangents`.
class MeasureTab extends StatefulWidget {
  const MeasureTab({super.key});

  @override
  State<MeasureTab> createState() => _MeasureTabState();
}

class _Measures {
  final num area;
  final num perimeter;
  final Feature<Polygon> box;
  final Feature<Point> centroid, center, centerOfMass, pointOnFeature;
  final bool probeInside;
  final num probeDistance;
  final FeatureCollection<Point>? tangents;

  _Measures({
    required this.area,
    required this.perimeter,
    required this.box,
    required this.centroid,
    required this.center,
    required this.centerOfMass,
    required this.pointOnFeature,
    required this.probeInside,
    required this.probeDistance,
    required this.tangents,
  });
}

class _MeasureTabState extends State<MeasureTab> {
  /// A concave "C" shape, so the centres differ visibly. No closing vertex.
  List<LatLng> vertices = const [
    LatLng(52.540, 13.360),
    LatLng(52.545, 13.440),
    LatLng(52.528, 13.445),
    LatLng(52.530, 13.385),
    LatLng(52.505, 13.390),
    LatLng(52.503, 13.448),
    LatLng(52.488, 13.440),
    LatLng(52.492, 13.355),
  ].toList();
  LatLng probe = const LatLng(52.516, 13.465);

  Feature<Polygon> get polygon => Feature<Polygon>(
    geometry: Polygon(
      coordinates: [
        [...vertices.map(toPosition), toPosition(vertices.first)],
      ],
    ),
  );

  _Measures _compute() {
    final poly = polygon;
    final boundary = Feature<LineString>(
      geometry: LineString(coordinates: poly.geometry!.coordinates[0]),
    );
    final probePoint = Point(coordinates: toPosition(probe));
    final inside = booleanPointInPolygon(probePoint.coordinates, poly);
    FeatureCollection<Point>? tangents;
    if (!inside) {
      try {
        tangents = polygonTangents(probePoint, poly);
      } catch (_) {
        tangents = null; // e.g. degenerate shapes while dragging
      }
    }
    return _Measures(
      area: area(poly) ?? 0,
      perimeter: length(boundary),
      box: bboxPolygon(bbox(poly)),
      centroid: centroid(poly),
      center: center(poly),
      centerOfMass: centerOfMass(poly),
      pointOnFeature: pointOnFeature(poly),
      probeInside: inside,
      probeDistance: pointToLineDistance(probePoint, boundary.geometry!),
      tangents: tangents,
    );
  }

  static const _centroidColor = Colors.purple;
  static const _centerColor = Colors.blue;
  static const _massColor = Colors.teal;
  static const _onFeatureColor = Colors.brown;

  @override
  Widget build(BuildContext context) {
    final (m, ms) = timed(_compute);
    final probeText = m.probeInside
        ? 'probe inside, ${m.probeDistance.toStringAsFixed(2)} km from the edge'
        : 'probe outside, ${m.probeDistance.toStringAsFixed(2)} km away';
    return DemoMap(
      stats: OpStats(
        ms,
        vertices.length + 1,
        'area ${(m.area / 1e6).toStringAsFixed(2)} km² · '
        'perimeter ${m.perimeter.toStringAsFixed(2)} km',
      ),
      onBenchmark: () =>
          showBenchmark(context, 'all measurements', benchmarkMedian(_compute)),
      controls: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Drag the vertices and the probe.'),
          const LegendDot(_centroidColor, 'centroid'),
          const LegendDot(_centerColor, 'center (of bbox)'),
          const LegendDot(_massColor, 'centerOfMass'),
          const LegendDot(_onFeatureColor, 'pointOnFeature'),
          LegendDot(Colors.red, probeText),
        ],
      ),
      layers: [
        fm.PolygonLayer(
          polygons: [
            ...toMapPolygons(
              m.box,
              border: Colors.grey.shade600,
              borderWidth: 1,
            ),
            ...toMapPolygons(
              polygon,
              fill: Colors.amber.withValues(alpha: 0.3),
              border: Colors.amber.shade900,
            ),
          ],
        ),
        if (m.tangents != null)
          fm.PolylineLayer(
            polylines: [
              for (final t in m.tangents!.features)
                fm.Polyline(
                  points: [probe, toLatLng(t.geometry!.coordinates)],
                  color: Colors.red,
                  strokeWidth: 1.5,
                  pattern: fm.StrokePattern.dashed(segments: const [6, 4]),
                ),
            ],
          ),
        fm.CircleLayer(
          circles: [
            for (final (p, c) in [
              (m.centroid, _centroidColor),
              (m.center, _centerColor),
              (m.centerOfMass, _massColor),
              (m.pointOnFeature, _onFeatureColor),
            ])
              fm.CircleMarker(
                point: toLatLng(p.geometry!.coordinates),
                radius: 6,
                color: c,
                borderColor: Colors.white,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            for (var i = 0; i < vertices.length; i++)
              dragHandle(
                vertices[i],
                (p) => setState(() => vertices[i] = p),
                color: Colors.amber.shade900,
                size: 14,
              ),
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
