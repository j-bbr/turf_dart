part of 'polygon_clipping.dart';

class _SineCosine {
  final _Dec sine;
  final _Dec cosine;
  _SineCosine(this.sine, this.cosine);
}

class _SweepEvent {
  /// Orders sweep events in the sweep event queue.
  static int compare(_SweepEvent a, _SweepEvent b) {
    // favor event with a point that the sweep line hits first
    final ptCmp = comparePoints(a.point, b.point);
    if (ptCmp != 0) return ptCmp;

    // the points are the same, so link them if needed
    if (!identical(a.point, b.point)) a.link(b);

    // favor right events over left
    if (a.isLeft != b.isLeft) return a.isLeft ? 1 : -1;

    // we have two matching left or right endpoints
    // ordering of this case is the same as for their segments
    return _Segment.compare(a.segment, b.segment);
  }

  /// Orders points in sweep line order.
  static int comparePoints(_Pt aPt, _Pt bPt) {
    if (aPt.x < bPt.x) return -1;
    if (aPt.x > bPt.x) return 1;

    if (aPt.y < bPt.y) return -1;
    if (aPt.y > bPt.y) return 1;

    return 0;
  }

  _Pt point;
  bool isLeft;
  late _Segment segment;
  late _SweepEvent otherSE;
  _SweepEvent? consumedBy;

  /// Warning: [point] will be modified and re-used (for performance).
  _SweepEvent(this.point, this.isLeft) {
    final events = point.events;
    if (events == null) {
      point.events = [this];
    } else {
      events.add(this);
    }
  }

  void link(_SweepEvent other) {
    if (identical(other.point, point)) {
      throw StateError('Tried to link already linked events');
    }
    final otherEvents = other.point.events!;
    for (var i = 0, iMax = otherEvents.length; i < iMax; i++) {
      final evt = otherEvents[i];
      point.events!.add(evt);
      evt.point = point;
    }
    checkForConsuming();
  }

  /// Does a pass over the linked events and checks whether any pair of
  /// segments match and should be consumed.
  void checkForConsuming() {
    final events = point.events!;
    final numEvents = events.length;
    for (var i = 0; i < numEvents; i++) {
      final evt1 = events[i];
      if (evt1.segment.consumedBy != null) continue;
      for (var j = i + 1; j < numEvents; j++) {
        final evt2 = events[j];
        if (evt2.consumedBy != null) continue;
        if (!identical(evt1.otherSE.point.events, evt2.otherSE.point.events)) {
          continue;
        }
        evt1.segment.consume(evt2.segment);
      }
    }
  }

  List<_SweepEvent> getAvailableLinkedEvents() {
    // point.events is always of length 2 or greater
    final events = <_SweepEvent>[];
    for (final evt in point.events!) {
      if (!identical(evt, this) &&
          evt.segment.ringOut == null &&
          evt.segment.isInResult()) {
        events.add(evt);
      }
    }
    return events;
  }

  /// Returns a comparator for sorting linked events that favours the event
  /// giving the smallest left-side angle. All ring construction starts as
  /// low as possible heading to the right, so by always turning left as
  /// sharp as possible we get polygons without unnecessary loops and holes.
  int Function(_SweepEvent, _SweepEvent) getLeftmostComparator(
      _SweepEvent baseEvent) {
    final cache = <_SweepEvent, _SineCosine>{};

    _SineCosine fill(_SweepEvent linkedEvent) {
      final nextEvent = linkedEvent.otherSE;
      return _SineCosine(
        _sineOfAngle(point, baseEvent.point, nextEvent.point),
        _cosineOfAngle(point, baseEvent.point, nextEvent.point),
      );
    }

    return (_SweepEvent a, _SweepEvent b) {
      final ca = cache.putIfAbsent(a, () => fill(a));
      final cb = cache.putIfAbsent(b, () => fill(b));
      final asine = ca.sine, acosine = ca.cosine;
      final bsine = cb.sine, bcosine = cb.cosine;

      // both on or above x-axis
      if (asine.sign >= 0 && bsine.sign >= 0) {
        if (acosine < bcosine) return 1;
        if (acosine > bcosine) return -1;
        return 0;
      }

      // both below x-axis
      if (asine.sign < 0 && bsine.sign < 0) {
        if (acosine < bcosine) return -1;
        if (acosine > bcosine) return 1;
        return 0;
      }

      // one above x-axis, one below
      if (bsine < asine) return -1;
      if (bsine > asine) return 1;
      return 0;
    };
  }
}
