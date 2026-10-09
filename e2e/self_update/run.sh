#!/bin/sh
# Runs the updater end to end on macOS: a signed application installs a signed
# release of itself and restarts into it.
#
# Uses the public facade over a local HTTPS endpoint. SSL_CERT_FILE applies
# only to these child processes; the system trust store is not modified.
# The new bundle deliberately renames its executable to exercise relaunch.
#
# Usage: e2e/self_update/run.sh [work-directory]
set -eu

# Not $TMPDIR: Launch Services refuses to start an application from the
# per-user temporary directory, and says so to nobody — `open` exits 0 and the
# application never runs. The relaunch step would look like it worked.
work="${1:-/tmp/proton-updater-e2e}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
identifier="com.example.proton-updater-e2e"

case "$(uname -s)" in
Darwin) ;;
*)
  echo "this packaged self-update scenario runs on macOS only" >&2
  exit 1
  ;;
esac

openssl_root="$(brew --prefix openssl@3)"
openssl_bin="$openssl_root/bin/openssl"

rm -rf "$work"
mkdir -p "$work/keys" "$work/server" "$work/install" "$work/build"
moon install --path "$repo/e2e/self_update" --bin "$work/build"
binary="$work/build/self_update"

if [ -z "${PROTON_RUNTIME_ROOT:-}" ]; then
  PROTON_RUNTIME_ROOT=$(PROTON_CEF_SETUP_BOOTSTRAP=1 moon -C "$repo/cefsetup" run . --target native -- --runtime-only | tail -n 1)
  export PROTON_RUNTIME_ROOT
fi
if [ -z "${PROTON_HELPER_PATH:-}" ]; then
  moon install --path "$repo/proton/internal/cef_process" --bin "$work/build"
  PROTON_HELPER_PATH="$work/build/cef_process"
  export PROTON_HELPER_PATH
fi
"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost' -keyout "$work/keys/tls.key" \
  -out "$work/keys/tls.pem" 2>/dev/null
python3 - "$work" > "$work/server.log" 2>&1 <<'SERVER' &
import functools, http.server, pathlib, ssl, sys
root = pathlib.Path(sys.argv[1])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root / 'server'))
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(root / 'keys/tls.pem', root / 'keys/tls.key')
server.socket = context.wrap_socket(server.socket, server_side=True)
(root / 'port').write_text(str(server.server_port))
server.serve_forever()
SERVER
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
while [ ! -f "$work/port" ]; do
  if ! kill -0 "$server_pid" 2>/dev/null; then cat "$work/server.log"; exit 1; fi
  sleep 0.1
done
base="https://localhost:$(cat "$work/port")/"
export SSL_CERT_FILE="$work/keys/tls.pem"
export PROTON_E2E_ENDPOINT="${base}latest.json"

# Apple's LibreSSL ignores SSL_CERT_FILE. Use OpenSSL for this fixture only,
# so a process-local CA can authenticate HTTPS without changing system trust.
mkdir -p "$work/tls"
ln -s "$openssl_root/lib/libssl.3.dylib" "$work/tls/libssl.48.dylib"

# The publisher's key. A real release keeps this offline; here it lives beside
# the artifacts it signs because nothing about it is secret to this test.
"$openssl_bin" genrsa -out "$work/keys/private.pem" 2048 2>/dev/null
modulus="$("$openssl_bin" rsa -in "$work/keys/private.pem" -noout -modulus |
  sed 's/^Modulus=//' | tr 'A-Z' 'a-z')"
printf 'rsa-sha256:%s:010001' "$modulus" > "$work/keys/trusted.txt"

# Builds one signed bundle. Signing is ad-hoc: the check the updater makes is
# that the seal covers the contents and that both bundles call themselves the
# same application, and an ad-hoc signature establishes both.
make_bundle() {
  app="$1"
  version="$2"
  revision="$3"
  executable="$4"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$app/Contents/Frameworks"
  cp "$binary" "$app/Contents/MacOS/$executable"
  printf '%s' "$version" > "$app/Contents/Resources/version"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$executable</string>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleName</key><string>Updatee</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>ProtonUpdateRevision</key><string>$revision</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
  codesign --force --identifier "$identifier" --sign - "$app" 2>/dev/null
  codesign --verify --strict "$app"
}

make_bundle "$work/build/Old.app" "0.1.0" "1" "updatee"
make_bundle "$work/build/Updatee.app" "0.2.0" "2" "updatee-new"

# ditto, because the archive has to preserve what the bundle's own signature
# covers.
( cd "$work/build" && /usr/bin/ditto -c -k --keepParent "Updatee.app" \
  "$work/server/Updatee-0.2.0.zip" )

zip="$work/server/Updatee-0.2.0.zip"
size="$(stat -f%z "$zip")"
sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
artifact_signature="$("$openssl_bin" dgst -sha256 -sign "$work/keys/private.pem" "$zip" |
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
"$openssl_bin" dgst -sha256 -sign "$work/keys/private.pem" "$work/server/latest.json" |
  xxd -p | tr -d '\n' > "$work/server/latest.json.sig"

export PROTON_E2E_KEY="$(cat "$work/keys/trusted.txt")"
python3 - "$work" <<'TESTS'
import os, pathlib, shutil, signal, subprocess, sys, time
root = pathlib.Path(sys.argv[1])
for mode in ['install', 'prevent-before', 'prevent-will', 'force-exit', 'ordinary-quit', 'cleanup-failure']:
    install = root / 'install'
    shutil.rmtree(install)
    install.mkdir()
    bundle = install / 'Updatee.app'
    shutil.copytree(root / 'build/Old.app', bundle, symlinks=True)
    log = install / 'events.log'
    env = dict(os.environ, PROTON_E2E_MODE=mode, PROTON_E2E_LOG=str(log))
    env['DYLD_LIBRARY_PATH'] = str(root / 'tls')
    with (root / (mode + '.log')).open('w') as output:
        process = subprocess.Popen([str(bundle / 'Contents/MacOS/updatee')], env=env,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise AssertionError(f'{mode}: process did not finish; see {root / (mode + ".log")}')
    assert code == 0, (mode, code, (root / (mode + '.log')).read_text())
    updates = mode in ['install', 'prevent-before', 'prevent-will']
    deadline = time.monotonic() + 120
    while updates and (not log.exists() or 'new-cleaned' not in log.read_text()):
        assert time.monotonic() < deadline, (mode, 'replacement did not finish', log.read_text() if log.exists() else '')
        time.sleep(0.1)
    events = log.read_text().splitlines()
    assert events.index('downloaded') < events.index('quit') < events.index('shutdown-old'), (mode, events)
    version = (bundle / 'Contents/Resources/version').read_text()
    assert version == ('0.2.0' if updates else '0.1.0'), (mode, version, events)
    if updates:
        assert events.index('shutdown-old') < events.index('started-new'), (mode, events)
        assert 'run-returned' not in events, (mode, events)
        assert not (bundle / 'Contents/MacOS/updatee').exists()
        subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
    if mode.startswith('prevent-'):
        phase = 'before-quit' if mode == 'prevent-before' else 'will-quit'
        assert events.count(phase) == 2, (mode, events)
    if mode == 'force-exit':
        assert 'run-returned' not in events and 'started-new' not in events, events
    if mode in ['ordinary-quit', 'cleanup-failure']:
        assert 'run-returned' in events and 'started-new' not in events, events
    if mode == 'cleanup-failure':
        assert 'cleanup-failed' in events, events
    assert not list(install.glob('.proton-update-*')), (mode, 'leaked stage')
    retained = install / '.Updatee.app.proton-update'
    assert not retained.exists() or not list(retained.iterdir()), (mode, 'retained old bundle')
    print(f'PASS {mode}: ' + ' -> '.join(events), flush=True)
TESTS
