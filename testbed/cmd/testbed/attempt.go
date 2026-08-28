package main

import (
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

	if err := clearStats(ctx, o.root); err != nil {
		return nil, false, err
	}
	if err := l.LoadMission(ctx, o.mapName, o.mission); err != nil {
		return nil, false, err
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

	results, crashed := waitForWaves(ctx, l, o)
	if err := copyStats(ctx, o.root, path); err != nil {
		return results, crashed, err
	}
	return results, crashed, nil
}

// waitForWaves polls the statistics file, and notices a server that has gone.
func waitForWaves(ctx context.Context, l lab.Lab, o options) ([]wave.Result, bool) {
	deadline := time.Now().Add(o.timeout)
	staged := filepath.Join(os.TempDir(), "testbed-stats.jsonl")

	for {
		if time.Now().After(deadline) {
			o.say("gave up after %s", o.timeout)
			return readStaged(ctx, o.root, staged), false
		}
		select {
		case <-ctx.Done():
			return readStaged(ctx, o.root, staged), false
		case <-time.After(20 * time.Second):
		}

		if _, err := l.Do("status"); err != nil {
			o.say("the server stopped answering, which is a crash in what is being measured")
			return readStaged(ctx, o.root, staged), true
		}
		results := readStaged(ctx, o.root, staged)
		if len(results) >= o.waves {
			return results, false
		}
	}
}

func readStaged(ctx context.Context, root, staged string) []wave.Result {
	if err := copyStats(ctx, root, staged); err != nil {
		return nil
	}
	results, err := wave.Read(staged)
	if err != nil {
		return nil
	}
	return results
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
