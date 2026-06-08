#!/usr/bin/env swift
//
// validate_level.swift — Boss-Man level validator
//
// Drops a candidate maze design into `map` below, then `swift
// scripts/validate_level.swift` prints either ✅ with the formatted
// Swift literal ready to paste into Levels.swift, or ❌ with a list of
// rule violations.
//
// Rules enforced (current Boss-Man geometry):
//   • Exactly 17 rows × 36 cols.
//   • Rows 0 and 16: full wall perimeter with a single ' ' gap at col 18
//     (top/bottom tunnel mouths).
//   • Row 8: ' ' at cols 0 and 35 (side tunnel mouths).
//   • Cols 0 and 35 are '#' on every other row.
//   • Spawn cells must be walkable (not '#'):
//       – power pellets at file (1,2), (1,33), (15,2), (15,33)
//       – bosses at file (1,1), (1,34), (15,1), (15,34)
//       – worker at file (9,18)
//   • Hideout 'H' alcoves: row in 1…15, col in 1…34; exactly 3 wall
//     neighbors and 1 '.' (pellet) neighbor; the cell one further step
//     in the pellet direction must be '#'.
//   • At least 6 valid H alcoves (matches the level-12 ask; bumped up
//     from the legacy ≥5 floor).
//   • Tunnel-aware flood fill from the worker spawn must reach every
//     walkable cell.
//
// Re-run after every edit. The script exits with status 1 on failure
// so CI can wire it up if desired.

import Foundation

// --- Edit this candidate map, then re-run the script ----------------
let map: [String] = [
    "################## #################",
    "#D..............................P..#",
    "#.####.#####.############.####.###.#",
    "#.....C........................##H.#",
    "#.########.############.#####.####.#",
    "#.#......#............#.....#....#.#",
    "#.#.####.#####.##########.#.####.#.#",
    "#.#....#.#...#.......M..#.#.....F..#",
    " .#.##.#.#.#.#.########.#.#.######. ",
    "#.#.#H.#.#.#.#..........#.#.#......#",
    "#.#.####.#.#.############.#.#.####.#",
    "#.#.H#...#.#..............#.#....#.#",
    "#.######.#.################.#.####.#",
    "#.H#...............................#",
    "#.#H######.############H#########.##",
    "#P............F........#........C..#",
    "################## #################"
]
// --------------------------------------------------------------------

func validate(_ map: [String]) -> [String] {
    var errors: [String] = []
    guard map.count == 17 else { errors.append("Need 17 rows, got \(map.count)")
    return errors }
    for (i, r) in map.enumerated() {
        if r.count != 36 { errors.append("Row \(i) len=\(r.count): [\(r)]") }
    }
    if !errors.isEmpty { return errors }
    let g: [[Character]] = map.map { Array($0) }
    func at(_ r: Int, _ c: Int) -> Character {
        if r < 0 || r >= g.count || c < 0 || c >= g[r].count { return "?" }
        return g[r][c]
    }
    for c in 0..<36 {
        if c == 18 {
            if at(0,c) != " " { errors.append("Row 0 col 18 ≠ space (tunnel)") }
            if at(16,c) != " " { errors.append("Row 16 col 18 ≠ space (tunnel)") }
        } else {
            if at(0,c) != "#" { errors.append("Row 0 col \(c) ≠ '#'") }
            if at(16,c) != "#" { errors.append("Row 16 col \(c) ≠ '#'") }
        }
    }
    if at(8,0) != " " { errors.append("Row 8 col 0 ≠ space (tunnel mouth)") }
    if at(8,35) != " " { errors.append("Row 8 col 35 ≠ space (tunnel mouth)") }
    for r in 1...15 where r != 8 {
        if at(r,0) != "#" { errors.append("Row \(r) col 0 ≠ '#'") }
        if at(r,35) != "#" { errors.append("Row \(r) col 35 ≠ '#'") }
    }
    func walkable(_ r: Int, _ c: Int) -> Bool { at(r,c) != "#" && at(r,c) != "?" }
    let must: [(Int,Int,String)] = [
        (1,2,"PP-TL"), (1,33,"PP-TR"), (15,2,"PP-BL"), (15,33,"PP-BR"),
        (1,1,"BOLTON"), (1,34,"BOSS"), (15,1,"LUMBERGH"), (15,34,"WADDAMS"),
        (9,18,"worker")
    ]
    for (r,c,n) in must {
        if !walkable(r,c) { errors.append("\(n) at (\(r),\(c)) NOT walkable, is '\(at(r,c))'") }
    }
    var hCount = 0
    var hList: [String] = []
    for r in 0..<17 {
        for c in 0..<36 {
            if at(r,c) == "H" {
                hCount += 1
                if !(r >= 1 && r <= 15 && c >= 1 && c <= 34) {
                    errors.append("H at (\(r),\(c)) not interior")
                    continue
                }
                var walls = 0
                var opens: [(Int,Int)] = []
                for (dr,dc) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    if at(r+dr,c+dc) == "#" { walls += 1 } else { opens.append((dr,dc)) }
                }
                guard walls == 3, opens.count == 1 else {
                    errors.append("H at (\(r),\(c)) walls=\(walls) opens=\(opens.count); want 3+1")
                    continue
                }
                let (dr,dc) = opens[0]
                let pellet = at(r+dr,c+dc)
                if pellet != "." { errors.append("H at (\(r),\(c)) open neighbor '\(pellet)' ≠ '.'")
                continue }
                let behind = at(r+2*dr,c+2*dc)
                if behind != "#" {
                    errors.append("H at (\(r),\(c)) wall-behind-pellet '\(behind)' at (\(r+2*dr),\(c+2*dc)) ≠ '#'")
                    continue
                }
                hList.append("(\(r),\(c))")
            }
        }
    }
    if hCount < 6 { errors.append("Need ≥6 H tiles, got \(hCount)") }
    // Tunnel-aware flood fill from worker spawn.
    var visited = Array(repeating: Array(repeating: false, count: 36), count: 17)
    var stack = [(9,18)]
    while let (r,c) = stack.popLast() {
        if r < 0 || r >= 17 || c < 0 || c >= 36 { continue }
        if visited[r][c] { continue }
        guard walkable(r,c) else { continue }
        visited[r][c] = true
        for (dr,dc) in [(-1,0),(1,0),(0,-1),(0,1)] {
            var nr = r+dr, nc = c+dc
            if r == 8 && dc == -1 && c == 0 { nc = 35 }
            if r == 8 && dc == 1 && c == 35 { nc = 0 }
            if c == 18 && dr == -1 && r == 0 { nr = 16 }
            if c == 18 && dr == 1 && r == 16 { nr = 0 }
            stack.append((nr,nc))
        }
    }
    var unreach = 0
    for r in 0..<17 {
        for c in 0..<36 {
            if walkable(r,c) && !visited[r][c] {
                if unreach < 8 { errors.append("Unreachable walkable at (\(r),\(c)) '\(at(r,c))'") }
                unreach += 1
            }
        }
    }
    if unreach > 8 { errors.append("...and \(unreach-8) more unreachable cells") }
    print("Valid H positions: \(hList.joined(separator: ", "))")
    print("H count: \(hCount), unreachable: \(unreach)")
    return errors
}

let errs = validate(map)
if errs.isEmpty {
    print("✅ Maze valid — paste this into Levels.swift:")
    print("    [")
    for r in map { print("        \"\(r)\",") }
    print("    ]")
    exit(0)
} else {
    print("❌ \(errs.count) errors:")
    for e in errs { print("  - \(e)") }
    exit(1)
}


