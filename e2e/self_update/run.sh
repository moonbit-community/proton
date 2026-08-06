#!/bin/sh
# Runs the updater end to end on macOS: a signed application installs a signed
# release of itself and restarts into it.
#
# Everything the client refuses on is real here — the RSA signatures over the
# manifest and the artifact, the SHA-256, the version comparison, the freshness
# window, the bundle's code signature. Only the transport is not: the harness
# serves the three files from a directory instead of over HTTPS. That keeps the
# ordering of the checks exactly as it ships and avoids needing a certificate
# the client would trust.
#
# Usage: e2e/self_update/run.sh [work-directory]
set -eu

# Not $TMPDIR: Launch Services refuses to start an application from the
# per-user temporary directory, and says so to nobody — `open` exits 0 and the
# application never runs. The relaunch step would look like it worked.
work="${1:-/tmp/proton-updater-e2e}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
identifier="com.example.proton-updater-e2e"
base="https://updates.example.com/"

case "$(uname -s)" in
Darwin) ;;
*)
  echo "the updater is implemented on macOS only" >&2
  exit 1
  ;;
esac

binary="$repo/_build/native/debug/build/moonbit-community/proton/e2e/self_update/self_update.exe"
native_dist="${PROTON_NATIVE_DIST:-$repo/native/dist}"
if [ ! -x "$binary" ]; then
  echo "build it first: moon -C e2e build --target native" >&2
  exit 1
fi

rm -rf "$work"
mkdir -p "$work/keys" "$work/server" "$work/install" "$work/build"

# The publisher's key. A real release keeps this offline; here it lives beside
# the artifacts it signs because nothing about it is secret to this test.
openssl genrsa -out "$work/keys/private.pem" 2048 2>/dev/null
modulus="$(openssl rsa -in "$work/keys/private.pem" -noout -modulus |
  sed 's/^Modulus=//' | tr 'A-Z' 'a-z')"
printf 'rsa-sha256:%s:010001' "$modulus" > "$work/keys/trusted.txt"

# Builds one signed bundle. Signing is ad-hoc: the check the updater makes is
# that the seal covers the contents and that both bundles call themselves the
# same application, and an ad-hoc signature establishes both.
make_bundle() {
  app="$1"
  version="$2"
  revision="$3"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$app/Contents/Frameworks"
  cp "$binary" "$app/Contents/MacOS/updatee"
  cp "$native_dist/lib/libproton.dylib" "$app/Contents/Frameworks/libproton.dylib"
  otool -l "$app/Contents/MacOS/updatee" |
    awk '/cmd LC_RPATH/{getline; getline; print $2}' |
    while IFS= read -r rpath; do
      install_name_tool -delete_rpath "$rpath" "$app/Contents/MacOS/updatee"
    done
  install_name_tool -add_rpath '@executable_path/../Frameworks' \
    "$app/Contents/MacOS/updatee"
  printf '%s' "$version" > "$app/Contents/Resources/version"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>updatee</string>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleName</key><string>Updatee</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>ProtonUpdateRevision</key><string>$revision</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
  codesign --force --sign - "$app/Contents/Frameworks/libproton.dylib" 2>/dev/null
  codesign --force --identifier "$identifier" --sign - "$app" 2>/dev/null
  codesign --verify --strict "$app"
}

make_bundle "$work/install/Updatee.app" "0.1.0" "1"
make_bundle "$work/build/Updatee.app" "0.2.0" "2"

# ditto, because the archive has to preserve what the bundle's own signature
# covers.
( cd "$work/build" && /usr/bin/ditto -c -k --keepParent "Updatee.app" \
  "$work/server/Updatee-0.2.0.zip" )

zip="$work/server/Updatee-0.2.0.zip"
size="$(stat -f%z "$zip")"
sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
artifact_signature="$(openssl dgst -sha256 -sign "$work/keys/private.pem" "$zip" |
  xxd -p | tr -d '\n')"
cat > "$work/server/latest.json" <<JSON
{
  "schema_version": 2,
  "version": "0.2.0",
  "revision": 2,
  "published_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "platforms": {
    "darwin-arm64": {
      "kind": "full",
      "url": "${base}Updatee-0.2.0.zip",
      "size": $size,
      "sha256": "$sha",
      "signature": "$artifact_signature"
    }
  }
}
JSON
openssl dgst -sha256 -sign "$work/keys/private.pem" "$work/server/latest.json" |
  xxd -p | tr -d '\n' > "$work/server/latest.json.sig"

echo "installed version before: $(cat "$work/install/Updatee.app/Contents/Resources/version")"
PROTON_E2E_ENDPOINT="${base}latest.json" \
PROTON_E2E_BASE="$base" \
PROTON_E2E_ROOT="$work/server" \
PROTON_E2E_KEY="$(cat "$work/keys/trusted.txt")" \
PROTON_E2E_ROLE="update" \
  "$work/install/Updatee.app/Contents/MacOS/updatee"

# The relaunched process is started by Launch Services, so it finishes after
# this script's child has exited. Its own log entry is the only evidence it ran.
attempt=0
while [ "$attempt" -lt 10 ]; do
  if [ -f "$work/install/relaunched.txt" ] &&
    grep -q '0\.2\.0' "$work/install/relaunched.txt" &&
    [ "$(find "$work/install" -maxdepth 1 -type d -name '*.app.previous-*' | wc -l | tr -d ' ')" = 0 ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "installed version after:  $(cat "$work/install/Updatee.app/Contents/Resources/version")"
echo "launch log:"
sed 's/^/  /' "$work/install/relaunched.txt"
previous_count=$(find "$work/install" -maxdepth 1 -type d -name '*.app.previous-*' | wc -l | tr -d ' ')
echo "kept previous bundles: $previous_count"
test "$previous_count" = 0
echo "staging entries left:  $(find "$work/install" -maxdepth 1 -name '.proton-update-*' | wc -l | tr -d ' ')"
codesign --verify --strict "$work/install/Updatee.app"
echo "installed bundle signature: valid"

test "$(cat "$work/install/Updatee.app/Contents/Resources/version")" = "0.2.0"
grep -q 'started 0\.1\.0' "$work/install/relaunched.txt"
grep -q 'started 0\.2\.0' "$work/install/relaunched.txt"
test "$(find "$work/install" -maxdepth 1 -name '.proton-update-*' | wc -l | tr -d ' ')" = "0"
echo "OK"
