// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelProbe —— **只读**探测：我自己是谁、我的头像在哪、可见窗口多大
//
// 原则：只用官方现成的 API 读，绝不修改官方任何对象。
//   * 自己是谁：Lua 的 Self.id（退回 Cpp.self.id）
//   * 我的头像：room.photoModel + room.getPhoto(id)（官方 Room 自带的接口）
//   * 可见窗口：头像对象上的 photoMask（官方遮罩，就是头像看到的那个框）
// 这些都是"读"，出问题最多是读不到，不会把游戏弄崩。

.pragma library

// ⚠ `.pragma library` 的 JS 里，QML 上下文的全局对象（Cpp/Lua/Config）**不一定可见** ——
//   备份里当时能用的那份老代码，是把它们当**参数**传进来的，从不直接引用 ✗
//   所以这里也照做：由 QML 侧调用 init(Cpp, Lua) 注入；同时保留带 typeof 守卫的
//   全局兜底，两条路任一可用就行（任一不可用也不会抛 ReferenceError）。
var ENV = { cpp: null, lua: null }

function init(cpp, lua) {
  ENV.cpp = cpp || null
  ENV.lua = lua || null
}

function luaObj() {
  if (ENV.lua) return ENV.lua
  try { if (typeof Lua !== "undefined" && Lua) return Lua } catch (e) { /* 没有就算了 */ }
  return null
}

function cppObj() {
  if (ENV.cpp) return ENV.cpp
  try { if (typeof Cpp !== "undefined" && Cpp) return Cpp } catch (e) { /* 没有就算了 */ }
  return null
}

function selfId() {
  var L = luaObj()
  try {
    var v = L ? L.ev("Self and Self.id or nil") : null
    if (typeof v === "number") return v
  } catch (e) { /* 下面再试 */ }
  try {
    var C = cppObj()
    if (C && C.self && typeof C.self.id === "number") return C.self.id
  } catch (e) { /* 拿不到就 -1 */ }
  return -1
}

/// 我的头像对象（找不到返回 null）
function myPhoto(room) {
  if (!room || !room.getPhoto) return null
  var id = selfId()
  if (id < 0) return null
  try {
    return room.getPhoto(id)
  } catch (e) {
    return null
  }
}

/// 头像当前显示的是哪个武将 / 哪张皮肤（读模型，不猜）
function myGeneral(room) {
  var p = myPhoto(room)
  if (!p) return ""
  try { return "" + (p.general || "") } catch (e) { return "" }
}

/// 可见窗口：向上找 photoMask，拿到它在 photo 坐标系里的中心与尺寸
function windowOf(photo) {
  var node = photo
  for (var d = 0; d < 8 && node; d++) {
    var mask = null
    try { mask = node.photoMask } catch (e) { mask = null }
    if (mask && mask.width > 0 && mask.height > 0) {
      try {
        var c = mask.mapToItem(photo, mask.width / 2, mask.height / 2)
        return { found: true, cx: c.x, cy: c.y, w: mask.width, h: mask.height }
      } catch (e) { break }
    }
    node = node.parent
  }
  // 找不到就退回头像自身（至少不会画到莫名其妙的地方）
  try {
    return { found: false, cx: photo.width / 2, cy: photo.height / 2,
             w: photo.width, h: photo.height }
  } catch (e) {
    return null
  }
}

/// 某个玩家的武将 id（只读房间的 photo ✓，不碰任何东西）
function generalOf(room, pid) {
  if (!room || !room.getPhoto || pid === undefined || pid === null) return ""
  try {
    var p = room.getPhoto(pid)
    return p ? ("" + (p.general || "")) : ""
  } catch (e) {
    return ""
  }
}

/// 把一个取自 `photo` 的矩形，用 **photo→base 的仿射变换**搬到 base 坐标系。
///
/// ⚠ 绝不能手算 `photo.x + 局部坐标 × photo.scale` ✗：
///   多人局里 photo 会被缩放，而且它上面可能还有别的变换层。
///   用"局部原点 + 两个基向量"来映射 —— 正好是 mapToItem 的语义 ✓
///
///   rect = { cx, cy, w, h }（photo 局部坐标系里的矩形）
///   返回 { x, y, w, h }（base 坐标系，左上角 + 尺寸）
function mapRect(photo, base, rect) {
  if (!photo || !base || !rect) return null
  if (!(rect.w > 0) || !(rect.h > 0)) return null
  try {
    var ox = rect.cx - rect.w / 2
    var oy = rect.cy - rect.h / 2
    var p0 = photo.mapToItem(base, ox, oy)
    var px = photo.mapToItem(base, ox + rect.w, oy)
    var py = photo.mapToItem(base, ox, oy + rect.h)
    // 用基向量的分量差当尺寸（支持等比缩放；带旋转时理论上不会有，下面兜一下）
    var w = px.x - p0.x, h = py.y - p0.y
    if (w < 0) w = -w
    if (h < 0) h = -h
    return { x: p0.x, y: p0.y, w: w, h: h }
  } catch (e) {
    return null
  }
}

/// 「需要保护、不能被皮肤盖住」的区域，映射到 base 坐标系。
///
/// 为什么需要它：这些区域长在立绘窗口内部（装备区 y 91~171、
/// 图标标记从牌底往上 21px），而我们的皮肤层是房间级兄弟节点、
/// 永远画在武将牌之上 → 不处理就必然盖住它们。
///
/// 只读 Photo 上的官方别名 ✓（`Photo.qml:33-35` 导出）：
///   areasSealed → EquipArea      picMarkArea → PicMarkArea
///   markArea    → MarkArea       （默认不用，它会向上长、高度随内容变）
///
/// ⚠ 区域**没有内容时也照样返回矩形** —— 调用方拿它"垫一块底"，
///   所以"有没有内容"不影响返回值，遮罩因此可以保持静态、不必重算 ✓
function protectRects(room, base, names) {
  var p = myPhoto(room)
  if (!p) return null
  if (!base) base = room
  if (!names || !names.length) names = ["areaSealed", "picMarkArea"]

  var out = []
  for (var i = 0; i < names.length; i++) {
    var node = null
    try { node = p[names[i]] } catch (e) { node = null }
    if (!node) {
      out.push({ ok: false, name: names[i], x: 0, y: 0, w: 0, h: 0 })
      continue
    }
    var r = null
    try {
      r = mapRect(p, base, {
        cx: node.x + node.width / 2,
        cy: node.y + node.height / 2,
        w: node.width,
        h: node.height,
      })
    } catch (e) { r = null }
    if (!r) {
      out.push({ ok: false, name: names[i], x: 0, y: 0, w: 0, h: 0 })
    } else {
      out.push({ ok: true, name: names[i], x: r.x, y: r.y, w: r.w, h: r.h })
    }
  }
  return out
}

/// 取一个 QML 对象的**构造名**（如 `TargetTip_QMLTYPE_123`）。
///   ⚠ QML 的 `toString()` 给的是这个，不是纯净的类名；
///   用它做匹配时要用 `indexOf` + 边界判断，别做 == 比较 ✗
function typeName(o) {
  if (!o) return ""
  try { return "" + (o.toString ? o.toString() : "") } catch (e) { return "" }
}

/// `name` 是否作为**独立词**出现在类型名里（避免 "MarkArea" 命中 "PicMarkArea"）✗
function typeHas(o, name) {
  var s = typeName(o)
  if (!s) return false
  var i = s.indexOf(name)
  if (i < 0) return false
  var before = i === 0 ? "" : s.charAt(i - 1)
  var after = s.charAt(i + name.length)
  // 前面不能是字母（`PicMarkArea` 里 `MarkArea` 前是 'c' → 拒绝 ✓）
  var okBefore = !/[A-Za-z]/.test(before)
  var okAfter = (after === "" || after === "_")
  return okBefore && okAfter
}

/// 找武将牌上的**会被皮肤盖住的显示层**（只读；找不到的字段为 null）。
///
/// 为什么要它：这些层和立绘在同一个子树里、都是 z=0，
/// 而我们的皮肤层是房间的兄弟 → **没有夹层**可用 ✗
/// 所以只能把它们搬到皮肤上面去（见 SkelHost 的 adoptMarks）。
///
/// 识别方式（越靠前越稳）：
///   * `markArea` / `picMarkArea` → Photo 公开别名（`Photo.qml:34-35`），再兜底形状
///   * `equipArea`  → ★ **没有别名**：按**独有属性**认
///     （`EquipArea.qml:23/28/30` 的 `itemHeight`/`items`/`subtypes` 三件套 ✓）
///   * `specialArea` → 按独有成员认（有 `updatePileInfo` **和** `specialContainer`）
///   * `saveme` / `restIndicator` → 按构造名认（它们没有可靠的特征属性）
///
/// ⚠ `markArea` 这个名字在 Photo 上**同时是一个函数**
///   （`Photo.qml:448 handleMarkAreaUpdate`），取到的可能是函数 →
///   所以必须判 `width` 存不存在 ✓
function markNodes(photo) {
  if (!photo) return null
  var out = {
    markArea: null, picMarkArea: null, equipArea: null,
    specialArea: null, saveme: null, restIndicator: null,
  }

  function usable(o) {
    if (!o) return false
    try { return (typeof o.width === "number" && typeof o.height === "number") }
    catch (e) { return false }
  }

  var props = [["markArea", "markArea"], ["picMarkArea", "picMarkArea"]]
  for (var i = 0; i < props.length; i++) {
    var v = null
    try { v = photo[props[i][0]] } catch (e) { v = null }
    if (usable(v)) out[props[i][1]] = v
  }

  // 翻直接子对象
  var kids = []
  try { kids = photo.children || [] } catch (e) { kids = [] }

  // 「求桃/阵亡/投降图」的候选累加器（见下面 ④）
  var savemeCandidates = []
  var savemeBest = null      // 特征最像的
  var savemeFallback = null  // 次像的（兜底）

  for (var j = 0; j < kids.length; j++) {
    var k = kids[j]
    if (!usable(k)) continue

    // ① 装备区：独有属性三件套（最可靠）
    if (!out.equipArea) {
      try {
        if (typeof k.itemHeight === "number"
            && k.items !== undefined && k.subtypes !== undefined) {
          out.equipArea = k
        }
      } catch (e) { /* 不是它 */ }
    }

    // ② 「武将牌上的牌」区：有 updatePileInfo **且**有 specialContainer
    if (!out.specialArea) {
      try {
        if (typeof k.updatePileInfo === "function" && k.specialContainer !== undefined) {
          out.specialArea = k
        }
      } catch (e) { /* 不是它 */ }
    }

    // ③ 构造名兜底（注意边界，别让 MarkArea 命中 PicMarkArea ✗）
    if (!out.picMarkArea && typeHas(k, "PicMarkArea")) out.picMarkArea = k
    if (!out.markArea && typeHas(k, "MarkArea")) out.markArea = k
    if (!out.restIndicator && typeHas(k, "RestIndicator")) out.restIndicator = k

    // ④ 求桃 / 阵亡 / 投降图（`Photo.qml:178-194`）
    //
    //   ⚠ 它是**唯一一个没有 id 的 Image**，所以只能靠特征认 ✓
    //     第一版只用 `scale===0.75 && anchors.centerIn` → 用户实测**没命中** ✗
    //
    //   这一版用**最可靠的特征**：它的 `source` 路径由三种状态拼出来，
    //   无论哪种状态，路径里**一定**含这些片段之一：
    //       `deathDir + "surrender"` / `deathDir + "saveme"` / `getRoleDeathPic(...)`
    //   而 `SkinBank.deathDir = Cpp.path + "/image/photo/death/"`（SkinBank.qml:22）✓
    //   所以判 `source` 里有没有 `/photo/death/` 就够了 —— 这个片段只有它用 ✓
    //
    //   另外把每个 Image 候选的 `source` 尾巴也记进日志，下次一跑可核对 ✓
    if (!out.saveme) {
      var nm = typeName(k)
      if (nm.indexOf("Image") === 0) {
        var src = ""
        try { src = "" + (k.source || "") } catch (e) { src = "" }
        var hasCenterIn = false
        try { hasCenterIn = !!(k.anchors && k.anchors.centerIn) } catch (e) { hasCenterIn = false }
        var isDeathDir = (src.indexOf("/photo/death/") >= 0)
        if (savemeCandidates.length < 14) {
          savemeCandidates.push("#" + j + ":"
            + (isDeathDir ? "★" : "")
            + "src=…" + src.slice(-26)
            + " sc=" + k.scale
            + " cIn=" + (hasCenterIn ? "Y" : "N"))
        }
        if (isDeathDir && savemeBest === null) savemeBest = k
        if (hasCenterIn && k.scale === 0.75 && savemeFallback === null) savemeFallback = k
      }
    }
  }
  out.saveme = savemeBest || savemeFallback

  // ★ 兜底：**递归搜整棵子树**找那张死亡图（不再只翻直接子对象）✗
  //
  //   为什么加这条：用户实测"濒死/阵亡/投降都不出现"，
  //   而它按 `Photo.qml:178` 的缩进看**应该**是 Photo 的直接子对象。
  //   但与其继续赌层级，不如**整棵子树找一遍** ——
  //   判据仍是那个唯一可靠的片段：`source` 里含 `/photo/death/` ✓
  //   （`SkinBank.deathDir = Cpp.path + "/image/photo/death/"`，SkinBank.qml:22）
  //
  //   深度限 6 层，避免大子树遍历过慢 ✓
  if (!out.saveme) {
    var found = null
    var walk = function (node, depth) {
      if (!node || found || depth > 6) return
      var ch = []
      try { ch = node.children || [] } catch (e) { ch = [] }
      for (var q = 0; q < ch.length; q++) {
        var c = ch[q]
        if (!c) continue
        var s = ""
        try { s = "" + (c.source || "") } catch (e2) { s = "" }
        if (s.indexOf("/photo/death/") >= 0) { found = c; return }
        walk(c, depth + 1)
        if (found) return
      }
    }
    walk(photo, 0)
    out.saveme = found
  }

  out._savemeCandidates = savemeCandidates

  // ★ 无条件诊断：把子树里所有**带 source 属性**的对象列出来（前 20 个）
  //   目的：一次看清这张牌上到底有哪些图、路径各是什么 ✓
  //   —— 比"我猜它叫什么、在哪里"快得多 ✗
  var srcList = []
  var walk2 = function (node, depth) {
    if (!node || depth > 6 || srcList.length >= 20) return
    var ch = []
    try { ch = node.children || [] } catch (e) { ch = [] }
    for (var q = 0; q < ch.length; q++) {
      var c = ch[q]
      if (!c) continue
      var s = ""
      try { s = "" + (c.source || "") } catch (e2) { s = "" }
      if (s !== "") {
        var vis = true
        try { vis = (c.visible !== false) } catch (e3) { vis = true }
        srcList.push(typeName(c).split("_")[0] + (vis ? "" : "(隐)") + "=" + s.slice(-24))
      }
      walk2(c, depth + 1)
      if (srcList.length >= 20) return
    }
  }
  walk2(photo, 0)
  out._srcList = srcList
  return out
}

/// 给我自己的头像算一份"该往哪儿画"的几何（全部是 `base` 坐标系里的数字）
///
/// ⚠ `base` 必须传**我们的层实际挂着的那个父对象**。
///   以前这里固定用 `room.window.contentItem`，而层挂在 UI 页面上 ——
///   两个坐标系不一样，位置就全错（症状：层画到别处/看不见）✗
function geom(room, base) {
  var p = myPhoto(room)
  if (!p) return null
  var w = windowOf(p)
  if (!w) return null
  if (!base) {
    try { base = room.window ? room.window.contentItem : room } catch (e) { base = room }
  }
  var topLeft = null
  var center = null
  try {
    topLeft = p.mapToItem(base, 0, 0)
    center = p.mapToItem(base, w.cx, w.cy)
  } catch (e) {
    return null
  }
  if (!topLeft || !center) return null
  // 官方那条缩放公式里的"画面高"：**用窗口高 × 4**
  //   实证（老日志）：area=412x664 win=103x166 → 恰好 4 倍。
  //   刻意不用 `photo.height × 4`：万一 photo 本身就是那块大区域（664），
  //   基准会大 4 倍 → 骨架缩放错 4 倍 → 头像里只能看到骨架的一个角落 ✗
  var frameH = w.h * 4
  if (!(frameH > 0)) { frameH = 664 }
  return {
    general: myGeneral(room),
    winX: center.x - w.w / 2,
    winY: center.y - w.h / 2,
    winW: w.w,
    winH: w.h,
    photoX: topLeft.x,
    photoY: topLeft.y,
    frameH: frameH,
    found: w.found,
  }
}
