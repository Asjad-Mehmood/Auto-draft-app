import 'package:auto_draft/src/engine/code_parser.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib = CodeLibrary.defaults();

  test('a code with a line number', () {
    final p = parseCode('RE1', lib);
    expect(p.refs.single.feature.code, 'RE');
    expect(p.refs.single.number, 1);
    expect(p.refs.single.key, 'RE#1');
  });

  test('a code without a number is line 0', () {
    expect(parseCode('wl', lib).refs.single.number, 0);
  });

  test('control words apply to the code before them', () {
    final p = parseCode('re2 st', lib);
    expect(p.refs.single.controls, {Control.start});
    expect(parseCode('BLD3 CLS', lib).refs.single.controls, {Control.close});
    expect(parseCode('WL1 ARC', lib).refs.single.controls, {Control.arc});
    expect(parseCode('WL1 EARC ARC', lib).refs.single.controls, {Control.endArc, Control.arc});
    expect(parseCode('BLD4 RECT', lib).refs.single.controls, {Control.rect});
  });

  test('one point on two lines', () {
    final p = parseCode('WL1 ST GT1', lib);
    expect(p.refs.map((r) => r.key), ['WL#1', 'GT#1']);
    expect(p.refs[0].controls, {Control.start});
    expect(p.refs[1].controls, isEmpty);
  });

  test('commas, slashes and semicolons separate words too', () {
    expect(parseCode('RE1,ST', lib).refs.single.controls, {Control.start});
    expect(parseCode('RE1/KB1', lib).refs.length, 2);
  });

  test('an unknown first word, remarks and stray controls', () {
    final p = parseCode('XYZ', lib);
    expect(p.refs, isEmpty);
    expect(p.unknown, 'XYZ');
    final q = parseCode('TR NEEM', lib);
    expect(q.refs.single.feature.code, 'TR');
    expect(q.remarks, ['NEEM']);
    final s = parseCode('ST RE1', lib);
    expect(s.strayControls, ['ST']);
    expect(s.refs.single.controls, isEmpty);
  });

  test('an empty code is a plain point', () {
    expect(parseCode('', lib).isEmpty, isTrue);
    expect(parseCode('   ', lib).isEmpty, isTrue);
  });

  test('a code that ends in digits wins over a shorter code', () {
    final l = CodeLibrary([
      const FeatureCode(code: 'TB', name: 'Top of bank', kind: CodeKind.line, layer: 'TB'),
      const FeatureCode(code: 'TB2', name: 'Second bank', kind: CodeKind.line, layer: 'TB2'),
    ]);
    expect(parseCode('TB2', l).refs.single.feature.code, 'TB2');
    expect(parseCode('TB21', l).refs.single.feature.code, 'TB2');
    expect(parseCode('TB21', l).refs.single.number, 1);
    expect(parseCode('TB7', l).refs.single.feature.code, 'TB');
  });

  test('control words cannot be codes', () {
    expect(validCode('CLS'), isFalse);
    expect(validCode('ST'), isFalse);
    expect(validCode('RE'), isTrue);
    expect(validCode('1RE'), isFalse);
  });

  test('the default codes are valid, unique and not control words', () {
    final seen = <String>{};
    for (final c in defaultCodes) {
      expect(validCode(c.code), isTrue, reason: c.code);
      expect(validLayer(c.layer), isTrue, reason: c.layer);
      expect(seen.add(c.code), isTrue, reason: 'duplicate ${c.code}');
      expect(lineTypes, contains(c.lineType));
      if (c.kind == CodeKind.point) expect(c.symbol, isNotEmpty, reason: c.code);
    }
  });

  test('a code list round-trips through JSON', () {
    final back = CodeLibrary.fromJsonString(lib.toJsonString())!;
    expect(back.all.length, lib.all.length);
    expect(back['TR']!.symbol, 'AD_TREE');
    expect(back['CL']!.lineType, 'CENTER');
    expect(CodeLibrary.fromJsonString('{"format":"x"}'), isNull);
    expect(CodeLibrary.fromJsonString('not json'), isNull);
  });
}
