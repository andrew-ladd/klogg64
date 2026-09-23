#!/usr/bin/env bash
# Build a credential-free Apple Silicon installer from an existing CMake build.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <build-directory> <output-directory>" >&2
  exit 2
fi

build_dir=$(cd "$1" && pwd)
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$2"
output_dir=$(cd "$2" && pwd)
source_app="$build_dir/output/klogg.app"
test -f "$source_app/Contents/MacOS/klogg"

# Use the Qt installation that built the application (override for local use).
macdeployqt=${MACDEPLOYQT:-macdeployqt}
stage=$(mktemp -d "${TMPDIR:-/tmp}/klogg-pkg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/root/Applications/klogg.app"
mkdir -p "$stage/root/Applications"
ditto "$source_app" "$app"
mkdir -p "$app/Contents/SharedSupport"
cp "$repo_dir/COPYING" "$repo_dir/NOTICE" "$app/Contents/SharedSupport/"
"$macdeployqt" "$app" -always-overwrite -verbose=1

version=${PKG_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")}
if [[ ! $version =~ ^[0-9]+(\.[0-9]+){0,3}$ ]]; then
  echo "Invalid numeric package version: $version" >&2
  exit 1
fi

# Audit the deployed payload, then sign nested code before its enclosing bundle.
# This intentionally uses local ad-hoc signatures and no Apple credentials.
python3 - "$app" "$stage/requirements.plist" <<'PY'
import pathlib
import plistlib
import re
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
for path in sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if not path.is_file() or path.is_symlink():
        continue
    description = subprocess.check_output(['file', '-b', str(path)], text=True)
    if 'Mach-O' not in description:
        continue
    subprocess.run(['lipo', str(path), '-verify_arch', 'arm64'], check=True)
    links = subprocess.check_output(['otool', '-arch', 'arm64', '-L', str(path)], text=True)
    for line in links.splitlines():
        if line.startswith('\t'):
            dependency = line.strip().split(' (', 1)[0]
            if dependency.startswith('/') and not dependency.startswith(('/System/Library/', '/usr/lib/')):
                raise SystemExit(f'Unbundled dependency: {path}: {dependency}')
    subprocess.run(['codesign', '--force', '--sign', '-', str(path)], check=True)

for framework in sorted(app.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True):
    subprocess.run(['codesign', '--force', '--sign', '-', str(framework)], check=True)

binary = app / 'Contents/MacOS/klogg'
build_info = subprocess.check_output(['xcrun', 'vtool', '-arch', 'arm64', '-show-build', str(binary)], text=True)
minimum = re.search(r'\bminos\s+([0-9.]+)', build_info)
if not minimum:
    raise SystemExit('Cannot determine the application deployment target')
with open(sys.argv[2], 'wb') as stream:
    plistlib.dump({'arch': ['arm64'], 'os': [minimum.group(1)]}, stream)
print(f'Packaging ARM64 app for macOS {minimum.group(1)} and later')
PY

codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
# macdeployqt ships the native Cocoa plugin, not the offscreen test plugin.
env -u QT_PLUGIN_PATH -u QML2_IMPORT_PATH -u DYLD_FRAMEWORK_PATH \
  -u DYLD_LIBRARY_PATH "$app/Contents/MacOS/klogg" -v

pkgbuild --analyze --root "$stage/root" "$stage/components.plist"
python3 - "$stage/components.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, 'rb') as stream:
    components = plistlib.load(stream)
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleOverwriteAction'] = 'upgrade'
with open(path, 'wb') as stream:
    plistlib.dump(components, stream)
PY

pkgbuild --root "$stage/root" \
  --component-plist "$stage/components.plist" \
  --identifier com.github.variar.klogg \
  --version "$version" \
  --install-location / \
  "$stage/klogg-component.pkg"
productbuild --synthesize --product "$stage/requirements.plist" \
  --package "$stage/klogg-component.pkg" "$stage/distribution.xml"

package_name="klogg-${version}-mac-arm64.pkg"
productbuild --distribution "$stage/distribution.xml" \
  --package-path "$stage" "$output_dir/$package_name"
pkgutil --payload-files "$output_dir/$package_name" > "$stage/payload.txt"
grep -q 'Applications/klogg.app/Contents/MacOS/klogg' "$stage/payload.txt"
(cd "$output_dir" && shasum -a 256 "$package_name" > "$package_name.sha256")
echo "Created $output_dir/$package_name"
