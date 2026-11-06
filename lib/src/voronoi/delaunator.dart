// Dart port of Delaunator 5.1.0 (https://github.com/mapbox/delaunator),
// a fast Delaunay triangulation of 2D points.
//
// ISC License
//
// Copyright (c) 2021, Mapbox
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

import 'dart:math' as math;
import 'dart:typed_data';

import '../robust/orient2d.dart';

const double _epsilon = 2.220446049250313e-16; // 2^-52
final Uint32List _edgeStack = Uint32List(512);

/// A Delaunay triangulation of points given as `[x0, y0, x1, y1, ...]`.
///
/// Internal to turf, used by `voronoi`.
class Delaunator {
  final Float64List coords;

  late final Uint32List _triangles;
  late final Int32List _halfedges;
  late final int _hashSize;
  late final Uint32List _hullPrev;
  late final Uint32List _hullNext;
  late final Uint32List _hullTri;
  late final Int32List _hullHash;
  late final Uint32List _ids;
  late final Float64List _dists;

  int trianglesLen = 0;
  double _cx = 0;
  double _cy = 0;
  int _hullStart = 0;

  /// Indices of the points on the convex hull, counter-clockwise assuming
  /// the y axis points down (clockwise for y up).
  late Uint32List hull;

  /// Triangle vertex indices, three per triangle.
  late Uint32List triangles;

  /// For each half-edge, the twin half-edge in the adjacent triangle, or -1
  /// on the hull.
  late Int32List halfedges;

  Delaunator(this.coords) {
    final n = coords.length >> 1;
    final maxTriangles = math.max(2 * n - 5, 0);
    _triangles = Uint32List(maxTriangles * 3);
    _halfedges = Int32List(maxTriangles * 3);
    _hashSize = math.sqrt(n).ceil();
    _hullPrev = Uint32List(n);
    _hullNext = Uint32List(n);
    _hullTri = Uint32List(n);
    _hullHash = Int32List(math.max(_hashSize, 1));
    _ids = Uint32List(n);
    _dists = Float64List(n);
    hull = _triangles;
    triangles = _triangles;
    halfedges = _halfedges;
    update();
  }

  void update() {
    final hullPrev = _hullPrev,
        hullNext = _hullNext,
        hullTri = _hullTri,
        hullHash = _hullHash;
    final n = coords.length >> 1;

    // populate an array of point indices; calculate input data bbox
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (var i = 0; i < n; i++) {
      final x = coords[2 * i];
      final y = coords[2 * i + 1];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      _ids[i] = i;
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;

    var i0 = 0, i1 = 0, i2 = 0;

    // pick a seed point close to the center
    var minDist = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = _dist(cx, cy, coords[2 * i], coords[2 * i + 1]);
      if (d < minDist) {
        i0 = i;
        minDist = d;
      }
    }
    final i0x = coords[2 * i0];
    final i0y = coords[2 * i0 + 1];

    // find the point closest to the seed
    minDist = double.infinity;
    for (var i = 0; i < n; i++) {
      if (i == i0) continue;
      final d = _dist(i0x, i0y, coords[2 * i], coords[2 * i + 1]);
      if (d < minDist && d > 0) {
        i1 = i;
        minDist = d;
      }
    }
    var i1x = coords[2 * i1];
    var i1y = coords[2 * i1 + 1];

    var minRadius = double.infinity;

    // find the third point which forms the smallest circumcircle with the
    // first two
    for (var i = 0; i < n; i++) {
      if (i == i0 || i == i1) continue;
      final r =
          _circumradius(i0x, i0y, i1x, i1y, coords[2 * i], coords[2 * i + 1]);
      if (r < minRadius) {
        i2 = i;
        minRadius = r;
      }
    }
    var i2x = coords[2 * i2];
    var i2y = coords[2 * i2 + 1];

    if (minRadius == double.infinity) {
      // order collinear points by dx (or dy if all x are identical)
      // and return the list as a hull
      for (var i = 0; i < n; i++) {
        final dx = coords[2 * i] - coords[0];
        _dists[i] = dx != 0 && !dx.isNaN ? dx : coords[2 * i + 1] - coords[1];
      }
      _quicksort(_ids, _dists, 0, n - 1);
      final hull = Uint32List(n);
      var j = 0;
      var d0 = double.negativeInfinity;
      for (var i = 0; i < n; i++) {
        final id = _ids[i];
        final d = _dists[id];
        if (d > d0) {
          hull[j++] = id;
          d0 = d;
        }
      }
      this.hull = Uint32List.sublistView(hull, 0, j);
      triangles = Uint32List(0);
      halfedges = Int32List(0);
      return;
    }

    // swap the order of the seed points for counter-clockwise orientation
    if (orient2d(i0x, i0y, i1x, i1y, i2x, i2y) < 0) {
      final i = i1;
      final x = i1x;
      final y = i1y;
      i1 = i2;
      i1x = i2x;
      i1y = i2y;
      i2 = i;
      i2x = x;
      i2y = y;
    }

    final center = _circumcenter(i0x, i0y, i1x, i1y, i2x, i2y);
    _cx = center[0];
    _cy = center[1];

    for (var i = 0; i < n; i++) {
      _dists[i] = _dist(coords[2 * i], coords[2 * i + 1], center[0], center[1]);
    }

    // sort the points by distance from the seed triangle circumcenter
    _quicksort(_ids, _dists, 0, n - 1);

    // set up the seed triangle as the starting hull
    _hullStart = i0;
    var hullSize = 3;

    hullNext[i0] = hullPrev[i2] = i1;
    hullNext[i1] = hullPrev[i0] = i2;
    hullNext[i2] = hullPrev[i1] = i0;

    hullTri[i0] = 0;
    hullTri[i1] = 1;
    hullTri[i2] = 2;

    hullHash.fillRange(0, hullHash.length, -1);
    hullHash[_hashKey(i0x, i0y)] = i0;
    hullHash[_hashKey(i1x, i1y)] = i1;
    hullHash[_hashKey(i2x, i2y)] = i2;

    trianglesLen = 0;
    _addTriangle(i0, i1, i2, -1, -1, -1);

    var xp = 0.0, yp = 0.0;
    for (var k = 0; k < _ids.length; k++) {
      final i = _ids[k];
      final x = coords[2 * i];
      final y = coords[2 * i + 1];

      // skip near-duplicate points
      if (k > 0 && (x - xp).abs() <= _epsilon && (y - yp).abs() <= _epsilon) {
        continue;
      }
      xp = x;
      yp = y;

      // skip seed triangle points
      if (i == i0 || i == i1 || i == i2) continue;

      // find a visible edge on the convex hull using edge hash
      var start = 0;
      for (var j = 0, key = _hashKey(x, y); j < _hashSize; j++) {
        start = hullHash[(key + j) % _hashSize];
        if (start != -1 && start != hullNext[start]) break;
      }

      start = hullPrev[start];
      var e = start;
      int q;
      while (true) {
        q = hullNext[e];
        if (!(orient2d(x, y, coords[2 * e], coords[2 * e + 1], coords[2 * q],
                coords[2 * q + 1]) >=
            0)) {
          break;
        }
        e = q;
        if (e == start) {
          e = -1;
          break;
        }
      }
      if (e == -1) continue; // likely a near-duplicate point; skip it

      // add the first triangle from the point
      var t = _addTriangle(e, i, hullNext[e], -1, -1, hullTri[e]);

      // recursively flip triangles from the point until they satisfy the
      // Delaunay condition
      hullTri[i] = _legalize(t + 2);
      hullTri[e] = t; // keep track of boundary triangles on the hull
      hullSize++;

      // walk forward through the hull, adding more triangles and flipping
      // recursively
      var nn = hullNext[e];
      while (true) {
        q = hullNext[nn];
        if (!(orient2d(x, y, coords[2 * nn], coords[2 * nn + 1], coords[2 * q],
                coords[2 * q + 1]) <
            0)) {
          break;
        }
        t = _addTriangle(nn, i, q, hullTri[i], -1, hullTri[nn]);
        hullTri[i] = _legalize(t + 2);
        hullNext[nn] = nn; // mark as removed
        hullSize--;
        nn = q;
      }

      // walk backward from the other side, adding more triangles and flipping
      if (e == start) {
        while (true) {
          q = hullPrev[e];
          if (!(orient2d(x, y, coords[2 * q], coords[2 * q + 1], coords[2 * e],
                  coords[2 * e + 1]) <
              0)) {
            break;
          }
          t = _addTriangle(q, i, e, -1, hullTri[e], hullTri[q]);
          _legalize(t + 2);
          hullTri[q] = t;
          hullNext[e] = e; // mark as removed
          hullSize--;
          e = q;
        }
      }

      // update the hull indices
      _hullStart = hullPrev[i] = e;
      hullNext[e] = hullPrev[nn] = i;
      hullNext[i] = nn;

      // save the two new edges in the hash table
      hullHash[_hashKey(x, y)] = i;
      hullHash[_hashKey(coords[2 * e], coords[2 * e + 1])] = e;
    }

    hull = Uint32List(hullSize);
    for (var i = 0, e = _hullStart; i < hullSize; i++) {
      hull[i] = e;
      e = hullNext[e];
    }

    // trim typed triangle mesh arrays
    triangles = Uint32List.sublistView(_triangles, 0, trianglesLen);
    halfedges = Int32List.sublistView(_halfedges, 0, trianglesLen);
  }

  /// An angle-based key for the edge hash used for the advancing convex
  /// hull.
  int _hashKey(double x, double y) =>
      (_pseudoAngle(x - _cx, y - _cy) * _hashSize).floor() % _hashSize;

  /// Flips an edge in a pair of triangles if it doesn't satisfy the
  /// Delaunay condition.
  int _legalize(int a) {
    final triangles = _triangles, halfedges = _halfedges;

    var i = 0;
    var ar = 0;

    // recursion eliminated with a fixed-size stack
    while (true) {
      final b = halfedges[a];

      // if the pair of triangles doesn't satisfy the Delaunay condition
      // (p1 is inside the circumcircle of [p0, pl, pr]), flip them,
      // then do the same check/flip recursively for the new pair of
      // triangles
      final a0 = a - a % 3;
      ar = a0 + (a + 2) % 3;

      if (b == -1) {
        // convex hull edge
        if (i == 0) break;
        a = _edgeStack[--i];
        continue;
      }

      final b0 = b - b % 3;
      final al = a0 + (a + 1) % 3;
      final bl = b0 + (b + 2) % 3;

      final p0 = triangles[ar];
      final pr = triangles[a];
      final pl = triangles[al];
      final p1 = triangles[bl];

      final illegal = _inCircle(
          coords[2 * p0],
          coords[2 * p0 + 1],
          coords[2 * pr],
          coords[2 * pr + 1],
          coords[2 * pl],
          coords[2 * pl + 1],
          coords[2 * p1],
          coords[2 * p1 + 1]);

      if (illegal) {
        triangles[a] = p1;
        triangles[b] = p0;

        final hbl = halfedges[bl];

        // edge swapped on the other side of the hull (rare); fix the
        // half-edge reference
        if (hbl == -1) {
          var e = _hullStart;
          do {
            if (_hullTri[e] == bl) {
              _hullTri[e] = a;
              break;
            }
            e = _hullPrev[e];
          } while (e != _hullStart);
        }
        _link(a, hbl);
        _link(b, halfedges[ar]);
        _link(ar, bl);

        final br = b0 + (b + 1) % 3;

        // don't worry about hitting the cap: it can only happen on extremely
        // degenerate input
        if (i < _edgeStack.length) {
          _edgeStack[i++] = br;
        }
      } else {
        if (i == 0) break;
        a = _edgeStack[--i];
      }
    }

    return ar;
  }

  void _link(int a, int b) {
    _halfedges[a] = b;
    if (b != -1) _halfedges[b] = a;
  }

  int _addTriangle(int i0, int i1, int i2, int a, int b, int c) {
    final t = trianglesLen;

    _triangles[t] = i0;
    _triangles[t + 1] = i1;
    _triangles[t + 2] = i2;

    _link(t, a);
    _link(t + 1, b);
    _link(t + 2, c);

    trianglesLen += 3;

    return t;
  }
}

/// Monotonically increases with real angle, without trigonometry.
double _pseudoAngle(double dx, double dy) {
  final s = dx.abs() + dy.abs();
  final p = dx / (s == 0 ? 1 : s);
  return (dy > 0 ? 3 - p : 1 + p) / 4; // [0..1]
}

double _dist(double ax, double ay, double bx, double by) {
  final dx = ax - bx;
  final dy = ay - by;
  return dx * dx + dy * dy;
}

bool _inCircle(double ax, double ay, double bx, double by, double cx, double cy,
    double px, double py) {
  final dx = ax - px;
  final dy = ay - py;
  final ex = bx - px;
  final ey = by - py;
  final fx = cx - px;
  final fy = cy - py;

  final ap = dx * dx + dy * dy;
  final bp = ex * ex + ey * ey;
  final cp = fx * fx + fy * fy;

  return dx * (ey * cp - bp * fy) -
          dy * (ex * cp - bp * fx) +
          ap * (ex * fy - ey * fx) <
      0;
}

double _circumradius(
    double ax, double ay, double bx, double by, double cx, double cy) {
  final dx = bx - ax;
  final dy = by - ay;
  final ex = cx - ax;
  final ey = cy - ay;

  final bl = dx * dx + dy * dy;
  final cl = ex * ex + ey * ey;
  final d = 0.5 / (dx * ey - dy * ex);

  final x = (ey * bl - dy * cl) * d;
  final y = (dx * cl - ex * bl) * d;

  // collinear points give NaN or infinity; treat both as "no circle"
  final r = x * x + y * y;
  return r.isNaN ? double.infinity : r;
}

List<double> _circumcenter(
    double ax, double ay, double bx, double by, double cx, double cy) {
  final dx = bx - ax;
  final dy = by - ay;
  final ex = cx - ax;
  final ey = cy - ay;

  final bl = dx * dx + dy * dy;
  final cl = ex * ex + ey * ey;
  final d = 0.5 / (dx * ey - dy * ex);

  final x = ax + (ey * bl - dy * cl) * d;
  final y = ay + (dx * cl - ex * bl) * d;

  return [x, y];
}

void _quicksort(Uint32List ids, Float64List dists, int left, int right) {
  if (right - left <= 20) {
    for (var i = left + 1; i <= right; i++) {
      final temp = ids[i];
      final tempDist = dists[temp];
      var j = i - 1;
      while (j >= left && dists[ids[j]] > tempDist) {
        ids[j + 1] = ids[j--];
      }
      ids[j + 1] = temp;
    }
  } else {
    final median = (left + right) >> 1;
    var i = left + 1;
    var j = right;
    _swap(ids, median, i);
    if (dists[ids[left]] > dists[ids[right]]) _swap(ids, left, right);
    if (dists[ids[i]] > dists[ids[right]]) _swap(ids, i, right);
    if (dists[ids[left]] > dists[ids[i]]) _swap(ids, left, i);

    final temp = ids[i];
    final tempDist = dists[temp];
    while (true) {
      do {
        i++;
      } while (dists[ids[i]] < tempDist);
      do {
        j--;
      } while (dists[ids[j]] > tempDist);
      if (j < i) break;
      _swap(ids, i, j);
    }
    ids[left + 1] = ids[j];
    ids[j] = temp;

    if (right - i + 1 >= j - left) {
      _quicksort(ids, dists, i, right);
      _quicksort(ids, dists, left, j - 1);
    } else {
      _quicksort(ids, dists, left, j - 1);
      _quicksort(ids, dists, i, right);
    }
  }
}

void _swap(Uint32List arr, int i, int j) {
  final tmp = arr[i];
  arr[i] = arr[j];
  arr[j] = tmp;
}
