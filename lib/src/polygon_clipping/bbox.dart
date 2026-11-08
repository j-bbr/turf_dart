part of 'polygon_clipping.dart';

/// An axis-aligned bounding box: lower-left and upper-right corners.
class _Bbox {
  final _Pt ll;
  final _Pt ur;

  _Bbox(this.ll, this.ur);
}

bool _isInBbox(_Bbox bbox, _Pt point) =>
    bbox.ll.x <= point.x &&
    point.x <= bbox.ur.x &&
    bbox.ll.y <= point.y &&
    point.y <= bbox.ur.y;

/// Returns either `null`, or the overlap of the two boxes. If there is only
/// one point of overlap, a box with identical corners is returned.
_Bbox? _getBboxOverlap(_Bbox? b1, _Bbox? b2) {
  if (b1 == null || b2 == null) return null;
  // check if the bboxes overlap at all
  if (b2.ur.x < b1.ll.x ||
      b1.ur.x < b2.ll.x ||
      b2.ur.y < b1.ll.y ||
      b1.ur.y < b2.ll.y) {
    return null;
  }

  // find the middle two X values
  final lowerX = b1.ll.x < b2.ll.x ? b2.ll.x : b1.ll.x;
  final upperX = b1.ur.x < b2.ur.x ? b1.ur.x : b2.ur.x;

  // find the middle two Y values
  final lowerY = b1.ll.y < b2.ll.y ? b2.ll.y : b1.ll.y;
  final upperY = b1.ur.y < b2.ur.y ? b1.ur.y : b2.ur.y;

  // put those middle values together to get the overlap
  return _Bbox(_Pt(lowerX, lowerY), _Pt(upperX, upperY));
}
