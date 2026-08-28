/*
Package lab drives one test-bed server.

Every rule here exists because breaking it produced a run that looked fine and
measured nothing:

  - one runner at a time, held by a lock file. Two scripts waiting on the same
    "is a run going" check both started, and each map change pulled the other's
    mission out from under it.
  - the map is loaded before the mission is named. A changelevel resets
    tf_mvm_popfile to the map's own mission, and naming a mission on a map that
    has been up for hours reports the right popfile with none of its robots.
  - the plugin the server has loaded is checked against the one on disk. A run
    with --no-build measured a two hour old build and said the fix did nothing.
  - RED is checked for defenders and BLU for robots before the wave counts.
    Twenty two robots and an empty RED still produces a file, and the file is
    empty of everything that matters.
*/
package lab

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/m-this/tf2-mvm-bots/testbed/internal/rcon"
)

// Lab is a server and the rules for talking to it.
type Lab struct {
	Client rcon.Client
	Say    func(format string, args ...any)
}

// ErrPrecondition is a run that must not be believed. Separate from a transport
// error because this one means the server is fine and the run is not.
var ErrPrecondition = errors.New("the run did not meet its preconditions")

func (l Lab) say(format string, args ...any) {
	if l.Say != nil {
		l.Say(format, args...)
	}
}

// Do runs one command, and says what it sent when it fails.
func (l Lab) Do(command string) (string, error) {
	out, err := l.Client.Do(command)
	if err != nil {
		return out, fmt.Errorf("%q: %w", command, err)
	}
	return out, nil
}

// WaitForRcon blocks until the server answers, which is the whole of it being up.
func (l Lab) WaitForRcon(ctx context.Context, limit time.Duration) error {
	deadline := time.Now().Add(limit)
	for {
		if _, err := l.Client.Do("status"); err == nil {
			return nil
		} else if errors.Is(err, rcon.ErrAuth) {
			return err
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("the server did not answer rcon within %s", limit)
		}
		if err := sleep(ctx, 5*time.Second); err != nil {
			return err
		}
	}
}

var (
	mapLine    = regexp.MustCompile(`(?m)^map\s+:\s+(\S+)`)
	playerLine = regexp.MustCompile(`(?m)^players\s*:\s*(\d+)\s+humans,\s+(\d+)\s+bots`)
	botName    = regexp.MustCompile(`(?m)^#\s+\d+\s+"([^"]*)"\s+BOT`)
	popLine    = regexp.MustCompile(`Current popfile is:\s*(\S+)`)
	versionRow = regexp.MustCompile(`"Defender TFBots"\s+\(([^)]+)\)`)
)

// Roster is who is on the server, split the way a run cares about.
type Roster struct {
	Humans    int
	Bots      int
	Robots    int // BLU, which the game names TFBot
	Defenders int // ours, which the mod gives a name of its own
	Host      bool
}

// Roster reads status and says who is there.
func (l Lab) Roster() (Roster, error) {
	out, err := l.Do("status")
	if err != nil {
		return Roster{}, err
	}
	var r Roster
	if m := playerLine.FindStringSubmatch(out); m != nil {
		r.Humans, _ = strconv.Atoi(m[1])
		r.Bots, _ = strconv.Atoi(m[2])
	}
	for _, m := range botName.FindAllStringSubmatch(out, -1) {
		switch name := m[1]; {
		case name == "testbed-host":
			r.Host = true
		case strings.HasSuffix(name, "TFBot"):
			r.Robots++
		default:
			r.Defenders++
		}
	}
	return r, nil
}

// CurrentMap is the map the server is on.
func (l Lab) CurrentMap() (string, error) {
	out, err := l.Do("status")
	if err != nil {
		return "", err
	}
	if m := mapLine.FindStringSubmatch(out); m != nil {
		return m[1], nil
	}
	return "", fmt.Errorf("status said nothing about a map: %q", trim(out))
}

// PopFile is the mission the server says it is playing.
func (l Lab) PopFile() (string, error) {
	out, err := l.Do("tf_mvm_popfile")
	if err != nil {
		return "", err
	}
	if m := popLine.FindStringSubmatch(out); m != nil {
		return m[1], nil
	}
	return "", fmt.Errorf("could not read the popfile from %q", trim(out))
}

// PluginVersion is the version of the mod the server has loaded, which is not
// always the version on disk.
func (l Lab) PluginVersion() (string, error) {
	out, err := l.Do("sm plugins list")
	if err != nil {
		return "", err
	}
	if m := versionRow.FindStringSubmatch(out); m != nil {
		return m[1], nil
	}
	return "", fmt.Errorf("the defender mod is not in the plugin list: %q", trim(out))
}

/*
LoadMission puts the server on a map and a mission, in that order.

The order is the whole point. A changelevel resets tf_mvm_popfile, so naming the
mission first throws the name away; and naming it on a map already up leaves
missions like mvm_mannworks_intermediate2 reporting themselves as loaded with
none of their robots built.
*/
func (l Lab) LoadMission(ctx context.Context, mapName, mission string) error {
	/* server.cfg runs on map load, and the first map can load before the entrypoint has written
	   ours. Executing it by hand costs nothing when it was already read, and is the difference
	   between measuring six bots and none: without it the mod has no team composition and RED stays
	   empty, which the settle step then refuses. */
	if _, err := l.Do("exec server.cfg"); err != nil {
		l.say("could not exec server.cfg, which usually means RED will stay empty: %v", err)
	}

	l.say("loading %s", mapName)
	if _, err := l.Do("changelevel " + mapName); err != nil {
		// A changelevel drops the connection, which is not a failure.
		l.say("the changelevel closed the connection, which is expected")
	}
	if err := sleep(ctx, 10*time.Second); err != nil {
		return err
	}
	if err := l.WaitForRcon(ctx, 3*time.Minute); err != nil {
		return err
	}
	if err := l.waitForMap(ctx, mapName); err != nil {
		return err
	}
	if err := sleep(ctx, 20*time.Second); err != nil {
		return err
	}

	if mission == "" {
		return nil
	}
	l.say("naming mission %s", mission)
	if _, err := l.Do("tf_mvm_popfile " + mission); err != nil {
		return err
	}
	if err := sleep(ctx, 15*time.Second); err != nil {
		return err
	}

	loaded, err := l.PopFile()
	if err != nil {
		return err
	}
	if !strings.Contains(loaded, mission) {
		return fmt.Errorf("%w: asked for %s and the server is playing %s", ErrPrecondition, mission, loaded)
	}

	// The map load reads server.cfg again, and the mission was named after it.
	// Executing it here is what puts the lineup back for the round about to start.
	if _, err := l.Do("exec server.cfg"); err != nil {
		l.say("could not exec server.cfg after the map load: %v", err)
	}
	return nil
}

func (l Lab) waitForMap(ctx context.Context, want string) error {
	deadline := time.Now().Add(3 * time.Minute)
	for {
		if got, err := l.CurrentMap(); err == nil && got == want {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("%w: the server never reached %s", ErrPrecondition, want)
		}
		if err := sleep(ctx, 5*time.Second); err != nil {
			return err
		}
	}
}

/*
Settle waits for the mod to fill RED, then nudges the round.

Bounded, and the bound failing is a refusal rather than a shrug: a run with
nobody on RED writes a file full of zeros, which reads as a mission nobody could
win rather than as a test-bed that never started.
*/
func (l Lab) Settle(ctx context.Context, wantDefenders int, limit time.Duration) error {
	l.say("waiting for the mod to fill RED")
	deadline := time.Now().Add(limit)
	for {
		roster, err := l.Roster()
		if err == nil && roster.Defenders >= wantDefenders {
			l.say("RED holds %d defenders", roster.Defenders)
			break
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("%w: RED never reached %d defenders", ErrPrecondition, wantDefenders)
		}
		if err := sleep(ctx, 5*time.Second); err != nil {
			return err
		}
	}
	if err := sleep(ctx, 5*time.Second); err != nil {
		return err
	}
	_, _ = l.Do("mp_tournament_restart")
	return nil
}

// Compose runs a docker compose subcommand against the test-bed.
func Compose(ctx context.Context, file string, args ...string) error {
	full := append([]string{"compose", "-f", file}, args...)
	cmd := exec.CommandContext(ctx, "docker", full...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	return cmd.Run()
}

func sleep(ctx context.Context, d time.Duration) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(d):
		return nil
	}
}

func trim(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 200 {
		return s[:200] + "..."
	}
	return s
}

/*
JumpToWave starts the mission partway in, which is how a wave three report is
made without playing waves one and two for half an hour.

The jump is a cheat command, so cheats go on for it and back to what they were
after. Restoring the previous value rather than zero: a server somebody had set
cheats on deliberately should not have them turned off by a measurement.
*/
func (l Lab) JumpToWave(ctx context.Context, wave int) error {
	before, err := l.Do("sv_cheats")
	if err != nil {
		return err
	}
	restore := "0"
	if strings.Contains(before, `"sv_cheats" = "1"`) {
		restore = "1"
	}

	if err := sleep(ctx, 5*time.Second); err != nil {
		return err
	}
	if _, err := l.Do("sv_cheats 1"); err != nil {
		return err
	}
	if _, err := l.Do(fmt.Sprintf("tf_mvm_jump_to_wave %d", wave)); err != nil {
		return err
	}
	_, err = l.Do("sv_cheats " + restore)
	return err
}
