// The embedded fixture files (test/fixtures/*_fixtures.g.dart) must match
// the GeoJSON files they were generated from. Regenerate them with
// `dart run tool/embed_fixtures.dart`.
@TestOn('vm')
library test_components_embedded_fixtures_test;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/embed_fixtures.dart' as embed;

void main() {
  for (final module in embed.embeddedModules()) {
    test('$module fixtures are up to date', () {
      final current = File(embed.outputPath(module)).readAsStringSync();
      expect(current == embed.generate(module), isTrue,
          reason: 'run `dart run tool/embed_fixtures.dart $module`');
    });
  }
}
