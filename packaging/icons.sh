#!/usr/bin/env bash
# Regenerate the Mota-Engil PDF Editor app icons from assets/app-icon/pdfcraft.svg and the Windows PDF file icon
# from assets/app-icon/pdfcraft-document.svg. Both are master vectors.
#
# Needs: resvg (brew install resvg / cargo install resvg) and python3 (stdlib only, for the icon containers).
# The outputs are committed, so building and packaging
# never need these tools. After running it, update the sha256 values in ATTRIBUTION.toml, then
# `cargo xtask assets --write`.
#
#   packaging/icons.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/assets/app-icon"
SVG="$DIR/pdfcraft.svg"
ID="io.github.davidsanculane-dev.versa-pdf"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v resvg >/dev/null || { echo "error: resvg not found (brew install resvg)" >&2; exit 1; }

# The master is a full-bleed 512 tile (rx=112): right for Windows and Linux. macOS icons follow
# Apple's grid instead: an 824 px body centred on a transparent 1024 canvas.
MAC="$TMP/macos.svg"
{
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
  echo '<g transform="translate(100 100) scale(1.609375)">'
  sed '1d;$d' "$SVG"
  echo '</g>'
  echo '</svg>'
} >"$MAC"

render() { resvg -w "$2" -h "$2" "$1" "$3" </dev/null; }

# 1024 px PNG on Apple's grid (also the runtime Dock icon on macOS, see apps/pdfcraft/src/main.rs).
render "$MAC" 1024 "$DIR/pdfcraft-1024.png"

# Linux hicolor theme (full bleed; hicolor/256x256 is also the runtime icon on Windows and Linux).
for s in 16 24 32 48 64 128 256 512; do
  mkdir -p "$DIR/hicolor/${s}x${s}/apps"
  render "$SVG" "$s" "$DIR/hicolor/${s}x${s}/apps/$ID.png"
done
mkdir -p "$DIR/hicolor/scalable/apps"
cp "$SVG" "$DIR/hicolor/scalable/apps/$ID.svg"

# Windows .ico: PNG-compressed entries, 16-256 px. The document icon has its own resource
# in pdfcraft.exe; the app icon remains the first/default icon.
for name in pdfcraft pdfcraft-document; do
  ICO_PNGS=()
  for s in 16 20 24 32 40 48 64 128 256; do
    render "$DIR/$name.svg" "$s" "$TMP/$name-$s.png"
    ICO_PNGS+=("$TMP/$name-$s.png")
  done
  python3 - "$DIR/$name.ico" "${ICO_PNGS[@]}" <<'PY'
import struct, sys
out, pngs = sys.argv[1], sys.argv[2:]
blobs = [open(p, "rb").read() for p in pngs]
head = struct.pack("<HHH", 0, 1, len(blobs))
entries, data, offset = b"", b"", 6 + 16 * len(blobs)
for b in blobs:
    w, h = struct.unpack(">II", b[16:24])  # IHDR
    entries += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(b), offset)
    data += b
    offset += len(b)
open(out, "wb").write(head + entries + data)
PY
done

# macOS .icns: PNG-backed icon families, written directly so regeneration also works off macOS.
ICNS_PNGS=()
ICNS_SIZES=(16 32 64 128 256 512 1024)
for s in "${ICNS_SIZES[@]}"; do
  if [ "$s" = 1024 ]; then
    ICNS_PNGS+=("$DIR/pdfcraft-1024.png")
  else
    render "$MAC" "$s" "$TMP/macos-$s.png"
    ICNS_PNGS+=("$TMP/macos-$s.png")
  fi
done
python3 - "$DIR/pdfcraft.icns" "${ICNS_PNGS[@]}" <<'PY'
import struct, sys

out, *paths = sys.argv[1:]
types = (b"icp4", b"icp5", b"icp6", b"ic07", b"ic08", b"ic09", b"ic10")
chunks = []
for kind, path in zip(types, paths):
    with open(path, "rb") as source:
        png = source.read()
    chunks.append(kind + struct.pack(">I", len(png) + 8) + png)
body = b"".join(chunks)
with open(out, "wb") as target:
    target.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY
echo "icons written to $DIR"
