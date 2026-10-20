#!/usr/bin/env bash
# Build an isolated server copy and test only a disposable local PostgreSQL DB.
# Installs nothing, changes no server checkout/config, and stops both processes.
set -euo pipefail

mobile_root=$(cd "$(dirname "$0")/.." && pwd)
server_root=$(dirname "$mobile_root")
pg_bin=${PG_BIN:-/opt/homebrew/opt/postgresql@18/bin}
flutter_bin=${FLUTTER_BIN:-"$HOME/opt/flutter/bin/flutter"}
go_bin=${GO_BIN:-go}
for executable in "$pg_bin/initdb" "$pg_bin/pg_ctl" "$pg_bin/createdb" "$flutter_bin" "$go_bin" python3; do
  command -v "$executable" >/dev/null || { echo "Missing dependency: $executable" >&2; exit 1; }
done
if [[ -n "${API2_IOS_SIMULATOR:-}" ]]; then
  python3 - "$API2_IOS_SIMULATOR" <<'PY'
import json, subprocess, sys
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
matches = [d for items in devices["devices"].values() for d in items if d["udid"] == sys.argv[1]]
if len(matches) != 1 or matches[0]["state"] != "Booted":
    raise SystemExit("API2_IOS_SIMULATOR must name an already booted iOS simulator")
PY
fi
python3 - <<'PY'
import socket
for port in (15438, 19090):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", port))
PY
# Keep PostgreSQL's Unix socket path below macOS's length limit.
test_work=$(mktemp -d /private/tmp/gemsnote-api2-live.XXXXXX)
echo "Temporary test data and logs: $test_work"
server_pid=
postgres_started=false
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ "$postgres_started" == true ]]; then
    "$pg_bin/pg_ctl" -D "$test_work/pgdata" -m fast -w stop >> "$test_work/postgres-stop.log" 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 - "$server_root" "$test_work" <<'PY'
from pathlib import Path
import secrets
import shutil
import sys
root, work = map(Path, sys.argv[1:])
server = work / "server"
server.mkdir()
for name in ("app", "conf", "messages", "database", "public", "go.mod", "go.sum"):
    source = root / name
    if source.is_dir():
        shutil.copytree(source, server / name, ignore=shutil.ignore_patterns(
            "upload", "node_modules", ".DS_Store", "app.conf", "tmp"))
    else:
        shutil.copy2(source, server / name)
config = (root / "conf/app.conf-default").read_text()
values = {
    "http.addr": "127.0.0.1",
    "http.port": "19090",
    "site.url": "http://127.0.0.1:19090",
    "db.type": "postgresql",
    "db.url": "postgresql://gemsnote_test@127.0.0.1:15438/gemsnote?sslmode=disable",
    "app.secret": secrets.token_urlsafe(48),
}
lines = []
for line in config.splitlines():
    key = line.split("=", 1)[0].strip()
    if key in values:
        line = key + "=" + values.pop(key)
    lines.append(line)
# Insert remaining defaults before the first named config section.
index = next(i for i, line in enumerate(lines) if line.startswith("["))
lines[index:index] = [key + "=" + value for key, value in values.items()]
(server / "conf/app.conf").write_text("\n".join(lines) + "\n")
PY
"$pg_bin/initdb" -D "$test_work/pgdata" -U gemsnote_test --auth=trust --no-locale -E UTF8 > "$test_work/initdb.log" 2>&1
"$pg_bin/pg_ctl" -D "$test_work/pgdata" -l "$test_work/postgres.log" \
  -o "-h 127.0.0.1 -p 15438 -k $test_work" -w start
postgres_started=true
"$pg_bin/createdb" -h 127.0.0.1 -p 15438 -U gemsnote_test gemsnote
(
  cd "$test_work/server"
  "$go_bin" run ./app/cmd build . "$test_work/revel" prod
  "$go_bin" build -o "$test_work/gemsnote" ./app/tmp
) > "$test_work/build.log" 2>&1
revel_dir=$(cd "$test_work/server" && "$go_bin" list -m -f '{{.Dir}}' github.com/revel/revel)
mkdir -p "$test_work/runtime/github.com/gemsnote" "$test_work/runtime/github.com/revel"
ln -s "$test_work/server" "$test_work/runtime/github.com/gemsnote/gemsnote"
ln -s "$revel_dir" "$test_work/runtime/github.com/revel/revel"
(
  cd "$test_work/server"
  exec "$test_work/gemsnote" -importPath github.com/gemsnote/gemsnote \
    -srcPath "$test_work/runtime" -runMode prod
) > "$test_work/server.log" 2>&1 &
server_pid=$!
python3 - "$server_pid" <<'PY'
import os
import socket
import sys
import time
for attempt in range(100):
    os.kill(int(sys.argv[1]), 0)
    try:
        with socket.create_connection(("127.0.0.1", 19090), timeout=.2):
            break
    except OSError:
        time.sleep(.1)
else:
    raise SystemExit("Temporary API2 server did not become ready")
PY
(
  cd "$mobile_root"
  if [[ -n "${API2_IOS_SIMULATOR:-}" ]]; then
    run_id=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
    echo "Native fixture run: $run_id"
    for phase in seed resume; do
      "$flutter_bin" test integration_test/native_api2_session_test.dart \
        -d "$API2_IOS_SIMULATOR" --no-uninstall \
        --dart-define="API2_TEST_RUN=$run_id" --dart-define="API2_TEST_PHASE=$phase"
      if [[ "$phase" == seed ]]; then
        # Flutter's runner may already have exited. The resume test separately
        # requires a different PID and the persisted fixture marker.
        python3 - "$API2_IOS_SIMULATOR" <<'PY'
import subprocess, sys
result = subprocess.run(
    ["xcrun", "simctl", "terminate", sys.argv[1], "com.github.gemsnote"],
    capture_output=True, text=True)
if result.returncode and "found nothing to terminate" not in result.stderr:
    raise SystemExit(result.stderr)
print("Seed process stopped" if result.returncode == 0 else "Seed process already exited")
PY
      fi
    done
  else
    GEMSNOTE_DISPOSABLE_API2=1 "$flutter_bin" test test/live/api2_postgres_test.dart --reporter expanded "$@"
  fi
) 2>&1 | tee "$test_work/flutter-test.log"
