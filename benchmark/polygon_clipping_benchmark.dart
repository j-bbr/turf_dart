import 'package:benchmark/benchmark.dart';
import 'package:turf/turf.dart';

// Budget (mid-range phone): intersect / difference of a polygon with up to
// 2,000 vertices and a 64-point circle in 50 ms.
final Feature<Polygon> polygon = circle(
  Feature(geometry: Point(coordinates: Position(13.4050, 52.5200))),
  8,
  steps: 2000,
);

final Feature<Polygon> disc = circle(
  Feature(geometry: Point(coordinates: Position(13.4300, 52.5300))),
  1,
  steps: 64,
);

final FeatureCollection pair = FeatureCollection(features: [polygon, disc]);

void main() {
  group('polygon clipping (2,000 vertices x 64-point circle)', () {
    benchmark('polygonIntersect', () {
      polygonIntersect(pair);
    });
    benchmark('difference', () {
      difference(pair);
    });
    benchmark('union', () {
      union(pair);
    });
  });
}
