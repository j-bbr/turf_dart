part of 'polygon_clipping.dart';

/// Gives segments unique ids, for consistent sorting of segments and sweep
/// events when all else is identical.
int _segmentId = 0;

class _State {
  final List<_RingIn> rings;
  final List<int> windings;
  final List<_MultiPolyIn> multiPolys;
  _State(this.rings, this.windings, this.multiPolys);
}

class _Segment {
  /// Orders segments in the sweep line tree.
  ///
  /// Consider the vertical line that lies an infinitesimal step to the right
  /// of the right-more of the two left endpoints of the input segments.
  /// Imagine slowly moving a point up from negative infinity in the
  /// increasing y direction. Which of the two segments will that point
  /// intersect first? That segment comes 'before' the other one.
  ///
  /// If neither segment would be intersected by such a line (if one or more
  /// of the segments are vertical), then the line to be considered is
  /// directly on the right-more of the two left inputs.
  static int compare(_Segment a, _Segment b) {
    final alx = a.leftSE.point.x;
    final blx = b.leftSE.point.x;
    final arx = a.rightSE.point.x;
    final brx = b.rightSE.point.x;

    // check if they're even in the same vertical plane
    if (brx < alx) return 1;
    if (arx < blx) return -1;

    final aly = a.leftSE.point.y;
    final bly = b.leftSE.point.y;
    final ary = a.rightSE.point.y;
    final bry = b.rightSE.point.y;

    // is left endpoint of segment B the right-more?
    if (alx < blx) {
      // are the two segments in the same horizontal plane?
      if (bly < aly && bly < ary) return 1;
      if (bly > aly && bly > ary) return -1;

      // is the B left endpoint colinear to segment A?
      final aCmpBLeft = a.comparePoint(b.leftSE.point);
      if (aCmpBLeft < 0) return 1;
      if (aCmpBLeft > 0) return -1;

      // is the A right endpoint colinear to segment B ?
      final bCmpARight = b.comparePoint(a.rightSE.point);
      if (bCmpARight != 0) return bCmpARight;

      // colinear segments, consider the one with left-more
      // left endpoint to be first (arbitrary?)
      return -1;
    }

    // is left endpoint of segment A the right-more?
    if (alx > blx) {
      if (aly < bly && aly < bry) return -1;
      if (aly > bly && aly > bry) return 1;

      // is the A left endpoint colinear to segment B?
      final bCmpALeft = b.comparePoint(a.leftSE.point);
      if (bCmpALeft != 0) return bCmpALeft;

      // is the B right endpoint colinear to segment A?
      final aCmpBRight = a.comparePoint(b.rightSE.point);
      if (aCmpBRight < 0) return 1;
      if (aCmpBRight > 0) return -1;

      // colinear segments, consider the one with left-more
      // left endpoint to be first (arbitrary?)
      return 1;
    }

    // if we get here, the two left endpoints are in the same
    // vertical plane, ie alx === blx

    // consider the lower left-endpoint to come first
    if (aly < bly) return -1;
    if (aly > bly) return 1;

    // left endpoints are identical
    // check for colinearity by using the left-more right endpoint

    // is the A right endpoint more left-more?
    if (arx < brx) {
      final bCmpARight = b.comparePoint(a.rightSE.point);
      if (bCmpARight != 0) return bCmpARight;
    }

    // is the B right endpoint more left-more?
    if (arx > brx) {
      final aCmpBRight = a.comparePoint(b.rightSE.point);
      if (aCmpBRight < 0) return 1;
      if (aCmpBRight > 0) return -1;
    }

    if (!arx.eq(brx)) {
      // are these two [almost] vertical segments with opposite orientation?
      // if so, the one with the lower right endpoint comes first
      final ay = ary - aly;
      final ax = arx - alx;
      final by = bry - bly;
      final bx = brx - blx;
      if (ay > ax && by < bx) return 1;
      if (ay < ax && by > bx) return -1;
    }

    // we have colinear segments with matching orientation
    // consider the one with more left-more right endpoint to be first
    if (arx > brx) return 1;
    if (arx < brx) return -1;

    // if we get here, two two right endpoints are in the same
    // vertical plane, ie arx === brx

    // consider the lower right-endpoint to come first
    if (ary < bry) return -1;
    if (ary > bry) return 1;

    // right endpoints identical as well, so the segments are idential
    // fall back on creation order as consistent tie-breaker
    if (a.id < b.id) return -1;
    if (a.id > b.id) return 1;

    // identical segment, ie a === b
    return 0;
  }

  final int id;
  _SweepEvent leftSE;
  _SweepEvent rightSE;
  List<_RingIn>? rings;
  List<int>? windings;
  _RingOut? ringOut;
  _Segment? consumedBy;
  _Segment? prev;

  bool _prevInResultSet = false;
  _Segment? _prevInResult;
  _State? _beforeState;
  _State? _afterState;
  bool? _isInResult;

  /// Warning: a reference to [rings] and [windings] is stored, and possibly
  /// modified later.
  _Segment(this.leftSE, this.rightSE, this.rings, this.windings)
      : id = ++_segmentId {
    leftSE.segment = this;
    leftSE.otherSE = rightSE;
    rightSE.segment = this;
    rightSE.otherSE = leftSE;
  }

  static _Segment fromRing(_Pt pt1, _Pt pt2, _RingIn ring) {
    _Pt leftPt, rightPt;
    int winding;

    // ordering the two points according to sweep line ordering
    final cmpPts = _SweepEvent.comparePoints(pt1, pt2);
    if (cmpPts < 0) {
      leftPt = pt1;
      rightPt = pt2;
      winding = 1;
    } else if (cmpPts > 0) {
      leftPt = pt2;
      rightPt = pt1;
      winding = -1;
    } else {
      throw StateError(
          'Tried to create degenerate segment at [${pt1.x}, ${pt1.y}]');
    }

    final leftSE = _SweepEvent(leftPt, true);
    final rightSE = _SweepEvent(rightPt, false);
    return _Segment(leftSE, rightSE, [ring], [winding]);
  }

  /// When a segment is split, the rightSE is replaced with a new sweep event.
  void replaceRightSE(_SweepEvent newRightSE) {
    rightSE = newRightSE;
    rightSE.segment = this;
    rightSE.otherSE = leftSE;
    leftSE.otherSE = rightSE;
  }

  _Bbox bbox() {
    final y1 = leftSE.point.y;
    final y2 = rightSE.point.y;
    return _Bbox(
      _Pt(leftSE.point.x, y1 < y2 ? y1 : y2),
      _Pt(rightSE.point.x, y1 > y2 ? y1 : y2),
    );
  }

  /// A vector from the left point to the right.
  _Pt vector() => _Pt(
        rightSE.point.x - leftSE.point.x,
        rightSE.point.y - leftSE.point.y,
      );

  bool isAnEndpoint(_Pt pt) =>
      (pt.x.eq(leftSE.point.x) && pt.y.eq(leftSE.point.y)) ||
      (pt.x.eq(rightSE.point.x) && pt.y.eq(rightSE.point.y));

  /// Compares this segment with a point.
  ///
  ///   1: point lies above the segment (to the left of vertical)
  ///   0: point is colinear to segment
  ///  -1: point lies below the segment (to the right of vertical)
  int comparePoint(_Pt point) =>
      _precision.orient(leftSE.point, point, rightSE.point);

  /// Given another segment, returns the first non-trivial intersection
  /// between the two segments (in terms of sweep line ordering), if it
  /// exists.
  ///
  /// A 'non-trivial' intersection is one that will cause one or both of the
  /// segments to be split(). As such, 'trivial' vs. 'non-trivial'
  /// intersection:
  ///
  ///   * endpoint of segA with endpoint of segB --> trivial
  ///   * endpoint of segA with point along segB --> non-trivial
  ///   * endpoint of segB with point along segA --> non-trivial
  ///   * point along segA with point along segB --> non-trivial
  ///
  /// If no non-trivial intersection exists, returns `null`.
  _Pt? getIntersection(_Segment other) {
    // If bboxes don't overlap, there can't be any intersections
    final tBbox = bbox();
    final oBbox = other.bbox();
    final bboxOverlap = _getBboxOverlap(tBbox, oBbox);
    if (bboxOverlap == null) return null;

    // We first check to see if the endpoints can be considered intersections.
    // This will 'snap' intersections to endpoints if possible, and will
    // handle cases of colinearity.

    final tlp = leftSE.point;
    final trp = rightSE.point;
    final olp = other.leftSE.point;
    final orp = other.rightSE.point;

    // does each endpoint touch the other segment?
    // note that we restrict the 'touching' definition to only allow segments
    // to touch endpoints that lie forward from where we are in the sweep line
    // pass
    final touchesOtherLSE = _isInBbox(tBbox, olp) && comparePoint(olp) == 0;
    final touchesThisLSE =
        _isInBbox(oBbox, tlp) && other.comparePoint(tlp) == 0;
    final touchesOtherRSE = _isInBbox(tBbox, orp) && comparePoint(orp) == 0;
    final touchesThisRSE =
        _isInBbox(oBbox, trp) && other.comparePoint(trp) == 0;

    // do left endpoints match?
    if (touchesThisLSE && touchesOtherLSE) {
      // these two cases are for colinear segments with matching left
      // endpoints, and one segment being longer than the other
      if (touchesThisRSE && !touchesOtherRSE) return trp;
      if (!touchesThisRSE && touchesOtherRSE) return orp;
      // either the two segments match exactly (two trival intersections)
      // or just on their left endpoint (one trivial intersection
      return null;
    }

    // does this left endpoint matches (other doesn't)
    if (touchesThisLSE) {
      // check for segments that just intersect on opposing endpoints
      if (touchesOtherRSE) {
        if (tlp.x.eq(orp.x) && tlp.y.eq(orp.y)) return null;
      }
      // t-intersection on left endpoint
      return tlp;
    }

    // does other left endpoint matches (this doesn't)
    if (touchesOtherLSE) {
      // check for segments that just intersect on opposing endpoints
      if (touchesThisRSE) {
        if (trp.x.eq(olp.x) && trp.y.eq(olp.y)) return null;
      }
      // t-intersection on left endpoint
      return olp;
    }

    // trivial intersection on right endpoints
    if (touchesThisRSE && touchesOtherRSE) return null;

    // t-intersections on just one right endpoint
    if (touchesThisRSE) return trp;
    if (touchesOtherRSE) return orp;

    // None of our endpoints intersect. Look for a general intersection
    // between infinite lines laid over the segments
    final pt = _intersection(tlp, vector(), olp, other.vector());

    // are the segments parrallel? Note that if they were colinear with
    // overlap, they would have an endpoint intersection and that case was
    // already handled above
    if (pt == null) return null;

    // is the intersection found between the lines not on the segments?
    if (!_isInBbox(bboxOverlap, pt)) return null;

    // round the the computed point if needed
    return _precision.snap(pt);
  }

  /// Splits this segment on [point].
  ///
  ///  * This segment retains its leftSE and gets a new rightSE.
  ///  * A new segment is generated which adopts the original rightSE, and
  ///    gets a new leftSE.
  ///
  /// Returns the newly generated sweep events.
  List<_SweepEvent> split(_Pt point) {
    final newEvents = <_SweepEvent>[];
    final alreadyLinked = point.events != null;

    final newLeftSE = _SweepEvent(point, true);
    final newRightSE = _SweepEvent(point, false);
    final oldRightSE = rightSE;
    replaceRightSE(newRightSE);
    newEvents.add(newRightSE);
    newEvents.add(newLeftSE);
    final newSeg = _Segment(
      newLeftSE,
      oldRightSE,
      List<_RingIn>.of(rings!),
      List<int>.of(windings!),
    );

    // when splitting a nearly vertical downward-facing segment,
    // sometimes one of the resulting new segments is vertical, in which
    // case its left and right events may need to be swapped
    if (_SweepEvent.comparePoints(newSeg.leftSE.point, newSeg.rightSE.point) >
        0) {
      newSeg.swapEvents();
    }
    if (_SweepEvent.comparePoints(leftSE.point, rightSE.point) > 0) {
      swapEvents();
    }

    // if the point we just used to create new sweep events with was already
    // linked to other events, we need to check if either of the affected
    // segments should be consumed
    if (alreadyLinked) {
      newLeftSE.checkForConsuming();
      newRightSE.checkForConsuming();
    }

    return newEvents;
  }

  /// Swaps which event is left and right.
  void swapEvents() {
    final tmpEvt = rightSE;
    rightSE = leftSE;
    leftSE = tmpEvt;
    leftSE.isLeft = true;
    rightSE.isLeft = false;
    final w = windings!;
    for (var i = 0, iMax = w.length; i < iMax; i++) {
      w[i] *= -1;
    }
  }

  /// Consumes another segment: takes over its rings and marks it consumed.
  /// Used for perfectly overlapping segments.
  void consume(_Segment other) {
    _Segment consumer = this;
    _Segment consumee = other;
    while (consumer.consumedBy != null) {
      consumer = consumer.consumedBy!;
    }
    while (consumee.consumedBy != null) {
      consumee = consumee.consumedBy!;
    }

    final cmp = _Segment.compare(consumer, consumee);
    if (cmp == 0) return; // already consumed
    // the winner of the consumption is the earlier segment
    // according to sweep line ordering
    if (cmp > 0) {
      final tmp = consumer;
      consumer = consumee;
      consumee = tmp;
    }

    // make sure a segment doesn't consume it's prev
    if (identical(consumer.prev, consumee)) {
      final tmp = consumer;
      consumer = consumee;
      consumee = tmp;
    }

    final consumeeRings = consumee.rings!;
    final consumeeWindings = consumee.windings!;
    final consumerRings = consumer.rings!;
    final consumerWindings = consumer.windings!;
    for (var i = 0, iMax = consumeeRings.length; i < iMax; i++) {
      final ring = consumeeRings[i];
      final winding = consumeeWindings[i];
      final index = consumerRings.indexOf(ring);
      if (index == -1) {
        consumerRings.add(ring);
        consumerWindings.add(winding);
      } else {
        consumerWindings[index] += winding;
      }
    }
    consumee.rings = null;
    consumee.windings = null;
    consumee.consumedBy = consumer;

    // mark sweep events consumed as to maintain ordering in sweep event queue
    consumee.leftSE.consumedBy = consumer.leftSE;
    consumee.rightSE.consumedBy = consumer.rightSE;
  }

  /// The first segment in the previous-segment chain that is in the result.
  _Segment? prevInResult() {
    if (_prevInResultSet) return _prevInResult;
    final p = prev;
    if (p == null) {
      _prevInResult = null;
    } else if (p.isInResult()) {
      _prevInResult = p;
    } else {
      _prevInResult = p.prevInResult();
    }
    _prevInResultSet = true;
    return _prevInResult;
  }

  _State beforeState() {
    final cached = _beforeState;
    if (cached != null) return cached;
    final p = prev;
    final _State state;
    if (p == null) {
      state = _State([], [], []);
    } else {
      final seg = p.consumedBy ?? p;
      state = seg.afterState();
    }
    _beforeState = state;
    return state;
  }

  _State afterState() {
    final cached = _afterState;
    if (cached != null) return cached;

    final before = beforeState();
    final ringsAfter = List<_RingIn>.of(before.rings);
    final windingsAfter = List<int>.of(before.windings);
    final mpsAfter = <_MultiPolyIn>[];
    final state = _State(ringsAfter, windingsAfter, mpsAfter);
    _afterState = state;

    // calculate ringsAfter, windingsAfter
    final myRings = rings!;
    final myWindings = windings!;
    for (var i = 0, iMax = myRings.length; i < iMax; i++) {
      final ring = myRings[i];
      final winding = myWindings[i];
      final index = ringsAfter.indexOf(ring);
      if (index == -1) {
        ringsAfter.add(ring);
        windingsAfter.add(winding);
      } else {
        windingsAfter[index] += winding;
      }
    }

    // calculate polysAfter
    final polysAfter = <_PolyIn>[];
    final polysExclude = <_PolyIn>[];
    for (var i = 0, iMax = ringsAfter.length; i < iMax; i++) {
      if (windingsAfter[i] == 0) continue; // non-zero rule
      final ring = ringsAfter[i];
      final poly = ring.poly;
      if (polysExclude.contains(poly)) continue;
      if (ring.isExterior) {
        polysAfter.add(poly);
      } else {
        if (!polysExclude.contains(poly)) polysExclude.add(poly);
        polysAfter.remove(ring.poly);
      }
    }

    // calculate multiPolysAfter
    for (final poly in polysAfter) {
      final mp = poly.multiPoly;
      if (!mpsAfter.contains(mp)) mpsAfter.add(mp);
    }

    return state;
  }

  /// Is this segment part of the final result?
  bool isInResult() {
    // if we've been consumed, we're not in the result
    if (consumedBy != null) return false;

    final cached = _isInResult;
    if (cached != null) return cached;

    final mpsBefore = beforeState().multiPolys;
    final mpsAfter = afterState().multiPolys;

    final bool result;
    switch (_operation.type) {
      case _OpType.union:
        // UNION - included iff:
        //  * On one side of us there is 0 poly interiors AND
        //  * On the other side there is 1 or more.
        result = mpsBefore.isEmpty != mpsAfter.isEmpty;
        break;

      case _OpType.intersection:
        // INTERSECTION - included iff:
        //  * on one side of us all multipolys are rep. with poly interiors AND
        //  * on the other side of us, not all multipolys are repsented
        //    with poly interiors
        final least = math.min(mpsBefore.length, mpsAfter.length);
        final most = math.max(mpsBefore.length, mpsAfter.length);
        result = most == _operation.numMultiPolys && least < most;
        break;

      case _OpType.xor:
        // XOR - included iff:
        //  * the difference between the number of multipolys represented
        //    with poly interiors on our two sides is an odd number
        final diff = (mpsBefore.length - mpsAfter.length).abs();
        result = diff % 2 == 1;
        break;

      case _OpType.difference:
        // DIFFERENCE included iff:
        //  * on exactly one side, we have just the subject
        bool isJustSubject(List<_MultiPolyIn> mps) =>
            mps.length == 1 && mps[0].isSubject;
        result = isJustSubject(mpsBefore) != isJustSubject(mpsAfter);
        break;
    }

    _isInResult = result;
    return result;
  }
}
