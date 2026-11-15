// A survey point as it comes from the field: number, coordinates, level and the code the
// surveyor typed. Pure Dart (no Flutter), so the engine also runs on the command line.

class SurveyPoint {
  const SurveyPoint({required this.id, required this.e, required this.n, this.z, this.code = '', this.row = 0});

  /// The point number or name as written in the file ("101", "STN1")
  final String id;

  /// Easting and northing, in metres
  final double e;
  final double n;

  /// The level (reduced level), or null when the file has none for this point
  final double? z;

  /// The field code with everything the surveyor typed after it: "RE1 ST", "TR", "BLD2 CL"
  final String code;

  /// The line in the file it came from (1 = first line), for messages
  final int row;

  SurveyPoint copyWith({String? code, double? e, double? n, double? z}) =>
      SurveyPoint(id: id, e: e ?? this.e, n: n ?? this.n, z: z ?? this.z, code: code ?? this.code, row: row);

  @override
  String toString() => 'SurveyPoint($id, $e, $n, $z, "$code")';
}

/// A point on a drawn line or shape: easting, northing and level
class Vertex {
  const Vertex(this.e, this.n, [this.z = 0]);
  final double e;
  final double n;
  final double z;

  @override
  bool operator ==(Object other) => other is Vertex && other.e == e && other.n == n && other.z == z;

  @override
  int get hashCode => Object.hash(e, n, z);

  @override
  String toString() => 'Vertex($e, $n, $z)';
}
