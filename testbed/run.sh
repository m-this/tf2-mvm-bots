#!/bin/sh
# Run a mission with nobody playing, and write down what the bots did with it.
#
#   testbed/run.sh                                  one mission on Decoy
#   testbed/run.sh --mission mvm_decoy_advanced     a named popfile
#   testbed/run.sh --waves 12 --timeout 3600        stop after twelve results
#   testbed/run.sh --out results/after.jsonl        somewhere to compare against
#   testbed/run.sh --docker                         compile in the image instead
#
# It brings the server up, waits for the game to finish downloading itself the
# first time, sends the mission, and then watches the statistics file until it
# has the wave results it was asked for or the timeout runs out. The server is
# left running unless --down is given, because the second run of the day should
# not download the game again.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)

map=${TESTBED_MAP:-mvm_decoy}
mission=""
waves=6
timeout=2400
out=""
down=0
rebuild=1
# Where the mod is compiled. The host is the fast way and needs spcomp and the
# fetched sources; the image needs nothing but Docker and pays for a compile and
# a layer export on every rebuild.
in_docker=0

while [ $# -gt 0 ]; do
	case "$1" in
	--map) map=$2; shift 2 ;;
	--mission) mission=$2; shift 2 ;;
	--waves) waves=$2; shift 2 ;;
	--timeout) timeout=$2; shift 2 ;;
	--out) out=$2; shift 2 ;;
	--down) down=1; shift ;;
	--no-build) rebuild=0; shift ;;
	--docker) in_docker=1; shift ;;
	-h | --help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

: "${TESTBED_RCONPW:=testbed}"
: "${TESTBED_PORT:=27025}"
stats_file=${TESTBED_STATS_FILE:-mvmbots_stats.jsonl}
export TESTBED_MAP=$map TESTBED_RCONPW TESTBED_PORT TESTBED_STATS_FILE=$stats_file

compose_file=$here/compose.yml
[ "$in_docker" = 1 ] && compose_file=$here/compose.docker.yml

compose="docker compose -f $compose_file"
# rcon.py reads the password and the port from the environment, and takes the
# commands as arguments
rcon="SRCDS_RCONPW=$TESTBED_RCONPW SRCDS_PORT=$TESTBED_PORT python3 $here/rcon.py"
remote_stats="/home/steam/tf-dedicated/tf/addons/sourcemod/logs/$stats_file"

say() { printf '[test-bed] %s\n' "$1"; }

# A machine that already runs a Team Fortress 2 server has the game on it
# already. Copying it beats downloading it again, and the script leaves the
# volume alone if it is not empty.
#
# The game only, never the other server's addons/: see seed-volume.sh for what
# copying those costs.
if [ "${TESTBED_SEED_FROM:-}" != "" ]; then
	sh "$here/seed-volume.sh" "$TESTBED_SEED_FROM"
elif docker volume inspect tf2-archipelago_tf2game >/dev/null 2>&1; then
	say "found a Team Fortress 2 install in tf2-archipelago_tf2game"
	sh "$here/seed-volume.sh"
fi

# Whatever the seed did or did not do, the volume needs a game in it. The image
# has SourceMod and the server scripts and not the fifteen gigabytes, so a
# volume nobody seeded starts a server that exits 127 on a missing srcds_run.
sh "$here/install-game.sh"

# Compiling on the host, not in an image. The container mounts what this writes,
# so a rebuild is a compile and a restart rather than a compile, a copy, a chown
# and a layer export.
if [ "$rebuild" = 1 ]; then
	say "building"

	if [ "$in_docker" = 1 ]; then
		$compose build
	else
		sh "$here/build.sh" >"$here/build/build.log" 2>&1 || {
			say "the build failed, see testbed/build/build.log"
			tail -20 "$here/build/build.log"
			exit 1
		}
	fi
fi

# Whether there was a server here before this run, which decides whether the
# build below has to be carried in by a restart.
running=$($compose ps --status running -q srcds 2>/dev/null || true)

say "starting the server on $map"
$compose up -d

# A rebuild reaches a live server through a restart and never through the copy
# the entrypoint runs every thirty seconds. That copy truncates each file before
# writing it, and truncating one the running game has mapped is a SIGBUS in
# whatever it executes out of that page next: the entrypoint says as much above
# its cp, and says it cost a day. A container that has just come up already has
# the new build, so only one that was already running needs this.
if [ "$rebuild" = 1 ] && [ -n "$running" ]; then
	say "restarting the server onto the new build"
	$compose restart
fi

# The first start downloads the game, which is tens of gigabytes, and then
# SourceMod, and only then does the supervisor in the entrypoint have somewhere
# to install to. Waiting for rcon to answer is waiting for all of it.
say "waiting for the server to answer rcon (the first run downloads the game)"
waited=0
until eval "$rcon status" >/dev/null 2>&1; do
	waited=$((waited + 10))
	if [ "$waited" -ge "$timeout" ]; then
		say "the server never came up"
		exit 1
	fi
	sleep 10
done

# server.cfg runs on map load, and the first map can load before the supervisor
# in the entrypoint has written ours. Executing it by hand costs nothing when it
# was already read, and is the difference between measuring six bots and none.
eval "$rcon 'exec server.cfg'" >/dev/null 2>&1 || true

# Start from an empty file so the run being measured is the run in the file.
$compose exec -T srcds sh -c "rm -f $remote_stats" >/dev/null 2>&1 || true

if [ -n "$mission" ]; then
	say "loading mission $mission"
	eval "$rcon 'tf_mvm_popfile $mission'" >/dev/null || true
	sleep 15
fi

# The bots ready themselves up once they have bought their upgrades, so this is
# a nudge rather than the thing that starts the wave. It matters on the first
# wave of a fresh server, where the mod has not filled RED yet.
eval "$rcon 'mp_tournament_restart'" >/dev/null 2>&1 || true

say "watching for $waves wave results, giving up after ${timeout}s"

start=$(date +%s)
results=0

while [ "$results" -lt "$waves" ]; do
	now=$(date +%s)
	if [ $((now - start)) -ge "$timeout" ]; then
		say "timed out with $results of $waves results"
		break
	fi

	sleep 20

	# A crashing server looks exactly like a slow one from out here: no new
	# results, for as long as the timeout allows. It is worth ten characters of
	# grep to be told which it is.
	#
	# This run's logs only. The container keeps everything it has ever printed,
	# across every restart, so one crash in the morning read as a crash in every
	# run for the rest of the day: each of them stopped twenty seconds in and
	# wrote a results file with nothing in it.
	crashes=$($compose logs --since "$((now - start + 5))s" srcds 2>&1 |
		grep -ciE 'core dumped|Segmentation fault|Bus error' || true)

	if [ "${crashes:-0}" -gt 0 ]; then
		say "the game server has crashed ${crashes} time(s): that is a bug in what is being measured, not a slow wave"
		say "docker compose -f $here/compose.yml logs srcds | grep -i 'core dumped'"
		break
	fi

	results=$($compose exec -T srcds sh -c "grep -c wave_end $remote_stats 2>/dev/null || true" | tr -d '\r')
	results=${results:-0}

	say "$results of $waves waves finished"
done

mkdir -p "$root/testbed/results"
out=${out:-$root/testbed/results/$(date +%Y%m%d-%H%M%S).jsonl}

$compose exec -T srcds sh -c "cat $remote_stats 2>/dev/null || true" >"$out"

say "wrote $out"

if [ "$down" = 1 ]; then
	say "stopping the server"
	$compose down
fi

go run "$here/report" "$out"
