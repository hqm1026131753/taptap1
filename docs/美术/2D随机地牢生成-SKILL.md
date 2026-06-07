# 2D Random Dungeon Generator

> Procedural dungeon/map generation for 2D tile-based games.
> Core algorithm: BSP (Binary Space Partitioning) with room placement and corridor connection.

---

## When to Use

Generate random dungeon layouts for roguelikes, top-down shooters, survival games, or any tile-based 2D game. Produces a 2D grid array with rooms, corridors, and wall tiles.

---

## Algorithm Overview

```
1. Start with a rectangular space (the full map)
2. BSP Split: Recursively split space into sub-regions
3. Room Placement: Place a random room inside each leaf region
4. Corridor Connection: Connect rooms at each BSP node
5. Wall Generation: Add wall borders around rooms/corridors
6. Output: 2D grid (0=floor, 1=wall, 2=corridor, 3=door)
```

---

## Parameters

| Param | Default | Range | Effect |
|-------|---------|-------|--------|
| width | 40 | 20-120 | Map width in tiles |
| height | 30 | 20-80 | Map height in tiles |
| minRoomSize | 4 | 3-8 | Minimum room width/height |
| maxRoomSize | 12 | 6-20 | Maximum room width/height |
| minLeafSize | 8 | 6-16 | Minimum BSP leaf size |
| roomPadding | 1 | 0-3 | Tiles between room edge and leaf edge |
| corridorWidth | 1 | 1-3 | Width of connecting corridors |
| maxDepth | 5 | 3-8 | Max BSP recursion depth |

---

## Implementation (JavaScript)

```javascript
class DungeonGenerator {
  constructor(opts = {}) {
    this.width = opts.width || 40;
    this.height = opts.height || 30;
    this.minRoom = opts.minRoomSize || 4;
    this.maxRoom = opts.maxRoomSize || 12;
    this.minLeaf = opts.minLeafSize || 8;
    this.padding = opts.roomPadding || 1;
    this.corridorW = opts.corridorWidth || 1;
    this.maxDepth = opts.maxDepth || 5;
    this.grid = [];
  }

  generate() {
    // 1. Initialize grid as all walls
    this.grid = Array.from({length: this.height}, () =>
      Array(this.width).fill(1)
    );

    // 2. BSP split
    const root = new BSPNode(0, 0, this.width, this.height);
    this.splitNode(root, 0);

    // 3. Create rooms in leaf nodes
    const rooms = [];
    this.createRooms(root, rooms);

    // 4. Connect rooms via corridors
    this.connectNodes(root);

    // 5. Carve rooms into grid
    for (const room of rooms) {
      this.carveRoom(room);
    }

    return {
      grid: this.grid,
      rooms: rooms,
      width: this.width,
      height: this.height,
    };
  }

  splitNode(node, depth) {
    if (depth >= this.maxDepth) return;
    
    // Decide split direction (use longer axis)
    const w = node.w, h = node.h;
    const splitH = w < h ? true : (h < w ? false : Math.random() < 0.5);
    const max = (splitH ? h : w) - this.minLeaf;
    if (max < this.minLeaf) return;

    const split = this.minLeaf + Math.floor(Math.random() * (max - this.minLeaf + 1));

    if (splitH) {
      node.left = new BSPNode(node.x, node.y, w, split);
      node.right = new BSPNode(node.x, node.y + split, w, h - split);
    } else {
      node.left = new BSPNode(node.x, node.y, split, h);
      node.right = new BSPNode(node.x + split, node.y, w - split, h);
    }

    this.splitNode(node.left, depth + 1);
    this.splitNode(node.right, depth + 1);
  }

  createRooms(node, rooms) {
    if (node.left || node.right) {
      if (node.left) this.createRooms(node.left, rooms);
      if (node.right) this.createRooms(node.right, rooms);
      return;
    }

    // Leaf node: place a room
    const rw = this.minRoom + Math.floor(Math.random() *
      Math.min(this.maxRoom - this.minRoom, node.w - this.minRoom - this.padding * 2));
    const rh = this.minRoom + Math.floor(Math.random() *
      Math.min(this.maxRoom - this.minRoom, node.h - this.minRoom - this.padding * 2));

    const rx = node.x + this.padding + Math.floor(Math.random() *
      (node.w - rw - this.padding * 2));
    const ry = node.y + this.padding + Math.floor(Math.random() *
      (node.h - rh - this.padding * 2));

    node.room = { x: rx, y: ry, w: rw, h: rh, cx: Math.floor(rx + rw/2), cy: Math.floor(ry + rh/2) };
    rooms.push(node.room);
  }

  connectNodes(node) {
    if (!node.left || !node.right) return;

    this.connectNodes(node.left);
    this.connectNodes(node.right);

    // Connect the two child subtrees
    const roomA = this.getRoom(node.left);
    const roomB = this.getRoom(node.right);
    if (roomA && roomB) {
      this.connectRooms(roomA, roomB);
    }
  }

  getRoom(node) {
    if (node.room) return node.room;
    // BFS to find any room in the subtree
    const queue = [node.left, node.right];
    while (queue.length) {
      const n = queue.shift();
      if (!n) continue;
      if (n.room) return n.room;
      if (n.left) queue.push(n.left);
      if (n.right) queue.push(n.right);
    }
    return null;
  }

  connectRooms(a, b) {
    // L-shaped corridor from center of A to center of B
    const cx = a.cx, cy = a.cy;
    const tx = b.cx, ty = b.cy;
    
    // Randomly choose L-bend direction
    if (Math.random() < 0.5) {
      this.carveHCorridor(cx, tx, cy);
      this.carveVCorridor(cy, ty, tx);
    } else {
      this.carveVCorridor(cy, ty, cx);
      this.carveHCorridor(cx, tx, ty);
    }
  }

  carveHCorridor(x1, x2, y) {
    const minX = Math.min(x1, x2), maxX = Math.max(x1, x2);
    for (let x = minX; x <= maxX; x++) {
      for (let w = 0; w < this.corridorW; w++) {
        if (y + w < this.height && x < this.width) {
          this.grid[y + w][x] = 2; // corridor
        }
      }
    }
  }

  carveVCorridor(y1, y2, x) {
    const minY = Math.min(y1, y2), maxY = Math.max(y1, y2);
    for (let y = minY; y <= maxY; y++) {
      for (let w = 0; w < this.corridorW; w++) {
        if (y < this.height && x + w < this.width) {
          this.grid[y][x + w] = 2; // corridor
        }
      }
    }
  }

  carveRoom(room) {
    for (let y = room.y; y < room.y + room.h; y++) {
      for (let x = room.x; x < room.x + room.w; x++) {
        this.grid[y][x] = 0; // floor
      }
    }
  }

  // Add 1-tile-thick walls around rooms (replacing edge corridor tiles)
  addRoomWalls() {
    for (let y = 1; y < this.height - 1; y++) {
      for (let x = 1; x < this.width - 1; x++) {
        if (this.grid[y][x] === 0 || this.grid[y][x] === 2) continue;
        // Check if adjacent to floor or corridor
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (dx === 0 && dy === 0) continue;
            const ny = y + dy, nx = x + dx;
            if (ny >= 0 && ny < this.height && nx >= 0 && nx < this.width) {
              if (this.grid[ny][nx] === 0 || this.grid[ny][nx] === 2) {
                this.grid[y][x] = 1; // wall
              }
            }
          }
        }
      }
    }
  }

  // Place special rooms (loot room, boss room, spawn, exit)
  findFurthestRoom(rooms, from) {
    let best = null, bestDist = -1;
    for (const r of rooms) {
      const d = Math.hypot(r.cx - from.cx, r.cy - from.cy);
      if (d > bestDist) { bestDist = d; best = r; }
    }
    return best;
  }
}

class BSPNode {
  constructor(x, y, w, h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    this.left = null; this.right = null;
    this.room = null;
  }
}
```

---

## Tile Legend

| Value | Name | Description |
|-------|------|-------------|
| 0 | Floor | Walkable room floor |
| 1 | Wall | Impassable, blocks LOS |
| 2 | Corridor | Walkable passageway |
| 3 | Door | Opening between room and corridor (optional) |

---

## Usage Example

```javascript
const dg = new DungeonGenerator({
  width: 50,
  height: 35,
  minRoomSize: 4,
  maxRoomSize: 10,
  minLeafSize: 8,
  maxDepth: 4,
});

const result = dg.generate();
dg.addRoomWalls();

// result.grid is a 2D array ready for your game
// result.rooms contains all room rects with centers

// Find spawn point (first room center)
const spawn = result.rooms[0];
const playerSpawn = { x: spawn.cx, y: spawn.cy };

// Find exit (room furthest from spawn)
const exitRoom = dg.findFurthestRoom(result.rooms, spawn);
const exitPoint = { x: exitRoom.cx, y: exitRoom.cy };
```

---

## Converting to In-Game Coordinates

```
tileX * tileWidth  + tileWidth/2  → pixel center X
tileY * tileHeight + tileHeight/2 → pixel center Y
```

---

## Variations

### Cellular Automata (Caves)
For organic cave-like maps instead of rooms:

```javascript
function generateCave(width, height, fillChance = 0.45, steps = 4) {
  let grid = Array.from({length: height}, () =>
    Array.from({length: width}, () => Math.random() < fillChance ? 1 : 0)
  );
  
  for (let step = 0; step < steps; step++) {
    const newGrid = grid.map(row => [...row]);
    for (let y = 1; y < height-1; y++)
      for (let x = 1; x < width-1; x++) {
        const walls = countWallNeighbors(grid, x, y);
        newGrid[y][x] = (walls >= 5 || (grid[y][x] === 1 && walls >= 4)) ? 1 : 0;
      }
    grid = newGrid;
  }
  return grid;
}
```

### Drunkard's Walk (Tunnels)
For winding tunnel-like maps:

```javascript
function drunkardWalk(width, height, steps = 500) {
  const grid = Array.from({length: height}, () => Array(width).fill(1));
  let x = Math.floor(width/2), y = Math.floor(height/2);
  grid[y][x] = 0;
  for (let i = 0; i < steps; i++) {
    const dir = Math.floor(Math.random() * 4);
    if (dir === 0) x = Math.min(width-1, x+1);
    else if (dir === 1) x = Math.max(0, x-1);
    else if (dir === 2) y = Math.min(height-1, y+1);
    else y = Math.max(0, y-1);
    grid[y][x] = 0;
  }
  return grid;
}
```

---

## Integration Tips

1. **Enemy spawning**: Place enemies 1-3 tiles inside rooms, away from doors
2. **Loot placement**: Put high-value loot in deepest rooms
3. **Key/door system**: Place locked doors at corridor chokepoints
4. **Minimap**: Render grid as colored cells for a simple minimap
5. **Guarantee connectivity**: Always BFS-verify all floor tiles are reachable; re-run if disconnected
