// Voronoi cells computed in Web Mercator (for metric accuracy) and projected
// back to WGS84 still partition the plane by nearest site: a cell clipped to
// a circle contains the positions nearest to its site and no other site.
import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/geometry_matcher.dart';

void main() {
  test('Mercator voronoi cell of the nearest site ∩ circle', () {
    final center = Position(13.4050, 52.5200);
    final sites = [
      Position(13.3977, 52.5169),
      Position(13.3760, 52.5096),
      Position(13.4013, 52.5306),
      Position(13.4280, 52.5150),
      Position(13.3880, 52.5250),
    ];
    final probe = Position(13.3990, 52.5180);
    final radius =
        circle(Feature(geometry: Point(coordinates: center)), 2, steps: 64);

    // the site nearest to the probe, also what nearestPoint finds
    var nearest = 0;
    for (var i = 1; i < sites.length; i++) {
      if (distance(Point(coordinates: probe), Point(coordinates: sites[i])) <
          distance(
              Point(coordinates: probe), Point(coordinates: sites[nearest]))) {
        nearest = i;
      }
    }
    final found = nearestPoint(
      Feature<Point>(geometry: Point(coordinates: probe)),
      FeatureCollection<Point>(features: [
        for (final s in sites) Feature<Point>(geometry: Point(coordinates: s))
      ]),
    );
    expect(found.properties!['featureIndex'], nearest);

    // Voronoi in Web Mercator, cells back to WGS84
    final projected = FeatureCollection<Point>(features: [
      for (final s in sites)
        Feature<Point>(geometry: geoToMercator(Point(coordinates: s)) as Point)
    ]);
    final frame = bbox(geoToMercator(radius));
    final cells = voronoi(projected,
        bbox: BBox(frame.lng1 - 1000, frame.lat1 - 1000, frame.lng2 + 1000,
            frame.lat2 + 1000));
    final cell = geoToWgs84(cells.features[nearest]) as Feature;

    final clipped = polygonIntersect(
        FeatureCollection(features: [radius, cell as Feature<Polygon>]))!;
    expectGeoJsonOrientation(polygonalCoords(clipped));

    expect(booleanPointInPolygon(probe, clipped), isTrue);
    for (var i = 0; i < sites.length; i++) {
      if (i != nearest) {
        expect(booleanPointInPolygon(sites[i], clipped), isFalse);
      }
    }
  });
}
