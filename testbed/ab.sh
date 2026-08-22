#!/bin/sh
# Play the same maps twice with one feature switched, and keep both halves.
#
#   testbed/ab.sh --feature demo_sticky_first
#   testbed/ab.sh --feature demo_sticky_first --maps "mvm_coaltown mvm_decoy"
#   testbed/ab.sh --feature "demo_hold_fire,attack_strafe" --tag demo
#
# More than one feature is a comma separated list, and they move together: both
# off in one arm, both on in the other. That answers whether the pair is worth
# having and does not answer which of them did it, so it is a first screen and
# not a conclusion. Split it afterwards if it wins.
#
# A feature is a named switch with a default, and the point of one is that the
# same build can play both sides of an argument. This is the loop that does it:
# for each map, the mission is played once with the feature off and once with it
# on, and the two results files are kept apart.
#
# Off first and on second, per map, rather than every off run followed by every
# on run. The two halves of a pair are then minutes apart instead of hours, so
# whatever else the machine is doing drifts across both of them rather than
# across one. It is not a controlled experiment; it is the cheapest thing that
# is not obviously wrong.
#
# Read the two halves with:
#
#   go run ./testbed/sweepreport results/ab-<tag>/on results/ab-<tag>/off
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)

feature=""
waves=6
timeout=1500
maps=""
tag=""

while [ $# -gt 0 ]; do
	case "$1" in
	--feature) feature=$2; shift 2 ;;
	--waves) waves=$2; shift 2 ;;
	--timeout) timeout=$2; shift 2 ;;
	--maps) maps=$2; shift 2 ;;
	--tag) tag=$2; shift 2 ;;
	-h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

if [ -z "$feature" ]; then
	echo "ab: --feature is required, e.g. --feature demo_sticky_first" >&2
	exit 2
fi

# A list of features makes a poor directory name
[ -n "$tag" ] || tag=$(echo "$feature" | tr ',' '-')

if [ -z "$maps" ]; then
	maps=$(docker exec mvmbots-testbed-srcds-1 sh -c \
		'ls /home/steam/tf-dedicated/tf/maps/ 2>/dev/null' 2>/dev/null |
		sed -n 's/^\(mvm_[a-z0-9_]*\)\.bsp$/\1/p' | sort | tr '\n' ' ')
fi

if [ -z "$maps" ]; then
	echo "ab: no maps found, is the test-bed server up?" >&2
	exit 1
fi

out=$root/testbed/results/ab-$tag
mkdir -p "$out/off" "$out/on"
log=$out/ab.log

say() { printf '[ab] %s\n' "$1" | tee -a "$log"; }

say "feature: $feature"
say "maps: $maps"
say "waves per arm: $waves"

# The first run of the pair pays for the compile. Everything after it is the
# same build, which is the whole point: one mod, one switch.
build=""

for map in $maps; do
	for arm in off on; do
		value=0
		[ "$arm" = on ] && value=1

		# One name=value per feature, which is the format BOT_FEATURES already takes
		features=""

		for name in $(echo "$feature" | tr ',' ' '); do
			[ -n "$features" ] && features="$features,"
			features="$features$name=$value"
		done

		say "=== $map, $features ==="

		TESTBED_BOT_FEATURES="$features" \
			sh "$here/run.sh" --map "$map" --waves "$waves" --timeout "$timeout" \
			$build --out "$out/$arm/$map.jsonl" >"$out/$arm/$map.log" 2>&1 || true

		build="--no-build"

		results=$(grep -c '"event":"wave_end"' "$out/$arm/$map.jsonl" 2>/dev/null || true)

		# The results file records which features were on. If that disagrees with
		# what this asked for, the run measured the wrong thing and saying so here
		# is cheaper than finding out from the numbers.
		first=$(echo "$feature" | cut -d, -f1)
		seen=$(grep -o "$first" "$out/$arm/$map.jsonl" 2>/dev/null | head -1 || true)

		say "$map $arm: ${results:-0} wave results, $first named in file: ${seen:-no}"
	done
done

say "done: $out"
