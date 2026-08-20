#!/usr/bin/env python3
"""Read what the bots did with a run, and say whether it beat the last one.

    testbed/report.py results/after.jsonl
    testbed/report.py results/after.jsonl --baseline results/before.jsonl

One run on its own is a table of waves. Two runs is the question worth asking:
did the change help. The comparison is per wave where both runs played the same
wave of the same map, because wave 6 of Decoy is not wave 6 of Rottenburg and
averaging across them says nothing.

A word on how much to believe it. A wave is not deterministic, the bots draw
their loadouts, and a giant that walks left instead of right decides a wave. A
single run is an anecdote. The clear rate over a dozen waves is worth something;
a two second difference in one wave's duration is not.
"""

import argparse
import json
import statistics
import sys
from pathlib import Path

# What is counted per wave, and how to say it in a heading
COLUMNS = [
    ("duration", "secs"),
    ("robot_kills", "kills"),
    ("giant_kills", "giants"),
    ("defender_deaths", "deaths"),
    ("backstabs", "stabs"),
    ("sentries_lost", "sentry-"),
    ("buster_detonations", "busters"),
]


def load(path: Path) -> list[dict]:
    """Every wave result in a file, in the order they were played.

    A line that is not JSON is a line the server was killed halfway through
    writing, which is a thing that happens to the last line of a file and is
    not a reason to refuse the rest of it.
    """
    waves = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if record.get("event") == "wave_end":
            waves.append(record)
    return waves


def key(wave: dict) -> tuple[str, int]:
    return (wave.get("map", "?"), wave.get("wave", 0))


def summarise(waves: list[dict]) -> dict:
    cleared = [w for w in waves if w.get("result") == "cleared"]
    return {
        "waves": len(waves),
        "cleared": len(cleared),
        "clear_rate": len(cleared) / len(waves) if waves else 0.0,
        # Only cleared waves have a meaningful duration: a lost one is timed
        # from the wave starting to the bomb going in, which is a different
        # thing being measured under the same name.
        "median_duration": statistics.median([w.get("duration", 0.0) for w in cleared]) if cleared else 0.0,
        "robot_kills": sum(w.get("robot_kills", 0) for w in waves),
        "defender_deaths": sum(w.get("defender_deaths", 0) for w in waves),
        "backstabs": sum(w.get("backstabs", 0) for w in waves),
        "sentries_lost": sum(w.get("sentries_lost", 0) for w in waves),
        "buster_detonations": sum(w.get("buster_detonations", 0) for w in waves),
    }


def print_table(waves: list[dict]) -> None:
    if not waves:
        print("no wave results in this file")
        return

    heads = ["map", "wave", "result"] + [label for _, label in COLUMNS]
    widths = [max(len(h), 9) for h in heads]

    print("  ".join(h.ljust(w) for h, w in zip(heads, widths)))
    for wave in waves:
        cells = [
            str(wave.get("map", "?")),
            str(wave.get("wave", 0)),
            str(wave.get("result", "?")),
        ]
        for field, _ in COLUMNS:
            value = wave.get(field, 0)
            cells.append(f"{value:.0f}" if isinstance(value, float) else str(value))
        print("  ".join(c.ljust(w) for c, w in zip(cells, widths)))


def print_summary(name: str, summary: dict) -> None:
    print(f"\n{name}")
    print(f"  waves played      {summary['waves']}")
    print(f"  cleared           {summary['cleared']} ({summary['clear_rate'] * 100:.0f}%)")
    print(f"  median clear time {summary['median_duration']:.0f}s")
    print(f"  robots killed     {summary['robot_kills']}")
    print(f"  defenders died    {summary['defender_deaths']}")
    print(f"  backstabbed       {summary['backstabs']}")
    print(f"  sentries lost     {summary['sentries_lost']}")
    print(f"  busters detonated {summary['buster_detonations']}")


def compare(after: list[dict], before: list[dict]) -> None:
    """The same wave of the same map, played twice.

    Waves either run played and the other did not are dropped and counted, not
    silently ignored: a run that only got through four waves is a run that says
    less than one that got through twelve, and the reader should be told.
    """
    before_by_key = {key(w): w for w in before}
    shared = [w for w in after if key(w) in before_by_key]
    dropped = len(after) - len(shared)

    print("\ncompared with the baseline, per wave")
    if not shared:
        print("  no wave was played by both runs")
        return

    heads = ["map", "wave", "result", "was", "secs", "was", "deaths", "was"]
    print("  ".join(h.ljust(9) for h in heads))

    for wave in shared:
        old = before_by_key[key(wave)]
        cells = [
            str(wave.get("map", "?")),
            str(wave.get("wave", 0)),
            str(wave.get("result", "?")),
            str(old.get("result", "?")),
            f"{wave.get('duration', 0.0):.0f}",
            f"{old.get('duration', 0.0):.0f}",
            str(wave.get("defender_deaths", 0)),
            str(old.get("defender_deaths", 0)),
        ]
        print("  ".join(c.ljust(9) for c in cells))

    if dropped:
        print(f"\n  {dropped} wave(s) in this run had no match in the baseline and are not above")

    now, then = summarise(shared), summarise([before_by_key[key(w)] for w in shared])
    gained = now["cleared"] - then["cleared"]
    print(f"\n  waves cleared     {then['cleared']} -> {now['cleared']} ({gained:+d})")
    print(f"  median clear time {then['median_duration']:.0f}s -> {now['median_duration']:.0f}s")
    print(f"  defenders died    {then['defender_deaths']} -> {now['defender_deaths']}")
    print(f"  backstabbed       {then['backstabs']} -> {now['backstabs']}")
    print(f"  sentries lost     {then['sentries_lost']} -> {now['sentries_lost']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results", type=Path, help="the JSONL file a run wrote")
    parser.add_argument("--baseline", type=Path, help="an earlier run to compare against")
    args = parser.parse_args()

    if not args.results.exists():
        print(f"{args.results} does not exist", file=sys.stderr)
        return 1

    waves = load(args.results)

    print_table(waves)
    print_summary(str(args.results), summarise(waves))

    if args.baseline:
        if not args.baseline.exists():
            print(f"{args.baseline} does not exist", file=sys.stderr)
            return 1
        compare(waves, load(args.baseline))

    return 0


if __name__ == "__main__":
    sys.exit(main())
