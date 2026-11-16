# Auto Draft: notes for working on this repository

- Flutter for Windows (same stack as Slope Calculator and Survey Toolkit). Flutter 3.47.7 in CI.
  A macOS build (`macos/`, `.github/workflows/macos.yml`) makes a test `.dmg`; the Windows program
  stays the released one, and Windows-only code (self-update) checks `Platform.isWindows`.
- The engine (`lib/src/engine/`) must stay plain Dart: no `package:flutter` imports, so the command line
  tool and the tests can use it.
- DXF output is R12 (AC1009). Layer and block names: letters, digits, `_ - $`, up to 31 characters.
  Every change to the writer is checked by `tool/check_dxf.py` (ezdxf) in CI: keep it passing.
- PDF to drawing (`lib/src/engine/pdf_in/`) writes AutoCAD 2000 (AC1015) instead, for hatches,
  lightweight polylines, lineweights and dimensions; `tool/check_pdf_dxf.py` checks it in CI.
- Before pushing: `dart format lib test tool`, `flutter analyze` (no issues), `flutter test`.
- Text for people is plain and short. No secrets in the repository.
- Merge only when the owner says "Merge". Don't tag a release unless the owner says so.
- Survey Toolkit and website changes belong in their own repositories, never here.
