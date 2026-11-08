import 'dart:math';

import 'package:benchmark/benchmark.dart';
import 'package:turf/turf.dart';

// Brief budget (mid-range phone): 30 points in 10 ms.
final Random _rnd = Random(30);
final FeatureCollection<Point> points = FeatureCollection<Point>(features: [
  for (var i = 0; i < 30; i++)
    Feature<Point>(
      geometry: Point(
        coordinates: Position(
          13.3 + _rnd.nextDouble() * 0.2,
          52.45 + _rnd.nextDouble() * 0.1,
        ),
      ),
    )
]);

final BBox box = BBox(13.3, 52.45, 13.5, 52.55);

void main() {
  group('voronoi', () {
    benchmark('30 points', () {
      voronoi(points, bbox: box);
    });
  });
}
