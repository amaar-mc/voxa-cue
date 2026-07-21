#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../../.." && pwd)
port=4175
path="/ml/gesture-classifier/recorder/"
url="http://127.0.0.1:$port$path"

if [ ! -d "/Applications/Google Chrome.app" ]; then
  echo "Google Chrome is required for Web Bluetooth on macOS." >&2
  exit 69
fi

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$repository_root" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM

attempt=1
while [ "$attempt" -le 20 ]; do
  if curl --silent --fail "$url" >/dev/null 2>&1; then
    open -a "/Applications/Google Chrome.app" "$url"
    echo "Voxa Gesture Recorder: $url"
    echo "Keep this terminal open. Press Control-C to stop."
    wait "$server_pid"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

echo "The gesture recorder could not start on port $port." >&2
exit 69
