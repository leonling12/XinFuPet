#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/releasebundle/XinFuPet.app"
BIN="$APP/Contents/MacOS/XinFuPet"
RESOURCES="$APP/Contents/Resources"
MANIFEST="$ROOT/verification/style-baseline.json"
ALLOWLIST="$ROOT/verification/runtime-resource-allowlist.json"

codesign --verify --deep --strict --verbose=2 "$APP"
python3 - "$MANIFEST" "$ALLOWLIST" "$RESOURCES" "$APP/Contents/Info.plist" <<'PY'
import hashlib, json, pathlib, plistlib, sys
import math, struct
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())['images']
allowlist=json.loads(pathlib.Path(sys.argv[2]).read_text())
resources=pathlib.Path(sys.argv[3])
info=plistlib.loads(pathlib.Path(sys.argv[4]).read_bytes())

# Keep the complete production art set byte-identical to the old base.
originals=resources/'Characters'
for rel, item in manifest.items():
    path=originals/rel
    if not path.is_file():
        raise SystemExit(f'Missing original art: {rel}')
    actual=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != item['sha256']:
        raise SystemExit(f'Original art hash changed: {rel}')
print(f'Original production art hashes verified: {len(manifest)} PNGs')

# The app bundle must contain exactly the portable resource allowlist.
categories=allowlist['resources']
records=[]
for category in ('originalProductionPNGs','canonicalMetadata','canonicalFrames','props','icons'):
    records.extend(categories.get(category,[]))
expected={}
for item in records:
    rel=item['path'] if isinstance(item,dict) else item
    digest=item.get('sha256') if isinstance(item,dict) else None
    if not digest:
        raise SystemExit(f'Allowlist entry has no SHA-256: {rel}')
    pure=pathlib.PurePosixPath(rel)
    if pure.is_absolute() or '..' in pure.parts:
        raise SystemExit(f'Non-portable allowlist path: {rel}')
    if rel in expected:
        raise SystemExit(f'Duplicate allowlist path: {rel}')
    expected[rel]=digest
actual_paths={p.relative_to(resources).as_posix() for p in resources.rglob('*') if p.is_file()}
if actual_paths != set(expected):
    missing=sorted(set(expected)-actual_paths)
    extra=sorted(actual_paths-set(expected))
    raise SystemExit(f'Runtime resource tree differs from allowlist; missing={missing}, extra={extra}')
for rel,digest in expected.items():
    actual=hashlib.sha256((resources/rel).read_bytes()).hexdigest()
    if actual != digest:
        raise SystemExit(f'Runtime resource SHA-256 mismatch: {rel}')
count=allowlist['status']['expectedRuntimeResourceFiles']
if len(expected) != count:
    raise SystemExit(f'Allowlist count mismatch: expected {count}, listed {len(expected)}')
print(f'Exact runtime resource tree and SHA-256 verified: {len(expected)} files')

# Check portable authored-action and walk metadata, including nested values.
for rel in ('Motion/CanonicalKeyframesV1/action-anchors.json','Motion/CanonicalKeyframesV1/walk-anchors.json'):
    metadata=json.loads((resources/rel).read_text())
    forbidden={'source_path','source_sha256','helpers','python','preview','source_grid','qa','absolute_path','sourcepath','helperpaths'}
    def scan(value):
        if isinstance(value,dict):
            for key,child in value.items():
                if key.lower() in forbidden:
                    raise SystemExit(f'Non-portable metadata field bundled in {rel}: {key}')
                scan(child)
        elif isinstance(value,list):
            for child in value: scan(child)
        elif isinstance(value,str) and value.startswith('/'):
            raise SystemExit(f'Absolute path bundled in {rel}')
    scan(metadata)
    if 'frameSHA256' in metadata:
        for frame,digest in metadata['frameSHA256'].items():
            path=resources/frame
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
                raise SystemExit(f'Authored action art hash changed: {frame}')
        if len(metadata['frameSHA256']) != 104:
            raise SystemExit(f'Expected 104 canonical frame hashes, got {len(metadata["frameSHA256"])}')

# Every authored action frame must match its action canvas. Per-action canvas
# values are optional and otherwise inherit the portable global canvas.
action_metadata=json.loads((resources/'Motion/CanonicalKeyframesV1/action-anchors.json').read_text())
global_canvas=action_metadata['canvas']
for actor, actions in action_metadata['actors'].items():
    for action, spec in actions.items():
        canvas=spec.get('canvas', global_canvas)
        width,height=canvas.get('width'),canvas.get('height')
        if (not isinstance(width,(int,float)) or isinstance(width,bool) or
            not isinstance(height,(int,float)) or isinstance(height,bool) or
            not math.isfinite(width) or not math.isfinite(height) or
            width<=0 or height<=0 or int(width)!=width or int(height)!=height):
            raise SystemExit(f'Invalid authored action canvas: {actor}.{action}')
        for name in spec['files']:
            pure=pathlib.PurePosixPath(name)
            if pure.is_absolute() or '..' in pure.parts or len(pure.parts)!=1:
                raise SystemExit(f'Invalid action frame name: {actor}.{action}: {name}')
            path=resources/'Motion/CanonicalKeyframesV1/frames'/actor/name
            data=path.read_bytes()
            if len(data)<24 or data[:8]!=b'\x89PNG\r\n\x1a\n':
                raise SystemExit(f'Invalid action PNG: {path.relative_to(resources)}')
            actual_width,actual_height=struct.unpack('>II',data[16:24])
            if (actual_width,actual_height)!=(width,height):
                raise SystemExit(f'Action canvas mismatch for {actor}.{action}: metadata={width}x{height}, PNG={actual_width}x{actual_height} ({name})')
print('Portable action and walk metadata verified (104 canonical frame hashes).')

if info.get('CFBundleName') != '芙莉莲与辛美尔' or info.get('CFBundleDisplayName') != '芙莉莲与辛美尔':
    raise SystemExit('Unexpected product display name')
if info.get('CFBundleShortVersionString') != '0.1.0' or info.get('CFBundleVersion') != '0.1.0':
    raise SystemExit('Unexpected product version')
if info.get('CFBundleIdentifier') != 'local.xi.xinfupet':
    raise SystemExit('Unexpected bundle identifier')
print('Bundle identity verified: 芙莉莲与辛美尔 0.1.0 (local.xi.xinfupet)')
PY

if rg -n 'F01RigRenderer|H01RigRenderer|HimmelRigRenderer|RigMotionRenderer|ActorContentRig|PoseWarp|GenericRig|renderTimelineSample' "$ROOT/Sources/XinFuPet"; then
  echo "Rig/limb dispatcher source unexpectedly present" >&2
  exit 1
fi
if nm -m "$BIN" 2>/dev/null | rg -q 'F01RigRenderer|H01RigRenderer|HimmelRigRenderer|RigMotionRenderer|ActorContentRig|PoseWarp|GenericRig'; then
  echo "Rig/limb dispatcher symbol unexpectedly present in release binary" >&2
  exit 1
fi
rg -q 'AssetStore.shared.productionImage' "$ROOT/Sources/XinFuPet/ActorView.swift"
rg -q 'fullBody.contents = cgImage' "$ROOT/Sources/XinFuPet/ActorView.swift"
rg -q 'fullBody.removeAnimation\(forKey: "pose"\)' "$ROOT/Sources/XinFuPet/ActorView.swift"
if rg -n 'CATransition|animateTransform|addAnimation\(' "$ROOT/Sources/XinFuPet/ActorView.swift"; then
  echo "Whole-body image transitions or elastic transforms unexpectedly present" >&2
  exit 1
fi
rg -q 'view.setPose\(current.pose, transition: 0\)' "$ROOT/Sources/XinFuPet/AnimationEngine.swift"
rg -q 'view.setCanonicalAction' "$ROOT/Sources/XinFuPet/AnimationEngine.swift"
rg -q 'if !PetSettings.shared.paused \{ elapsed \+= delta \* speed \}' "$ROOT/Sources/XinFuPet/AnimationEngine.swift"
echo "Whole-image, no-fade action clock confirmed; no rig/limb renderer is bundled."
