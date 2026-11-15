// UTM (WGS 84) ↔ latitude / longitude, for Google Earth. Krüger's series (third order in n), within
// a millimetre across a zone. Pakistan lies in zones 41 to 44 (Lahore and Islamabad 43,
// Karachi 42, Quetta 42, Peshawar 42).
import 'dart:math' as math;

const _a = 6378137.0;
const _f = 1 / 298.257223563;
const _k0 = 0.9996;

const _n = _f / (2 - _f);
final _bigA = _a / (1 + _n) * (1 + _n * _n / 4 + math.pow(_n, 4) / 64);

final _alpha = [
  _n / 2 - 2 / 3 * _n * _n + 5 / 16 * math.pow(_n, 3),
  13 / 48 * _n * _n - 3 / 5 * math.pow(_n, 3),
  61 / 240 * math.pow(_n, 3),
];
final _beta = [
  _n / 2 - 2 / 3 * _n * _n + 37 / 96 * math.pow(_n, 3),
  1 / 48 * _n * _n + 1 / 15 * math.pow(_n, 3),
  17 / 480 * math.pow(_n, 3),
];
final _delta = [
  2 * _n - 2 / 3 * _n * _n - 2 * math.pow(_n, 3),
  7 / 3 * _n * _n - 8 / 5 * math.pow(_n, 3),
  56 / 15 * math.pow(_n, 3),
];

double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

/// Latitude and longitude in degrees of a UTM point
(double, double) utmToLatLon(double e, double n, int zone, {bool north = true}) {
  final xi = (n - (north ? 0 : 10000000)) / (_k0 * _bigA);
  final eta = (e - 500000) / (_k0 * _bigA);
  var xi1 = xi, eta1 = eta;
  for (var j = 1; j <= 3; j++) {
    xi1 -= _beta[j - 1] * math.sin(2 * j * xi) * _cosh(2 * j * eta);
    eta1 -= _beta[j - 1] * math.cos(2 * j * xi) * _sinh(2 * j * eta);
  }
  final chi = math.asin(math.sin(xi1) / _cosh(eta1));
  var phi = chi;
  for (var j = 1; j <= 3; j++) {
    phi += _delta[j - 1] * math.sin(2 * j * chi);
  }
  final lon0 = (zone * 6 - 183) * math.pi / 180;
  final lon = lon0 + math.atan2(_sinh(eta1), math.cos(xi1));
  return (phi * 180 / math.pi, lon * 180 / math.pi);
}

/// UTM easting and northing of a latitude / longitude in the given zone
(double, double) latLonToUtm(double lat, double lon, int zone) {
  final phi = lat * math.pi / 180;
  final lam = (lon - (zone * 6 - 183)) * math.pi / 180;
  final e2 = 2 * math.sqrt(_n) / (1 + _n);
  final t = _sinh(_atanh(math.sin(phi)) - e2 * _atanh(e2 * math.sin(phi)));
  final xi1 = math.atan2(t, math.cos(lam));
  final eta1 = _atanh(math.sin(lam) / math.sqrt(1 + t * t));
  var xi = xi1, eta = eta1;
  for (var j = 1; j <= 3; j++) {
    xi += _alpha[j - 1] * math.sin(2 * j * xi1) * _cosh(2 * j * eta1);
    eta += _alpha[j - 1] * math.cos(2 * j * xi1) * _sinh(2 * j * eta1);
  }
  final e = 500000 + _k0 * _bigA * eta;
  final n = _k0 * _bigA * xi + (lat < 0 ? 10000000 : 0);
  return (e, n);
}
