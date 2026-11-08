// Dart port of polygon-clipping 0.15.7 by Mike Fogel
// (https://github.com/mfogel/polygon-clipping), with the orientation-based
// segment comparison of its TypeScript fork polyclip-ts 0.16.8 by Luiz Felipe
// Machado Barboza (https://github.com/luizbarboza/polyclip-ts), which turf.js
// v7 uses for `intersect`, `union`, `difference` and `mask`.
//
// The MIT License (MIT)
//
// Copyright (c) 2018 Mike Fogel
// Copyright (c) 2023 Luiz Felipe Machado Barboza
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

/// Martinez–Rueda–Feito sweep-line polygon clipping (union, intersection,
/// difference, xor) on planar coordinates.
///
/// Internal to turf; the public API is `polygonIntersect`, `union`,
/// `difference` and `mask`.
library turf_polygon_clipping;

import 'dart:collection';
import 'dart:math' as math;

import 'package:geotypes/geotypes.dart';

part 'decimal.dart';
part 'precision.dart';
part 'vector.dart';
part 'bbox.dart';
part 'sweep_event.dart';
part 'segment.dart';
part 'geom_in.dart';
part 'geom_out.dart';
part 'sweep_line.dart';
part 'operation.dart';

/// Coordinates of a MultiPolygon: polygons → rings → positions.
typedef MultiPolygonCoords = List<List<List<Position>>>;

/// The union of [geom] and all of [moreGeoms].
MultiPolygonCoords clipUnion(
  MultiPolygonCoords geom, [
  List<MultiPolygonCoords> moreGeoms = const [],
]) =>
    _operation.run(_OpType.union, geom, moreGeoms);

/// The intersection of [geom] and all of [moreGeoms].
MultiPolygonCoords clipIntersection(
  MultiPolygonCoords geom, [
  List<MultiPolygonCoords> moreGeoms = const [],
]) =>
    _operation.run(_OpType.intersection, geom, moreGeoms);

/// The symmetric difference of [geom] and all of [moreGeoms].
MultiPolygonCoords clipXor(
  MultiPolygonCoords geom, [
  List<MultiPolygonCoords> moreGeoms = const [],
]) =>
    _operation.run(_OpType.xor, geom, moreGeoms);

/// [subject] minus all of [clipping].
MultiPolygonCoords clipDifference(
  MultiPolygonCoords subject, [
  List<MultiPolygonCoords> clipping = const [],
]) =>
    _operation.run(_OpType.difference, subject, clipping);
