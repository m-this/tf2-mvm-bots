// Read the wave lines a run produced and say what happened.
//
//	go run ./report results/batch/current-1.jsonl
//	go run ./report results/after.jsonl results/before.jsonl
//
// With two files it compares them, the first being the run under test.
//
// The interesting numbers are not the ones that say whether the team held.
// Waves cleared is almost always the same for two builds of the same mod;
// what separates them is who did the work and what killed them.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

// One wave, as the statistics plugin writes it. Unknown fields are ignored, so
// an older file missing the contribution numbers still reads.
type wave struct {
	Event    string  `json:"event"`
	Map      string  `json:"map"`
	Wave     int     `json:"wave"`
	Result   string  `json:"result"`
	Duration float64 `json:"duration"`

	RobotKills        int `json:"robot_kills"`
	GiantKills        int `json:"giant_kills"`
	TankKills         int `json:"tank_kills"`
	DefenderDeaths    int `json:"defender_deaths"`
	Backstabs         int `json:"backstabs"`
	SentriesLost      int `json:"sentries_lost"`
	BusterDetonations int `json:"buster_detonations"`

	Damage       int `json:"damage"`
	TankDamage   int `json:"tank_damage"`
	SentryDamage int `json:"sentry_damage"`
	Healing      int `json:"healing"`
	Ubers        int `json:"ubers"`

	// Per class, keyed by the class name the plugin writes
	DamageBy   map[string]int `json:"-"`
	KillsBy    map[string]int `json:"-"`
	GiantsBy   map[string]int `json:"-"`
	KilledByBy map[string]int `json:"-"`
}

var classes = []string{"scout", "soldier", "pyro", "demoman", "heavy",
	"engineer", "medic", "sniper", "spy"}

// The per-class fields are flat keys rather than nested objects, because the
// plugin writes them with one format string and no allocation.
func (w *wave) unpackClasses(raw map[string]int) {
	w.DamageBy = map[string]int{}
	w.KillsBy = map[string]int{}
	w.GiantsBy = map[string]int{}
	w.KilledByBy = map[string]int{}

	for _, c := range classes {
		w.DamageBy[c] = raw["damage_"+c]
		w.KillsBy[c] = raw["kills_"+c]
		w.GiantsBy[c] = raw["giantkills_"+c]
		w.KilledByBy[c] = raw["killedby_"+c]
	}

	w.KilledByBy["sentry"] = raw["killedby_sentry"]
	w.KilledByBy["tank"] = raw["killedby_tank"]
}

func load(path string) ([]wave, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var waves []wave

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if !strings.HasPrefix(line, "{") {
			continue
		}

		var w wave
		if err := json.Unmarshal([]byte(line), &w); err != nil {
			continue
		}

		// Wave zero is the tournament restart writing a result for a wave
		// nobody played, and it drags every average it appears in.
		if w.Event != "wave_end" || w.Wave == 0 {
			continue
		}

		var raw map[string]int
		_ = json.Unmarshal([]byte(line), &raw)
		w.unpackClasses(raw)

		waves = append(waves, w)
	}

	return waves, scanner.Err()
}

type summary struct {
	waves, cleared                        int
	kills, giants, deaths, stabs          int
	sentriesLost, busters                 int
	damage, tankDamage, sentryDamage      int
	healing, ubers                        int
	damageBy, killsBy, giantsBy, killedBy map[string]int
}

func summarise(waves []wave) summary {
	s := summary{
		damageBy: map[string]int{}, killsBy: map[string]int{},
		giantsBy: map[string]int{}, killedBy: map[string]int{},
	}

	for _, w := range waves {
		s.waves++
		if w.Result == "cleared" {
			s.cleared++
		}

		s.kills += w.RobotKills
		s.giants += w.GiantKills
		s.deaths += w.DefenderDeaths
		s.stabs += w.Backstabs
		s.sentriesLost += w.SentriesLost
		s.busters += w.BusterDetonations
		s.damage += w.Damage
		s.tankDamage += w.TankDamage
		s.sentryDamage += w.SentryDamage
		s.healing += w.Healing
		s.ubers += w.Ubers

		for k, v := range w.DamageBy {
			s.damageBy[k] += v
		}
		for k, v := range w.KillsBy {
			s.killsBy[k] += v
		}
		for k, v := range w.GiantsBy {
			s.giantsBy[k] += v
		}
		for k, v := range w.KilledByBy {
			s.killedBy[k] += v
		}
	}

	return s
}

// Descending by value, dropping zeroes, so a line only names what happened
func ranked(m map[string]int) string {
	type pair struct {
		name  string
		count int
	}

	var pairs []pair
	for k, v := range m {
		if v > 0 {
			pairs = append(pairs, pair{k, v})
		}
	}

	sort.Slice(pairs, func(i, j int) bool {
		if pairs[i].count != pairs[j].count {
			return pairs[i].count > pairs[j].count
		}
		return pairs[i].name < pairs[j].name
	})

	var parts []string
	for _, p := range pairs {
		parts = append(parts, fmt.Sprintf("%s %d", p.name, p.count))
	}

	if len(parts) == 0 {
		return "nothing"
	}

	return strings.Join(parts, "  ")
}

func percent(part, whole int) string {
	if whole == 0 {
		return "0%"
	}
	return fmt.Sprintf("%.0f%%", float64(part)/float64(whole)*100)
}

func print(name string, s summary) {
	fmt.Printf("\n%s\n", name)
	fmt.Printf("  waves played      %d\n", s.waves)
	fmt.Printf("  cleared           %d (%s)\n", s.cleared, percent(s.cleared, s.waves))
	fmt.Printf("  robots killed     %d, of them %d giants\n", s.kills, s.giants)
	fmt.Printf("  defenders died    %d\n", s.deaths)
	fmt.Printf("  sentries lost     %d\n", s.sentriesLost)

	if s.damage == 0 {
		fmt.Printf("  (no contribution numbers in this file)\n")
		return
	}

	fmt.Printf("  damage dealt      %d\n", s.damage)
	fmt.Printf("  of it, sentries   %d (%s)\n", s.sentryDamage, percent(s.sentryDamage, s.damage))
	fmt.Printf("  damage to tanks   %d\n", s.tankDamage)
	fmt.Printf("  healing done      %d, %d ubers\n", s.healing, s.ubers)
	fmt.Printf("  damage by class   %s\n", ranked(s.damageBy))
	fmt.Printf("  kills by class    %s\n", ranked(s.killsBy))
	fmt.Printf("  giants by class   %s\n", ranked(s.giantsBy))
	fmt.Printf("  killed us         %s\n", ranked(s.killedBy))
}

func compare(now, then summary) {
	fmt.Printf("\ncompared\n")
	fmt.Printf("  cleared           %s -> %s\n", percent(then.cleared, then.waves), percent(now.cleared, now.waves))
	fmt.Printf("  defenders died    %d -> %d\n", then.deaths, now.deaths)
	fmt.Printf("  damage dealt      %d -> %d\n", then.damage, now.damage)
	fmt.Printf("  sentry damage     %d -> %d\n", then.sentryDamage, now.sentryDamage)
	fmt.Printf("  healing done      %d -> %d\n", then.healing, now.healing)
	fmt.Printf("  sentries lost     %d -> %d\n", then.sentriesLost, now.sentriesLost)
}

func main() {
	args := os.Args[1:]

	if len(args) == 0 || len(args) > 2 {
		fmt.Fprintln(os.Stderr, "usage: report <after.jsonl> [before.jsonl]")
		return
	}

	after, err := load(args[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if len(after) == 0 {
		fmt.Printf("%s\n  no wave results in this file\n", args[0])
		return
	}

	now := summarise(after)
	print(args[0], now)

	if len(args) == 1 {
		return
	}

	before, err := load(args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	then := summarise(before)
	print(args[1], then)
	compare(now, then)
}
