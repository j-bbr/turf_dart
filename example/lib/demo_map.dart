// The map every tab draws on: no tiles, a neutral background, a 0.01°
// graticule (by default), the sample data note, a status bar with the computation time
// and vertex count of the current result, and a benchmark button.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' show BBox;

import 'sample_data.dart';

/// Timing of the current operation, shown in the status bar.
class OpStats {
  final double ms;
  final int vertices;
  final String? note;

  const OpStats(this.ms, this.vertices, [this.note]);
}

/// Runs [op] and returns its result with the elapsed milliseconds.
(T, double) timed<T>(T Function() op) {
  final sw = Stopwatch()..start();
  final result = op();
  return (result, sw.elapsedMicroseconds / 1000);
}

/// The median of 100 runs of [op], in milliseconds.
double benchmarkMedian(void Function() op, {int runs = 100}) {
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    op();
    times.add(sw.elapsedMicroseconds / 1000);
  }
  times.sort();
  return times[runs ~/ 2];
}

/// Graticule lines every [step] degrees over [box].
List<Polyline> graticule(BBox box, double step) {
  final lines = <Polyline>[];
  Polyline line(LatLng a, LatLng b) => Polyline(
    points: [a, b],
    color: const Color(0x22000000),
    strokeWidth: 0.5,
  );
  for (var lng = box.lng1.toDouble(); lng <= box.lng2 + 1e-9; lng += step) {
    lines.add(
      line(LatLng(box.lat1.toDouble(), lng), LatLng(box.lat2.toDouble(), lng)),
    );
  }
  for (var lat = box.lat1.toDouble(); lat <= box.lat2 + 1e-9; lat += step) {
    lines.add(
      line(LatLng(lat, box.lng1.toDouble()), LatLng(lat, box.lng2.toDouble())),
    );
  }
  return lines;
}

final List<Polyline> _cityGraticule = graticule(SampleData.frameBox, 0.01);

class DemoMap extends StatelessWidget {
  final List<Widget> layers;
  final OpStats? stats;
  final VoidCallback? onBenchmark;
  final TapCallback? onTap;
  final Widget? controls;
  final MapController? controller;
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;

  /// The initial view; the sample data's city by default.
  final LatLng initialCenter;
  final double initialZoom;
  final double minZoom;

  /// Background grid lines; a 0.01° graticule over the city by default.
  final List<Polyline>? grid;

  const DemoMap({
    super.key,
    required this.layers,
    this.stats,
    this.onBenchmark,
    this.onTap,
    this.controls,
    this.controller,
    this.onPositionChanged,
    this.initialCenter = SampleData.center,
    this.initialZoom = 12,
    this.minZoom = 9,
    this.grid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (controls != null)
          Material(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: controls,
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: initialZoom,
                  minZoom: minZoom,
                  maxZoom: 19,
                  backgroundColor: const Color(0xFFF1EFE9),
                  onTap: onTap,
                  onPositionChanged: onPositionChanged,
                ),
                children: [
                  PolylineLayer(polylines: grid ?? _cityGraticule),
                  ...layers,
                ],
              ),
              Positioned(
                right: 6,
                bottom: 4,
                child: Text(
                  'Sample shapes: approximate, hand-made',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
        Material(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stats == null
                        ? '—'
                        : '${stats!.ms.toStringAsFixed(2)} ms · '
                              '${stats!.vertices} vertices'
                              '${stats!.note == null ? '' : ' · ${stats!.note}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (onBenchmark != null)
                  TextButton.icon(
                    onPressed: onBenchmark,
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('Benchmark ×100'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A draggable vertex handle for a [MarkerLayer].
Marker dragHandle(
  LatLng point,
  ValueChanged<LatLng> onMoved, {
  Color color = Colors.deepOrange,
  double size = 18,
}) => Marker(
  point: point,
  width: size,
  height: size,
  child: _DragHandle(point: point, onMoved: onMoved, color: color),
);

class _DragHandle extends StatelessWidget {
  final LatLng point;
  final ValueChanged<LatLng> onMoved;
  final Color color;

  const _DragHandle({
    required this.point,
    required this.onMoved,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final offset = camera.latLngToScreenOffset(point) + d.delta;
        onMoved(camera.screenOffsetToLatLng(offset));
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

/// Shows a snackbar with a benchmark result.
void showBenchmark(BuildContext context, String name, double medianMs) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$name: median ${medianMs.toStringAsFixed(2)} ms of 100 runs',
      ),
    ),
  );
}

/// A slider with a fixed-width label in front of it.
class LabeledSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int? divisions;
  final double labelWidth;
  final ValueChanged<double> onChanged;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.labelWidth = 110,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: labelWidth, child: Text(label)),
      SizedBox(
        width: 180,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

/// A switch with a label.
class LabeledSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const LabeledSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      Text(label),
    ],
  );
}

/// A small coloured dot and a label, for legends.
class LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const LegendDot(this.color, this.label, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
