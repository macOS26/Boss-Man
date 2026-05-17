#!/bin/bash
# Validates a Swift Levels.swift file: each maze row must be 30 chars,
# 17 rows per level, walkable at (1,15),(2,15),(27,15),(28,15),(1,1),(2,1),(27,1),(28,1),
# and contains at least one of P,F,C,M and one D.
awk '
/^let officeMaps/ { in_array=1; level=0; row=0; next }
in_array && /^    \[/ { level++; row=0; next }
in_array && /^    \]/ {
    if (row != 17) printf "Level %d has %d rows (need 17)\n", level, row
    next
}
in_array && /^        "/ {
    line = $0
    sub(/^[ \t]+"/, "", line)
    sub(/",?$/, "", line)
    L = length(line)
    if (L != 30) printf "Level %d row %d length=%d: |%s|\n", level, row, L, line
    rows[level,row] = line
    row++
}
END {
    for (lv = 1; lv <= level; lv++) {
        # row index 1 corresponds to y=15, row index 15 to y=1
        for (col_check = 0; col_check < 4; col_check++) {
            split("1 2 27 28", cols, " ")
        }
        # Use substring (1-indexed in awk)
        r1 = rows[lv, 1]
        r15 = rows[lv, 15]
        for (i = 1; i <= 4; i++) {
            c = (i==1?1:(i==2?2:(i==3?27:28)))
            ch1 = substr(r1, c+1, 1)
            ch15 = substr(r15, c+1, 1)
            if (ch1 == "#") printf "Level %d y=15 col %d is wall (%s)\n", lv, c, ch1
            if (ch15 == "#") printf "Level %d y=1 col %d is wall (%s)\n", lv, c, ch15
        }
        has_P=0; has_F=0; has_C=0; has_M=0; has_D=0
        for (r = 0; r < 17; r++) {
            line = rows[lv, r]
            if (index(line, "P") > 0) has_P=1
            if (index(line, "F") > 0) has_F=1
            if (index(line, "C") > 0) has_C=1
            if (index(line, "M") > 0) has_M=1
            if (index(line, "D") > 0) has_D=1
        }
        if (!has_P) printf "Level %d missing P\n", lv
        if (!has_F) printf "Level %d missing F\n", lv
        if (!has_C) printf "Level %d missing C\n", lv
        if (!has_M) printf "Level %d missing M\n", lv
        if (!has_D) printf "Level %d missing D\n", lv
    }
    print "Validation complete. " level " levels."
}
' "$1"
