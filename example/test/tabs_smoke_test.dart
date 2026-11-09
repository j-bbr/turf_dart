// Opens every tab and exercises its main interaction, without exceptions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turf_example/main.dart';

void main() {
  testWidgets('every tab renders and computes', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DemoApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    const tabs = [
      'measure',
      'lines',
      'geodesic',
      'transform',
      'circle',
      'intersect / difference / union',
      'mask',
      'bboxClip',
      'voronoi',
    ];
    expect(find.byType(Tab), findsNWidgets(tabs.length));
    for (final tab in tabs) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(find.textContaining(' ms · '), findsOneWidget, reason: tab);
      expect(tester.takeException(), isNull, reason: tab);
    }

    // clip tab: every operation
    await tester.tap(
      find.widgetWithText(Tab, 'intersect / difference / union'),
    );
    await tester.pumpAndSettle();
    for (final op in ['difference', 'union', 'intersect']) {
      await tester.tap(find.text(op).last);
      await tester.pumpAndSettle();
    }

    // lines tab: simplify, along and the slice
    await tester.tap(find.widgetWithText(Tab, 'lines'));
    await tester.pumpAndSettle();
    expect(find.text('M10'), findsOneWidget);
    for (final slider in find.byType(Slider).evaluate().toList()) {
      await tester.drag(find.byWidget(slider.widget), const Offset(60, 0));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);

    // transform tab: rotate and smooth further
    await tester.tap(find.widgetWithText(Tab, 'transform'));
    await tester.pumpAndSettle();
    for (final slider in find.byType(Slider).evaluate().toList()) {
      await tester.drag(find.byWidget(slider.widget), const Offset(50, 0));
      await tester.pumpAndSettle();
    }

    // geodesic tab: long distances in every direction cross the antimeridian
    await tester.tap(find.widgetWithText(Tab, 'geodesic'));
    await tester.pumpAndSettle();
    for (final dx in [-400.0, 400.0, -150.0]) {
      await tester.drag(find.byType(Slider).first, Offset(dx, 0));
      await tester.drag(find.byType(Slider).last, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'geodesic $dx');
    }

    // voronoi tab: clip the probe's cell to a circle
    await tester.tap(find.widgetWithText(Tab, 'voronoi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('nearestPoint'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
