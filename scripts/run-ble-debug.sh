#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_directory")
port=4173
tester_directory="$repository_root/tools/ble-debug"
url="http://127.0.0.1:$port/"

if [ ! -d "/Applications/Google Chrome.app" ]; then
  echo "Google Chrome is required for Web Bluetooth on macOS." >&2
  exit 69
fi

cd "$repository_root"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$tester_directory" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM

server_ready=false
attempt=1
while [ "$attempt" -le 20 ]; do
  if curl --silent --fail "$url" >/dev/null 2>&1; then
    server_ready=true
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid" || true
    echo "The BLE debug server could not start. Port $port may already be in use." >&2
    exit 69
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

if [ "$server_ready" != true ]; then
  echo "The BLE debug server did not become ready at $url." >&2
  exit 69
fi

open -a "/Applications/Google Chrome.app" "$url"

echo "Voxa Cue BLE tester: $url"
echo "Keep this terminal open. Press Control-C when testing is finished."
wait "$server_pid"
