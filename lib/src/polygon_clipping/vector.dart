part of 'polygon_clipping.dart';

/// A mutable point (or vector). Points keep identity: sweep events at the
/// same location are linked by sharing one [_Pt] instance.
class _Pt {
  _Dec x;
  _Dec y;

  /// Sweep events located at this point; `null` until the first one is
  /// created.
  List<_SweepEvent>? events;

  _Pt(this.x, this.y);

  @override
  String toString() => '[$x, $y]';
}

/// Cross product of two vectors with first point at origin.
_Dec _crossProduct(_Pt a, _Pt b) => a.x * b.y - a.y * b.x;

/// Dot product of two vectors with first point at origin.
_Dec _dotProduct(_Pt a, _Pt b) => a.x * b.x + a.y * b.y;

_Dec _length(_Pt v) => _dotProduct(v, v).sqrt();

/// The sine of the angle from pShared → pAngle to pShared → pBase.
_Dec _sineOfAngle(_Pt pShared, _Pt pBase, _Pt pAngle) {
  final vBase = _Pt(pBase.x - pShared.x, pBase.y - pShared.y);
  final vAngle = _Pt(pAngle.x - pShared.x, pAngle.y - pShared.y);
  return _crossProduct(vAngle, vBase).div(_length(vAngle)).div(_length(vBase));
}

/// The cosine of the angle from pShared → pAngle to pShared → pBase.
_Dec _cosineOfAngle(_Pt pShared, _Pt pBase, _Pt pAngle) {
  final vBase = _Pt(pBase.x - pShared.x, pBase.y - pShared.y);
  final vAngle = _Pt(pAngle.x - pShared.x, pAngle.y - pShared.y);
  return _dotProduct(vAngle, vBase).div(_length(vAngle)).div(_length(vBase));
}

/// The point where the line through [pt] with direction [v] crosses the
/// horizontal line at [y], or `null` for parallel lines.
_Pt? _horizontalIntersection(_Pt pt, _Pt v, _Dec y) {
  if (v.y.isZero) return null;
  return _Pt(pt.x + v.x.div(v.y) * (y - pt.y), y);
}

/// The point where the line through [pt] with direction [v] crosses the
/// vertical line at [x], or `null` for parallel lines.
_Pt? _verticalIntersection(_Pt pt, _Pt v, _Dec x) {
  if (v.x.isZero) return null;
  return _Pt(x, pt.y + v.y.div(v.x) * (x - pt.x));
}

/// The intersection of two lines, each given by a base point and a vector,
/// or `null` for parallel (including overlapping) lines.
_Pt? _intersection(_Pt pt1, _Pt v1, _Pt pt2, _Pt v2) {
  // take some shortcuts for vertical and horizontal lines
  // this also ensures we don't calculate an intersection and then discover
  // it's actually outside the bounding box of the line
  if (v1.x.isZero) return _verticalIntersection(pt2, v2, pt1.x);
  if (v2.x.isZero) return _verticalIntersection(pt1, v1, pt2.x);
  if (v1.y.isZero) return _horizontalIntersection(pt2, v2, pt1.y);
  if (v2.y.isZero) return _horizontalIntersection(pt1, v1, pt2.y);

  // General case for non-overlapping segments.
  // This algorithm is based on Schneider and Eberly.
  // http://www.cimec.org.ar/~ncalvo/Schneider_Eberly.pdf - pg 244

  final kross = _crossProduct(v1, v2);
  if (kross.isZero) return null;

  final ve = _Pt(pt2.x - pt1.x, pt2.y - pt1.y);
  final d1 = _crossProduct(ve, v1).div(kross);
  final d2 = _crossProduct(ve, v2).div(kross);

  // take the average of the two calculations to minimize rounding error
  final x1 = pt1.x + d2 * v1.x, x2 = pt2.x + d1 * v2.x;
  final y1 = pt1.y + d2 * v1.y, y2 = pt2.y + d1 * v2.y;
  return _Pt((x1 + x2).div(_Dec.two), (y1 + y2).div(_Dec.two));
}
