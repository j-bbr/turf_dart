# turf_dart example: flutter_map demo

Interactive examples of turf_dart on a
[flutter_map](https://pub.dev/packages/flutter_map) map without tiles. Each
tab shows a few related operations with draggable inputs:

| Tab | Operations |
| --- | --- |
| measure | `area`, `length`, `bbox`, `bboxPolygon`, `centroid`, `center`, `centerOfMass`, `pointOnFeature`, `booleanPointInPolygon`, `pointToLineDistance`, `polygonTangents` |
| lines | `length`, `simplify`, `along`, `lineSliceAlong`, `nearestPointOnLine`, `pointToLineDistance`, `lineIntersect` |
| geodesic | `distance`, `bearing`, `midpoint`, `greatCircle`, `destination`, and their rhumb-line counterparts `rhumbDistance`, `rhumbBearing`, `rhumbDestination` (world scale) |
| transform | `transformRotate`, `polygonSmooth`, `explode`, `envelope`, `booleanIntersects`, `booleanContains` |
| circle | `circle` |
| intersect / difference / union | `polygonIntersect`, `difference`, `union` of shapes with draggable vertices |
| mask | `mask`, with and without `keepHoles` |
| bboxClip | `bboxClip` of lines and polygons |
| voronoi | `voronoi` (in Web Mercator via `geoToMercator` / `geoToWgs84`), `nearestPoint`, `polygonIntersect` |

Every tab shows the computation time and vertex count of its result; the
benchmark button reports the median of 100 runs.

```sh
flutter pub get
flutter run -d chrome
flutter test                       # opens every tab
flutter build web --base-href /turf_dart/
```

The sample shapes in `assets/` (a simplified S-Bahn Ring in Berlin, three tram
lines, a few museums) are approximate and hand-made, not survey data.

It depends on this checkout of turf (`path: ..`, plus a
`dependency_overrides` entry because `turf_pip` depends on turf from pub.dev).
