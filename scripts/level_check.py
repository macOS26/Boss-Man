import re, sys, collections

path = sys.argv[1]
src = open(path).read()

levels = []
in_arr = False
current = None
for line in src.splitlines():
    s = line.strip()
    if s.startswith('let officeMaps'):
        in_arr = True; continue
    if not in_arr: continue
    if s.startswith('['):
        current = []; continue
    if s == ']' or s == '],':
        if current is not None:
            levels.append(current); current = None
        continue
    m = re.match(r'^"(.*?)",?$', s)
    if m and current is not None:
        current.append(m.group(1))

spawns = [("worker",1,15),("boss1",34,15),("boss2",1,1),("boss3",34,1)]
pellets = [("PP_TL",2,15),("PP_TR",33,15),("PP_BL",2,1),("PP_BR",33,1)]
# tunnel "mouth" cells (must be walkable gap) and their inner approach cells.
tunnel_mouths = [("tunnel_L (0,8)",0,8),("tunnel_R (35,8)",35,8),
                 ("tunnel_T (18,16)",18,16),("tunnel_B (18,0)",18,0)]
tunnel_inner = [("inner_L (1,8)",1,8),("inner_R (34,8)",34,8),
                ("inner_T (18,15)",18,15),("inner_B (18,1)",18,1)]
TUNNEL_PARTNERS = {
    (0, 8): (35, 8), (35, 8): (0, 8),
    (18, 0): (18, 16), (18, 16): (18, 0),
}

def walkable(rows, x, y):
    r = len(rows)-1-y
    if r<0 or r>=len(rows): return False
    if x<0 or x>=len(rows[r]): return False
    return rows[r][x] != '#'

def bfs(rows, sx, sy):
    seen = {(sx,sy)}
    q = collections.deque([(sx,sy)])
    while q:
        x,y = q.popleft()
        for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
            nx,ny = x+dx, y+dy
            if (nx,ny) in seen: continue
            if walkable(rows, nx, ny):
                seen.add((nx,ny)); q.append((nx,ny))
        if (x,y) in TUNNEL_PARTNERS:
            p = TUNNEL_PARTNERS[(x,y)]
            if p not in seen and walkable(rows, *p):
                seen.add(p); q.append(p)
    return seen

def is_border_ok(c, ri, ci):
    # walls everywhere except the 4 tunnel mouths, which must be ' '.
    if (ci == 18 and ri == 0) or (ci == 18 and ri == 16):
        return c == ' '
    if ri == 8 and (ci == 0 or ci == 35):
        return c == ' '
    return c == '#'

fail = 0
for i, rows in enumerate(levels, 1):
    for ri, row in enumerate(rows):
        if len(row) != 36:
            print(f"Level {i} row {ri} len={len(row)}: |{row}|"); fail+=1
    if len(rows) != 17:
        print(f"Level {i}: {len(rows)} rows (need 17)"); fail+=1
    for ci, c in enumerate(rows[0]):
        if not is_border_ok(c, 0, ci):
            print(f"Level {i} top border bad at col {ci}: '{c}'"); fail+=1
    for ci, c in enumerate(rows[-1]):
        if not is_border_ok(c, 16, ci):
            print(f"Level {i} bottom border bad at col {ci}: '{c}'"); fail+=1
    for ri in range(1, len(rows)-1):
        for ci in [0, 35]:
            c = rows[ri][ci]
            if not is_border_ok(c, ri, ci):
                print(f"Level {i} row {ri} side wall bad at col {ci}: '{c}' |{rows[ri]}|"); fail+=1
    if not walkable(rows, 1, 15):
        print(f"Level {i}: worker spawn (1,15) not walkable"); fail+=1; continue
    reachable = bfs(rows, 1, 15)
    hideouts = [(x,y) for y in range(17) for x in range(36) if rows[16-y][x] == 'H']
    if not hideouts:
        print(f"Level {i}: no hideout (H) cell"); fail+=1
    for hx, hy in hideouts:
        if (hx,hy) not in reachable:
            print(f"Level {i}: hideout ({hx},{hy}) unreachable from worker"); fail+=1
    for name, x, y in spawns + pellets + tunnel_mouths + tunnel_inner:
        if not walkable(rows, x, y):
            print(f"Level {i}: {name} is a wall"); fail+=1
        elif (x,y) not in reachable:
            print(f"Level {i}: {name} UNREACHABLE from worker"); fail+=1
print(f"\nSummary: {len(levels)} levels, {fail} issues")
