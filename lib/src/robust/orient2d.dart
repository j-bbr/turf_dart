// Port of `orient2d` from robust-predicates 3.0.3
// (https://github.com/mourner/robust-predicates), itself a port of
// Jonathan Richard Shewchuk's "Adaptive Precision Floating-Point Arithmetic
// and Fast Robust Predicates for Computational Geometry".
//
// robust-predicates is released into the public domain (The Unlicense).
// The macros of the original source are expanded by hand below.

import 'dart:typed_data';

const double _epsilon = 1.1102230246251565e-16;
const double _splitter = 134217729;
const double _resulterrbound = (3 + 8 * _epsilon) * _epsilon;
const double _ccwerrboundA = (3 + 16 * _epsilon) * _epsilon;
const double _ccwerrboundB = (2 + 12 * _epsilon) * _epsilon;
const double _ccwerrboundC = (9 + 64 * _epsilon) * _epsilon * _epsilon;

final Float64List _b = Float64List(4);
final Float64List _c1 = Float64List(8);
final Float64List _c2 = Float64List(12);
final Float64List _d = Float64List(16);
final Float64List _u = Float64List(4);

/// Exact orientation test of the points a, b and c.
///
/// Computes the sign of `(ay - cy) * (bx - cx) - (ax - cx) * (by - cy)`
/// exactly, following robust-predicates' convention: in a y-up coordinate
/// system (such as lng/lat) the result is negative when a, b, c are in
/// counter-clockwise order, positive when clockwise, and zero when they are
/// collinear. The magnitude approximates twice the triangle's area.
double orient2d(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
) {
  final detleft = (ay - cy) * (bx - cx);
  final detright = (ax - cx) * (by - cy);
  final det = detleft - detright;

  final detsum = (detleft + detright).abs();
  if (det.abs() >= _ccwerrboundA * detsum) return det;

  return -_orient2dadapt(ax, ay, bx, by, cx, cy, detsum);
}

/// The non-robust version of [orient2d].
double orient2dfast(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
) =>
    (ay - cy) * (bx - cx) - (ax - cx) * (by - cy);

double _orient2dadapt(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
  double detsum,
) {
  final acx = ax - cx;
  final bcx = bx - cx;
  final acy = ay - cy;
  final bcy = by - cy;

  _crossProduct(acx, bcx, acy, bcy, _b);

  var det = _estimate(4, _b);
  var errbound = _ccwerrboundB * detsum;
  if (det >= errbound || -det >= errbound) {
    return det;
  }

  final acxtail = _twoDiffTail(ax, cx, acx);
  final bcxtail = _twoDiffTail(bx, cx, bcx);
  final acytail = _twoDiffTail(ay, cy, acy);
  final bcytail = _twoDiffTail(by, cy, bcy);

  if (acxtail == 0 && acytail == 0 && bcxtail == 0 && bcytail == 0) {
    return det;
  }

  errbound = _ccwerrboundC * detsum + _resulterrbound * det.abs();
  det += (acx * bcytail + bcy * acxtail) - (acy * bcxtail + bcx * acytail);
  if (det >= errbound || -det >= errbound) return det;

  _crossProduct(acxtail, bcx, acytail, bcy, _u);
  final c1len = _sum(4, _b, 4, _u, _c1);

  _crossProduct(acx, bcxtail, acy, bcytail, _u);
  final c2len = _sum(c1len, _c1, 4, _u, _c2);

  _crossProduct(acxtail, bcxtail, acytail, bcytail, _u);
  final dlen = _sum(c2len, _c2, 4, _u, _d);

  return _d[dlen - 1];
}

/// `Two_Diff_Tail(a, b, x, y)`: the roundoff error `y` of `x = a - b`.
double _twoDiffTail(double a, double b, double x) {
  final bvirt = a - x;
  return a - (x + bvirt) + (bvirt - b);
}

/// `Cross_Product(a, b, c, d, D)`: the exact expansion of `a * d - c * b`
/// written to `D[0..3]`.
void _crossProduct(double a, double b, double c, double d, Float64List out) {
  // Two_Product(a, d, s1, s0)
  final s1 = a * d;
  var cc = _splitter * a;
  var ahi = cc - (cc - a);
  var alo = a - ahi;
  cc = _splitter * d;
  var bhi = cc - (cc - d);
  var blo = d - bhi;
  final s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo);

  // Two_Product(c, b, t1, t0)
  final t1 = c * b;
  cc = _splitter * c;
  ahi = cc - (cc - c);
  alo = c - ahi;
  cc = _splitter * b;
  bhi = cc - (cc - b);
  blo = b - bhi;
  final t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo);

  // Two_Two_Diff(s1, s0, t1, t0, u3, D[2], D[1], D[0])
  // = Two_One_Diff(s1, s0, t0, _j, _0, D[0])
  var i = s0 - t0;
  var bvirt = s0 - i;
  out[0] = s0 - (i + bvirt) + (bvirt - t0);
  final j = s1 + i;
  bvirt = j - s1;
  final zero = s1 - (j - bvirt) + (i - bvirt);
  // + Two_One_Diff(_j, _0, t1, u3, D[2], D[1])
  i = zero - t1;
  bvirt = zero - i;
  out[1] = zero - (i + bvirt) + (bvirt - t1);
  final u3 = j + i;
  bvirt = u3 - j;
  out[2] = j - (u3 - bvirt) + (i - bvirt);
  out[3] = u3;
}

double _estimate(int elen, Float64List e) {
  var q = e[0];
  for (var i = 1; i < elen; i++) {
    q += e[i];
  }
  return q;
}

double _at(Float64List list, int i) => i < list.length ? list[i] : 0.0;

/// `fast_expansion_sum_zeroelim` from Shewchuk's original code.
int _sum(int elen, Float64List e, int flen, Float64List f, Float64List h) {
  double q, qnew, hh, bvirt;
  var enow = e[0];
  var fnow = f[0];
  var eindex = 0;
  var findex = 0;
  if ((fnow > enow) == (fnow > -enow)) {
    q = enow;
    enow = _at(e, ++eindex);
  } else {
    q = fnow;
    fnow = _at(f, ++findex);
  }
  var hindex = 0;
  if (eindex < elen && findex < flen) {
    if ((fnow > enow) == (fnow > -enow)) {
      // Fast_Two_Sum(enow, q, qnew, hh)
      qnew = enow + q;
      hh = q - (qnew - enow);
      enow = _at(e, ++eindex);
    } else {
      // Fast_Two_Sum(fnow, q, qnew, hh)
      qnew = fnow + q;
      hh = q - (qnew - fnow);
      fnow = _at(f, ++findex);
    }
    q = qnew;
    if (hh != 0) {
      h[hindex++] = hh;
    }
    while (eindex < elen && findex < flen) {
      if ((fnow > enow) == (fnow > -enow)) {
        // Two_Sum(q, enow, qnew, hh)
        qnew = q + enow;
        bvirt = qnew - q;
        hh = q - (qnew - bvirt) + (enow - bvirt);
        enow = _at(e, ++eindex);
      } else {
        // Two_Sum(q, fnow, qnew, hh)
        qnew = q + fnow;
        bvirt = qnew - q;
        hh = q - (qnew - bvirt) + (fnow - bvirt);
        fnow = _at(f, ++findex);
      }
      q = qnew;
      if (hh != 0) {
        h[hindex++] = hh;
      }
    }
  }
  while (eindex < elen) {
    qnew = q + enow;
    bvirt = qnew - q;
    hh = q - (qnew - bvirt) + (enow - bvirt);
    enow = _at(e, ++eindex);
    q = qnew;
    if (hh != 0) {
      h[hindex++] = hh;
    }
  }
  while (findex < flen) {
    qnew = q + fnow;
    bvirt = qnew - q;
    hh = q - (qnew - bvirt) + (fnow - bvirt);
    fnow = _at(f, ++findex);
    q = qnew;
    if (hh != 0) {
      h[hindex++] = hh;
    }
  }
  if (q != 0 || hindex == 0) {
    h[hindex++] = q;
  }
  return hindex;
}
