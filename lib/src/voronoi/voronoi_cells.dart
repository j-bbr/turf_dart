// Dart port of the Delaunay and Voronoi classes of d3-delaunay 6.0.6
// (https://github.com/d3/d3-delaunay), limited to clipped cell polygons.
//
// ISC License
//
// Copyright 2018-2021 Observable, Inc.
// Copyright 2021 Mapbox
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

import 'delaunator.dart';

/// A Delaunay triangulation with the indexes the Voronoi diagram needs.
///
/// Internal to turf, used by `voronoi`.
class Delaunay {
  /// The point coordinates `[x0, y0, x1, y1, ...]`; jittered in place when
  /// all points are collinear.
  final Float64List points;
  late Delaunator _delaunator;
  final Int32List inedges;
  final Int32List _hullIndex;
  late Int32List halfedges;
  late Uint32List hull;
  late Int32List triangles;

  /// Point indices sorted along the line, when all points are collinear.
  List<int>? collinear;

  Delaunay(this.points)
      : inedges = Int32List(points.length ~/ 2),
        _hullIndex = Int32List(points.length ~/ 2) {
    _delaunator = Delaunator(points);
    _init();
  }

  void _init() {
    var d = _delaunator;

    // check for collinear
    if (d.hull.length > 2 && _isCollinear(d)) {
      final n = points.length ~/ 2;
      final sorted = List<int>.generate(n, (i) => i)
        ..sort((i, j) {
          final dx = points[2 * i] - points[2 * j];
          if (dx != 0) return dx < 0 ? -1 : 1;
          final dy = points[2 * i + 1] - points[2 * j + 1];
          return dy < 0 ? -1 : (dy > 0 ? 1 : 0);
        }); // for exact neighbors
      collinear = sorted;
      final e = sorted.first, f = sorted.last;
      final r = 1e-8 *
          _hypot(points[2 * f + 1] - points[2 * e + 1],
              points[2 * f] - points[2 * e]);
      for (var i = 0; i < n; ++i) {
        final x = points[2 * i], y = points[2 * i + 1];
        points[2 * i] = x + math.sin(x + y) * r;
        points[2 * i + 1] = y + math.cos(x - y) * r;
      }
      d = _delaunator = Delaunator(points);
    } else {
      collinear = null;
    }

    halfedges = d.halfedges;
    hull = d.hull;
    triangles = Int32List.fromList(d.triangles);
    inedges.fillRange(0, inedges.length, -1);
    _hullIndex.fillRange(0, _hullIndex.length, -1);

    // Compute an index from each point to an (arbitrary) incoming halfedge
    // Used to give the first neighbor of each point; for this reason,
    // on the hull we give priority to exterior halfedges
    for (var e = 0, n = halfedges.length; e < n; ++e) {
      final p = triangles[e % 3 == 2 ? e - 2 : e + 1];
      if (halfedges[e] == -1 || inedges[p] == -1) inedges[p] = e;
    }
    for (var i = 0, n = hull.length; i < n; ++i) {
      _hullIndex[hull[i]] = i;
    }

    // degenerate case: 1 or 2 (distinct) points
    if (hull.length <= 2 && hull.isNotEmpty) {
      triangles = Int32List(3)..fillRange(0, 3, -1);
      halfedges = Int32List(3)..fillRange(0, 3, -1);
      triangles[0] = hull[0];
      inedges[hull[0]] = 1;
      if (hull.length == 2) {
        inedges[hull[1]] = 0;
        triangles[1] = hull[1];
        triangles[2] = hull[1];
      }
    }
  }

  /// A triangulation is collinear if all its triangles have a null area.
  static bool _isCollinear(Delaunator d) {
    final triangles = d.triangles, coords = d.coords;
    for (var i = 0; i < triangles.length; i += 3) {
      final a = 2 * triangles[i],
          b = 2 * triangles[i + 1],
          c = 2 * triangles[i + 2];
      final cross = (coords[c] - coords[a]) * (coords[b + 1] - coords[a + 1]) -
          (coords[b] - coords[a]) * (coords[c + 1] - coords[a + 1]);
      if (cross > 1e-10) return false;
    }
    return true;
  }

  /// One step of the walk towards the point nearest to (x, y), from point i.
  int step(int i, double x, double y) {
    if (points.length < 2) return -1;
    if (inedges[i] == -1) return (i + 1) % (points.length >> 1);
    var c = i;
    var dc = _sq(x - points[i * 2]) + _sq(y - points[i * 2 + 1]);
    final e0 = inedges[i];
    var e = e0;
    do {
      final t = triangles[e];
      final dt = _sq(x - points[t * 2]) + _sq(y - points[t * 2 + 1]);
      if (dt < dc) {
        dc = dt;
        c = t;
      }
      e = e % 3 == 2 ? e - 2 : e + 1;
      if (triangles[e] != i) break; // bad triangulation
      e = halfedges[e];
      if (e == -1) {
        e = hull[(_hullIndex[i] + 1) % hull.length];
        if (e != t) {
          if (_sq(x - points[e * 2]) + _sq(y - points[e * 2 + 1]) < dc) {
            return e;
          }
        }
        break;
      }
    } while (e != e0);
    return c;
  }
}

double _sq(double v) => v * v;
double _hypot(double a, double b) => math.sqrt(a * a + b * b);

/// The Voronoi diagram of a [Delaunay] triangulation, clipped to the box
/// [xmin], [ymin], [xmax], [ymax].
///
/// Internal to turf, used by `voronoi`.
class Voronoi {
  final Delaunay delaunay;
  final double xmin, ymin, xmax, ymax;
  late final Float64List circumcenters;
  late final Float64List vectors;

  Voronoi(this.delaunay, this.xmin, this.ymin, this.xmax, this.ymax) {
    if (!(xmax >= xmin) || !(ymax >= ymin)) {
      throw ArgumentError('invalid bounds');
    }
    vectors = Float64List(delaunay.points.length * 2);
    _init();
  }

  void _init() {
    final points = delaunay.points,
        hull = delaunay.hull,
        triangles = delaunay.triangles;
    double? bx, by; // lazily computed barycenter of the hull

    // Compute circumcenters.
    circumcenters = Float64List(triangles.length ~/ 3 * 2);
    for (var i = 0, j = 0, n = triangles.length; i < n; i += 3, j += 2) {
      final t1 = triangles[i] * 2;
      final t2 = triangles[i + 1] * 2;
      final t3 = triangles[i + 2] * 2;
      if (t1 < 0 || t2 < 0 || t3 < 0) continue; // degenerate placeholder
      final x1 = points[t1];
      final y1 = points[t1 + 1];
      final x2 = points[t2];
      final y2 = points[t2 + 1];
      final x3 = points[t3];
      final y3 = points[t3 + 1];

      final dx = x2 - x1;
      final dy = y2 - y1;
      final ex = x3 - x1;
      final ey = y3 - y1;
      final ab = (dx * ey - dy * ex) * 2;

      double x, y;
      if (ab.abs() < 1e-9) {
        // For a degenerate triangle, the circumcenter is at the infinity, in
        // a direction orthogonal to the halfedge and away from the "center"
        // of the diagram <bx, by>, defined as the hull's barycenter.
        if (bx == null || by == null) {
          var sx = 0.0, sy = 0.0;
          for (final h in hull) {
            sx += points[h * 2];
            sy += points[h * 2 + 1];
          }
          bx = sx / hull.length;
          by = sy / hull.length;
        }
        final a = 1e9 * _sign((bx - x1) * ey - (by - y1) * ex);
        x = (x1 + x3) / 2 - a * ey;
        y = (y1 + y3) / 2 + a * ex;
      } else {
        final d = 1 / ab;
        final bl = dx * dx + dy * dy;
        final cl = ex * ex + ey * ey;
        x = x1 + (ey * bl - dy * cl) * d;
        y = y1 + (dx * cl - ex * bl) * d;
      }
      circumcenters[j] = x;
      circumcenters[j + 1] = y;
    }

    // Compute exterior cell rays.
    if (hull.isEmpty) return;
    var h = hull[hull.length - 1];
    int p0, p1 = h * 4;
    double x0, x1 = points[2 * h];
    double y0, y1 = points[2 * h + 1];
    vectors.fillRange(0, vectors.length, 0);
    for (var i = 0; i < hull.length; ++i) {
      h = hull[i];
      p0 = p1;
      x0 = x1;
      y0 = y1;
      p1 = h * 4;
      x1 = points[2 * h];
      y1 = points[2 * h + 1];
      vectors[p0 + 2] = vectors[p1] = y0 - y1;
      vectors[p0 + 3] = vectors[p1 + 1] = x1 - x0;
    }
  }

  static double _sign(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

  bool contains(int i, double x, double y) {
    if (x.isNaN || y.isNaN) return false;
    return delaunay.step(i, x, y) == i;
  }

  /// The clipped cell of point [i] as a closed ring of `[x, y]` pairs, or
  /// `null` (coincident point or empty cell).
  List<List<double>>? cellPolygon(int i) {
    final points = _clip(i);
    if (points == null || points.isEmpty) return null;
    final ring = <List<double>>[
      [points[0], points[1]]
    ];
    var n = points.length;
    while (n > 1 && points[0] == points[n - 2] && points[1] == points[n - 1]) {
      n -= 2;
    }
    for (var k = 2; k < n; k += 2) {
      if (points[k] != points[k - 2] || points[k + 1] != points[k - 1]) {
        ring.add([points[k], points[k + 1]]);
      }
    }
    ring.add([ring[0][0], ring[0][1]]);
    return ring;
  }

  List<double>? _cell(int i) {
    final inedges = delaunay.inedges,
        halfedges = delaunay.halfedges,
        triangles = delaunay.triangles;
    final e0 = inedges[i];
    if (e0 == -1) return null; // coincident point
    final points = <double>[];
    var e = e0;
    do {
      final t = e ~/ 3;
      points
        ..add(circumcenters[t * 2])
        ..add(circumcenters[t * 2 + 1]);
      e = e % 3 == 2 ? e - 2 : e + 1;
      if (triangles[e] != i) break; // bad triangulation
      e = halfedges[e];
    } while (e != e0 && e != -1);
    return points;
  }

  List<double> _box() => [xmax, ymin, xmax, ymax, xmin, ymax, xmin, ymin];

  List<double>? _clip(int i) {
    // degenerate case (1 valid point: return the box)
    if (i == 0 && delaunay.hull.length == 1) return _box();
    final points = _cell(i);
    if (points == null) return null;
    final v = i * 4;
    return _simplify(vectors[v] != 0 || vectors[v + 1] != 0
        ? _clipInfinite(i, points, vectors[v], vectors[v + 1], vectors[v + 2],
            vectors[v + 3])
        : _clipFinite(i, points));
  }

  List<double>? _clipFinite(int i, List<double> points) {
    final n = points.length;
    List<double>? p;
    double x0, y0, x1 = points[n - 2], y1 = points[n - 1];
    int c0, c1 = _regioncode(x1, y1);
    int e0, e1 = 0;
    for (var j = 0; j < n; j += 2) {
      x0 = x1;
      y0 = y1;
      x1 = points[j];
      y1 = points[j + 1];
      c0 = c1;
      c1 = _regioncode(x1, y1);
      if (c0 == 0 && c1 == 0) {
        e0 = e1;
        e1 = 0;
        if (p != null) {
          p.addAll([x1, y1]);
        } else {
          p = [x1, y1];
        }
      } else {
        double sx0, sy0, sx1, sy1;
        if (c0 == 0) {
          final s = _clipSegment(x0, y0, x1, y1, c0, c1);
          if (s == null) continue;
          sx0 = s[0];
          sy0 = s[1];
          sx1 = s[2];
          sy1 = s[3];
        } else {
          final s = _clipSegment(x1, y1, x0, y0, c1, c0);
          if (s == null) continue;
          sx1 = s[0];
          sy1 = s[1];
          sx0 = s[2];
          sy0 = s[3];
          e0 = e1;
          e1 = _edgecode(sx0, sy0);
          if (e0 != 0 && e1 != 0) _edge(i, e0, e1, p!, p.length);
          if (p != null) {
            p.addAll([sx0, sy0]);
          } else {
            p = [sx0, sy0];
          }
        }
        e0 = e1;
        e1 = _edgecode(sx1, sy1);
        if (e0 != 0 && e1 != 0) _edge(i, e0, e1, p!, p.length);
        if (p != null) {
          p.addAll([sx1, sy1]);
        } else {
          p = [sx1, sy1];
        }
      }
    }
    if (p != null) {
      e0 = e1;
      e1 = _edgecode(p[0], p[1]);
      if (e0 != 0 && e1 != 0) _edge(i, e0, e1, p, p.length);
    } else if (contains(i, (xmin + xmax) / 2, (ymin + ymax) / 2)) {
      return _box();
    }
    return p;
  }

  List<double>? _clipSegment(
      double x0, double y0, double x1, double y1, int c0, int c1) {
    // for more robustness, always consider the segment in the same order
    final flip = c0 < c1;
    if (flip) {
      final tx = x0, ty = y0, tc = c0;
      x0 = x1;
      y0 = y1;
      c0 = c1;
      x1 = tx;
      y1 = ty;
      c1 = tc;
    }
    while (true) {
      if (c0 == 0 && c1 == 0) {
        return flip ? [x1, y1, x0, y0] : [x0, y0, x1, y1];
      }
      if (c0 & c1 != 0) return null;
      double x, y;
      final c = c0 != 0 ? c0 : c1;
      if (c & 8 != 0) {
        x = x0 + (x1 - x0) * (ymax - y0) / (y1 - y0);
        y = ymax;
      } else if (c & 4 != 0) {
        x = x0 + (x1 - x0) * (ymin - y0) / (y1 - y0);
        y = ymin;
      } else if (c & 2 != 0) {
        y = y0 + (y1 - y0) * (xmax - x0) / (x1 - x0);
        x = xmax;
      } else {
        y = y0 + (y1 - y0) * (xmin - x0) / (x1 - x0);
        x = xmin;
      }
      if (c0 != 0) {
        x0 = x;
        y0 = y;
        c0 = _regioncode(x0, y0);
      } else {
        x1 = x;
        y1 = y;
        c1 = _regioncode(x1, y1);
      }
    }
  }

  List<double>? _clipInfinite(int i, List<double> points, double vx0,
      double vy0, double vxn, double vyn) {
    List<double>? p = List<double>.of(points);
    var q = _project(p[0], p[1], vx0, vy0);
    if (q != null) p.insertAll(0, q);
    q = _project(p[p.length - 2], p[p.length - 1], vxn, vyn);
    if (q != null) p.addAll(q);
    p = _clipFinite(i, p);
    if (p != null) {
      var n = p.length;
      int c0, c1 = _edgecode(p[n - 2], p[n - 1]);
      for (var j = 0; j < n; j += 2) {
        c0 = c1;
        c1 = _edgecode(p[j], p[j + 1]);
        if (c0 != 0 && c1 != 0) {
          j = _edge(i, c0, c1, p, j);
          n = p.length;
        }
      }
    } else if (contains(i, (xmin + xmax) / 2, (ymin + ymax) / 2)) {
      p = [xmin, ymin, xmax, ymin, xmax, ymax, xmin, ymax];
    }
    return p;
  }

  int _edge(int i, int e0, int e1, List<double> p, int j) {
    while (e0 != e1) {
      double x, y;
      switch (e0) {
        case 5: // top-left
          e0 = 4;
          continue;
        case 4: // top
          e0 = 6;
          x = xmax;
          y = ymin;
          break;
        case 6: // top-right
          e0 = 2;
          continue;
        case 2: // right
          e0 = 10;
          x = xmax;
          y = ymax;
          break;
        case 10: // bottom-right
          e0 = 8;
          continue;
        case 8: // bottom
          e0 = 9;
          x = xmin;
          y = ymax;
          break;
        case 9: // bottom-left
          e0 = 1;
          continue;
        case 1: // left
          e0 = 5;
          x = xmin;
          y = ymin;
          break;
        default:
          return j;
      }
      // Note: this implicitly checks for out of bounds: if P[j] or P[j+1]
      // are undefined, the conditional statement will be executed.
      final outOfBounds = j + 1 >= p.length;
      if ((outOfBounds || p[j] != x || p[j + 1] != y) && contains(i, x, y)) {
        p.insertAll(j, [x, y]);
        j += 2;
      }
    }
    return j;
  }

  List<double>? _project(double x0, double y0, double vx, double vy) {
    var t = double.infinity;
    double c;
    double? x, y;
    if (vy < 0) {
      // top
      if (y0 <= ymin) return null;
      if ((c = (ymin - y0) / vy) < t) {
        y = ymin;
        x = x0 + (t = c) * vx;
      }
    } else if (vy > 0) {
      // bottom
      if (y0 >= ymax) return null;
      if ((c = (ymax - y0) / vy) < t) {
        y = ymax;
        x = x0 + (t = c) * vx;
      }
    }
    if (vx > 0) {
      // right
      if (x0 >= xmax) return null;
      if ((c = (xmax - x0) / vx) < t) {
        x = xmax;
        y = y0 + (t = c) * vy;
      }
    } else if (vx < 0) {
      // left
      if (x0 <= xmin) return null;
      if ((c = (xmin - x0) / vx) < t) {
        x = xmin;
        y = y0 + (t = c) * vy;
      }
    }
    if (x == null || y == null) return null;
    return [x, y];
  }

  int _edgecode(double x, double y) =>
      (x == xmin
          ? 1
          : x == xmax
              ? 2
              : 0) |
      (y == ymin
          ? 4
          : y == ymax
              ? 8
              : 0);

  int _regioncode(double x, double y) =>
      (x < xmin
          ? 1
          : x > xmax
              ? 2
              : 0) |
      (y < ymin
          ? 4
          : y > ymax
              ? 8
              : 0);

  List<double>? _simplify(List<double>? p) {
    if (p != null && p.length > 4) {
      for (var i = 0; i < p.length; i += 2) {
        final j = (i + 2) % p.length, k = (i + 4) % p.length;
        if (p[i] == p[j] && p[j] == p[k] ||
            p[i + 1] == p[j + 1] && p[j + 1] == p[k + 1]) {
          p.removeRange(j, j + 2);
          i -= 2;
        }
      }
      if (p.isEmpty) p = null;
    }
    return p;
  }
}
