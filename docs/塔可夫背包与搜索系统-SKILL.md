# 塔可夫风格背包与搜索系统

> Immersive grid-based inventory and container search system.
> 核心：网格背包、物品旋转、容器搜索进度、拖拽转移、装备面板。

---

## 一、网格背包系统

### 1.1 格子定义

背包是一个固定宽高的网格，每个物品占据 `w×h` 格。

```javascript
// 背包尺寸
const BACKPACK_SIZES = {
  pockets:   { w: 2, h: 2, name: '口袋' },      // 基础（默认）
  small:     { w: 4, h: 3, name: '小背包' },
  medium:    { w: 5, h: 4, name: '中型背包' },
  large:     { w: 6, h: 5, name: '大型背包' },
  assault:   { w: 6, h: 7, name: '突击背包' },
};

// 物品尺寸定义
const ITEM_SIZES = {
  bullet:     { w: 1, h: 1 },
  medkit:     { w: 1, h: 1 },
  key:        { w: 1, h: 1 },
  junk_small: { w: 1, h: 1 },
  pistol:     { w: 1, h: 2 },
  smg:        { w: 1, h: 3 },
  magazine:   { w: 1, h: 2 },
  junk_medium:{ w: 1, h: 2 },
  grenade:    { w: 1, h: 2 },
  armor:      { w: 2, h: 2 },
  helmet:     { w: 2, h: 2 },
  rig:        { w: 2, h: 2 },
  backpack:   { w: 2, h: 2 },
  junk_large: { w: 2, h: 2 },
  rifle:      { w: 1, h: 4 },
  shotgun:    { w: 1, h: 4 },
  sniper:     { w: 1, h: 5 },
  loot_epic:  { w: 2, h: 2 },
  loot_legend:{ w: 2, h: 2 },
};
```

### 1.2 网格背包类

```javascript
class GridInventory {
  constructor(width, height) {
    this.width = width;
    this.height = height;
    this.grid = Array.from({length: height}, () => Array(width).fill(null));
    this.items = [];
  }

  canPlace(itemW, itemH, x, y, rotated = false) {
    const w = rotated ? itemH : itemW;
    const h = rotated ? itemW : itemH;
    if (x + w > this.width || y + h > this.height) return false;
    for (let row = y; row < y + h; row++) {
      for (let col = x; col < x + w; col++) {
        if (this.grid[row][col] !== null) return false;
      }
    }
    return true;
  }

  findSpace(itemW, itemH, rotated = false) {
    const w = rotated ? itemH : itemW;
    const h = rotated ? itemW : itemH;
    for (let y = 0; y <= this.height - h; y++) {
      for (let x = 0; x <= this.width - w; x++) {
        if (this.canPlace(w, h, x, y, false)) return { x, y, rotated };
      }
    }
    return null;
  }

  placeItem(item, x, y, rotated = false) {
    const w = rotated ? item.h : item.w;
    const h = rotated ? item.w : item.h;
    if (!this.canPlace(w, h, x, y)) return false;
    const entry = { ...item, x, y, rotated };
    this.items.push(entry);
    for (let row = y; row < y + h; row++) {
      for (let col = x; col < x + w; col++) {
        this.grid[row][col] = entry;
      }
    }
    return true;
  }

  removeItem(itemId) {
    const idx = this.items.findIndex(i => i.id === itemId);
    if (idx === -1) return null;
    const item = this.items[idx];
    const w = item.rotated ? item.h : item.w;
    const h = item.rotated ? item.w : item.h;
    for (let row = item.y; row < item.y + h; row++) {
      for (let col = item.x; col < item.x + w; col++) {
        this.grid[row][col] = null;
      }
    }
    this.items.splice(idx, 1);
    return item;
  }

  rotate(itemId) {
    const item = this.items.find(i => i.id === itemId);
    if (!item) return false;
    const removed = this.removeItem(itemId);
    if (!removed) return false;
    const newW = removed.rotated ? removed.h : removed.w;
    const newH = removed.rotated ? removed.w : removed.h;
    if (this.canPlace(newW, newH, removed.x, removed.y, !removed.rotated)) {
      this.placeItem(removed, removed.x, removed.y, !removed.rotated);
      return true;
    }
    this.placeItem(removed, removed.x, removed.y, removed.rotated);
    return false;
  }
}
```

---

## 二、搜索系统

### 2.1 搜索流程

```
靠近容器/尸体 → 按 E → 搜索进度条（1~3秒）
    ↓
打开搜索面板
┌──────────────────────────────┐
│  容器内容物 (grid)            │
│  ┌──┬──┬──┬──┬──┐           │
│  │🔫│  │  │  │  │           │
│  ├──┼──┼──┼──┼──┤           │
│  │  │💎│  │  │  │           │
│  ├──┼──┼──┼──┼──┤           │
│  │  │  │🩹│  │  │           │
│  └──┴──┴──┴──┴──┘           │
│                              │
│  你的背包 (grid)              │
│  ┌──┬──┬──┬──┐              │
│  │🔑│  │  │  │              │
│  ├──┼──┼──┼──┤              │
│  │  │🧻│🧻│  │              │
│  ├──┼──┼──┼──┤              │
│  │  │  │  │  │              │
│  └──┴──┴──┴──┘              │
│                              │
│  [点击物品转移] 按 Esc 关闭   │
└──────────────────────────────┘
```

### 2.2 搜索实现

```javascript
class SearchSystem {
  constructor(playerInv) {
    this.playerInv = playerInv;
    this.containerInv = null;
    this.isOpen = false;
    this.isSearching = false;
    this.searchProgress = 0;
    this.searchDuration = 0;
    this.currentContainer = null;
    this.onFinish = null;
  }

  startSearch(container) {
    if (this.isSearching) return;
    this.isSearching = true;
    this.searchProgress = 0;
    this.currentContainer = container;
    const itemCount = container.contents?.length || 3;
    this.searchDuration = 60 + itemCount * 15;
  }

  updateSearch() {
    if (!this.isSearching) return false;
    this.searchProgress++;
    if (this.searchProgress >= this.searchDuration) {
      this.finishSearch();
      return true;
    }
    return false;
  }

  finishSearch() {
    this.isSearching = false;
    this.containerInv = this.buildContainerGrid(this.currentContainer);
    this.isOpen = true;
    if (this.onFinish) this.onFinish(this.currentContainer);
  }

  takeItem(itemId) {
    if (!this.containerInv) return false;
    const item = this.containerInv.removeItem(itemId);
    if (!item) return false;
    const space = this.playerInv.findSpace(item.w, item.h);
    if (space) {
      this.playerInv.placeItem(item, space.x, space.y);
      return true;
    }
    this.containerInv.placeItem(item, item.x, item.y, item.rotated);
    return false;
  }

  putItem(itemId) {
    if (!this.containerInv) return false;
    const item = this.playerInv.removeItem(itemId);
    if (!item) return false;
    const space = this.containerInv.findSpace(item.w, item.h);
    if (space) {
      this.containerInv.placeItem(item, space.x, space.y);
      return true;
    }
    this.playerInv.placeItem(item, item.x, item.y, item.rotated);
    return false;
  }

  buildContainerGrid(container) {
    const inv = new GridInventory(5, 4);
    if (container.contents) {
      for (const item of container.contents) {
        const space = inv.findSpace(item.w, item.h);
        if (space) inv.placeItem(item, space.x, space.y);
      }
    }
    return inv;
  }

  close() {
    this.isOpen = false;
    this.containerInv = null;
    this.currentContainer = null;
  }
}
```

---

## 三、UI 渲染

### 3.1 网格渲染

```javascript
function renderGrid(ctx, inv, offsetX, offsetY, cellSize, label) {
  const padding = 4;
  const totalW = inv.width * cellSize + padding * 2;
  const totalH = inv.height * cellSize + padding * 2;

  ctx.fillStyle = 'rgba(0,0,0,0.8)';
  ctx.strokeStyle = '#555';
  ctx.lineWidth = 1;
  ctx.strokeRect(offsetX, offsetY, totalW, totalH);
  ctx.fillRect(offsetX, offsetY, totalW, totalH);

  ctx.fillStyle = '#aaa';
  ctx.font = '11px Arial';
  ctx.textAlign = 'left';
  ctx.fillText(label, offsetX + padding, offsetY + padding + 10);

  const gridX = offsetX + padding;
  const gridY = offsetY + padding + 16;
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 0.5;
  for (let x = 0; x <= inv.width; x++) {
    ctx.beginPath();
    ctx.moveTo(gridX + x * cellSize, gridY);
    ctx.lineTo(gridX + x * cellSize, gridY + inv.height * cellSize);
    ctx.stroke();
  }
  for (let y = 0; y <= inv.height; y++) {
    ctx.beginPath();
    ctx.moveTo(gridX, gridY + y * cellSize);
    ctx.lineTo(gridX + inv.width * cellSize, gridY + y * cellSize);
    ctx.stroke();
  }

  for (const item of inv.items) {
    const w = item.rotated ? item.h * cellSize : item.w * cellSize;
    const h = item.rotated ? item.w * cellSize : item.h * cellSize;
    const ix = gridX + item.x * cellSize;
    const iy = gridY + item.y * cellSize;

    ctx.fillStyle = 'rgba(50,50,70,0.9)';
    ctx.fillRect(ix + 1, iy + 1, w - 2, h - 2);
    ctx.strokeStyle = '#666';
    ctx.lineWidth = 1;
    ctx.strokeRect(ix + 1, iy + 1, w - 2, h - 2);

    if (item.rarity >= 4) {
      ctx.strokeStyle = '#a855f7';
      ctx.lineWidth = 2;
      ctx.strokeRect(ix + 1, iy + 1, w - 2, h - 2);
    }
    if (item.rarity >= 5) {
      ctx.strokeStyle = '#ffd700';
      ctx.shadowColor = '#ffd700';
      ctx.shadowBlur = 6;
      ctx.strokeRect(ix + 1, iy + 1, w - 2, h - 2);
      ctx.shadowBlur = 0;
    }

    ctx.fillStyle = '#fff';
    ctx.font = `${Math.min(cellSize * 0.6, 20)}px Arial`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(item.icon || '📦', ix + w/2, iy + h/2);

    if (cellSize >= 28) {
      ctx.fillStyle = '#aaa';
      ctx.font = '9px Arial';
      ctx.textBaseline = 'bottom';
      ctx.textAlign = 'left';
      ctx.fillText(item.name, ix + 3, iy + h - 2);
    }
  }
}
```

### 3.2 搜索进度条

```javascript
function renderSearchProgress(ctx, progress, total) {
  const barW = 300, barH = 20;
  const x = (800 - barW) / 2;
  const y = 400;

  ctx.fillStyle = 'rgba(0,0,0,0.8)';
  ctx.fillRect(x - 10, y - 30, barW + 20, barH + 40);

  ctx.fillStyle = '#444';
  ctx.fillRect(x, y, barW, barH);

  const pct = Math.min(progress / total, 1);
  ctx.fillStyle = pct < 0.5 ? '#f39c12' : pct < 0.8 ? '#4ecca3' : '#ffd700';
  ctx.fillRect(x, y, barW * pct, barH);

  ctx.strokeStyle = '#666';
  ctx.lineWidth = 1;
  ctx.strokeRect(x, y, barW, barH);

  ctx.fillStyle = '#fff';
  ctx.font = '14px Arial';
  ctx.textAlign = 'center';
  ctx.fillText(`搜索中... ${Math.floor(pct * 100)}%`, 400, y - 10);
}
```

---

## 四、与游戏主循环集成

```javascript
function update() {
  if (searchSystem.isSearching) {
    const done = searchSystem.updateSearch();
    if (done) {
      document.getElementById('lootPanel').style.display = 'block';
    }
  }

  if (keys['e'] && !searchSystem.isOpen && !searchSystem.isSearching) {
    const target = findNearestContainer(player);
    if (target) {
      searchSystem.startSearch(target);
    }
    else if (game.nearExtract) {
      victoryFunc();
    }
  }

  if (keys['escape'] && searchSystem.isOpen) {
    searchSystem.close();
    document.getElementById('lootPanel').style.display = 'none';
  }
}
```

---

## 五、初始化

```javascript
// 玩家初始背包（口袋大小）
const playerInv = new GridInventory(2, 2);

// 更换更大背包
function equipBackpack(bpItem) {
  const size = BACKPACK_SIZES[bpItem.sizeKey] || BACKPACK_SIZES.medium;
  const newInv = new GridInventory(size.w, size.h);
  for (const item of playerInv.items) {
    const space = newInv.findSpace(item.w, item.h);
    if (space) newInv.placeItem(item, space.x, space.y);
  }
  Object.assign(playerInv, newInv);
}

// 搜索系统
const searchSystem = new SearchSystem(playerInv);
```
