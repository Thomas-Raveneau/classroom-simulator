#!/bin/sh
# End-to-end run of the real game with three instances over the ENet backend:
# a host, a client, and a player joining once the game is running.
# Usage: tests/e2e/run.sh [path to the Godot binary]
# On a simulated bad connection: NET_LATENCY=150 NET_JITTER=30 NET_LOSS=5 tests/e2e/run.sh
GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/../.." || exit 1

# Each instance is killed after 150 seconds, whatever happens.
run() {
	perl -e 'alarm 150; exec @ARGV' "$GODOT" --headless --path . res://tests/e2e/e2e_player.tscn -- \
		--lobby-backend=enet "--lobby-name=$1" "--e2e-role=$2" \
		"--net-latency=${NET_LATENCY:-0}" "--net-jitter=${NET_JITTER:-0}" "--net-loss=${NET_LOSS:-0}" \
		2>&1 | sed "s/^/$2 | /"
}

run Host host & host_pid=$!
run Client client & client_pid=$!
run Late late & late_pid=$!
wait $host_pid $client_pid $late_pid
