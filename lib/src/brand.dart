// The product's name, version and colours, in one place. The release workflow stamps the version
// with --dart-define=APP_VERSION=x.y.z; a local build shows the version in pubspec.yaml.
import 'package:flutter/material.dart';

const appName = 'Auto Draft';
const appTagline = 'Survey points to a finished drawing';
const appPublisher = 'exceltokml.com';
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const websiteUrl = 'https://www.exceltokml.com';

/// The logo's colours: deep navy with survey gold, the same family as Excel to KML, Traverse & Level
/// and Slope Calculator.
abstract final class BrandColors {
  static const navy = Color(0xFF0A1A36);
  static const navyLight = Color(0xFF17386B);
  static const gold = Color(0xFFE9B949);
  static const goldLight = Color(0xFFF7D774);

  /// The drawing area, dark as in a CAD program
  static const canvas = Color(0xFF0B1220);
}
