#!/bin/sh
# Play the same mission N times on each of two builds, one run at a time.
#
#   testbed/batch.sh 3 /tmp/bots-base
#
# Sequential on purpose. The watchdog this mod trips measures how long a frame
# took, and running two servers on four cores makes frames take longer, so
# parallel runs invent crashes that are not in the code. Wave duration is a
# measured number here too, and it moves for the same reason.
set -eu

runs=${1:-3}
base=${2:-}
map=${MAP:-mvm_decoy}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=$here/results/batch
mkdir -p "$out"

# The lineup both builds are forced to play, so the run measures the code and
# not the team. Set COMP to empty to let each build choose for itself, which is
# how the per-map Composition is measured against whatever the old one did.
comp=${COMP-scout,soldier,demoman,heavyweapons,engineer,medic}

play() {
	tree=$1 name=$2 i=$3
	echo "=== $name run $i"
	TESTBED_BIND=127.0.0.1 \
	TESTBED_MAP=$map \
	TESTBED_BOT_TEAM_COMP="$comp" \
	TESTBED_BOT_TEAM_SIZE=6 \
	TESTBED_HOST=1 \
		sh "$tree/testbed/run.sh" --map "$map" --waves 6 --timeout 1800 \
			--out "$out/$name-$i.jsonl" >"$out/$name-$i.log" 2>&1 || true

	# The container is recreated by the next run, and `docker compose logs` goes
	# with it. A crash whose log is gone is a crash nobody can diagnose, so the
	# server's own output is kept next to the numbers it produced.
	docker compose -f "$here/compose.yml" logs --no-color srcds \
		>"$out/$name-$i.srcds.log" 2>&1 || true

	if grep -qi "has crashed" "$out/$name-$i.log"; then
		echo "    crashed"
		grep -iE "WatchDog|Segmentation|Bus error|FATAL" "$out/$name-$i.srcds.log" | tail -3
	fi
}

i=1
while [ "$i" -le "$runs" ]; do
	play "$here/.." current "$i"
	[ -n "$base" ] && play "$base" base "$i"
	i=$((i + 1))
done

echo
echo "=== every run"
for f in "$out"/*.jsonl; do
	printf '%s  ' "$(basename "$f" .jsonl)"
	python3 "$here/report.py" "$f" 2>/dev/null | tr '\n' ' '
	echo
done
