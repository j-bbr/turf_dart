// Runs turf.js fixtures (in/*.geojson, out/*.geojson) for a polygon
// clipping wrapper, from embedded fixture maps (see tool/embed_fixtures.dart).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:turf/turf.dart';

import 'geometry_matcher.dart';

typedef ClipFn = Feature<GeometryObject>? Function(FeatureCollection fc);

/// For each `in/<name>.geojson` in [fixtures]:
/// * with `out/<name>.geojson`, the result must match it. The expected
///   result is the out file's Feature, or - for turf.js' intersect and
///   difference fixtures, which store the inputs followed by the result -
///   the feature after the inputs (`null` when there is none);
/// * without one, the operation must not throw (regression cases of
///   turf.js issues).
///
/// Names containing `skip` are skipped, as in turf.js.
void runClipFixtures(Map<String, String> fixtures, ClipFn op) {
  final names = fixtures.keys
      .where((k) => k.startsWith('in/'))
      .map((k) => k.substring(3))
      .toList()
    ..sort();
  for (final name in names) {
    final input = FeatureCollection.fromJson(
        _fixPolygonTypes(jsonDecode(fixtures['in/$name']!))
            as Map<String, dynamic>);
    final outSource = fixtures['out/$name'];
    test(name, () {
      final result = op(input);
      if (outSource == null) return;
      final outJson = jsonDecode(outSource);
      GeoJSONObject? expected;
      if (outJson == null) {
        expected = null;
      } else if (outJson['type'] == 'FeatureCollection') {
        final features = outJson['features'] as List;
        expected = features.length > input.features.length
            ? Feature.fromJson(features.last as Map<String, dynamic>)
            : null;
      } else {
        expected = GeoJSONObject.fromJson(outJson as Map<String, dynamic>);
      }

      if (expected == null) {
        expect(result, isNull);
        return;
      }
      expect(result, isNotNull);
      final expectedGeom = (expected as Feature).geometry!;
      expect(result!.geometry!.type, expectedGeom.type);
      final coords = polygonalCoords(result);
      expect(coords,
          matchesCoords(polygonalCoords(expectedGeom), checkOrientation: true));
      expectGeoJsonOrientation(coords);
    }, skip: name.contains('skip'));
  }
}

/// turf.js accepts MultiPolygon coordinates under `"type": "Polygon"` (one
/// fixture relies on it); geotypes does not, so fix the type by nesting
/// depth.
dynamic _fixPolygonTypes(dynamic json) {
  for (final f in (json['features'] as List)) {
    final geom = f['geometry'];
    if (geom == null || geom['type'] != 'Polygon') continue;
    var depth = 0;
    dynamic c = geom['coordinates'];
    while (c is List && c.isNotEmpty) {
      depth++;
      c = c.first;
    }
    if (depth == 4) geom['type'] = 'MultiPolygon';
  }
  return json;
}
