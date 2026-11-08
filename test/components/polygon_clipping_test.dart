// End-to-end cases of polyclip-ts / polygon-clipping, run against the
// clipper core. Fixtures are embedded (see tool/embed_fixtures.dart), so the
// suite runs on the VM and in the browser.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:turf/src/polygon_clipping/polygon_clipping.dart';

import '../context/geometry_matcher.dart';
import '../fixtures/polygon_clipping_fixtures.g.dart';

typedef _Op = Coords Function(Coords, List<Coords>);

final Map<String, _Op> _ops = {
  'union': clipUnion,
  'intersection': clipIntersection,
  'xor': clipXor,
  'difference': clipDifference,
};

void main() {
  group('polygon clipping end to end', () {
    final targets = <String, Map<String, String>>{};
    polygonClippingFixtures.forEach((path, content) {
      final parts = path.split('/');
      targets.putIfAbsent(parts[0], () => {})[parts[1]] = content;
    });

    for (final target in targets.keys.toList()..sort()) {
      final files = targets[target]!;
      final argsJson = jsonDecode(files['args.geojson']!);
      final args = [
        for (final f in argsJson['features'] as List)
          coordsFromJson(f['geometry']['coordinates'] as List)
      ];

      group(target, () {
        for (final name in files.keys.toList()..sort()) {
          if (name == 'args.geojson') continue;
          final opName = name.substring(0, name.length - '.geojson'.length);
          final opNames = opName == 'all' ? _ops.keys.toList() : [opName];
          final resultJson = jsonDecode(files[name]!);
          final options = (resultJson['properties'] ?? {})['options'];
          final expected =
              coordsFromJson(resultJson['geometry']['coordinates'] as List);

          for (final op in opNames) {
            test(op, () {
              final eps = options == null ? null : options['precision'];
              clipSetPrecision(eps == null ? null : (eps as num).toDouble());
              try {
                final result = _ops[op]!(args.first, args.sublist(1));
                expect(result, matchesCoords(expected, checkOrientation: true));
                expectGeoJsonOrientation(result);
              } finally {
                clipSetPrecision(null);
              }
            });
          }
        }
      });
    }
  });
}
