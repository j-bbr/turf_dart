import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/fuzz_runs.dart';
import '../context/geometry_matcher.dart';
import '../fixtures/voronoi_fixtures.g.dart';

FeatureCollection<Point> _points(List<List<double>> coords) =>
    FeatureCollection<Point>(features: [
      for (final c in coords)
        Feature<Point>(geometry: Point(coordinates: Position(c[0], c[1])))
    ]);

double _area(Polygon p) =>
    p.coordinates.isEmpty ? 0 : signedArea2(p.coordinates[0]) / 2;

/// One cell per point, every point inside (or on) its own cell, cells
/// counter-clockwise, and the cells tiling the box.
void _expectValidDiagram(FeatureCollection<Point> points,
    FeatureCollection<Polygon> cells, BBox box) {
  expect(cells.features, hasLength(points.features.length));
  var total = 0.0;
  final seen = <String>{};
  for (var i = 0; i < cells.features.length; i++) {
    final cell = cells.features[i].geometry!;
    final p = points.features[i].geometry!.coordinates;
    expectGeoJsonOrientation(polygonalCoords(cell));
    expect(booleanPointInPolygon(p, cell), isTrue,
        reason: 'point $i outside its cell');
    // count the area of duplicated points once
    if (seen.add('${p.lng},${p.lat}')) total += _area(cell);
  }
  final boxArea = (box.lng2 - box.lng1) * (box.lat2 - box.lat1);
  expect(total, closeTo(boxArea, boxArea * 1e-9));
}

void main() {
  group('voronoi', () {
    group('turf.js fixtures', () {
      final names = voronoiFixtures.keys
          .where((k) => k.startsWith('in/'))
          .map((k) => k.substring(3))
          .toList()
        ..sort();
      for (final name in names) {
        test(name, () {
          final json =
              jsonDecode(voronoiFixtures['in/$name']!) as Map<String, dynamic>;
          final input = FeatureCollection<Point>.fromJson(json);
          final bboxJson = json['bbox'] as List?;
          final box = bboxJson == null
              ? null
              : BBox.fromJson(bboxJson.cast<num>().toList());
          final result = voronoi(input, bbox: box);
          final expected = FeatureCollection.fromJson(
              jsonDecode(voronoiFixtures['out/$name']!)
                  as Map<String, dynamic>);

          expect(result.features, hasLength(expected.features.length));
          for (var i = 0; i < result.features.length; i++) {
            // turf.js uses d3-voronoi, which snaps vertices with an
            // epsilon of 1e-6; our vertices are exact circumcenters
            expect(
                polygonalCoords(result.features[i]),
                matchesCoords(polygonalCoords(expected.features[i]),
                    tolerance: 1e-5),
                reason: 'cell $i');
            expect(result.features[i].properties,
                expected.features[i].properties ?? {});
          }
          _expectValidDiagram(input, result, box ?? BBox(-180, -85, 180, 85));
        });
      }
    });

    final box = BBox(13.3, 52.45, 13.5, 52.55);

    test('2 points', () {
      final pts = _points([
        [13.38, 52.50],
        [13.42, 52.52],
      ]);
      _expectValidDiagram(pts, voronoi(pts, bbox: box), box);
    });

    test('3 points', () {
      final pts = _points([
        [13.38, 52.50],
        [13.42, 52.52],
        [13.45, 52.47],
      ]);
      _expectValidDiagram(pts, voronoi(pts, bbox: box), box);
    });

    test('30 points', () {
      final rnd = Random(30);
      final pts = _points([
        for (var i = 0; i < 30; i++)
          [13.3 + rnd.nextDouble() * 0.2, 52.45 + rnd.nextDouble() * 0.1]
      ]);
      _expectValidDiagram(pts, voronoi(pts, bbox: box), box);
    });

    test('1 point: the whole box', () {
      final pts = _points([
        [13.4, 52.5]
      ]);
      final cells = voronoi(pts, bbox: box);
      expect(_area(cells.features[0].geometry!), closeTo(0.2 * 0.1, 1e-12));
    });

    test('collinear points', () {
      final pts = _points([
        [13.32, 52.50],
        [13.36, 52.50],
        [13.40, 52.50],
        [13.44, 52.50],
      ]);
      _expectValidDiagram(pts, voronoi(pts, bbox: box), box);
    });

    test('duplicate points share a cell', () {
      final pts = _points([
        [13.38, 52.50],
        [13.42, 52.52],
        [13.38, 52.50],
      ]);
      final cells = voronoi(pts, bbox: box);
      expect(polygonalCoords(cells.features[2]),
          matchesCoords(polygonalCoords(cells.features[0])));
      _expectValidDiagram(pts, cells, box);
    });

    test('copies properties', () {
      final pts = _points([
        [13.38, 52.50],
        [13.42, 52.52],
      ]);
      pts.features[0].properties = {'name': 'a'};
      final cells = voronoi(pts, bbox: box);
      expect(cells.features[0].properties, {'name': 'a'});
      expect(cells.features[1].properties, <String, dynamic>{});
    });

    test('no points', () {
      expect(voronoi(_points([]), bbox: box).features, isEmpty);
    });

    // Property: every sample point lies in the cell of its nearest point.
    test('nearest-point property (${fuzzRuns()} runs)', () {
      final runs = fuzzRuns();
      for (var run = 0; run < runs; run++) {
        final rnd = Random(run);
        final n = 2 + rnd.nextInt(40);
        final pts = _points([
          for (var i = 0; i < n; i++)
            [13.3 + rnd.nextDouble() * 0.2, 52.45 + rnd.nextDouble() * 0.1]
        ]);
        final cells = voronoi(pts, bbox: box);
        for (var gx = 0; gx < 20; gx++) {
          for (var gy = 0; gy < 20; gy++) {
            final q = Position(
                13.3 + 0.2 * (gx + 0.5) / 20, 52.45 + 0.1 * (gy + 0.5) / 20);
            // nearest point, skipping near-ties
            var best = -1;
            var bestD = double.infinity, secondD = double.infinity;
            for (var i = 0; i < n; i++) {
              final p = pts.features[i].geometry!.coordinates;
              final d = pow(p.lng - q.lng, 2) + pow(p.lat - q.lat, 2);
              if (d < bestD) {
                secondD = bestD;
                bestD = d.toDouble();
                best = i;
              } else if (d < secondD) {
                secondD = d.toDouble();
              }
            }
            if (secondD - bestD < 1e-12) continue;
            expect(booleanPointInPolygon(q, cells.features[best].geometry!),
                isTrue,
                reason: 'seed $run: $q not in the cell of point $best');
          }
        }
      }
    }, timeout: const Timeout.factor(10));
  });
}
