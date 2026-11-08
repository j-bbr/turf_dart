part of 'polygon_clipping.dart';

/// The sweep line status structure.
///
/// NOTE: We must be careful not to change any segments while they are in
/// the tree, as the tree cannot be told to rebalance itself. Before
/// splitting a segment that's in the tree, we remove it from the tree, do
/// the split, then re-insert it. (Even though splitting a segment
/// *shouldn't* change its correct position in the sweep line tree, the
/// reality is because of rounding errors, it sometimes does.)
class _SweepLine {
  final SplayTreeSet<_SweepEvent> queue;
  final SplayTreeMap<_Segment, _Segment> tree =
      SplayTreeMap<_Segment, _Segment>(_Segment.compare);
  final List<_Segment> segments = [];

  _SweepLine(this.queue);

  List<_SweepEvent> process(_SweepEvent event) {
    final segment = event.segment;
    final newEvents = <_SweepEvent>[];

    // if we've already been consumed by another segment,
    // clean up our body parts and get out
    if (event.consumedBy != null) {
      if (event.isLeft) {
        queue.remove(event.otherSE);
      } else {
        tree.remove(segment);
      }
      return newEvents;
    }

    if (event.isLeft) tree.putIfAbsent(segment, () => segment);

    // skip consumed segments still in tree
    _Segment? prevSeg = tree.lastKeyBefore(segment);
    while (prevSeg != null && prevSeg.consumedBy != null) {
      prevSeg = tree.lastKeyBefore(prevSeg);
    }

    // skip consumed segments still in tree
    _Segment? nextSeg = tree.firstKeyAfter(segment);
    while (nextSeg != null && nextSeg.consumedBy != null) {
      nextSeg = tree.firstKeyAfter(nextSeg);
    }

    if (event.isLeft) {
      // Check for intersections against the previous segment in the sweep
      // line
      _Pt? prevMySplitter;
      if (prevSeg != null) {
        final prevInter = prevSeg.getIntersection(segment);
        if (prevInter != null) {
          if (!segment.isAnEndpoint(prevInter)) prevMySplitter = prevInter;
          if (!prevSeg.isAnEndpoint(prevInter)) {
            newEvents.addAll(_splitSafely(prevSeg, prevInter));
          }
        }
      }

      // Check for intersections against the next segment in the sweep line
      _Pt? nextMySplitter;
      if (nextSeg != null) {
        final nextInter = nextSeg.getIntersection(segment);
        if (nextInter != null) {
          if (!segment.isAnEndpoint(nextInter)) nextMySplitter = nextInter;
          if (!nextSeg.isAnEndpoint(nextInter)) {
            newEvents.addAll(_splitSafely(nextSeg, nextInter));
          }
        }
      }

      // For simplicity, even if we find more than one intersection we only
      // spilt on the 'earliest' (sweep-line style) of the intersections.
      // The other intersection will be handled in a future process().
      if (prevMySplitter != null || nextMySplitter != null) {
        _Pt mySplitter;
        if (prevMySplitter == null) {
          mySplitter = nextMySplitter!;
        } else if (nextMySplitter == null) {
          mySplitter = prevMySplitter;
        } else {
          final cmpSplitters =
              _SweepEvent.comparePoints(prevMySplitter, nextMySplitter);
          mySplitter = cmpSplitters <= 0 ? prevMySplitter : nextMySplitter;
        }

        // Rounding errors can cause changes in ordering,
        // so remove afected segments and right sweep events before splitting
        queue.remove(segment.rightSE);
        newEvents.add(segment.rightSE);

        newEvents.addAll(segment.split(mySplitter));
      }

      if (newEvents.isNotEmpty) {
        // We found some intersections, so re-do the current event to
        // make sure sweep line ordering is totally consistent for later
        // use with the segment 'prev' pointers
        tree.remove(segment);
        newEvents.add(event);
      } else {
        // done with left event
        segments.add(segment);
        segment.prev = prevSeg;
      }
    } else {
      // event.isRight

      // since we're about to be removed from the sweep line, check for
      // intersections between our previous and next segments
      if (prevSeg != null && nextSeg != null) {
        final inter = prevSeg.getIntersection(nextSeg);
        if (inter != null) {
          if (!prevSeg.isAnEndpoint(inter)) {
            newEvents.addAll(_splitSafely(prevSeg, inter));
          }
          if (!nextSeg.isAnEndpoint(inter)) {
            newEvents.addAll(_splitSafely(nextSeg, inter));
          }
        }
      }

      tree.remove(segment);
    }

    return newEvents;
  }

  /// Safely splits a segment that is currently in the data structures, i.e.
  /// a segment other than the one that is currently being processed.
  List<_SweepEvent> _splitSafely(_Segment seg, _Pt pt) {
    // Rounding errors can cause changes in ordering,
    // so remove afected segments and right sweep events before splitting
    tree.remove(seg);
    final rightSE = seg.rightSE;
    queue.remove(rightSE);
    final newEvents = seg.split(pt);
    newEvents.add(rightSE);
    // splitting can trigger consumption
    if (seg.consumedBy == null) tree.putIfAbsent(seg, () => seg);
    return newEvents;
  }
}
