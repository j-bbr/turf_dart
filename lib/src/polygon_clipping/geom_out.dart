part of 'polygon_clipping.dart';

class _IntersectionLE {
  final int index;
  final _Pt point;
  _IntersectionLE(this.index, this.point);
}

class _RingOut {
  /// Given the segments from the sweep line pass, computes and returns a
  /// series of closed rings from all the segments marked to be part of the
  /// result.
  static List<_RingOut> factory(List<_Segment> allSegments) {
    final ringsOut = <_RingOut>[];

    for (final segment in allSegments) {
      if (!segment.isInResult() || segment.ringOut != null) continue;

      _SweepEvent prevEvent;
      var event = segment.leftSE;
      var nextEvent = segment.rightSE;
      final events = <_SweepEvent>[event];

      final startingPoint = event.point;
      final intersectionLEs = <_IntersectionLE>[];

      // Walk the chain of linked events to form a closed ring
      while (true) {
        prevEvent = event;
        event = nextEvent;
        events.add(event);

        // Is the ring complete?
        if (identical(event.point, startingPoint)) break;

        while (true) {
          final availableLEs = event.getAvailableLinkedEvents();

          // Did we hit a dead end? This shouldn't happen.
          // Indicates some earlier part of the algorithm malfunctioned.
          if (availableLEs.isEmpty) {
            final firstPt = events[0].point;
            final lastPt = events[events.length - 1].point;
            throw StateError(
                'Unable to complete output ring starting at [${firstPt.x},'
                ' ${firstPt.y}]. Last matching segment found ends at'
                ' [${lastPt.x}, ${lastPt.y}].');
          }

          // Only one way to go, so cotinue on the path
          if (availableLEs.length == 1) {
            nextEvent = availableLEs[0].otherSE;
            break;
          }

          // We must have an intersection. Check for a completed loop
          int? indexLE;
          for (var j = 0, jMax = intersectionLEs.length; j < jMax; j++) {
            if (identical(intersectionLEs[j].point, event.point)) {
              indexLE = j;
              break;
            }
          }
          // Found a completed loop. Cut that off and make a ring
          if (indexLE != null) {
            final intersectionLE = intersectionLEs[indexLE];
            intersectionLEs.removeRange(indexLE, intersectionLEs.length);
            final ringEvents =
                events.sublist(intersectionLE.index, events.length);
            events.removeRange(intersectionLE.index, events.length);
            ringEvents.insert(0, ringEvents[0].otherSE);
            ringsOut.add(_RingOut(ringEvents.reversed.toList()));
            continue;
          }
          // register the intersection
          intersectionLEs.add(_IntersectionLE(events.length, event.point));
          // Choose the left-most option to continue the walk
          final comparator = event.getLeftmostComparator(prevEvent);
          availableLEs.sort(comparator);
          nextEvent = availableLEs[0].otherSE;
          break;
        }
      }

      ringsOut.add(_RingOut(events));
    }
    return ringsOut;
  }

  final List<_SweepEvent> events;
  _PolyOut? poly;
  bool? _isExteriorRing;
  bool _enclosingRingSet = false;
  _RingOut? _enclosingRing;

  _RingOut(this.events) {
    for (final evt in events) {
      evt.segment.ringOut = this;
    }
  }

  List<Position>? getGeom() {
    // Remove superfluous points (ie extra points along a straight line),
    var prevPt = events[0].point;
    final points = <_Pt>[prevPt];
    for (var i = 1, iMax = events.length - 1; i < iMax; i++) {
      final pt = events[i].point;
      final nextPt = events[i + 1].point;
      if (_precision.orient(pt, prevPt, nextPt) == 0) continue;
      points.add(pt);
      prevPt = pt;
    }

    // ring was all (within rounding error of angle calc) colinear points
    if (points.length == 1) return null;

    // check if the starting point is necessary
    final pt = points[0];
    final nextPt = points[1];
    if (_precision.orient(pt, prevPt, nextPt) == 0) points.removeAt(0);

    points.add(points[0]);
    final exterior = isExteriorRing();
    final ordered = exterior ? points : points.reversed;
    return [for (final p in ordered) Position(p.x.toDouble(), p.y.toDouble())];
  }

  bool isExteriorRing() {
    var cached = _isExteriorRing;
    if (cached == null) {
      final enclosing = enclosingRing();
      cached = enclosing != null ? !enclosing.isExteriorRing() : true;
      _isExteriorRing = cached;
    }
    return cached;
  }

  _RingOut? enclosingRing() {
    if (!_enclosingRingSet) {
      _enclosingRing = _calcEnclosingRing();
      _enclosingRingSet = true;
    }
    return _enclosingRing;
  }

  /// Returns the ring that encloses this one, if any.
  _RingOut? _calcEnclosingRing() {
    // start with the ealier sweep line event so that the prevSeg
    // chain doesn't lead us inside of a loop of ours
    var leftMostEvt = events[0];
    for (var i = 1, iMax = events.length; i < iMax; i++) {
      final evt = events[i];
      if (_SweepEvent.compare(leftMostEvt, evt) > 0) leftMostEvt = evt;
    }

    var prevSeg = leftMostEvt.segment.prevInResult();
    var prevPrevSeg = prevSeg?.prevInResult();

    while (true) {
      // no segment found, thus no ring can enclose us
      if (prevSeg == null) return null;

      // no segments below prev segment found, thus the ring of the prev
      // segment must loop back around and enclose us
      if (prevPrevSeg == null) return prevSeg.ringOut;

      // if the two segments are of different rings, the ring of the prev
      // segment must either loop around us or the ring of the prev prev
      // seg, which would make us and the ring of the prev peers
      if (!identical(prevPrevSeg.ringOut, prevSeg.ringOut)) {
        if (!identical(prevPrevSeg.ringOut!.enclosingRing(), prevSeg.ringOut)) {
          return prevSeg.ringOut;
        } else {
          return prevSeg.ringOut!.enclosingRing();
        }
      }

      // two segments are from the same ring, so this was a penisula
      // of that ring. iterate downward, keep searching
      prevSeg = prevPrevSeg.prevInResult();
      prevPrevSeg = prevSeg?.prevInResult();
    }
  }
}

class _PolyOut {
  final _RingOut exteriorRing;
  final List<_RingOut> interiorRings = [];

  _PolyOut(this.exteriorRing) {
    exteriorRing.poly = this;
  }

  void addInterior(_RingOut ring) {
    interiorRings.add(ring);
    ring.poly = this;
  }

  List<List<Position>>? getGeom() {
    final exterior = exteriorRing.getGeom();
    // exterior ring was all (within rounding error of angle calc) colinear
    // points
    if (exterior == null) return null;
    final geom = <List<Position>>[exterior];
    for (final ring in interiorRings) {
      final ringGeom = ring.getGeom();
      // interior ring was all (within rounding error of angle calc) colinear
      // points
      if (ringGeom == null) continue;
      geom.add(ringGeom);
    }
    return geom;
  }
}

class _MultiPolyOut {
  final List<_RingOut> rings;
  late final List<_PolyOut> polys = _composePolys(rings);

  _MultiPolyOut(this.rings);

  MultiPolygonCoords getGeom() {
    final geom = <List<List<Position>>>[];
    for (final poly in polys) {
      final polyGeom = poly.getGeom();
      // exterior ring was all (within rounding error of angle calc) colinear
      // points
      if (polyGeom == null) continue;
      geom.add(polyGeom);
    }
    return geom;
  }

  static List<_PolyOut> _composePolys(List<_RingOut> rings) {
    final polys = <_PolyOut>[];
    for (final ring in rings) {
      if (ring.poly != null) continue;
      if (ring.isExteriorRing()) {
        polys.add(_PolyOut(ring));
      } else {
        final enclosingRing = ring.enclosingRing()!;
        if (enclosingRing.poly == null) polys.add(_PolyOut(enclosingRing));
        enclosingRing.poly!.addInterior(ring);
      }
    }
    return polys;
  }
}
