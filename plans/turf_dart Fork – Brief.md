# turf\_dart Fork – Brief

Nov 6, 2026 

## Purpose and scope

The fork adds the polygon operations that the Dart port of Turf lacks and the Stadtjagd app needs to shade where a hidden spot can no longer be: `intersect`, `difference`, `union`, `mask`, `bboxClip` and `voronoi`. Each function follows the turf.js API and behaviour, so it can go upstream to [dartclub/turf\_dart](https://github.com/dartclub/turf_dart) as its own pull request. `circle` already exists.

This brief is exported as Markdown into the fork itself (suggested path: doc/stadtjagd-fork.md), so a coding session in the repository has the full context. Paths in it are relative to the repository root.

**How the app uses it.** Every open card keeps an open area, starting as the play area. A "yes" answer intersects it with a region, a "no" subtracts the region, and the map draws a frame with the open area cut out as holes. The regions are circles (Radar), half-planes (Compass, Thermometer), precomputed polygons (station cells, districts), Voronoi cells built live (Tentacles). Buffers, needed only for the optional Closer than me question, are left out of this brief for now. The app calls the fork only through its own `SearchArea` class.

**Out of scope:** the other unimplemented turf.js modules (grids, interpolation, aggregation, random, `lineSplit`, `kinks`, `dissolve`), 3D, geodesic polygon clipping, and buffer (for now). Clipping is planar in lng/lat, as in turf.js.

## Current state of turf\_dart

turf\_dart is at version 0.0.14 (released 24 September 2026), MIT-licensed, pure Dart and works on Flutter web. It already has `circle` and a bounding-box clipper, but `Progress.md` still lists both as missing, so the code is the reference, not the progress list. Checked against a clone of `main` at commit `25e661e`.

### What the app needs that already exists

| Need | In turf\_dart | Notes |
| --- | --- | --- |
| Circle polygon | `circle(GeoJSONObject center, num radius, {num? steps, Unit? unit, Map? properties})` → `Feature<Polygon>` | Since 0.0.11. Defaults: 64 steps, **kilometres**; pass `unit: Unit.meters` |
| Point at distance and bearing | `destination(Point origin, num distance, num bearing, [Unit unit = Unit.kilometers])` | Also `destinationRaw` on `Position` |
| Bounding-box clip | `lineclip(...)` and `polygonclip(List<Position> ring, BBox bbox)` in `lib/src/lineclip.dart` | Since 0.0.12. Clips one ring; there is no `bboxClip` wrapper for features with holes or multipolygons yet |
| Distance, bearing | `distance`, `bearing`, rhumb variants |  |
| Point in polygon | `booleanPointInPolygon` |  |
| Nearest point | `nearestPoint` |  |
| Point to line | `pointToLineDistance` |  |
| Projection | `geoToMercator`, `geoToWgs84` (`{bool mutate = false}`) | Whole GeoJSON objects |
| Simplify, area, bbox | `simplify`, `area`, `bbox`, `bboxPolygon` |  |
| Line intersections | `lineIntersect`, plus `sweepline_intersections` as a dependency | Useful inside a clipper |

Still missing: `intersect`, `difference`, `union`, `mask`, `bboxClip` (feature-level), `voronoi`, `buffer`.

### Conventions

- **GeoJSON types** come from the `geotypes` package: `Feature<Polygon>`, `Polygon(coordinates: [[Position(lng, lat), ...]])`, `MultiPolygon`, `FeatureCollection`, `BBox`. Nested GeometryCollections are not supported, by design.
- **Module layout** (from `CONTRIBUTING.md`): `lib/<module>.dart` exports the public API, `lib/src/<module>.dart` holds the implementation, `test/components/<module>_test.dart` the tests, `benchmark/<module>_benchmark.dart` the benchmark.
- **Fixtures:** `test/examples/<module>/in/*.geojson` and `out/*.geojson`, taken over from turf.js.
- **Process:** a `feature-<name>` branch from `main`, a draft pull request linked to its issue, Effective Dart doc comments, tests and a benchmark, a README mention, then review.
- **Dependencies today:** `geotypes`, `turf_equality`, `turf_pip`, `rbush`, `sweepline_intersections`, `path`. Dart SDK `>=2.17.0 <4.0.0`.
- **Commands:** `dart pub get`, `dart test`, `dart run benchmark`.

## Functions to add

In order of need. Signatures follow turf.js v7 and the existing turf\_dart style (a `FeatureCollection` in, a `Feature` out, options as named parameters); names may change in review.

| Function | turf.js v7 | Proposed Dart signature | Priority | Approach |
| --- | --- | --- | --- | --- |
| `intersect` | `intersect(fc, {properties})` → Feature or `null` | `Feature<GeometryObject>? intersect(FeatureCollection features, {Map<String, dynamic>? properties})` | Must | Polygon clipper, see below |
| `difference` | `difference(fc)`: the first minus all others → Feature or `null` | `Feature<GeometryObject>? difference(FeatureCollection features, {Map<String, dynamic>? properties})` | Must | Same clipper |
| `union` | `union(fc, {properties})` → Feature or `null` | `Feature<GeometryObject>? union(FeatureCollection features, {Map<String, dynamic>? properties})` | Must | Same clipper |
| `mask` | `mask(polygon, mask?, {mutate})` → Polygon with the input as holes | `Feature<GeometryObject> mask(GeoJSONObject polygons, {Feature<Polygon>? mask, bool keepHoles = false})` | Must | turf.js behaviour by default; `keepHoles: true` returns `difference([mask, ...polygons])`, so holes in the input are shaded |
| `voronoi` | `voronoi(points, {bbox})` → FeatureCollection of Polygons | `FeatureCollection<Polygon> voronoi(FeatureCollection<Point> points, {BBox? bbox})` | Must (Tentacles) | Delaunay triangulation, cells from circumcentres, clip to bbox |
| `bboxClip` | `bboxClip(feature, bbox)` | `Feature<GeometryObject> bboxClip(Feature feature, BBox bbox)` | Should | Wrap the existing `lineclip` / `polygonclip` per ring and per polygon |

`intersect`, `difference` and `union` all return `null` for an empty result, as in turf.js; the app treats `null` as an empty open area.

**Geometry type.** All three clipping results can be a `Polygon` or a `MultiPolygon`, so the return type is `Feature<GeometryObject>`, and callers switch on the geometry. Check how `geotypes` handles a common Polygon/MultiPolygon supertype before settling the signature.

## Implementation notes

### intersect, difference, union: one polygon clipper

turf.js v7 builds all three on [polyclip-ts](https://github.com/luizbarboza/polyclip-ts) (MIT), a TypeScript version of Mike Fogel's polygon-clipping, using the Martinez–Rueda–Feito sweep-line method in O((n + k) log n) for n edges and k intersections. It is about 1,600 lines across 15 files and has two dependencies: `bignumber.js` for exact arithmetic and `splaytree-ts`.

Port it as `lib/src/polygon_clipping/`, with the three public functions as thin wrappers:

- **Splay tree:** Dart's `SplayTreeMap` / `SplayTreeSet` from `dart:collection` replace `splaytree-ts`; check that the comparator-based ordering and "find next / previous" operations map one to one.
- **Precision:** polyclip-ts uses `bignumber.js`. Start with `double` plus the epsilon comparisons from the original polygon-clipping (its `rounder` snaps coordinates to a grid) and keep the precision code behind one interface, so an exact type (`decimal` or `rational` packages) can be swapped in if the fuzz tests find failures.
- **Inputs:** Polygon, MultiPolygon, and Features or FeatureCollections of them. Outputs are rings closed and oriented the GeoJSON way: counter-clockwise outer rings, clockwise holes.
- **Port the tests too:** polyclip-ts ships many end-to-end fixture cases; they matter more than the code.

### mask

`mask(polygons, mask: frame, keepHoles: true)` returns the frame with the polygons cut out. turf.js 7.4.0 unions the inputs with polyclip-ts and pushes only each result polygon's outer ring (`contour[0]`) into the mask, so holes in the input are dropped. The app needs them: an open area can have holes (a Radar "no" inside it), and those must be shaded.

- **Default `keepHoles: false`:** exactly the turf.js behaviour and output (a Polygon), so the turf.js fixtures pass unchanged.
- **`keepHoles: true`:** `difference([mask, ...polygons])`, returning a Polygon, or a MultiPolygon when a hole becomes a shaded island. Document the option in the doc comment and add fixtures for it.
- The return type is `Feature<GeometryObject>` so both cases fit; with the default it is always a Polygon.

### bboxClip

A wrapper over the existing `lineclip` and `polygonclip`: clip every ring of every polygon, drop rings that vanish, keep holes, and return the same geometry type. It is Sutherland–Hodgman against a box, so the result can have zero-width slivers along the box edge; that matches turf.js. The app uses it for Compass half-planes, the frame clipped at the player's latitude or longitude.

### voronoi

turf.js v7 uses the old `d3-voronoi` (Fortune's algorithm). A cleaner route for Dart:

1. Delaunay triangulation by porting [Delaunator](https://github.com/mapbox/delaunator) (ISC, about 600 lines, plus its `robust-predicates` dependency for an exact orientation test), or using the `delaunay` package on pub.dev (3.0.0, adapted from Delaunator; check its licence and API first).
2. Cells from the triangles' circumcentres around each point, clipped to the bbox, as in `d3-delaunay`'s `Voronoi` class (ISC). That class already handles the unbounded hull cells by clipping against the box.
3. Return one Polygon per input point, in input order, as turf.js does.

Coordinates are treated as planar, like turf.js. The app projects to Web Mercator first; document that callers should do the same for metric accuracy.

For the app's Tentacles question only one cell is needed. The half-plane method (frame clipped by the perpendicular bisector to each other candidate, via `intersect`) is a fallback that needs no triangulation.

## Dependencies and licences

Everything to port is under MIT, ISC or the Unlicense, all compatible with turf\_dart's MIT licence; keep the original copyright notices in the ported files. Prefer ports over new pub.dev dependencies, because upstream keeps its dependency list short.

| Source | Licence | Used for | Port or depend |
| --- | --- | --- | --- |
| [turf.js](https://github.com/Turfjs/turf) 7.4.0 modules (`@turf/intersect`, `difference`, `union`, `mask`, `bbox-clip`, `voronoi`) | MIT | API shape, behaviour, test fixtures | Port |
| [polyclip-ts](https://github.com/luizbarboza/polyclip-ts) | MIT | `intersect`, `difference`, `union`, `mask` | Port (≈ 1,600 lines) |
| `splaytree-ts` | BSD-3-Clause | Sweep-line status structure inside polyclip-ts | Replace with `dart:collection` |
| `bignumber.js` | MIT | Exact arithmetic inside polyclip-ts | Replace with `double` + epsilon first |
| [Delaunator](https://github.com/mapbox/delaunator) 5.1.0 | ISC | Delaunay triangulation for `voronoi` | Port (≈ 600 lines) |
| `robust-predicates` | Unlicense | Exact `orient2d` inside Delaunator | Port `orient2d` only |
| [d3-delaunay](https://github.com/d3/d3-delaunay) 6.0.6 | ISC | Voronoi cells from a triangulation, clipped to a box | Port the `Voronoi` class |
| `delaunay` on pub.dev (3.0.0) | Not stated on its page | Alternative to porting Delaunator | Check licence before use |

turf.js 7.4.0 itself depends on polyclip-ts (0.16.8) for `intersect`, `union`, `difference` and `mask`, and on `d3-voronoi` for `voronoi` (npm registry, checked today).

## Tests and benchmarks

A function is done when the turf.js fixtures pass, the Stadtjagd cases pass, the property tests find nothing in 10,000 random runs, and the benchmark is within budget. Tests run with `dart test` and also with `dart test -p chrome`, because the app ships on the web and JavaScript numbers behave differently from the Dart VM's in edge cases.

### Fixtures from turf.js and polyclip-ts

- Copy each module's `test/in/*.geojson` and `test/out/*.geojson` from turf.js 7.4.0 into `test/examples/<module>/in` and `out`, as the existing modules do.
- Port polyclip-ts's end-to-end cases for the clipper; they cover degenerate inputs (shared edges, touching vertices, self-overlap, empty results) that the turf.js fixtures barely touch.
- Compare with a coordinate tolerance of 1e-9 degrees and with ring rotation and orientation normalised.

### Stadtjagd cases

| Case | Checks |
| --- | --- |
| S-Bahn Ring polygon ∩ 1 km circle | Result inside both; area matches a shapely reference within 0.1% |
| Ring − a circle fully inside it | One polygon with one hole |
| Ring ∩ a half-plane at the player's latitude | Split edge lies on that latitude |
| Ten chained answers on one card | Result equals a shapely reference; no slivers below 1 m² |
| An answer that empties the area | Returns `null` |
| `mask` of an open area with a hole | The hole is shaded (MultiPolygon or Polygon with an island) |
| `voronoi` of 2, 3 and 30 points | One cell per point, cells tile the bbox, every point inside its own cell |

Reference results come from a short Python script with shapely, kept in `tool/reference/` and committed with its output files.

### Property tests

- **Clipper:** for random polygon pairs, every point of a 50 × 50 sample grid is inside `intersect(a, b)` exactly when it is inside both, inside `union` when inside either, inside `difference` when inside `a` and not `b`.
- **Voronoi:** for random points, every grid point is inside the cell of its nearest point (ties excepted).
- **Robustness:** inputs with snapped and nearly-collinear coordinates, and very small polygons (a few metres across at Berlin's latitude).

### Benchmarks

`benchmark/<module>_benchmark.dart`, run with `dart run benchmark` and once in Chrome on a mid-range phone.

| Operation | Input | Budget on a mid-range phone |
| --- | --- | --- |
| `intersect` / `difference` | Open area (≤ 2,000 vertices) and a 64-point circle | 50 ms |
| `voronoi` | 30 points | 10 ms |

## Workflow

Each feature branch starts from upstream `main` and becomes one upstream pull request. A separate `stadtjagd` branch merges them all for the app to use before upstream accepts them.

1. **Talk to upstream first.** Open one issue on dartclub/turf\_dart proposing the polygon-clipping port and listing the planned pull requests; ask whether anyone is already working on them. Also point out that `Progress.md` still lists `circle` as missing.
2. **Fork** to your own account and add upstream as a remote.
3. **Branches**, named as `CONTRIBUTING.md` asks, in this order:
   1. `feature-polygon-clipping`: the clipper core plus `intersect`, `difference`, `union` (they share all the code, so one pull request).
   2. `feature-mask`: depends on 1.
   3. `feature-bbox-clip`: independent; wraps the existing `lineclip`.
   4. `feature-voronoi`: independent.
4. **Each pull request** carries the code in `lib/src/<module>.dart`, the export in `lib/<module>.dart`, tests, fixtures, a benchmark, doc comments with an example, a `Progress.md` tick and a README mention. Open it as a draft early.
5. **CI** in the fork: `dart analyze`, `dart format --set-exit-if-changed`, `dart test` and `dart test -p chrome` on every push.
6. **Integration branch** `stadtjagd`: merge the feature branches as they pass. The app pins a commit, not the branch, so a rebase never changes the app silently:

```yaml
dependencies:
  turf:
    git:
      url: https://github.com/<your-account>/turf_dart.git
      ref: <commit sha on the stadtjagd branch>
```

Once upstream releases a version with the functions, the app switches back to `turf: ^<version>` from pub.dev. Because the app only calls the geometry through its `SearchArea` class, that switch changes no game code.

## Example app

A Flutter app in `example/flutter_map_demo/` shows every new operation on the map. It uses [flutter\_map](https://pub.dev/packages/flutter_map) (8.x) with no tile layer, so it needs no tile server, no key and no tile attribution. It also serves as a visual test and as an on-device benchmark, and gives each upstream pull request a live demo to link.

### Setup

- **Its own package:** `example/flutter_map_demo/pubspec.yaml` depends on `turf: path: ../..`, `flutter_map` and `latlong2`. turf\_dart itself gains no Flutter dependency.
- **Keep the root checks clean:** exclude `example/flutter_map_demo/**` in the root `analysis_options.yaml` (the root `dart analyze` has no Flutter SDK), and list it in `.pubignore` so it isn't published to pub.dev.
- **No raster layer:** `MapOptions(backgroundColor: ...)` in a neutral colour, a graticule drawn as a `PolylineLayer` every 0.01° for orientation, and the sample shapes as reference outlines.
- **Sample data in `assets/`:** a simplified S-Bahn Ring polygon, a few tram lines and some museum points around Berlin, as GeoJSON. They come from OpenStreetMap, so the app shows "© OpenStreetMap contributors" in a corner. Hand-drawn shapes cover edge cases: shared edges, touching vertices, holes.
- **Conversion:** a small helper turns geotypes `Polygon`/`MultiPolygon` into flutter\_map `Polygon(points:, holePointsList:)` and `LineString` into `Polyline`.
- **Status bar:** every result shows its computation time in milliseconds and its vertex count. A benchmark button runs the current operation 100 times and shows the median.

### Tabs

| Tab | Interaction | Shows |
| --- | --- | --- |
| `circle` | Tap a centre; sliders for radius (100 m–5 km) and steps (8–128) | The circle polygon and its vertices |
| `intersect` / `difference` / `union` | Two shapes with draggable vertices, or presets (Ring + circle, overlapping squares, a shape with a hole); a switch between the three operations | Both inputs as outlines, the result filled |
| `mask` | An open area with a hole (the Ring minus a circle) inside a frame; a `keepHoles` switch | The shading with and without the hole |
| `bboxClip` | A draggable, resizable rectangle over the Ring and the tram lines | Clipped polygons and lines |
| `voronoi` | Tap to add or remove points; a Tentacles mode with a player marker and radius | All cells clipped to the view; in Tentacles mode, the cell of the nearest candidate intersected with the circle |
| Search area | A player marker and a hidden spot; buttons for Radar yes/no, Compass, Thermometer, Tentacles | The open area after each answer, shaded with `mask(keepHoles: true)`; the hidden spot always stays unshaded |

The search-area tab is the Stadtjagd use case end to end, and the place to catch the "never shade the true spot" bugs early.

### Web build

A workflow in the fork runs `flutter build web --base-href /turf_dart/` in `example/flutter_map_demo/` and publishes it to GitHub Pages on every push to the `stadtjagd` branch.

## Milestones

F1 unblocks the app's shading; F2 and F3 can follow in either order, each adding its tab to the example app. The app's M0 prototype needs none of these, because `circle` and `destination` already exist.

- [ ] **F0 Setup.** Fork, upstream issue opened, CI running `dart test` on VM and Chrome, the shapely reference script in `tool/reference/`. Done when CI is green on an untouched fork.
- [ ] **F1 Polygon clipping.** polyclip-ts ported; `intersect`, `difference`, `union` with turf.js and polyclip-ts fixtures, the Stadtjagd cases and the grid property test. Done when all pass on VM and Chrome and the 50 ms budget holds.
- [ ] **F2 mask and bboxClip.** `mask` with the hole-keeping option; feature-level `bboxClip` over the existing `lineclip`. Done when their fixtures and the Stadtjagd mask case pass.
- [ ] **F3 voronoi.** Delaunator, `orient2d` and the d3-delaunay `Voronoi` cell builder ported; turf.js `voronoi` fixtures and the nearest-point grid test pass. Done when 30 points take under 10 ms.
- [ ] **F4 Example app.** The flutter\_map demo with a tab per operation and the search-area playground, built for the web and deployed from the fork. Each of F1–F3 adds its tab as it lands; F4 finishes the playground, the benchmark button and the deployment. Done when every tab works in Chrome on a phone and the link is in the README.
- [ ] **F5 Upstream.** One pull request per branch, reviews addressed, `Progress.md` and README updated. Done when upstream merges F1, or says it won't, and the app pins its final source.

## Open questions

- [ ] Is anyone upstream already porting polygon clipping? (No branch for it on dartclub/turf\_dart as of today; issues not checked.)
- [ ] Does `double` plus epsilon hold up in the clipper's fuzz tests, or is an exact number type needed?
- [ ] Port Delaunator, or depend on the `delaunay` package once its licence is known?

## Sources

- [dartclub/turf\_dart](https://github.com/dartclub/turf_dart): clone of `main` at `25e661e` (24 September 2026), `pubspec.yaml`, `CONTRIBUTING.md`, `lib/src/circle.dart`, `lib/src/lineclip.dart`, `Progress.md`
- [turf on pub.dev, changelog](https://pub.dev/packages/turf/changelog): `circle` in 0.0.11, `lineclip` in 0.0.12
- [dartclub/geotypes](https://github.com/dartclub/geotypes): `GeometryObject`, `Feature<T extends GeometryObject>`
- [polyclip-ts](https://github.com/luizbarboza/polyclip-ts): algorithm, licence, size (cloned)
- npm registry entries for `@turf/intersect`, `@turf/union`, `@turf/difference`, `@turf/mask`, `@turf/bbox-clip`, `@turf/voronoi`, `@turf/buffer` (7.4.0), `polyclip-ts`, `delaunator`, `d3-delaunay`, `robust-predicates`, `splaytree-ts`, `bignumber.js`; the `@turf/mask` 7.4.0 source
- [Delaunator](https://github.com/mapbox/delaunator) · [d3-delaunay](https://github.com/d3/d3-delaunay)
- [`delaunay` on pub.dev](https://pub.dev/documentation/delaunay/3.0.0)
- [Stadtjagd App – Coding Brief](https://claude.ai/artifact/BdvAo2qDQnt9z6i4h27Sjk): the app side, the search-area model
