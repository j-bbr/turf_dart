import 'package:flutter/material.dart';

import 'sample_data.dart';
import 'tabs/bbox_clip_tab.dart';
import 'tabs/circle_tab.dart';
import 'tabs/clip_tab.dart';
import 'tabs/geodesic_tab.dart';
import 'tabs/lines_tab.dart';
import 'tabs/mask_tab.dart';
import 'tabs/measure_tab.dart';
import 'tabs/transform_tab.dart';
import 'tabs/voronoi_tab.dart';

void main() => runApp(const DemoApp());

/// The tabs, in order: their labels and pages.
List<(String, Widget)> demoTabs(SampleData data) => [
  ('measure', const MeasureTab()),
  ('lines', LinesTab(data: data)),
  ('geodesic', const GeodesicTab()),
  ('transform', TransformTab(data: data)),
  ('circle', const CircleTab()),
  ('intersect / difference / union', ClipTab(data: data)),
  ('mask', MaskTab(data: data)),
  ('bboxClip', BboxClipTab(data: data)),
  ('voronoi', VoronoiTab(data: data)),
];

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'turf_dart examples',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: FutureBuilder<SampleData>(
      future: SampleData.load(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('${snapshot.error}')));
        }
        final data = snapshot.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _Tabs(data: data);
      },
    ),
  );
}

class _Tabs extends StatelessWidget {
  final SampleData data;

  const _Tabs({required this.data});

  @override
  Widget build(BuildContext context) {
    final tabs = demoTabs(data);
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('turf_dart examples'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final (label, _) in tabs) Tab(text: label)],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final (_, page) in tabs) page],
        ),
      ),
    );
  }
}
