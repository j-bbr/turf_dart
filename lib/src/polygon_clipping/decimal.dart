part of 'polygon_clipping.dart';

/// Number of decimal places of [_Dec.div] and [_Dec.sqrt] results, as
/// bignumber.js' default `DECIMAL_PLACES`.
const int _decimalPlaces = 20;

final List<BigInt> _pow10Cache = [BigInt.one];
final BigInt _ten = BigInt.from(10);
final BigInt _two = BigInt.two;
final BigInt _four = BigInt.from(4);

BigInt _pow10(int n) {
  while (_pow10Cache.length <= n) {
    _pow10Cache.add(_pow10Cache.last * _ten);
  }
  return _pow10Cache[n];
}

/// An arbitrary-precision decimal number, with the arithmetic semantics
/// polyclip-ts gets from bignumber.js in its default configuration:
/// addition, subtraction and multiplication are exact, division and square
/// root are rounded to 20 decimal places, rounding half away from zero
/// (`ROUND_HALF_UP`).
///
/// Doubles are converted through their shortest round-trip decimal
/// representation, as `new BigNumber(number)` does, and back with correct
/// rounding, as `BigNumber.toNumber()` does. The clipper therefore computes
/// the same results as turf.js v7, on the VM and in the browser.
///
/// For speed, a value keeps the nearest double ([d]) next to its exact form
/// `u * 10^-s`, and each is computed only when first needed. Comparisons are
/// decided by the doubles whenever they differ, which is exact because
/// rounding to the nearest double is monotonic; values converted from a
/// double are equal exactly when their doubles are equal.
class _Dec implements Comparable<_Dec> {
  BigInt? _u;
  int _s;
  double? _d;

  /// Whether the value is the shortest decimal representation of [_d],
  /// i.e. was converted from a double.
  final bool _fromDouble;

  _Dec._(BigInt u, int s)
      : _u = u,
        _s = s,
        _fromDouble = false;

  _Dec.fromDouble(double d)
      : _d = d == 0 ? 0.0 : d, // -0.0 and 0.0 are the same decimal
        _s = 0,
        _fromDouble = true {
    if (!d.isFinite) {
      throw ArgumentError.value(d, 'coordinate', 'must be finite');
    }
  }

  static final _Dec zero = _Dec.fromDouble(0);
  static final _Dec two = _Dec.fromDouble(2);

  /// Parses a decimal string such as `-12.5`, `1e-7` or `1.5e+300`.
  factory _Dec.parse(String str) {
    var mantissa = str;
    var exp = 0;
    final e = str.indexOf(RegExp('[eE]'));
    if (e >= 0) {
      mantissa = str.substring(0, e);
      exp = int.parse(str.substring(e + 1));
    }
    var scale = 0;
    final dot = mantissa.indexOf('.');
    if (dot >= 0) {
      scale = mantissa.length - dot - 1;
      mantissa = mantissa.substring(0, dot) + mantissa.substring(dot + 1);
    }
    var u = BigInt.parse(mantissa);
    scale -= exp;
    if (scale < 0) {
      u *= _pow10(-scale);
      scale = 0;
    }
    return _Dec._(u, scale);
  }

  void _materialize() {
    if (_u != null) return;
    final d = _d!;
    if (d == d.truncateToDouble() && d.abs() < 9007199254740992) {
      _u = BigInt.from(d.toInt());
      _s = 0;
      return;
    }
    final parsed = _Dec.parse(d.toString());
    _u = parsed._u;
    _s = parsed._s;
  }

  /// Unscaled value of the exact form `u * 10^-s`.
  BigInt get u {
    _materialize();
    return _u!;
  }

  /// Scale of the exact form `u * 10^-s`, never negative.
  int get s {
    _materialize();
    return _s;
  }

  /// The nearest double, as `BigNumber.toNumber()`.
  double get d => _d ??= double.parse(_s == 0 ? '${_u!}' : '${_u!}e-$_s');

  bool get isZero => _fromDouble ? _d == 0 : _u!.sign == 0;

  int get sign {
    if (_fromDouble) {
      final d = _d!;
      return d > 0 ? 1 : (d < 0 ? -1 : 0);
    }
    return _u!.sign;
  }

  _Dec operator +(_Dec o) {
    final u = this.u, s = this.s, ou = o.u, os = o.s;
    if (s == os) return _Dec._(u + ou, s);
    if (s < os) return _Dec._(u * _pow10(os - s) + ou, os);
    return _Dec._(u + ou * _pow10(s - os), s);
  }

  _Dec operator -(_Dec o) {
    final u = this.u, s = this.s, ou = o.u, os = o.s;
    if (s == os) return _Dec._(u - ou, s);
    if (s < os) return _Dec._(u * _pow10(os - s) - ou, os);
    return _Dec._(u - ou * _pow10(s - os), s);
  }

  _Dec operator *(_Dec o) => _Dec._(u * o.u, s + o.s);

  _Dec operator -() => _fromDouble ? _Dec.fromDouble(-_d!) : _Dec._(-u, s);

  _Dec abs() => sign < 0 ? -this : this;

  /// Division, rounded to [_decimalPlaces] decimal places, half away from
  /// zero.
  _Dec div(_Dec o) {
    if (o.isZero) throw UnsupportedError('Division by zero');
    // (u / 10^s) / (ou / 10^os) * 10^dp = u * 10^(os + dp) / (ou * 10^s)
    final n = u * _pow10(o.s + _decimalPlaces);
    final s = this.s;
    final d = s == 0 ? o.u : o.u * _pow10(s);
    var q = n ~/ d;
    final r = n.remainder(d);
    if (r.sign != 0 && (r.abs() * _two) >= d.abs()) {
      q += (n.sign * d.sign) > 0 ? BigInt.one : -BigInt.one;
    }
    return _Dec._(q, _decimalPlaces);
  }

  /// Square root, rounded to [_decimalPlaces] decimal places, half up.
  _Dec sqrt() {
    if (sign < 0) throw UnsupportedError('Square root of negative');
    if (isZero) return zero;
    // sqrt(u / 10^s) * 10^dp = sqrt(u * 10^(2dp - s)); round(sqrt(m)) is
    // floor((floor(sqrt(4m)) + 1) / 2) and floor(sqrt(m)) = isqrt(floor(m)).
    final k = 2 * _decimalPlaces - s;
    final m4 = k >= 0 ? u * _pow10(k) * _four : (u * _four) ~/ _pow10(-k);
    final t = _isqrt(m4);
    return _Dec._((t + BigInt.one) ~/ _two, _decimalPlaces);
  }

  int _exactCompare(_Dec o) {
    final u = this.u, s = this.s, ou = o.u, os = o.s;
    if (s == os) return u.compareTo(ou);
    if (s < os) return (u * _pow10(os - s)).compareTo(ou);
    return u.compareTo(ou * _pow10(s - os));
  }

  @override
  int compareTo(_Dec o) {
    if (identical(this, o)) return 0;
    final a = d, b = o.d;
    if (a < b) return -1;
    if (a > b) return 1;
    if (_fromDouble && o._fromDouble) return 0;
    return _exactCompare(o);
  }

  bool operator <(_Dec o) => compareTo(o) < 0;
  bool operator <=(_Dec o) => compareTo(o) <= 0;
  bool operator >(_Dec o) => compareTo(o) > 0;
  bool operator >=(_Dec o) => compareTo(o) >= 0;
  bool eq(_Dec o) => compareTo(o) == 0;

  double toDouble() => d;

  @override
  String toString() => d.toString();
}

/// floor(sqrt(n)) for n >= 0.
BigInt _isqrt(BigInt n) {
  if (n < _two) return n;
  // initial guess from the bit length, then Newton's method
  var x = BigInt.one << ((n.bitLength + 1) >> 1);
  while (true) {
    final y = (x + n ~/ x) >> 1;
    if (y >= x) return x;
    x = y;
  }
}

/// The unit roundoff of doubles, 2^-53.
const double _unitRoundoff = 1.1102230246251565e-16;

/// The sign of `(ay - cy) * (bx - cx) - (ax - cx) * (by - cy)` for exact
/// decimal coordinates, computed with doubles when a forward error bound
/// proves the sign, and exactly otherwise.
int _orientSign(_Pt a, _Pt b, _Pt c) {
  final ax = a.x.d, ay = a.y.d, bx = b.x.d, by = b.y.d;
  final cx = c.x.d, cy = c.y.d;

  final t1 = ay - cy, t2 = bx - cx, t3 = ax - cx, t4 = by - cy;
  final p1 = t1 * t2, p2 = t3 * t4;
  final det = p1 - p2;

  // Each double coordinate is within one unit roundoff of the decimal it
  // approximates, and each difference adds one rounding: the error of a
  // difference is at most 3u(|x| + |y|).
  const u3 = 3 * _unitRoundoff;
  final e1 = u3 * (ay.abs() + cy.abs());
  final e2 = u3 * (bx.abs() + cx.abs());
  final e3 = u3 * (ax.abs() + cx.abs());
  final e4 = u3 * (by.abs() + cy.abs());
  final err = (t1.abs() * e2 +
          (t2.abs() + e2) * e1 +
          t3.abs() * e4 +
          (t4.abs() + e4) * e3 +
          _unitRoundoff * (p1.abs() + p2.abs() + det.abs())) *
      1.001;

  if (err.isFinite) {
    if (det > err) return 1;
    if (-det > err) return -1;
  }

  final exact = (a.y - c.y) * (b.x - c.x) - (a.x - c.x) * (b.y - c.y);
  return exact.sign;
}
