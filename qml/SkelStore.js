// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelStore —— 我们自己的存档（"我选的是哪张骨骼皮肤"）
//
// 为什么不写 Config.enabledSkins：那是官方皮肤注册表，写进去官方就会去解析、
// 去渲染它 —— 而官方那条路画不了重骨架（冰魄映雪实测必崩）。
// 所以我们自己建表，存在客户端自己的库里（client.db），按本机账号分，
// 天然"每人独立"。

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

var TABLE = "fk_skel_mine"

function ensure(Cpp) {
  Cpp = Cpp || cppObj()
  if (!Cpp) return
  try {
    Cpp.sqlquery("CREATE TABLE IF NOT EXISTS " + TABLE + " ("
      + "owner TEXT, general TEXT, skin TEXT, PRIMARY KEY(owner, general))")
  } catch (e) { /* 已存在或库不可写，读写时再兜 */ }
}

/// 本机账号标识（换机器/换账号就是另一份，互不影响）
function owner(Cpp) {
  Cpp = Cpp || cppObj()
  if (!Cpp) return "default"
  try {
    if (Cpp.self && Cpp.self.screenName) return "" + Cpp.self.screenName
  } catch (e) { /* 没有就用默认 */ }
  return "default"
}

/// 读：这个武将选的是哪张（没选过就返回空串）
function get(Cpp, general) {
  if (!general) return ""
  Cpp = Cpp || cppObj()
  if (!Cpp) return ""
  try {
    ensure(Cpp)
    var rows = Cpp.sqlquery("SELECT skin FROM " + TABLE + " WHERE owner='"
      + owner(Cpp) + "' AND general='" + general + "'")
    if (rows && rows.length > 0 && rows[0] && rows[0].skin) return "" + rows[0].skin
  } catch (e) {
    console.warn("[fk-skel] 读存档失败: " + e)
  }
  return ""
}

/// 写：skin 传空串 = 清掉（回到不用骨骼皮肤）
function set(Cpp, general, skin) {
  if (!general) return
  Cpp = Cpp || cppObj()
  if (!Cpp) return
  try {
    ensure(Cpp)
    var o = owner(Cpp)
    if (!skin) {
      Cpp.sqlquery("DELETE FROM " + TABLE + " WHERE owner='" + o
        + "' AND general='" + general + "'")
    } else {
      Cpp.sqlquery("REPLACE INTO " + TABLE + " (owner, general, skin) VALUES ('"
        + o + "','" + general + "','" + skin + "')")
    }
    console.warn("[fk-skel] 存档 " + general + " -> " + (skin || "（清空）"))
  } catch (e) {
    console.warn("[fk-skel] 写存档失败: " + e)
  }
}

/// 清单：从 Lua 那边取（init.lua 扫 skins/ 得到的纯数据）
///
/// ⚠ 两种取法都试：`Fk.skel_skins`（挂在 Fk 上，最稳）和全局函数 `SkelSkinList()`。
///   扩展的 Lua 有可能跑在沙箱里 —— 那种情况下全局函数在 Lua.ev 里不存在，
///   只试一种就会"清单为空 → 整个包静默失效" ✗
function skins() {
  var L = luaObj()
  if (!L) {
    console.warn("[fk-skel] 拿不到 Lua 对象，清单读不了 —— "
      + "检查 SkelHost/SkelPicker 有没有调用 Store.init(Cpp, Lua)")
    return []
  }
  var tryExprs = [
    "Fk and Fk.skel_skins or nil",
    "(SkelSkinList and SkelSkinList()) or nil",
  ]
  for (var i = 0; i < tryExprs.length; i++) {
    try {
      var v = L.ev(tryExprs[i])
      if (v && v.length !== undefined && v.length > 0) return v
    } catch (e) {
      console.warn("[fk-skel] 清单读取失败(" + tryExprs[i] + "): " + e)
    }
  }
  console.warn("[fk-skel] 清单为空 —— 两种取法都没拿到。检查 init.lua 是否加载成功")
  return []
}

/// 某个武将可用哪些（generals 里含该武将）
///
/// ⚠ 匹配规则要**宽松**：场上读到的 id 常常是变体 ——
///   `ty_heg__lvlingqi` / `os_thoroughbred__zhangliao` / `mobile__qinghegongzhu` …
///   它们**都包含基础名**（实测配置里 8 个变体全符合这个规律）。
///   清单里的 generals 在 postLoad 阶段已用 Fk.same_generals 展开过；这里再加一层
///   "包含"匹配兜底，这样即使展开因为时机没生效，也仍然认得出来 ✓
function skinsForGeneral(general) {
  var all = skins()
  var out = []
  if (!general) return all
  var g = "" + general
  for (var i = 0; i < all.length; i++) {
    var gs = all[i].generals || []
    var hit = false
    for (var j = 0; j < gs.length; j++) {
      var base = "" + gs[j]
      if (base === g || (base.length >= 4 && g.indexOf(base) >= 0)) { hit = true; break }
    }
    if (hit) out.push(all[i])
  }
  return out
}

/// 按 key 找定义
function byKey(key) {
  var all = skins()
  for (var i = 0; i < all.length; i++) {
    if ("" + all[i].key === "" + key) return all[i]
  }
  return null
}

// ---------------------------------------------------------------------------
// 二期：取景微调（每人独立，存在本机库里 —— 和清单里的默认值分开）
//
// 语义照抄当时钩子里的做法：**mul 相乘、dx/dy 相加**。
// 这样清单里的默认值（比如冰魄映雪 scale 0.35 那套推导）仍然是基准，
// 微调只是叠在它上面，随时可以清掉回到默认 ✓
// ---------------------------------------------------------------------------

var TUNE_TABLE = "fk_skel_tune"

function tuneEnsure(Cpp) {
  Cpp = Cpp || cppObj()
  if (!Cpp) return
  try {
    Cpp.sqlquery("CREATE TABLE IF NOT EXISTS " + TUNE_TABLE + " ("
      + "owner TEXT, skin TEXT, mul TEXT, dx TEXT, dy TEXT, PRIMARY KEY(owner, skin))")
  } catch (e) { /* 已存在/不可写，读写时再兜 */ }
}

/// 读微调；没存过返回 null（调用方就用清单里的默认值）
function tuneGet(Cpp, skinKey) {
  if (!skinKey) return null
  Cpp = Cpp || cppObj()
  if (!Cpp) return null
  try {
    tuneEnsure(Cpp)
    var rows = Cpp.sqlquery("SELECT mul, dx, dy FROM " + TUNE_TABLE + " WHERE owner='"
      + owner(Cpp) + "' AND skin='" + skinKey + "'")
    if (rows && rows.length > 0 && rows[0]) {
      var r = rows[0]
      return {
        mul: (r.mul === "" || r.mul === null) ? null : (1 * r.mul),
        dx: (r.dx === "" || r.dx === null) ? null : (1 * r.dx),
        dy: (r.dy === "" || r.dy === null) ? null : (1 * r.dy),
      }
    }
  } catch (e) {
    console.warn("[fk-skel] 读取景微调失败: " + e)
  }
  return null
}

/// 写微调；传 null 表示这一项回到清单默认
function tuneSet(Cpp, skinKey, mul, dx, dy) {
  if (!skinKey) return
  Cpp = Cpp || cppObj()
  if (!Cpp) return
  try {
    tuneEnsure(Cpp)
    var o = owner(Cpp)
    var f = function (v) { return (v === null || v === undefined) ? "" : ("" + v) }
    Cpp.sqlquery("REPLACE INTO " + TUNE_TABLE + " (owner, skin, mul, dx, dy) VALUES ('"
      + o + "','" + skinKey + "','" + f(mul) + "','" + f(dx) + "','" + f(dy) + "')")
    console.warn("[fk-skel] 取景微调 " + skinKey + " -> mul=" + f(mul)
      + " dx=" + f(dx) + " dy=" + f(dy))
  } catch (e) {
    console.warn("[fk-skel] 写取景微调失败: " + e)
  }
}
