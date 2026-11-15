// The drawing for Google Earth (KML): a folder per feature with its lines in their colours, the point
// features as pins named after the code, and every survey point (switched off at first) with its
// number, code and level. Coordinates turned from UTM to latitude / longitude.
import 'aci.dart';
import 'drawing.dart';
import 'point.dart';
import 'utm.dart';

String writeKml(Drawing d, {required int zone, bool north = true, String title = ''}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
    ..writeln('<Document>')
    ..writeln('  <name>${_x(title.isEmpty ? 'Survey drawing' : title)}</name>')
    ..writeln(
      '  <description>${_x('Made with Auto Draft from UTM zone $zone${north ? 'N' : 'S'} (WGS 84)')}</description>',
    );

  String ll(Vertex v) {
    final (lat, lon) = utmToLatLon(v.e, v.n, zone, north: north);
    return '${lon.toStringAsFixed(8)},${lat.toStringAsFixed(8)},0';
  }

  // a style per layer: its colour as KML aabbggrr
  final layers = d.layers;
  for (final l in layers) {
    // bright colours read best on satellite pictures: AutoCAD's own (7 is white)
    final (rr, gg, bb) = aciRgb(l.color);
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    b
      ..writeln('  <Style id="${_id(l.name)}">')
      ..writeln('    <LineStyle><color>ff${h(bb)}${h(gg)}${h(rr)}</color><width>2</width></LineStyle>')
      ..writeln('    <PolyStyle><fill>0</fill></PolyStyle>')
      ..writeln(
        '    <IconStyle><color>ff${h(bb)}${h(gg)}${h(rr)}</color><scale>0.7</scale>'
        '<Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon></IconStyle>',
      )
      ..writeln('    <LabelStyle><scale>0.7</scale></LabelStyle>')
      ..writeln('  </Style>');
  }

  // lines, a folder per feature
  final byLayer = <String, List<DLine>>{};
  for (final l in d.lines) {
    (byLayer[l.layer] ??= []).add(l);
  }
  for (final e in byLayer.entries) {
    b.writeln('  <Folder><name>${_x(e.value.first.feature.name)}</name>');
    for (final l in e.value) {
      final name = '${l.feature.code}${l.number == 0 ? '' : l.number}';
      final coords = [...l.vertices.map(ll), if (l.closed && l.vertices.isNotEmpty) ll(l.vertices.first)].join(' ');
      b
        ..writeln('    <Placemark><name>${_x(name)}</name><styleUrl>#${_id(l.layer)}</styleUrl>')
        ..writeln('      <description>${_x('${l.feature.name}, points ${l.pointIds.join(', ')}')}</description>')
        ..writeln(
          '      <LineString><tessellate>1</tessellate><coordinates>$coords</coordinates></LineString></Placemark>',
        );
    }
    b.writeln('  </Folder>');
  }

  // point features
  final byFeature = <String, List<DSymbol>>{};
  for (final s in d.symbols.where((s) => s.feature != null)) {
    (byFeature[s.feature!.name] ??= []).add(s);
  }
  final pointsById = {for (final p in d.points) p.id: p};
  for (final e in byFeature.entries) {
    b.writeln('  <Folder><name>${_x(e.key)}</name>');
    for (final s in e.value) {
      final p = pointsById[s.pointId];
      final z = p?.z == null ? '' : ', level ${p!.z!.toStringAsFixed(d.options.levelDecimals)}';
      b.writeln(
        '    <Placemark><name>${_x(e.key)}</name><styleUrl>#${_id(s.layer)}</styleUrl>'
        '<description>${_x('Point ${s.pointId}$z')}</description><Point><coordinates>${ll(s.at)}</coordinates></Point></Placemark>',
      );
    }
    b.writeln('  </Folder>');
  }

  // contours, in their own colours
  if (d.contours.isNotEmpty) {
    for (final (name, layer) in [('minor', Layers.contourMinor), ('major', Layers.contourMajor)]) {
      final (rr, gg, bb) = aciRgb(layer.color);
      String h(int v) => v.toRadixString(16).padLeft(2, '0');
      b.writeln(
        '  <Style id="contour_$name"><LineStyle><color>ff${h(bb)}${h(gg)}${h(rr)}</color>'
        '<width>${name == 'major' ? 2 : 1}</width></LineStyle></Style>',
      );
    }
    b.writeln('  <Folder><name>Contours, every ${d.contourInterval} m</name>');
    for (final c in d.contours) {
      final coords = [...c.vertices.map(ll), if (c.closed) ll(c.vertices.first)].join(' ');
      b.writeln(
        '    <Placemark><name>${c.level.toStringAsFixed(2)}</name><styleUrl>#contour_${c.major ? 'major' : 'minor'}</styleUrl>'
        '<LineString><tessellate>1</tessellate><coordinates>$coords</coordinates></LineString></Placemark>',
      );
    }
    b.writeln('  </Folder>');
  }

  // every survey point, off at first (it can be many)
  b.writeln('  <Folder><name>All survey points (${d.points.length})</name><visibility>0</visibility>');
  for (final p in d.points) {
    final z = p.z == null ? '' : p.z!.toStringAsFixed(d.options.levelDecimals);
    b.writeln(
      '    <Placemark><name>${_x(p.id)}</name><visibility>0</visibility>'
      '<description>${_x([if (p.code.isNotEmpty) 'Code ${p.code}', if (z.isNotEmpty) 'Level $z', 'E ${p.e.toStringAsFixed(3)} N ${p.n.toStringAsFixed(3)}'].join(', '))}</description>'
      '<Point><coordinates>${ll(Vertex(p.e, p.n))}</coordinates></Point></Placemark>',
    );
  }
  b
    ..writeln('  </Folder>')
    ..writeln('</Document>')
    ..writeln('</kml>');
  return b.toString();
}

String _x(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _id(String layer) => 'L_${layer.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}';
