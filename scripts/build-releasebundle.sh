#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$ROOT/build/swift"
APP="$ROOT/build/releasebundle/XinFuPet.app"

swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release -Xswiftc -gnone
BIN_DIR="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/XinFuPet" "$APP/Contents/MacOS/XinFuPet"
strip -S "$APP/Contents/MacOS/XinFuPet"
python3 - "$ROOT" "$APP/Contents/Resources" <<'PY'
import hashlib, json, pathlib, shutil, sys

root = pathlib.Path(sys.argv[1])
source_root = root / 'Resources'
destination_root = pathlib.Path(sys.argv[2])
allowlist_path = root / 'verification/runtime-resource-allowlist.json'
allowlist = json.loads(allowlist_path.read_text())
categories = allowlist['resources']
records = []
for category in ('originalProductionPNGs', 'canonicalMetadata', 'canonicalFrames', 'props', 'icons'):
    records.extend(categories.get(category, []))

paths = [item['path'] if isinstance(item, dict) else item for item in records]
if len(paths) != allowlist['status']['expectedRuntimeResourceFiles']:
    raise SystemExit(f"Allowlist count mismatch: {len(paths)} files")
if len(paths) != len(set(paths)):
    raise SystemExit('Runtime resource allowlist contains duplicate paths')

for item in records:
    relative = item['path'] if isinstance(item, dict) else item
    path = pathlib.PurePosixPath(relative)
    if path.is_absolute() or '..' in path.parts:
        raise SystemExit(f'Non-portable resource path: {relative}')
    source = source_root.joinpath(*path.parts)
    if not source.is_file():
        raise SystemExit(f'Missing allowlisted resource: {relative}')
    expected = item.get('sha256') if isinstance(item, dict) else None
    if expected:
        actual = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f'SHA-256 mismatch before staging: {relative}')
    destination = destination_root.joinpath(*path.parts)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)

print(f"Staged only {len(paths)} SHA-256 allowlisted runtime resources.")
PY

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>芙莉莲与辛美尔</string>
<key>CFBundleDisplayName</key><string>芙莉莲与辛美尔</string>
<key>CFBundleIdentifier</key><string>local.xi.xinfupet</string>
<key>CFBundleVersion</key><string>0.1.0</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleExecutable</key><string>XinFuPet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built and ad-hoc signed isolated release bundle: $APP"
