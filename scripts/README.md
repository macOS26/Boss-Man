# Level scripts

## level_check.py (recommended)

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

## level_check.sh (legacy, awk)

Lightweight awk version that checks lengths, the four corner cells, and presence of `P`, `F`, `C`, `M`, `D`. Does **not** do connectivity. Kept for quick smoke tests:

```sh
scripts/level_check.sh Sources/Boss-Man/Levels.swift
```
