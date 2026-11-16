// Reads a PDF file: its objects, the cross-reference table (or stream), compressed object
// streams and the page tree. Plain Dart, so the command line and the tests use it too.
//
// Only what drafting needs: the pages, their content streams and resources (fonts, forms, the
// layers). Encrypted files are refused with a clear message.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Inflate;

/// A name, e.g. /Type
class PdfName {
  const PdfName(this.name);
  final String name;
  @override
  bool operator ==(Object other) => other is PdfName && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => '/$name';
}

/// A reference to an object: "12 0 R"
class PdfRef {
  const PdfRef(this.num, this.gen);
  final int num, gen;
  @override
  bool operator ==(Object other) => other is PdfRef && other.num == num && other.gen == gen;
  @override
  int get hashCode => num * 31 + gen;
  @override
  String toString() => '$num $gen R';
}

/// A string, as its bytes (literal or hex)
class PdfString {
  const PdfString(this.bytes);
  final Uint8List bytes;

  /// As text: UTF-16 with a byte-order mark, else one character per byte (PDFDocEncoding ≈ Latin-1)
  String get text {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codes = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        codes.add(bytes[i] << 8 | bytes[i + 1]);
      }
      return String.fromCharCodes(codes);
    }
    return latin1.decode(bytes);
  }

  @override
  String toString() => '($text)';
}

/// A dictionary followed by its (still encoded) data
class PdfStream {
  PdfStream(this.dict, this.raw);
  final Map<String, Object?> dict;
  final Uint8List raw;
}

/// The file could not be read
class PdfReadError implements Exception {
  PdfReadError(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------------------------
// Lexer: the tokens of the PDF syntax, also used for content streams
// ---------------------------------------------------------------------------------------------

bool isPdfWhite(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00;
bool isPdfDelim(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3C ||
    c == 0x3E ||
    c == 0x5B ||
    c == 0x5D ||
    c == 0x7B ||
    c == 0x7D ||
    c == 0x2F ||
    c == 0x25;

/// An operator or keyword in the stream (obj, R, m, l, BT …)
class PdfKeyword {
  const PdfKeyword(this.word);
  final String word;
  @override
  String toString() => word;
}

/// Marks the end of an array or dictionary while parsing
class _Close {
  const _Close(this.c);
  final int c;
}

class PdfLexer {
  PdfLexer(this.b, [this.pos = 0]);
  final Uint8List b;
  int pos;

  bool get atEnd => pos >= b.length;

  void skipWhite() {
    while (pos < b.length) {
      final c = b[pos];
      if (isPdfWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        // comment to the end of the line
        while (pos < b.length && b[pos] != 0x0A && b[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// The next object; a keyword as [PdfKeyword]; null at the end
  Object? next() {
    skipWhite();
    if (pos >= b.length) return null;
    final c = b[pos];
    switch (c) {
      case 0x2F: // /Name
        pos++;
        final start = pos;
        while (pos < b.length && !isPdfWhite(b[pos]) && !isPdfDelim(b[pos])) {
          pos++;
        }
        return PdfName(_unescapeName(latin1.decode(b.sublist(start, pos))));
      case 0x28: // (string)
        return _literal();
      case 0x3C: // <hex> or <<dict>>
        if (pos + 1 < b.length && b[pos + 1] == 0x3C) {
          pos += 2;
          return _dict();
        }
        return _hex();
      case 0x5B: // [array]
        pos++;
        return _array();
      case 0x5D:
      case 0x3E:
        pos += c == 0x3E && pos + 1 < b.length && b[pos + 1] == 0x3E ? 2 : 1;
        return _Close(c);
      case 0x7B:
      case 0x7D:
        pos++;
        return PdfKeyword(String.fromCharCode(c));
      case 0x29:
        pos++;
        return next();
    }
    // a number or a keyword
    final start = pos;
    while (pos < b.length && !isPdfWhite(b[pos]) && !isPdfDelim(b[pos])) {
      pos++;
    }
    if (pos == start) {
      pos++;
      return next();
    }
    final s = latin1.decode(b.sublist(start, pos));
    final n = num.tryParse(s);
    if (n != null) return n;
    if (s.startsWith('.') || s.startsWith('-.') || s.startsWith('+')) {
      final v = double.tryParse(s.replaceFirst('+', ''));
      if (v != null) return v;
    }
    switch (s) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    return PdfKeyword(s);
  }

  /// The next object with "n g R" read as a reference (in files, not in content streams)
  Object? nextObject() {
    final o = next();
    if (o is int) {
      final save = pos;
      final g = next();
      if (g is int) {
        final r = next();
        if (r is PdfKeyword && r.word == 'R') return PdfRef(o, g);
      }
      pos = save;
    }
    return o;
  }

  String _unescapeName(String s) {
    if (!s.contains('#')) return s;
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '#' && i + 2 < s.length) {
        final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (v != null) {
          out.writeCharCode(v);
          i += 2;
          continue;
        }
      }
      out.write(s[i]);
    }
    return out.toString();
  }

  PdfString _literal() {
    pos++; // (
    final out = <int>[];
    var depth = 1;
    while (pos < b.length) {
      final c = b[pos++];
      if (c == 0x5C) {
        if (pos >= b.length) break;
        final e = b[pos++];
        switch (e) {
          case 0x6E:
            out.add(0x0A);
          case 0x72:
            out.add(0x0D);
          case 0x74:
            out.add(0x09);
          case 0x62:
            out.add(0x08);
          case 0x66:
            out.add(0x0C);
          case 0x0D:
            if (pos < b.length && b[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var k = 0; k < 2 && pos < b.length && b[pos] >= 0x30 && b[pos] <= 0x37; k++) {
                v = v * 8 + (b[pos++] - 0x30);
              }
              out.add(v & 0xFF);
            } else {
              out.add(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.add(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        out.add(c);
      } else {
        out.add(c);
      }
    }
    return PdfString(Uint8List.fromList(out));
  }

  PdfString _hex() {
    pos++; // <
    final digits = <int>[];
    while (pos < b.length && b[pos] != 0x3E) {
      final c = b[pos++];
      final v = c >= 0x30 && c <= 0x39
          ? c - 0x30
          : c >= 0x41 && c <= 0x46
          ? c - 0x37
          : c >= 0x61 && c <= 0x66
          ? c - 0x57
          : -1;
      if (v >= 0) digits.add(v);
    }
    pos++; // >
    if (digits.length.isOdd) digits.add(0);
    final out = Uint8List(digits.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = digits[2 * i] << 4 | digits[2 * i + 1];
    }
    return PdfString(out);
  }

  List<Object?> _array() {
    final out = <Object?>[];
    while (true) {
      final o = nextObject();
      if (o == null && pos >= b.length) break;
      if (o is _Close) break;
      out.add(o);
    }
    return out;
  }

  Map<String, Object?> _dict() {
    final out = <String, Object?>{};
    while (true) {
      final k = next();
      if (k == null && pos >= b.length) break;
      if (k is _Close) break;
      if (k is! PdfName) continue;
      final v = nextObject();
      if (v is _Close) break;
      out[k.name] = v;
    }
    return out;
  }
}

// ---------------------------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------------------------

Uint8List _inflate(Uint8List data) {
  // skip the 2-byte zlib header; some writers get the checksum wrong, so it isn't checked
  if (data.length < 2) return Uint8List(0);
  final body = (data[0] & 0x0F) == 8 ? data.sublist(2) : data;
  try {
    return Uint8List.fromList(Inflate(body).getBytes());
  } catch (_) {
    return Uint8List.fromList(Inflate(data).getBytes());
  }
}

Uint8List _png(Uint8List data, Map<String, Object?>? parms) {
  final predictor = (parms?['Predictor'] as num?)?.toInt() ?? 1;
  if (predictor < 10) return data;
  final colors = (parms?['Colors'] as num?)?.toInt() ?? 1;
  final bpc = (parms?['BitsPerComponent'] as num?)?.toInt() ?? 8;
  final columns = (parms?['Columns'] as num?)?.toInt() ?? 1;
  final bpp = (colors * bpc + 7) ~/ 8;
  final row = (columns * colors * bpc + 7) ~/ 8;
  final out = BytesBuilder();
  var prev = Uint8List(row);
  for (var i = 0; i + row < data.length + 1 && i < data.length; i += row + 1) {
    final type = data[i];
    final cur = Uint8List(row);
    for (var x = 0; x < row && i + 1 + x < data.length; x++) {
      final raw = data[i + 1 + x];
      final left = x >= bpp ? cur[x - bpp] : 0;
      final up = prev[x];
      final upLeft = x >= bpp ? prev[x - bpp] : 0;
      cur[x] = switch (type) {
        1 => raw + left,
        2 => raw + up,
        3 => raw + ((left + up) >> 1),
        4 => raw + _paeth(left, up, upLeft),
        _ => raw,
      };
    }
    out.add(cur);
    prev = cur;
  }
  return out.toBytes();
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
}

Uint8List _asciiHex(Uint8List d) {
  final s = latin1.decode(d).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  final t = s.length.isOdd ? '${s}0' : s;
  return Uint8List.fromList([for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16)]);
}

Uint8List _ascii85(Uint8List d) {
  final out = BytesBuilder();
  final group = <int>[];
  for (final c in d) {
    if (c == 0x7E) break; // ~>
    if (isPdfWhite(c)) continue;
    if (c == 0x7A && group.isEmpty) {
      out.add([0, 0, 0, 0]);
      continue;
    }
    group.add(c - 33);
    if (group.length == 5) {
      var v = 0;
      for (final g in group) {
        v = v * 85 + g;
      }
      out.add([v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF]);
      group.clear();
    }
  }
  if (group.isNotEmpty) {
    final n = group.length;
    while (group.length < 5) {
      group.add(84);
    }
    var v = 0;
    for (final g in group) {
      v = v * 85 + g;
    }
    out.add([v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF].sublist(0, n - 1));
  }
  return out.toBytes();
}

Uint8List _lzw(Uint8List d, Map<String, Object?>? parms) {
  final early = (parms?['EarlyChange'] as num?)?.toInt() ?? 1;
  final out = BytesBuilder();
  var table = <List<int>>[
    for (var i = 0; i < 256; i++) [i],
    [],
    [],
  ];
  var width = 9;
  var bitBuf = 0, bits = 0;
  List<int>? prev;
  for (var i = 0; i < d.length; i++) {
    bitBuf = bitBuf << 8 | d[i];
    bits += 8;
    while (bits >= width) {
      final code = bitBuf >> (bits - width) & ((1 << width) - 1);
      bits -= width;
      bitBuf &= (1 << bits) - 1;
      if (code == 256) {
        table = [
          for (var j = 0; j < 256; j++) [j],
          [],
          [],
        ];
        width = 9;
        prev = null;
        continue;
      }
      if (code == 257) return out.toBytes();
      List<int> entry;
      if (code < table.length) {
        entry = table[code];
        if (prev != null) table.add([...prev, entry[0]]);
      } else if (prev != null) {
        entry = [...prev, prev[0]];
        table.add(entry);
      } else {
        continue;
      }
      out.add(entry);
      prev = entry;
      if (table.length + early >= (1 << width) && width < 12) width++;
    }
  }
  return out.toBytes();
}

/// A stream's data with its filters undone (images are left encoded: drafting doesn't need them)
Uint8List decodeStream(PdfStream s, PdfFile? file) {
  final filters = file?.resolve(s.dict['Filter']) ?? s.dict['Filter'];
  final parms = file?.resolve(s.dict['DecodeParms']) ?? s.dict['DecodeParms'];
  final fs = filters is List ? filters : (filters == null ? const [] : [filters]);
  final ps = parms is List ? parms : [parms];
  var data = s.raw;
  for (var i = 0; i < fs.length; i++) {
    final f = (fs[i] as PdfName?)?.name ?? '';
    final p = i < ps.length ? (file?.resolve(ps[i]) ?? ps[i]) as Map<String, Object?>? : null;
    switch (f) {
      case 'FlateDecode' || 'Fl':
        data = _png(_inflate(data), p);
      case 'LZWDecode' || 'LZW':
        data = _png(_lzw(data, p), p);
      case 'ASCIIHexDecode' || 'AHx':
        data = _asciiHex(data);
      case 'ASCII85Decode' || 'A85':
        data = _ascii85(data);
      default:
        return data; // DCT, JPX, CCITT …: images, left as they are
    }
  }
  return data;
}

// ---------------------------------------------------------------------------------------------
// The file
// ---------------------------------------------------------------------------------------------

class PdfFile {
  PdfFile._(this.bytes);

  final Uint8List bytes;
  final _offsets = <int, int>{}; // object number → byte offset
  final _inStream = <int, (int, int)>{}; // object number → (object stream, index)
  final _cache = <int, Object?>{};
  Map<String, Object?> trailer = {};

  static PdfFile parse(Uint8List bytes) {
    final f = PdfFile._(bytes);
    if (bytes.length < 8 || !latin1.decode(bytes.sublist(0, 1024.clamp(0, bytes.length))).contains('%PDF')) {
      throw PdfReadError("This isn't a PDF file.");
    }
    try {
      f._readXref();
    } catch (_) {
      f._offsets.clear();
      f._inStream.clear();
    }
    if (f._offsets.isEmpty && f._inStream.isEmpty || f.trailer['Root'] == null) f._scan();
    if (f.trailer['Encrypt'] != null) {
      throw PdfReadError(
        'This PDF is protected with a password or permissions. Save an unprotected copy from the program that made it, then open that.',
      );
    }
    return f;
  }

  /// The object a reference points to (anything else as it is)
  Object? resolve(Object? o) {
    var v = o;
    for (var guard = 0; v is PdfRef && guard < 32; guard++) {
      v = object(v.num);
    }
    return v;
  }

  Map<String, Object?>? dict(Object? o) {
    final v = resolve(o);
    if (v is Map<String, Object?>) return v;
    if (v is PdfStream) return v.dict;
    return null;
  }

  Object? object(int n) {
    if (_cache.containsKey(n)) return _cache[n];
    _cache[n] = null; // guards against loops
    Object? v;
    final at = _offsets[n];
    if (at != null) {
      v = _readAt(at);
    } else if (_inStream[n] case (final sn, final idx)) {
      v = _fromObjectStream(sn, idx, n);
    }
    _cache[n] = v;
    return v;
  }

  Object? _readAt(int at) {
    final lx = PdfLexer(bytes, at);
    final a = lx.next(), b = lx.next(), kw = lx.next();
    if (a is! int || b is! int || kw is! PdfKeyword || kw.word != 'obj') return null;
    final v = lx.nextObject();
    if (v is Map<String, Object?>) {
      final save = lx.pos;
      final k = lx.next();
      if (k is PdfKeyword && k.word == 'stream') {
        var p = lx.pos;
        if (p < bytes.length && bytes[p] == 0x0D) p++;
        if (p < bytes.length && bytes[p] == 0x0A) p++;
        final given = resolveLength(v['Length']);
        var len = given ?? -1;
        if (given == null || p + given > bytes.length || !_endstreamAt(p + given)) {
          final e = _indexOf('endstream', p);
          len = (e < 0 ? bytes.length : e) - p;
          while (len > 0 && (bytes[p + len - 1] == 0x0A || bytes[p + len - 1] == 0x0D)) {
            len--;
          }
        }
        return PdfStream(v, Uint8List.sublistView(bytes, p, p + len));
      }
      lx.pos = save;
    }
    return v;
  }

  int? resolveLength(Object? o) {
    if (o is int) return o;
    if (o is PdfRef) {
      final at = _offsets[o.num];
      if (at == null) return null;
      final lx = PdfLexer(bytes, at);
      lx.next();
      lx.next();
      lx.next();
      final v = lx.next();
      return v is int ? v : null;
    }
    return null;
  }

  bool _endstreamAt(int p) {
    final lx = PdfLexer(bytes, p);
    lx.skipWhite();
    return _matches('endstream', lx.pos);
  }

  bool _matches(String s, int at) {
    if (at + s.length > bytes.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (bytes[at + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  int _indexOf(String s, int from) {
    final first = s.codeUnitAt(0);
    for (var i = from; i + s.length <= bytes.length; i++) {
      if (bytes[i] == first && _matches(s, i)) return i;
    }
    return -1;
  }

  int _lastIndexOf(String s) {
    final first = s.codeUnitAt(0);
    for (var i = bytes.length - s.length; i >= 0; i--) {
      if (bytes[i] == first && _matches(s, i)) return i;
    }
    return -1;
  }

  Object? _fromObjectStream(int sn, int idx, int n) {
    final s = object(sn);
    if (s is! PdfStream) return null;
    final data = decodeStream(s, this);
    final count = (s.dict['N'] as num?)?.toInt() ?? 0;
    final first = (s.dict['First'] as num?)?.toInt() ?? 0;
    final lx = PdfLexer(data);
    final pairs = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final a = lx.next(), b = lx.next();
      if (a is int && b is int) pairs.add((a, b));
    }
    // cache every object of the stream at once
    Object? want;
    for (var i = 0; i < pairs.length; i++) {
      final (num, off) = pairs[i];
      final p = PdfLexer(data, first + off);
      final v = p.nextObject();
      if (num == n || i == idx) want ??= v;
      if (!_cache.containsKey(num) || _cache[num] == null) _cache[num] = v;
    }
    return want;
  }

  void _readXref() {
    final sx = _lastIndexOf('startxref');
    if (sx < 0) throw PdfReadError('no startxref');
    var at = PdfLexer(bytes, sx + 9).next() as int;
    final seen = <int>{};
    var first = true;
    while (!seen.contains(at) && at > 0 && at < bytes.length) {
      seen.add(at);
      final lx = PdfLexer(bytes, at);
      lx.skipWhite();
      Map<String, Object?> t;
      if (_matches('xref', lx.pos)) {
        lx.pos += 4;
        while (true) {
          final a = lx.next();
          if (a is PdfKeyword && a.word == 'trailer') break;
          final c = lx.next();
          if (a is! int || c is! int) throw PdfReadError('bad xref');
          for (var i = 0; i < c; i++) {
            final off = lx.next(), _ = lx.next(), kind = lx.next();
            if (off is int && kind is PdfKeyword && kind.word == 'n' && off > 0) {
              _offsets.putIfAbsent(a + i, () => off);
            }
          }
        }
        t = lx.nextObject() as Map<String, Object?>;
        // a hybrid file: its xref stream as well
        if (t['XRefStm'] is int) _xrefStream(t['XRefStm'] as int);
      } else {
        t = _xrefStream(at);
      }
      if (first) {
        trailer = Map.of(t);
        first = false;
      } else {
        for (final e in t.entries) {
          trailer.putIfAbsent(e.key, () => e.value);
        }
      }
      final prev = t['Prev'];
      if (prev is! int) break;
      at = prev;
    }
  }

  Map<String, Object?> _xrefStream(int at) {
    final s = _readAt(at);
    if (s is! PdfStream) throw PdfReadError('bad xref stream');
    final data = decodeStream(s, null);
    final w = [for (final x in s.dict['W'] as List) (x as num).toInt()];
    final size = (s.dict['Size'] as num).toInt();
    final index = (s.dict['Index'] as List?)?.map((x) => (x as num).toInt()).toList() ?? [0, size];
    var p = 0;
    int field(int n, int def) {
      if (n == 0) return def;
      var v = 0;
      for (var i = 0; i < n; i++) {
        v = v << 8 | (p < data.length ? data[p++] : 0);
      }
      return v;
    }

    for (var k = 0; k + 1 < index.length; k += 2) {
      for (var i = 0; i < index[k + 1]; i++) {
        final type = field(w[0], 1), a = field(w[1], 0), b = field(w[2], 0);
        final n = index[k] + i;
        if (type == 1 && a > 0) _offsets.putIfAbsent(n, () => a);
        if (type == 2) _inStream.putIfAbsent(n, () => (a, b));
      }
    }
    return s.dict;
  }

  /// A damaged file: find every "n g obj" and the trailer by reading it through
  void _scan() {
    _offsets.clear();
    final re = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
    final text = latin1.decode(bytes);
    for (final m in re.allMatches(text)) {
      _offsets[int.parse(m.group(1)!)] = m.start;
    }
    final t = text.lastIndexOf('trailer');
    if (t >= 0) {
      final o = PdfLexer(bytes, t + 7).nextObject();
      if (o is Map<String, Object?>) trailer = o;
    }
    if (trailer['Root'] == null) {
      // an xref-stream file without a trailer: the catalog is the object of /Type /Catalog
      for (final n in _offsets.keys) {
        final o = object(n);
        final d = o is PdfStream ? o.dict : o;
        if (d is Map<String, Object?> && d['Type'] == const PdfName('XRef')) {
          trailer = Map.of(d);
          _xrefStream(_offsets[n]!);
        }
        if (d is Map<String, Object?> && d['Type'] == const PdfName('Catalog')) {
          trailer['Root'] = PdfRef(n, 0);
          break;
        }
      }
    }
    if (trailer['Root'] == null) throw PdfReadError("This PDF is damaged and can't be read.");
  }

  // ---------------------------------------------------------------------------- pages

  late final List<PdfPageInfo> pages = _pages();

  List<PdfPageInfo> _pages() {
    final out = <PdfPageInfo>[];
    final root = dict(trailer['Root']);
    final seen = <Object?>{};
    void walk(Object? node, Map<String, Object?> inherited) {
      if (seen.contains(node)) return;
      seen.add(node);
      final d = dict(node);
      if (d == null) return;
      final inh = {
        ...inherited,
        for (final k in const ['Resources', 'MediaBox', 'CropBox', 'Rotate'])
          if (d[k] != null) k: d[k],
      };
      final kids = resolve(d['Kids']);
      if (kids is List) {
        for (final k in kids) {
          walk(k, inh);
        }
      } else {
        out.add(PdfPageInfo(this, d, inh));
      }
    }

    walk(root?['Pages'], const {});
    if (out.isEmpty) throw PdfReadError('This PDF has no pages.');
    return out;
  }

  /// The layers (optional content groups): object number → name
  late final Map<int, String> layerNames = () {
    final out = <int, String>{};
    final oc = dict(dict(trailer['Root'])?['OCProperties']);
    final groups = resolve(oc?['OCGs']);
    if (groups is List) {
      for (final g in groups) {
        if (g is PdfRef) {
          final n = resolve(dict(g)?['Name']);
          if (n is PdfString) out[g.num] = n.text;
        }
      }
    }
    return out;
  }();
}

class PdfPageInfo {
  PdfPageInfo(this.file, this.dict, this.inherited);
  final PdfFile file;
  final Map<String, Object?> dict;
  final Map<String, Object?> inherited;

  Map<String, Object?> get resources => file.dict(inherited['Resources']) ?? const {};

  /// [x0, y0, x1, y1] in points
  List<double> get mediaBox {
    final b = file.resolve(inherited['CropBox'] ?? inherited['MediaBox']);
    if (b is List && b.length == 4) {
      final v = [for (final x in b) (file.resolve(x) as num).toDouble()];
      return [
        v[0] < v[2] ? v[0] : v[2],
        v[1] < v[3] ? v[1] : v[3],
        v[0] > v[2] ? v[0] : v[2],
        v[1] > v[3] ? v[1] : v[3],
      ];
    }
    return [0, 0, 612, 792];
  }

  int get rotate => ((file.resolve(inherited['Rotate']) as num?)?.toInt() ?? 0) % 360;

  /// The content streams, joined
  Uint8List get content {
    final c = file.resolve(dict['Contents']);
    final parts = c is List ? c : [c];
    final out = BytesBuilder();
    for (final p in parts) {
      final s = file.resolve(p);
      if (s is PdfStream) {
        out.add(decodeStream(s, file));
        out.addByte(0x0A);
      }
    }
    return out.toBytes();
  }
}
