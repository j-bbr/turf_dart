import 'package:benchmark/benchmark.dart';
import 'package:turf/turf.dart';

final Feature<Polygon> frame = Feature(
  geometry: Polygon(coordinates: [
    [
      Position(13.0, 52.3),
      Position(13.8, 52.3),
      Position(13.8, 52.7),
      Position(13.0, 52.7),
      Position(13.0, 52.3),
    ]
  ]),
);

// A polygon with a hole: a 2,000-vertex polygon minus a 64-point circle.
final Feature<GeometryObject> polygonWithHole = difference(FeatureCollection(
  features: [
    circle(Feature(geometry: Point(coordinates: Position(13.405, 52.52))), 8,
        steps: 2000),
    circle(Feature(geometry: Point(coordinates: Position(13.41, 52.52))), 1,
        steps: 64),
  ],
))!;

void main() {
  group('mask', () {
    benchmark('turf.js behaviour', () {
      mask(polygonWithHole, mask: frame);
    });
    benchmark('keepHoles', () {
      mask(polygonWithHole, mask: frame, keepHoles: true);
    });
  });
}
