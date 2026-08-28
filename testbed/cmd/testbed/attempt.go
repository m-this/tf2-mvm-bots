package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/m-this/tf2-mvm-bots/testbed/internal/lab"
	"github.com/m-this/tf2-mvm-bots/testbed/internal/wave"
)

// playArm runs every attempt of one arm and collects what they produced.
func playArm(ctx context.Context, l lab.Lab, a arm, o options) (wave.Arm, error) {
	got := wave.Arm{Name: a.name}

	for i := 1; i <= o.attempts; i++ {
		o.say("=== %s attempt %d of %d", a.name, i, o.attempts)
		got.Attempts++

		path := filepath.Join(o.out, fmt.Sprintf("%s-%s-%d.jsonl", o.tag, a.name, i))
		results, crashed, err := playOnce(ctx, l, a, o, path)
		switch {
		case errors.Is(err, context.Canceled):
			return got, err
		case errors.Is(err, lab.ErrPrecondition):
			// Loud, and the run stops: a precondition that fails once fails the
			// same way every time, and grinding through the rest wastes an hour
			// to produce nothing.
			return got, err
		case err != nil:
			o.say("attempt %d did not finish: %v", i, err)
		}

		if crashed {
			got.Crashes++
		}
		if len(results) == 0 {
			got.Empty++
			o.say("attempt %d produced no wave result", i)
			continue
		}
		got.Results = append(got.Results, results...)
		o.say("attempt %d: %d waves, %d cleared", i, len(results), cleared(results))
	}
	return got, nil
}

func cleared(results []wave.Result) int {
	n := 0
	for _, r := range results {
		if r.Outcome == "cleared" {
			n++
		}
	}
	return n
}

// playOnce is one attempt: set the arm, load the mission, wait for the waves.
func playOnce(ctx context.Context, l lab.Lab, a arm, o options, path string) ([]wave.Result, bool, error) {
	if err := clearStats(ctx, o.root); err != nil {
		return nil, false, err
	}
	if err := l.LoadMission(ctx, o.mapName, o.mission); err != nil {
		return nil, false, err
	}

	/* The arm goes on after the map load, not before.
	   A map load execs server.cfg, and that file puts the container's own values back: an arm set
	   first is an arm the server has forgotten by the time the wave starts. */
	if _, err := l.Do("sm_redbots_manager_team_composition \"" + o.team + "\""); err != nil {
		return nil, false, err
	}
	for _, pair := range strings.Split(a.cvars, ",") {
		if pair = strings.TrimSpace(pair); pair == "" {
			continue
		}
		key, value, found := strings.Cut(pair, "=")
		if !found {
			return nil, false, fmt.Errorf("an arm cvar is key=value, not %q", pair)
		}
		if _, err := l.Do(key + " " + value); err != nil {
			return nil, false, err
		}
	}

	if err := l.Settle(ctx, o.defenders, 3*time.Minute); err != nil {
		return nil, false, err
	}
	if o.jump > 0 {
		o.say("jumping to wave %d", o.jump)
		if err := l.JumpToWave(ctx, o.jump); err != nil {
			return nil, false, err
		}
	}

	results, crashed, reason := waitForWaves(ctx, l, o)
	if err := copyStats(ctx, o.root, path); err != nil {
		return results, crashed, err
	}
	if len(results) == 0 && reason != "" && !crashed {
		// A run that produced nothing for a reason the watcher can name is
		// worth saying out loud, and worth keeping out of the numbers.
		o.say("nothing usable from this attempt: %s", reason)
	}
	return results, crashed, nil
}

/*
waitForWaves watches a running wave rather than only waiting for it.

A wave that goes wrong looks like a slow one for the first minute and like a
finished one at the end, so the difference has to be caught while it happens.
The watcher's reasons name what went wrong, which is worth more than a timeout
and an empty file.
*/
func waitForWaves(ctx context.Context, l lab.Lab, o options) ([]wave.Result, bool, string) {
	staged := filepath.Join(os.TempDir(), "testbed-stats.jsonl")

	watcher := &lab.Watcher{
		WantDefenders: o.defenders,
		// A wave lasts minutes and the polls are twenty seconds apart, so five
		// polls is well past a between-rounds lull and well short of a wave.
		PatienceRobots: 5,
		PatienceSilent: 6,
	}

	var found []wave.Result
	health, err := l.Wait(ctx, watcher, 20*time.Second, o.timeout, func() (int, int, bool) {
		lines, results := readStagedWithLines(ctx, o.root, staged)
		found = results
		begun := wave.Begun(staged)
		if len(results) >= o.waves {
			// Enough waves: say so by reporting the count the caller wanted.
			return lines, len(results), begun
		}
		return lines, 0, begun
	})
	if err != nil {
		return found, false, "cancelled"
	}

	if len(found) >= o.waves {
		return found, false, ""
	}
	o.say("%s", health.Reason)
	return found, health.Fatal, health.Reason
}

// readStagedWithLines is the results so far and how much has been written at
// all. The line count is what tells a quiet wave from a dead plugin.
func readStagedWithLines(ctx context.Context, root, staged string) (int, []wave.Result) {
	if err := copyStats(ctx, root, staged); err != nil {
		return 0, nil
	}
	body, err := os.ReadFile(staged)
	if err != nil {
		return 0, nil
	}
	lines := bytes.Count(body, []byte("\n"))

	results, err := wave.Read(staged)
	if err != nil {
		return lines, nil
	}
	return lines, results
}

const remoteStats = "/home/steam/tf-dedicated/tf/addons/sourcemod/logs/mvmbots_stats.jsonl"

func clearStats(ctx context.Context, root string) error {
	return exec.CommandContext(ctx, "docker", "exec", container(),
		"sh", "-c", "rm -f "+remoteStats).Run()
}

func copyStats(ctx context.Context, root, to string) error {
	if err := os.MkdirAll(filepath.Dir(to), 0o755); err != nil {
		return err
	}
	cmd := exec.CommandContext(ctx, "docker", "cp", container()+":"+remoteStats, to)
	cmd.Stderr = nil
	return cmd.Run()
}
