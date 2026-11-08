// Writes the inputs of the shapely reference cases to
// test/examples/shapely_reference/in. Each case is a FeatureCollection: the
// first feature is the starting polygon, every further feature one operation
// applied to the running result, with `"op": "intersect"` or `"difference"`.
//
// tool/reference/make_reference.py computes the expected results with
// shapely. Run both after changing a case:
//
//   dart run tool/reference/make_inputs.dart
//   python3 tool/reference/make_reference.py
//   dart run tool/embed_fixtures.dart shapely_reference
import 'dart:convert';
import 'dart:io';

import 'package:turf/turf.dart';

/// A simplified S-Bahn Ring (Berlin): its 27 stations, approximately, in
/// counter-clockwise order. Hand-made for tests, not survey data.
final List<Position> sBahnRing = [
  Position(13.2834, 52.5011), // Westkreuz
  Position(13.2903, 52.4964), // Halensee
  Position(13.3006, 52.4887), // Hohenzollerndamm
  Position(13.3122, 52.4800), // Heidelberger Platz
  Position(13.3287, 52.4776), // Bundesplatz
  Position(13.3434, 52.4783), // Innsbrucker Platz
  Position(13.3512, 52.4774), // Schöneberg
  Position(13.3655, 52.4757), // Südkreuz
  Position(13.3852, 52.4706), // Tempelhof
  Position(13.4316, 52.4675), // Hermannstraße
  Position(13.4428, 52.4693), // Neukölln
  Position(13.4547, 52.4728), // Sonnenallee
  Position(13.4614, 52.4934), // Treptower Park
  Position(13.4691, 52.5030), // Ostkreuz
  Position(13.4754, 52.5137), // Frankfurter Allee
  Position(13.4648, 52.5236), // Storkower Straße
  Position(13.4549, 52.5291), // Landsberger Allee
  Position(13.4386, 52.5404), // Greifswalder Straße
  Position(13.4271, 52.5445), // Prenzlauer Allee
  Position(13.4141, 52.5492), // Schönhauser Allee
  Position(13.3886, 52.5486), // Gesundbrunnen
  Position(13.3661, 52.5428), // Wedding
  Position(13.3439, 52.5364), // Westhafen
  Position(13.3290, 52.5345), // Beusselstraße
  Position(13.2995, 52.5306), // Jungfernheide
  Position(13.2844, 52.5180), // Westend
  Position(13.2836, 52.5072), // Messe Nord/ICC
  Position(13.2834, 52.5011), // Westkreuz
];

/// The frame the half-planes are clipped to.
final BBox frame = BBox(13.0, 52.3, 13.8, 52.7);

Feature<Polygon> ring() =>
    Feature(geometry: Polygon(coordinates: [sBahnRing]), properties: {});

Feature<Polygon> circleOp(double lng, double lat, double km, String op) {
  final c = circle(
      Feature(geometry: Point(coordinates: Position(lng, lat))), km,
      steps: 64);
  return Feature(geometry: c.geometry, properties: {'op': op});
}

Feature<Polygon> box(num west, num south, num east, num north, String op) =>
    Feature(
      geometry: Polygon(coordinates: [
        [
          Position(west, south),
          Position(east, south),
          Position(east, north),
          Position(west, north),
          Position(west, south),
        ]
      ]),
      properties: {'op': op},
    );

/// The part of the frame north (or south, east, west) of [value].
Feature<Polygon> halfPlane(String side, double value) {
  switch (side) {
    case 'north':
      return box(frame.lng1, value, frame.lng2, frame.lat2, 'intersect');
    case 'south':
      return box(frame.lng1, frame.lat1, frame.lng2, value, 'intersect');
    case 'east':
      return box(value, frame.lat1, frame.lng2, frame.lat2, 'intersect');
    default:
      return box(frame.lng1, frame.lat1, value, frame.lat2, 'intersect');
  }
}

/// The part of the frame closer to [to] than to [from]
/// (planar), as a polygon.
Feature<Polygon> bisectorHalfPlane(Position from, Position to) {
  final mx = (from.lng + to.lng) / 2, my = (from.lat + to.lat) / 2;
  final nx = to.lng - from.lng, ny = to.lat - from.lat;
  bool inside(Position p) => (p.lng - mx) * nx + (p.lat - my) * ny >= 0;
  Position cut(Position a, Position b) {
    final da = (a.lng - mx) * nx + (a.lat - my) * ny;
    final db = (b.lng - mx) * nx + (b.lat - my) * ny;
    final t = da / (da - db);
    return Position(a.lng + (b.lng - a.lng) * t, a.lat + (b.lat - a.lat) * t);
  }

  final corners = [
    Position(frame.lng1, frame.lat1),
    Position(frame.lng2, frame.lat1),
    Position(frame.lng2, frame.lat2),
    Position(frame.lng1, frame.lat2),
  ];
  final out = <Position>[];
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    if (inside(a)) out.add(a);
    if (inside(a) != inside(b)) out.add(cut(a, b));
  }
  return Feature(
    geometry: Polygon(coordinates: [
      [...out, out.first]
    ]),
    properties: {'op': 'intersect'},
  );
}

Map<String, List<Feature>> cases() => {
      // S-Bahn Ring polygon ∩ 1 km circle across the ring line
      'ring_intersect_circle': [
        ring(),
        circleOp(13.3886, 52.5486, 1, 'intersect'), // around Gesundbrunnen
      ],
      // Ring − a circle fully inside it: one polygon with one hole
      'ring_difference_inner_circle': [
        ring(),
        circleOp(13.4132, 52.5219, 1, 'difference'), // around Alexanderplatz
      ],
      // Ring ∩ the half-plane north of a latitude
      'ring_intersect_half_plane': [
        ring(),
        halfPlane('north', 52.52),
      ],
      // An intersection that empties the result
      'ring_intersect_far_circle': [
        ring(),
        circleOp(13.70, 52.40, 1, 'intersect'),
      ],
      // Ten chained operations
      'ten_chained_operations': [
        ring(),
        circleOp(13.4000, 52.5200, 3, 'intersect'),
        circleOp(13.4200, 52.5300, 1, 'difference'),
        halfPlane('north', 52.5050),
        bisectorHalfPlane(
            Position(13.3500, 52.5100), Position(13.3900, 52.5150)),
        circleOp(13.3950, 52.5250, 0.5, 'difference'),
        circleOp(13.4050, 52.5180, 2, 'intersect'),
        halfPlane('west', 13.4300),
        circleOp(13.3880, 52.5120, 0.3, 'difference'),
        bisectorHalfPlane(
            Position(13.4300, 52.5400), Position(13.4000, 52.5200)),
        circleOp(13.4100, 52.5100, 0.8, 'difference'),
      ],
    };

void main() {
  final encoder = JsonEncoder.withIndent('  ');
  cases().forEach((name, features) {
    final file = File('test/examples/shapely_reference/in/$name.geojson');
    file.writeAsStringSync(
        '${encoder.convert(FeatureCollection(features: features).toJson())}\n');
    stdout.writeln('wrote ${file.path}');
  });
}
