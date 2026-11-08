part of 'polygon_clipping.dart';

ArgumentError _invalidGeom() =>
    ArgumentError('Input geometry is not a valid Polygon or MultiPolygon');

class _RingIn {
  final _PolyIn poly;
  final bool isExterior;
  final List<_Segment> segments = [];
  late final _Bbox bbox;

  _RingIn(List<Position> geomRing, this.poly, this.isExterior) {
    if (geomRing.isEmpty) throw _invalidGeom();

    final firstPoint = _snapPosition(geomRing[0]);
    bbox = _Bbox(
      _Pt(firstPoint.x, firstPoint.y),
      _Pt(firstPoint.x, firstPoint.y),
    );

    var prevPoint = firstPoint;
    for (var i = 1, iMax = geomRing.length; i < iMax; i++) {
      final point = _snapPosition(geomRing[i]);
      // skip repeated points
      if (point.x.eq(prevPoint.x) && point.y.eq(prevPoint.y)) continue;
      segments.add(_Segment.fromRing(prevPoint, point, this));
      if (point.x < bbox.ll.x) bbox.ll.x = point.x;
      if (point.y < bbox.ll.y) bbox.ll.y = point.y;
      if (point.x > bbox.ur.x) bbox.ur.x = point.x;
      if (point.y > bbox.ur.y) bbox.ur.y = point.y;
      prevPoint = point;
    }
    // add segment from last to first if last is not the same as first
    if (!firstPoint.x.eq(prevPoint.x) || !firstPoint.y.eq(prevPoint.y)) {
      segments.add(_Segment.fromRing(prevPoint, firstPoint, this));
    }
  }

  static _Pt _snapPosition(Position p) {
    final x = p.lng.toDouble();
    final y = p.lat.toDouble();
    if (!x.isFinite || !y.isFinite) throw _invalidGeom();
    return _precision.snap(_Pt(_Dec.fromDouble(x), _Dec.fromDouble(y)));
  }

  List<_SweepEvent> getSweepEvents() {
    final sweepEvents = <_SweepEvent>[];
    for (final segment in segments) {
      sweepEvents.add(segment.leftSE);
      sweepEvents.add(segment.rightSE);
    }
    return sweepEvents;
  }
}

class _PolyIn {
  late final _RingIn exteriorRing;
  late final _Bbox bbox;
  final List<_RingIn> interiorRings = [];
  final _MultiPolyIn multiPoly;

  _PolyIn(List<List<Position>> geomPoly, this.multiPoly) {
    if (geomPoly.isEmpty) throw _invalidGeom();
    exteriorRing = _RingIn(geomPoly[0], this, true);
    // copy by value
    bbox = _Bbox(
      _Pt(exteriorRing.bbox.ll.x, exteriorRing.bbox.ll.y),
      _Pt(exteriorRing.bbox.ur.x, exteriorRing.bbox.ur.y),
    );
    for (var i = 1, iMax = geomPoly.length; i < iMax; i++) {
      final ring = _RingIn(geomPoly[i], this, false);
      if (ring.bbox.ll.x < bbox.ll.x) bbox.ll.x = ring.bbox.ll.x;
      if (ring.bbox.ll.y < bbox.ll.y) bbox.ll.y = ring.bbox.ll.y;
      if (ring.bbox.ur.x > bbox.ur.x) bbox.ur.x = ring.bbox.ur.x;
      if (ring.bbox.ur.y > bbox.ur.y) bbox.ur.y = ring.bbox.ur.y;
      interiorRings.add(ring);
    }
  }

  List<_SweepEvent> getSweepEvents() {
    final sweepEvents = exteriorRing.getSweepEvents();
    for (final ring in interiorRings) {
      sweepEvents.addAll(ring.getSweepEvents());
    }
    return sweepEvents;
  }
}

class _MultiPolyIn {
  final List<_PolyIn> polys = [];

  /// `null` for an empty multipolygon (polyclip-ts uses an infinite,
  /// inverted box, which overlaps nothing).
  _Bbox? bbox;
  final bool isSubject;

  _MultiPolyIn(MultiPolygonCoords geom, this.isSubject) {
    for (final geomPoly in geom) {
      final poly = _PolyIn(geomPoly, this);
      final bbox = this.bbox ??= _Bbox(
        _Pt(poly.bbox.ll.x, poly.bbox.ll.y),
        _Pt(poly.bbox.ur.x, poly.bbox.ur.y),
      );
      if (poly.bbox.ll.x < bbox.ll.x) bbox.ll.x = poly.bbox.ll.x;
      if (poly.bbox.ll.y < bbox.ll.y) bbox.ll.y = poly.bbox.ll.y;
      if (poly.bbox.ur.x > bbox.ur.x) bbox.ur.x = poly.bbox.ur.x;
      if (poly.bbox.ur.y > bbox.ur.y) bbox.ur.y = poly.bbox.ur.y;
      polys.add(poly);
    }
  }

  List<_SweepEvent> getSweepEvents() {
    final sweepEvents = <_SweepEvent>[];
    for (final poly in polys) {
      sweepEvents.addAll(poly.getSweepEvents());
    }
    return sweepEvents;
  }
}
