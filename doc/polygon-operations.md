# Polygon operations: implementation notes

This page describes how `polygonIntersect`, `difference`, `union`, `mask`, `bboxClip` and `voronoi` are built, tested and benchmarked, and where they differ from turf.js v7. Paths are relative to the repository root.

## Functions

| Function | turf.js v7 | Dart signature |
| --- | --- | --- |
| `polygonIntersect` | `intersect(fc, {properties})` | `Feature<GeometryObject>? polygonIntersect(FeatureCollection features, {Map<String, dynamic>? properties})` |
| `difference` | `difference(fc)`: the first minus all others | `Feature<GeometryObject>? difference(FeatureCollection features, {Map<String, dynamic>? properties})` |
| `union` | `union(fc, {properties})` | `Feature<GeometryObject>? union(FeatureCollection features, {Map<String, dynamic>? properties})` |
| `mask` | `mask(polygon, mask?)` | `Feature<GeometryObject> mask(GeoJSONObject polygons, {GeoJSONObject? mask, bool keepHoles = false})` |
| `bboxClip` | `bboxClip(feature, bbox)` | `Feature<GeometryObject> bboxClip(GeoJSONObject feature, BBox bbox)` |
| `voronoi` | `voronoi(points, {bbox})` | `FeatureCollection<Polygon> voronoi(FeatureCollection<Point> points, {BBox? bbox})` |

- **Naming:** turf.js' `intersect` is called `polygonIntersect`, because `lib/lineclip.dart` already exports a public `intersect(Position, Position, int, BBox)` helper. The other functions keep their turf.js names.
- **Empty results:** the three clipping functions return `null` for an empty result, as turf.js does.
- **Return type:** a clipping result can be a `Polygon` or a `MultiPolygon`. geotypes has no common supertype for the two, so the return type is `Feature<GeometryObject>`.

## Polygon clipper

`lib/src/polygon_clipping/` is a port of polygon-clipping 0.15.7 with the arithmetic of polyclip-ts 0.16.8, which turf.js v7 uses. It implements the Martinez–Rueda–Feito sweep line, in O((n + k) log n) for n edges and k intersections.

- **Sweep structures:** `SplayTreeSet` and `SplayTreeMap` from `dart:collection` replace splaytree-ts. Its previous/next lookups map to `lastKeyBefore` and `firstKeyAfter`.
- **Precision:** `double` with epsilon is not enough. The double version passes polygon-clipping's own 170 end-to-end cases but fails 43 of polyclip-ts' 199, and 13 of those crash.
  - The clipper therefore computes with a `BigInt` decimal that has bignumber.js semantics: `+`, `−` and `×` are exact, and `div` and `sqrt` are rounded to 20 decimal places, half up. Results match turf.js v7 on the VM and on the web.
  - Each value caches its nearest double, which decides most comparisons and orientation tests (`decimal.dart`). A 2,000-vertex polygon against a 64-point circle takes about 3 ms on the VM and in Chrome.
- **Input and output:** the clipper accepts Polygons, MultiPolygons, and Features or FeatureCollections of them. Output rings are closed and oriented the GeoJSON way: counter-clockwise outer rings and clockwise holes.

## mask

- **Default:** `mask` follows turf.js 7.4.0 exactly. It unions the inputs and cuts only each result polygon's outer ring out of the frame, so holes in the input stay unshaded. It always returns a Polygon.
- **`keepHoles: true`:** returns `frame − polygons`, so holes are shaded too. The result is a Polygon, or a MultiPolygon when a hole contains an island. When the polygons cover the whole frame, the result is an empty MultiPolygon rather than `null`.

## bboxClip

`bboxClip` is a wrapper over the existing `lineclip` and `polygonclip`. It clips every line and every ring, drops rings that vanish, keeps holes and properties, and returns the same geometry type.

It uses Sutherland–Hodgman, so a result can have zero-width slivers along the box edges, as in turf.js. Writing it uncovered a bug in `polygonclip`: a ring that enclosed the box with all of its vertices outside it came back empty. That is fixed.

## voronoi

The triangulation is a port of Delaunator 5.1.0. Its exact `orient2d` is ported from robust-predicates in `lib/src/robust/`. The cells come from a port of d3-delaunay 6.0.6's `Voronoi` class, which clips the unbounded hull cells to the box.

- **Scaling:** d3-delaunay's tolerances assume pixel coordinates. `voronoi` therefore scales the box to about 1,000 units, computes the diagram there and maps the cells back.
- **Output:** one Polygon per input point, in input order, with the point's properties.
- **Coordinates are planar.** For metric accuracy, project with `geoToMercator` first and project the cells back with `geoToWgs84`. The example app does this.

## Deviations from turf.js

- **`voronoi` cells:**
  - Rings are counter-clockwise.
  - Duplicate points share the cell of their first occurrence.
  - Vertices are exact, whereas turf.js' d3-voronoi snaps them to 1e-6. The turf.js fixtures are therefore compared with a 1e-5 tolerance.
- **`mask(keepHoles: true)`** is an addition. turf.js skips two of its own mask fixtures, and they are skipped here too.

## Dependencies and licences

Nothing new is added to `pubspec.yaml`; everything is ported. The ported files keep their original copyright notices.

| Source | Licence | Used for |
| --- | --- | --- |
| turf.js 7.4.0 modules | MIT | API, behaviour, test fixtures |
| polygon-clipping 0.15.7, polyclip-ts 0.16.8 | MIT | The polygon clipper |
| Delaunator 5.1.0 | ISC | Delaunay triangulation |
| robust-predicates | Unlicense | `orient2d` |
| d3-delaunay 6.0.6 | ISC | Voronoi cells clipped to a box |

## Tests

- **Fixtures:**
  - the turf.js 7.4.0 fixtures of all six modules;
  - polyclip-ts' end-to-end cases under `test/examples/polygon_clipping/`.
  - Geometries are compared with `test/context/geometry_matcher.dart`, which normalises ring rotation and orientation and uses a 1e-9 tolerance.
- **Browser runs:** `tool/embed_fixtures.dart` embeds the fixture files into `test/fixtures/*.g.dart`, so the suites also run with `dart test -p chrome`. `embedded_fixtures_test.dart` fails when an embedded file is stale.
- **shapely references:** `test/components/shapely_reference_test.dart` covers chained intersections and differences on a city-scale polygon, and `mask(keepHoles: true)` of polygons with holes and islands. Results must match shapely within 0.1 % of the area and on a 100 × 100 grid of sample points.
  - `tool/reference/make_inputs.dart` writes the inputs to `test/examples/shapely_reference/in/`.
  - `tool/reference/make_reference.py` writes the expected results to `out/`.
- **Property tests** check random inputs against point-in-polygon on a 50 × 50 grid.
  - **Clipper:** grid points must be inside the intersection when inside both inputs, inside the union when inside either, and inside the difference when inside the first and not the second.
  - **voronoi:** every grid point must lie in the cell of its nearest site.
  - **Inputs:** star-shaped, snapped, nearly collinear and metre-scale.
  - **Running:** 200 runs by default. For the full run, use `TURF_FUZZ_RUNS=10000 dart test test/components/polygon_clipping_property_test.dart test/components/voronoi_test.dart`.

## Benchmarks

Run `dart run benchmark`. The budgets are for a mid-range phone.

| Operation | Input | Budget | VM (desktop) |
| --- | --- | --- | --- |
| `polygonIntersect` / `difference` | 2,000-vertex polygon and a 64-point circle | 50 ms | about 3 ms |
| `voronoi` | 30 points | 10 ms | about 0.2 ms |
