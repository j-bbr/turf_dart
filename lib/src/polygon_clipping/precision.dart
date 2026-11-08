part of 'polygon_clipping.dart';

/// All number handling of the clipper that can be tuned sits behind this
/// interface: snapping incoming points and the orientation test.
abstract class _Precision {
  /// Snaps a point onto previously seen coordinate values (or returns it
  /// unchanged).
  _Pt snap(_Pt p);

  /// The sign of the orientation of [a], [b], [c]: the sign of
  /// `(ay - cy) * (bx - cx) - (ax - cx) * (by - cy)`, or `0` when the points
  /// count as collinear.
  int orient(_Pt a, _Pt b, _Pt c);

  /// Forgets all previously seen values.
  void reset();
}

/// polyclip-ts' precision handling on [_Dec] numbers.
///
/// Without [eps] (the default, as in turf.js) the orientation test is exact
/// and points are not snapped. With [eps], coordinates within [eps] of a
/// previously seen value are snapped to it and nearly collinear points
/// count as collinear.
class _DecimalPrecision implements _Precision {
  final _Dec? eps;
  SplayTreeSet<_Dec>? _xTree;
  SplayTreeSet<_Dec>? _yTree;

  _DecimalPrecision([this.eps]) {
    reset();
  }

  int _compare(_Dec a, _Dec b) {
    final e = eps;
    if (e != null && (b - a).abs() <= e) return 0;
    return a.compareTo(b);
  }

  @override
  void reset() {
    if (eps == null) return;
    _xTree = SplayTreeSet<_Dec>(_compare);
    _yTree = SplayTreeSet<_Dec>(_compare);
    snap(_Pt(_Dec.zero, _Dec.zero));
  }

  static _Dec _addAndReturn(SplayTreeSet<_Dec> tree, _Dec value) {
    final existing = tree.lookup(value);
    if (existing != null) return existing;
    tree.add(value);
    return value;
  }

  @override
  _Pt snap(_Pt p) {
    final xTree = _xTree, yTree = _yTree;
    if (xTree == null || yTree == null) return p;
    p.x = _addAndReturn(xTree, p.x);
    p.y = _addAndReturn(yTree, p.y);
    return p;
  }

  @override
  int orient(_Pt a, _Pt b, _Pt c) {
    final e = eps;
    if (e == null) return _orientSign(a, b, c);
    final ax = a.x, ay = a.y, cx = c.x, cy = c.y;
    final area2 = (ay - cy) * (b.x - cx) - (ax - cx) * (b.y - cy);
    {
      final dx = cx - ax, dy = cy - ay;
      if (area2 * area2 <= (dx * dx + dy * dy) * e) return 0;
    }
    return area2.sign;
  }
}

_Precision _precision = _DecimalPrecision();

/// Sets the snapping epsilon of the clipper, as polyclip-ts'
/// `setPrecision`; `null` (the default) means exact arithmetic without
/// snapping. For tests.
void clipSetPrecision(double? eps) {
  _precision = _DecimalPrecision(eps == null ? null : _Dec.fromDouble(eps));
}
