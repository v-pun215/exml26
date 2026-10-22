#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PORT="${PORT:-8765}"
SEED="${SEED:-7}"
GODOT="${GODOT:-}"

if [ -z "$GODOT" ]; then
	for candidate in \
		/Applications/Godot.app/Contents/MacOS/Godot \
		"$(command -v godot || true)" \
		"$(command -v godot4 || true)"
	do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			GODOT="$candidate"
			break
		fi
	done
fi

if [ -z "$GODOT" ]; then
	echo "Could not find Godot." >&2
	echo "Set GODOT=/path/to/godot and run this again." >&2
	exit 1
fi

if [ ! -d front/.godot ]; then
	echo "First run, importing assets..."
	"$GODOT" --headless --path front --import
fi

python3 tools/godot_bridge.py --port "$PORT" --seed "$SEED" &
BRIDGE_PID=$!

cleanup() {
	kill "$BRIDGE_PID" 2>/dev/null || true
	wait "$BRIDGE_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 0.5
if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
	echo "Bridge failed to start, is port $PORT already in use?" >&2
	exit 1
fi

echo "bridge on 127.0.0.1:$PORT, seed $SEED"
"$GODOT" --path front -- --port="$PORT"
