# Level scripts

## validate_level.swift (current geometry)

Single-map validator used while designing new floors. Paste a candidate 17×36 maze into the `map` array at the top, then:

```sh
swift scripts/validate_level.swift
```

On success it prints the maze formatted as a Swift literal you can paste into `Boss-Man/Boss-Man/Levels.swift`. On failure it lists every rule violation.

Checks: row count + width, perimeter walls, top/bottom + side tunnel gaps, walkability of the four power-pellet corners + four boss spawn cells + the worker spawn, 1-pellet H-alcove rule (3 walls + 1 pellet + wall behind), minimum 6 hideouts, and tunnel-aware flood-fill connectivity from the worker spawn.

## level_check.py (legacy)

Validates `Sources/Boss-Man/Levels.swift`:

- Every row is exactly 30 characters
- Each level has 17 rows
- Top/bottom rows are all walls; col 0 and col 29 are walls on every row
- Worker spawn `(1,15)`, boss spawns `(28,15)`, `(1,1)`, `(28,1)`, and the four power-pellet corners `(2,15)`, `(27,15)`, `(2,1)`, `(27,1)` are all walkable and reachable from the worker spawn via BFS

Run:

```sh
python3 scripts/level_check.py Sources/Boss-Man/Levels.swift
```

Exit prints `Summary: N levels, K issues`.

> Note: `level_check.py` and `level_check.sh` were written against an older 30-wide layout. Prefer `validate_level.swift` for current designs.

## level_check.sh (legacy, awk)

Lightweight awk version that checks lengths, the four corner cells, and presence of `P`, `F`, `C`, `M`, `D`. Does **not** do connectivity. Kept for quick smoke tests:

```sh
scripts/level_check.sh Sources/Boss-Man/Levels.swift
```
