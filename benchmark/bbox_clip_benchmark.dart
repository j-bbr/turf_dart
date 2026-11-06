import 'package:benchmark/benchmark.dart';
import 'package:turf/turf.dart';

final Feature<Polygon> area = circle(
  Feature(geometry: Point(coordinates: Position(13.4050, 52.5200))),
  8,
  steps: 2000,
);

// Compass: the area north of the player's latitude
final BBox north = BBox(13.0, 52.5250, 13.8, 52.7);

void main() {
  group('bboxClip', () {
    benchmark('2,000-vertex polygon, half-plane', () {
      bboxClip(area, north);
    });
  });
}
