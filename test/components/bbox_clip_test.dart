import 'dart:convert';

import 'package:test/test.dart';
import 'package:turf/turf.dart';

import '../context/geometry_matcher.dart';
import '../fixtures/bbox_clip_fixtures.g.dart';

void _expectLinesClose(List<List<Position>> actual, List<dynamic> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < actual.length; i++) {
    final line = expected[i] as List;
    expect(actual[i], hasLength(line.length));
    for (var j = 0; j < line.length; j++) {
      expect(actual[i][j].lng, closeTo((line[j][0] as num).toDouble(), 1e-9));
      expect(actual[i][j].lat, closeTo((line[j][1] as num).toDouble(), 1e-9));
    }
  }
}

Feature<Polygon> _square(num x, num y, num size) => Feature(
      geometry: Polygon(coordinates: [
        [
          Position(x, y),
          Position(x + size, y),
          Position(x + size, y + size),
          Position(x, y + size),
          Position(x, y),
        ]
      ]),
    );

void main() {
  group('bboxClip', () {
    group('turf.js fixtures', () {
      final names = bboxClipFixtures.keys
          .where((k) => k.startsWith('in/'))
          .map((k) => k.substring(3))
          .toList()
        ..sort();
      for (final name in names) {
        test(name, () {
          final input = FeatureCollection.fromJson(
              jsonDecode(bboxClipFixtures['in/$name']!)
                  as Map<String, dynamic>);
          final out = jsonDecode(bboxClipFixtures['out/$name']!);
          final expected = (out['features'] as List)[1]['geometry'];

          final clipped = bboxClip(input.features[0], bbox(input.features[1]));
          final geom = clipped.geometry!;
          expect(geom.type.name.toLowerCase(),
              (expected['type'] as String).toLowerCase());
          final coords = expected['coordinates'] as List;
          if (geom is LineString) {
            _expectLinesClose([geom.coordinates], [coords]);
          } else if (geom is MultiLineString) {
            _expectLinesClose(geom.coordinates, coords);
          } else if (geom is Polygon && coords.isEmpty) {
            expect(geom.coordinates, isEmpty);
          } else {
            expect(
                polygonalCoords(geom), matchesCoords(coordsFromJson(coords)));
          }
        });
      }
    });

    test('keeps properties', () {
      final f = _square(0, 0, 10)..properties = {'name': 'a'};
      expect(bboxClip(f, BBox(2, 2, 5, 5)).properties, {'name': 'a'});
    });

    test('accepts a bare geometry', () {
      final clipped = bboxClip(_square(0, 0, 10).geometry!, BBox(2, 2, 5, 5));
      expect(clipped.geometry, isA<Polygon>());
    });

    test('a polygon enclosing the bbox clips to the bbox', () {
      final clipped = bboxClip(_square(-10, -10, 30), BBox(0, 0, 5, 5));
      expect(
          polygonalCoords(clipped),
          matchesCoords([
            [
              [
                Position(0, 0),
                Position(5, 0),
                Position(5, 5),
                Position(0, 5),
                Position(0, 0),
              ]
            ]
          ]));
    });

    test('keeps holes inside the bbox and drops holes outside', () {
      final poly = Feature(
          geometry: Polygon(coordinates: [
        _square(0, 0, 10).geometry!.coordinates[0],
        // hole inside the bbox (clockwise)
        [
          Position(1, 1),
          Position(1, 2),
          Position(2, 2),
          Position(2, 1),
          Position(1, 1),
        ],
        // hole outside the bbox
        [
          Position(7, 7),
          Position(7, 8),
          Position(8, 8),
          Position(8, 7),
          Position(7, 7),
        ],
      ]));
      final clipped = bboxClip(poly, BBox(0, 0, 5, 5));
      expect((clipped.geometry as Polygon).coordinates, hasLength(2));
    });

    test('a polygon outside the bbox has no rings', () {
      final clipped = bboxClip(_square(20, 20, 1), BBox(0, 0, 5, 5));
      expect((clipped.geometry as Polygon).coordinates, isEmpty);
    });

    test('Compass half-plane: frame clipped at the player latitude', () {
      final frame = _square(13, 52.3, 0.6);
      final north = bboxClip(frame, BBox(13, 52.52, 13.6, 52.9));
      final ring = (north.geometry as Polygon).coordinates[0];
      for (final p in ring) {
        expect(p.lat, greaterThanOrEqualTo(52.52));
      }
      expect(ring.skip(1).where((p) => p.lat == 52.52), hasLength(2));
    });

    test('a line leaving and re-entering gives a MultiLineString', () {
      final line = Feature(
          geometry: LineString(coordinates: [
        Position(1, 1),
        Position(8, 1),
        Position(8, 4),
        Position(1, 4),
      ]));
      final clipped = bboxClip(line, BBox(0, 0, 5, 5));
      expect(clipped.geometry, isA<MultiLineString>());
      expect((clipped.geometry as MultiLineString).coordinates, hasLength(2));
    });

    test('throws for points', () {
      expect(
          () => bboxClip(Feature(geometry: Point(coordinates: Position(1, 1))),
              BBox(0, 0, 5, 5)),
          throwsArgumentError);
    });
  });
}
