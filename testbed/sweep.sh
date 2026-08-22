#!/bin/sh
# Play every map the server has, one after another, and keep what each one did.
#
#   testbed/sweep.sh                       every installed map, six waves each
#   testbed/sweep.sh --waves 4             fewer waves per map
#   testbed/sweep.sh --maps "mvm_decoy mvm_bigrock"
#
# A single map says whether a change works there. It does not say whether the
# thing it fixed was a property of that map's geometry, and most of what the
# engineer does is a property of geometry: where the nest goes, whether the
# ground takes a dispenser, how far the spawn door is. The only way to tell a
# map-shaped bug from a mod-shaped one is to play them all.
#
# One results file per map, plus one line per map in the sweep log saying how it
# went, so a sweep that dies halfway has still written down everything it got
# to. Nothing here is clever: it is run.sh in a loop with the map changed, and
# the reason it exists is that the loop takes hours and should not be a person.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)

waves=6
# Long enough for six waves of a mission nobody is helping with, and short
# enough that one map that never clears a wave does not eat the whole night.
timeout=2400
maps=""
tag=$(date +%Y%m%d-%H%M%S)

while [ $# -gt 0 ]; do
	case "$1" in
	--waves) waves=$2; shift 2 ;;
	--timeout) timeout=$2; shift 2 ;;
	--maps) maps=$2; shift 2 ;;
	--tag) tag=$2; shift 2 ;;
	-h | --help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

# What the server actually has, rather than what the config directory has an
# opinion about: configs/defenderbots/map names community maps nobody installed.
if [ -z "$maps" ]; then
	maps=$(docker exec mvmbots-testbed-srcds-1 sh -c \
		'ls /home/steam/tf-dedicated/tf/maps/ 2>/dev/null' 2>/dev/null |
		sed -n 's/^\(mvm_[a-z0-9_]*\)\.bsp$/\1/p' | sort | tr '\n' ' ')
fi

if [ -z "$maps" ]; then
	echo "sweep: no maps found, is the test-bed server up?" >&2
	exit 1
fi

out=$root/testbed/results/sweep-$tag
mkdir -p "$out"
log=$out/sweep.log

say() { printf '[sweep] %s\n' "$1" | tee -a "$log"; }

say "maps: $maps"
say "waves per map: $waves, timeout per map: ${timeout}s"

first=1

for map in $maps; do
	say "=== $map ==="
	started=$(date +%s)

	# The first map pays for the compile. Every one after it is the same build,
	# and rebuilding between maps would mean a sweep measured several different
	# mods and said so nowhere.
	build=""
	[ "$first" = 0 ] && build="--no-build"
	first=0

	if sh "$here/run.sh" --map "$map" --waves "$waves" --timeout "$timeout" \
		$build --out "$out/$map.jsonl" >"$out/$map.log" 2>&1; then
		status=ok
	else
		status=failed
	fi

	elapsed=$(( $(date +%s) - started ))
	results=$(grep -c '"event":"wave_end"' "$out/$map.jsonl" 2>/dev/null || echo 0)

	# A map the server crashed on is the single most important line in the file
	crashed=$(grep -ciE 'core dumped|Segmentation fault|Bus error' "$out/$map.log" 2>/dev/null || echo 0)

	say "$map: $status, $results wave results, ${elapsed}s, crashes $crashed"
done

say "done, results in $out"
