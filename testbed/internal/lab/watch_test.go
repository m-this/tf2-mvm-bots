package lab

import (
	"strings"
	"testing"
)

// The stall that cost nine Mannhunt runs: the mission is loaded, the wave is
// running, and there is not a robot in it. That has to be named in a minute
// rather than found in an empty file after twenty five.
func TestAWaveWithNoRobotsIsCalledOut(t *testing.T) {
	w := &Watcher{WantDefenders: 6, PatienceRobots: 3, PatienceSilent: 0}
	l := Lab{}

	var h Health
	for i := 0; i < 3; i++ {
		h = w.check(Roster{Defenders: 6, Robots: 0}, 10+i)
	}
	_ = l

	if h.Reason == "" {
		t.Fatal("three polls with no robot said nothing")
	}
	if !strings.Contains(h.Reason, "not playing") {
		t.Errorf("the reason reads %q", h.Reason)
	}
}

// A plugin that has stopped writing looks exactly like a quiet wave, until the
// samples stop growing.
func TestSilenceIsCalledOut(t *testing.T) {
	w := &Watcher{PatienceSilent: 3, PatienceRobots: 0}

	var h Health
	for i := 0; i < 4; i++ {
		h = w.check(Roster{Defenders: 6, Robots: 12}, 100)
	}
	if !strings.Contains(h.Reason, "statistics plugin") {
		t.Errorf("four silent polls read as %q", h.Reason)
	}
}

// A wave with robots and a growing file is a wave worth waiting for, however
// long it takes.
func TestAHealthyWaveIsLeftAlone(t *testing.T) {
	w := &Watcher{WantDefenders: 6, PatienceRobots: 3, PatienceSilent: 3}

	for i := 0; i < 10; i++ {
		if h := w.check(Roster{Defenders: 6, Robots: 20}, 100+i*7); h.Reason != "" {
			t.Fatalf("a healthy wave was stopped: %q", h.Reason)
		}
	}
}

// RED emptying mid-wave means the rest of the run measures a different team.
func TestAnEmptyRedIsCalledOut(t *testing.T) {
	w := &Watcher{WantDefenders: 6, PatienceRobots: 0, PatienceSilent: 0}

	if h := w.check(Roster{Defenders: 0, Robots: 20}, 10); !strings.Contains(h.Reason, "no defenders") {
		t.Errorf("an empty RED read as %q", h.Reason)
	}
}
