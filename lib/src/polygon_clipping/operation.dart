part of 'polygon_clipping.dart';

enum _OpType { union, intersection, xor, difference }

/// Limits on iterative processes to prevent infinite loops - usually caused
/// by floating-point math round-off errors.
const int _maxQueueSize = 1000000;
const int _maxSweepLineSegments = 1000000;

class _Operation {
  _OpType type = _OpType.union;
  int numMultiPolys = 0;

  MultiPolygonCoords run(
    _OpType type,
    MultiPolygonCoords geom,
    List<MultiPolygonCoords> moreGeoms,
  ) {
    this.type = type;
    _precision.reset();

    try {
      return _run(geom, moreGeoms);
    } finally {
      // free some memory we don't need anymore
      _precision.reset();
    }
  }

  MultiPolygonCoords _run(
    MultiPolygonCoords geom,
    List<MultiPolygonCoords> moreGeoms,
  ) {
    // Convert inputs to MultiPoly objects
    final multipolys = <_MultiPolyIn>[_MultiPolyIn(geom, true)];
    for (final g in moreGeoms) {
      multipolys.add(_MultiPolyIn(g, false));
    }
    numMultiPolys = multipolys.length;

    // BBox optimization for difference operation
    // If the bbox of a multipolygon that's part of the clipping doesn't
    // intersect the bbox of the subject at all, we can just drop that
    // multiploygon.
    if (type == _OpType.difference) {
      // in place removal
      final subject = multipolys[0];
      var i = 1;
      while (i < multipolys.length) {
        if (_getBboxOverlap(multipolys[i].bbox, subject.bbox) != null) {
          i++;
        } else {
          multipolys.removeAt(i);
        }
      }
    }

    // BBox optimization for intersection operation
    // If we can find any pair of multipolygons whose bbox does not overlap,
    // then the result will be empty.
    if (type == _OpType.intersection) {
      for (var i = 0, iMax = multipolys.length; i < iMax; i++) {
        final mpA = multipolys[i];
        for (var j = i + 1, jMax = multipolys.length; j < jMax; j++) {
          if (_getBboxOverlap(mpA.bbox, multipolys[j].bbox) == null) {
            return [];
          }
        }
      }
    }

    // Put segment endpoints in a priority queue
    final queue = SplayTreeSet<_SweepEvent>(_SweepEvent.compare);
    for (final mp in multipolys) {
      for (final evt in mp.getSweepEvents()) {
        queue.add(evt);

        if (queue.length > _maxQueueSize) {
          // prevents an infinite loop, an otherwise common manifestation of
          // bugs
          throw StateError(
              'Infinite loop when putting segment endpoints in a priority '
              'queue (queue size too big).');
        }
      }
    }

    // Pass the sweep line over those endpoints
    final sweepLine = _SweepLine(queue);
    while (queue.isNotEmpty) {
      final evt = queue.first;
      if (!queue.remove(evt)) {
        // prevents an infinite loop, an otherwise common manifestation of
        // bugs
        final seg = evt.segment;
        throw StateError(
            'Unable to pop() ${evt.isLeft ? 'left' : 'right'} SweepEvent '
            '[${evt.point.x}, ${evt.point.y}] from segment #${seg.id} '
            '[${seg.leftSE.point.x}, ${seg.leftSE.point.y}] -> '
            '[${seg.rightSE.point.x}, ${seg.rightSE.point.y}] from queue.');
      }

      if (queue.length > _maxQueueSize) {
        throw StateError('Infinite loop when passing sweep line over '
            'endpoints (queue size too big).');
      }

      if (sweepLine.segments.length > _maxSweepLineSegments) {
        throw StateError('Infinite loop when passing sweep line over '
            'endpoints (too many sweep line segments).');
      }

      final newEvents = sweepLine.process(evt);
      for (final newEvt in newEvents) {
        if (newEvt.consumedBy == null) queue.add(newEvt);
      }
    }

    // Collect and compile segments we're keeping into a multipolygon
    final ringsOut = _RingOut.factory(sweepLine.segments);
    final result = _MultiPolyOut(ringsOut);
    return result.getGeom();
  }
}

// singleton
final _Operation _operation = _Operation();
