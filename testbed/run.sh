#!/bin/sh
# Run a mission with nobody playing, and write down what the bots did with it.
#
#   testbed/run.sh                                  one mission on Decoy
#   testbed/run.sh --mission mvm_decoy_advanced     a named popfile
#   testbed/run.sh --waves 12 --timeout 3600        stop after twelve results
#   testbed/run.sh --out results/after.jsonl        somewhere to compare against
#   testbed/run.sh --wave 3                         start at wave 3 of the mission
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
# Which wave to start on. A report about one wave is a report about one wave, and
# playing the two before it to reach it costs half an hour a run.
jump=""
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
	--wave) jump=$2; shift 2 ;;
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

# Whether there was a server here before this run, which decides whether the
# build below has to be carried in by a restart.
running=$($compose ps --status running -q srcds 2>/dev/null || true)

# Nothing may write the staged tree while a server is reading it.
#
# The entrypoint copies that tree into the volume every thirty seconds and cp
# truncates each file before writing it. Truncating one the running game has
# mapped is a SIGBUS in whatever it executes out of that page next, or a SIGSEGV
# later once a half written one is executing. The entrypoint says so above its
# cp, and says it cost a day.
#
# Restarting afterwards is not enough: the copy only has to happen once in the
# seconds between the compiler writing a file and the restart, and it runs every
# thirty. So the server goes down first and comes back up onto the finished
# tree.
if [ "$rebuild" = 1 ] && [ -n "$running" ]; then
	say "stopping the server while the mod is rebuilt"
	$compose stop
fi

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

# A run measured under paging is not a measurement.
#
# A session once went from six clean waves to four failed runs in a row with no
# code change between them: 200 MB free, 5 GB swapped out, and swap-in bursting
# at 20 MB/s. A page fault that stalls the server is indistinguishable, to a
# watchdog that measures frame time, from an infinite loop. So the numbers said
# the build crashed and the machine was the answer.
#
# Checked rather than remembered. TESTBED_MIN_FREE_MB=0 turns it off.
free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 99999)

if [ "${TESTBED_MIN_FREE_MB:-1500}" -gt 0 ] && [ "$free_mb" -lt "${TESTBED_MIN_FREE_MB:-1500}" ]; then
	say "only ${free_mb} MB of memory available, and a run under paging measures the machine"
	say "free some up, or set TESTBED_MIN_FREE_MB=0 to run anyway"
	exit 1
fi

say "starting the server on $map"
$compose up -d

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

	# A popfile the game refused leaves the map's own mission running and says nothing about it.
	# Three sessions of "Bavarian Botbash wave 3" were measured against Rottenburg's default
	# intermediate mission because the name was wrong and nothing checked.
	loaded=$(eval "$rcon 'tf_mvm_popfile'" 2>/dev/null | tr -d '\r')

	case "$loaded" in
	*"$mission"*) : ;;
	*)
		say "the server refused mission $mission and is playing: $loaded"
		say "the names are in the game's own VPK: grep -ao 'mvm_<map>[a-z0-9_]*' tf/tf2_misc_dir.vpk"
		exit 1
		;;
	esac
fi

# Let the server finish standing up before telling it to restart the round.
#
# rcon answers early. The map is loaded by then and very little else is: the
# statistics plugin measured a 1541ms frame two seconds into a map, which is the
# server spawning entities and settling. Sending mp_tournament_restart into that
# put the spawning of every robot on top of it, and the watchdog killed the
# server there: the console shows the restart, then "NextBot tickrate changed
# from 0 to 7", then the fatal line, with RED still holding nobody but the host.
#
# So wait for RED to have somebody on it, which is the mod having done its own
# start-up work, and then a little longer. Bounded, because a server that never
# fills RED should still be told to start rather than hang here for ever.
say "waiting for the server to settle before restarting the round"

settled=0

while [ "$settled" -lt 60 ]; do
	players=$(eval "$rcon status" 2>/dev/null | sed -n 's/^players *: *\([0-9]*\) humans, \([0-9]*\) bots.*/\2/p')

	[ "${players:-0}" -gt 1 ] && break

	settled=$((settled + 5))
	sleep 5
done

sleep 5

# The bots ready themselves up once they have bought their upgrades, so this is
# a nudge rather than the thing that starts the wave. It matters on the first
# wave of a fresh server, where the mod has not filled RED yet.
eval "$rcon 'mp_tournament_restart'" >/dev/null 2>&1 || true

# The jump is a cheat command, so cheats go on for it and off again after. It
# grants the credits of the waves it skipped, which is what a team arriving at
# that wave would have had.
if [ -n "$jump" ]; then
	say "jumping to wave $jump"
	sleep 5
	eval "$rcon 'sv_cheats 1'" >/dev/null 2>&1 || true
	eval "$rcon 'tf_mvm_jump_to_wave $jump'" >/dev/null 2>&1 || true
	eval "$rcon 'sv_cheats 0'" >/dev/null 2>&1 || true
fi

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

		# Which kind, because the two lead opposite ways: the watchdog means
		# something took too long, a bare segfault means something is corrupt.
		# An evening went on telling them apart by hand.
		if $compose logs --since "$((now - start + 5))s" srcds 2>&1 | grep -q 'WatchdogHandler called'; then
			say "the engine watchdog killed it: a frame took too long, so look for what was slow"
			$compose logs --since "$((now - start + 5))s" srcds 2>&1 |
				grep -iE 'stuck:|WatchDog!' | tail -3 | sed 's/^/  /'
		else
			say "a segfault, with no watchdog before it: look for what is corrupt"
		fi

		# The core is the whole answer and finding it was the slow part.
		core=$($compose exec -T srcds sh -c 'ls -t /home/steam/tf-dedicated/core.* 2>/dev/null | head -1' | tr -d '\r')
		if [ -n "$core" ]; then
			say "docker cp $($compose ps -q srcds):$core /tmp/ && $here/symbolise-core.sh /tmp/$(basename "$core")"
		fi
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
