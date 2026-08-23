// Where a bot stood, and how close the fight was while he stood there.
//
// Every fault reported by a person watching the game has been a placement
// fault: a medic parked in a house healing whoever walks past, a soldier close
// enough to a robot to catch his own splash, an engineer swinging a wrench at a
// wall. The samples already carried the answer to all three, in `at` and
// `nearest_enemy`. Nothing read them, so the report could show a medic "beam on
// somebody 43% of the time" while he had not moved in two minutes.
//
// A share of samples is not a stopwatch, and the numbers here are deliberately
// blunt: how far he moved between two samples, how far the nearest robot was.
// Both are facts. What counts as parked is the opinion, and it lives here.
package main

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

// How far a bot must move between two samples to count as going somewhere.
//
// Samples are five seconds apart and the slowest class covers a thousand units
// in that time, so this is not a threshold anybody walking crosses by accident.
// A bot holding a corner strafes, and strafing stays under it.
const parkedStep = 100.0

// A rocket's own splash. A soldier closer to a robot than this is standing
// inside the weapon he is firing.
const blastRadius = 146.0

// The engineer has to be on top of a building to hit it with the wrench. Beyond
// this he is swinging at whatever is in front of him, which has been a wall.
const wrenchReach = 100.0

const sampleSeconds = 5.0

type standRollup struct {
	class         string
	samples       int
	steps         int
	parked        int
	longestParked int
	parkedAt      []float64
	travelled     float64
	wrenchOut     int
	wrenchStuck   int
	firing        int
	firingAtWorld int
	aimedAt       map[string]int
}

func distance(a, b []float64) float64 {
	if len(a) < 3 || len(b) < 3 {
		return -1
	}

	dx, dy, dz := a[0]-b[0], a[1]-b[1], a[2]-b[2]

	return math.Sqrt(dx*dx + dy*dy + dz*dz)
}

func percentile(values []float64, p float64) float64 {
	if len(values) == 0 {
		return -1
	}

	sorted := append([]float64(nil), values...)
	sort.Float64s(sorted)

	at := int(float64(len(sorted)) * p)

	if at >= len(sorted) {
		at = len(sorted) - 1
	}

	return sorted[at]
}

// Every building sample keyed by its owner and the instant it was taken, so an
// engineer's wrench swing can be measured against where his own nest was at
// that moment rather than where it ended up.
func nestByOwnerAndClock(buildings []buildingSample) map[string][][]float64 {
	out := map[string][][]float64{}

	for _, s := range buildings {
		key := fmt.Sprintf("%s|%.1f", s.Owner, s.Clock)
		out[key] = append(out[key], s.At)
	}

	return out
}

func rollupStanding(bots []botSample, buildings []buildingSample) map[string]*standRollup {
	nests := nestByOwnerAndClock(buildings)

	// While a wave is running, and not during the break.
	//
	// `t` is zero for every sample taken between waves, and the break is a
	// different game: bots stand on the upgrade station, the engineer stands on
	// his own teleporter entrance holding a wrench. Eleven of the fourteen
	// samples the first version of this flagged as an engineer stuck with a
	// wrench were him in the spawn between waves, doing nothing wrong.
	var ordered []botSample

	for _, s := range bots {
		if s.T > 0 {
			ordered = append(ordered, s)
		}
	}

	sort.SliceStable(ordered, func(i, j int) bool {
		if ordered[i].Who != ordered[j].Who {
			return ordered[i].Who < ordered[j].Who
		}

		return ordered[i].Clock < ordered[j].Clock
	})

	out := map[string]*standRollup{}
	run := 0

	for i, s := range ordered {
		r := out[s.Who]

		if r == nil {
			r = &standRollup{class: s.Class, aimedAt: map[string]int{}}
			out[s.Who] = r
		}

		r.samples++

		if s.Aim != "" {
			r.aimedAt[s.Aim]++
		}

		if s.Firing != 0 {
			r.firing++

			// The reported symptom, as a number at last: the trigger held with
			// the ray ending in a wall. A bot shooting a robot and a bot
			// shooting the wall in front of the robot are the same action
			// stack, the same weapon and the same position.
			if s.Aim == "world" {
				r.firingAtWorld++
			}
		}

		// Consecutive only within one bot and one wave. A wave boundary is a
		// respawn, and the walk from the front back to the spawn room is not a
		// step anybody took.
		if i == 0 || ordered[i-1].Who != s.Who || ordered[i-1].Wave != s.Wave {
			run = 0

			continue
		}

		step := distance(ordered[i-1].At, s.At)

		if step < 0 {
			continue
		}

		if s.Class == "engineer" && s.Slot == 2 {
			r.wrenchOut++

			key := fmt.Sprintf("%s|%.1f", s.Who, s.Clock)
			reach := -1.0

			for _, at := range nests[key] {
				if d := distance(s.At, at); d >= 0 && (reach < 0 || d < reach) {
					reach = d
				}
			}

			// Standing still is the half that makes this a fault. An engineer
			// walking to a hurt sentry with the wrench already out is doing the
			// right thing and was being counted as doing the wrong one: the
			// first version of this flagged 57% of his wrench samples and most
			// of them were him on his way there. Stopped, out of reach of
			// anything he owns, with the wrench out, is the reported symptom.
			if reach > wrenchReach && step < parkedStep {
				r.wrenchStuck++
			}
		}

		r.steps++
		r.travelled += step

		if step >= parkedStep {
			run = 0

			continue
		}

		r.parked++
		run++

		if run > r.longestParked {
			r.longestParked = run
			r.parkedAt = s.At
		}
	}

	return out
}

// How close the nearest robot was, per class.
//
// The complaint this answers is that the front line is too close, which is a
// claim about a distance and was argued about for two sessions without one.
func printEngagement(bots []botSample) {
	ranges := map[string][]float64{}
	inBlast := map[string]int{}

	for _, s := range bots {
		// -1 is the plugin saying there was no robot alive to measure against.
		if s.NearestEnemy < 0 {
			continue
		}

		ranges[s.Class] = append(ranges[s.Class], s.NearestEnemy)

		if s.NearestEnemy < blastRadius {
			inBlast[s.Class]++
		}
	}

	if len(ranges) == 0 {
		return
	}

	fmt.Printf("\n  how close the nearest robot was\n")

	// The median and the near tail, because they answer different complaints.
	// "The medic is nowhere near the fight" is the median. "The heavy is at
	// melee range" is the tenth percentile: his median was 865 in the run where
	// he was watched standing on top of a giant, and the median is not wrong,
	// it is answering the other question.
	for _, class := range sortedKeys(ranges) {
		fmt.Printf("    %-9s median %.0f, closest tenth under %.0f, point blank %d%% of samples\n",
			class, percentile(ranges[class], 0.5), percentile(ranges[class], 0.1),
			pct(inBlast[class], len(ranges[class])))
	}
}

func printStanding(bots []botSample, buildings []buildingSample) {
	if len(bots) == 0 {
		return
	}

	printEngagement(bots)

	rolled := rollupStanding(bots, buildings)

	fmt.Printf("\n  where they stood while a wave was running\n")

	for _, who := range sortedKeys(rolled) {
		r := rolled[who]

		if r.steps == 0 {
			continue
		}

		fmt.Printf("    %-16s %-9s stood still %d%% of the time, longest %.0fs",
			who, r.class, pct(r.parked, r.steps), float64(r.longestParked)*sampleSeconds)

		if len(r.parkedAt) == 3 {
			fmt.Printf(" at %.0f %.0f %.0f", r.parkedAt[0], r.parkedAt[1], r.parkedAt[2])
		}

		fmt.Printf(", %.0f units walked per wave\n", r.travelled/float64(max(wavesIn(bots, who), 1)))

		if r.firing > 0 {
			fmt.Printf("    %-16s %-9s trigger held in %d%% of samples, %d%% of those into the world%s\n",
				"", "", pct(r.firing, r.steps), pct(r.firingAtWorld, r.firing),
				topAim(r.aimedAt, r.samples))
		}

		if r.wrenchOut > 0 {
			fmt.Printf("    %-16s %-9s wrench out %d samples, %d%% of them stopped out of reach of his own buildings\n",
				"", "", r.wrenchOut, pct(r.wrenchStuck, r.wrenchOut))
		}
	}
}

func wavesIn(bots []botSample, who string) int {
	seen := map[int]bool{}

	for _, s := range bots {
		if s.Who == who && s.T > 0 {
			seen[s.Wave] = true
		}
	}

	return len(seen)
}

// What the bot spent the run pointing at, which is where the wall shows up.
func topAim(aimed map[string]int, samples int) string {
	type pair struct {
		name  string
		count int
	}

	var pairs []pair

	for name, count := range aimed {
		pairs = append(pairs, pair{name, count})
	}

	sort.Slice(pairs, func(i, j int) bool { return pairs[i].count > pairs[j].count })

	var parts []string

	for i, p := range pairs {
		if i == 3 {
			break
		}

		parts = append(parts, fmt.Sprintf("%s %d%%", p.name, pct(p.count, samples)))
	}

	if len(parts) == 0 {
		return ""
	}

	return " (aimed at " + strings.Join(parts, ", ") + ")"
}
