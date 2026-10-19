-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- fk-skel —— **独立的骨骼（Spine）皮肤支持**
--
-- 为什么另起一套：
--   官方那套（freekill-core 的 SkinArea/SkinMedia）是半成品 —— 显示皮肤的地方都走
--   `SkinArea` + **`OpacityMask`**，而且一次要建十几个预览格子；重骨架（冰魄映雪：
--   1MB 骨架 / 3300 顶点 mesh）走那条路必崩。所以这里完全另起：
--   **皮肤清单、资源解析、界面、存档全是我们自己的**，不调用 Fk:addSkinPackage，
--   也不依赖 Ltk.getSkeletonSkinData。
--
-- 唯一"借用"官方的一处：真正**画** Spine 的那一步。
--   Spine 的解码/绘制是核心 Qt 插件里的 C++ 类型（`import Spine` 的
--   SkeletonAnimation），QML 没法重写 —— 就像画线要用系统的图形库。
--   我们只是**直接把文件喂给它**，不经过任何皮肤注册表。
--
-- 皮肤清单：skins/<目录名>/skin.lua（我们自己的格式）

local extension = Package:new("fk-skel", Package.SpecialPack)
extension.extensionName = "fk-skel"

local SKINS_DIR = "packages/fk-skel/skins"

local UI_PACKAGE = "fk-skel-ui"

-- 对局内的宿主：页面 = 官方默认对局界面 + 我们在上面叠的一层。
-- 一个桌游同时只能选一个 UI 拓展包，所以要在 设置 → UI设置 → lunarltk 里选它。
-- 我们不去改官方那个 Room 组件，只是把**它自己**装进来再叠 —— 界面和原版一致。
Fk:addUIPackage {
  name = UI_PACKAGE,
  boardgame = "lunarltk",
  page = { url = "packages/fk-skel/qml/SkelHost.qml" },
}

Fk:loadTranslationTable {
  ["fk-skel"] = "骨骼皮肤（独立）",
  [UI_PACKAGE] = "骨骼皮肤UI（原版界面+骨骼支持）",
  ["Skel Picker"] = "骨骼皮肤换肤",
}

-- 大厅「更多」里的入口（换肤面板）
extension.customPages = {
  {
    name = "Skel Picker",
    iconUrl = "../../image/symbolic/mimetypes/image-x-generic-symbolic.svg",
    popup = true,
    qml = { url = "packages/fk-skel/qml/SkelPicker.qml" },
  },
}

--------------------------------------------------------------------------------
-- 我们自己的皮肤清单
--------------------------------------------------------------------------------
-- 扫描 skins/<目录>/skin.lua，汇总成**纯数据表**（只有字符串/数字），
-- 供 QML 通过 Lua.ev("SkelSkinList()") 取用。跨 Lua/QML 只传纯数据最稳。

--- 同名武将展开：场上的武将 id 常常是变体（ty_heg__lvlingqi / os_thoroughbred__zhangliao …），
--- 清单里只写基础 id 的话就永远认不出来 → 换肤点了没反应。
--- ⚠ 定义在**文件这一层**：postLoad 的回调里也要用它 ——
---   放进某个 block 里它就只是那个 block 的 local，回调里调用会退化成找全局 ✗
---   （老皮肤包的注释里专门警告过这个：会报 attempt to call a nil value，整个 postLoad 中断）
local function expandGenerals(gens)
  local out, seen = {}, {}
  local function add(g)
    if type(g) == "string" and g ~= "" and not seen[g] then
      seen[g] = true
      table.insert(out, g)
    end
  end
  for _, g in ipairs(gens or {}) do
    add(g)
    local same = nil
    pcall(function()
      if Fk and Fk.same_generals then same = Fk.same_generals[g] end
    end)
    if type(same) == "table" then
      for _, v in ipairs(same) do add(v) end
    end
  end
  return out
end

local function scanSkins()
  local list = {}
  -- 【一】用当时验证过的方式读目录：FileIO.ls 返回的是**名字**（不是路径），
  --       并且要 isDir/exists 双重确认。缺任何一个都要降级而不是崩。
  if type(FileIO) ~= "table" or type(FileIO.ls) ~= "function" then
    fk.qWarning("[fk-skel] 这个环境没有 FileIO.ls，读不了皮肤目录")
    return list
  end
  local ok, dirs = pcall(FileIO.ls, SKINS_DIR)
  if not ok or type(dirs) ~= "table" then
    fk.qWarning("[fk-skel] 读不到皮肤目录: " .. SKINS_DIR)
    return list
  end

  -- 【二】同名武将展开用文件这一层的 expandGenerals()（见它上面的说明）
  for _, d in ipairs(dirs) do
    d = tostring(d)
    if d ~= "." and d ~= ".." and not d:find("%.disabled$") then
      local base = SKINS_DIR .. "/" .. d
      local isDir = true
      if type(FileIO.isDir) == "function" then
        local ok2, v = pcall(FileIO.isDir, base)
        isDir = (ok2 and v) and true or false
      end
      local hasDef = true
      if type(FileIO.exists) == "function" then
        local ok3, v = pcall(FileIO.exists, base .. "/skin.lua")
        hasDef = (ok3 and v) and true or false
      end
      if isDir and hasDef then
        local path = base .. "/skin.lua"
        local ok2, def = pcall(dofile, path)
        if ok2 and type(def) == "table" then
          def.key = d
          def.generals = expandGenerals(def.generals)
          table.insert(list, def)
          fk.qInfo("[fk-skel] 清单: " .. tostring(def.name) .. "（" .. d .. "）武将 "
            .. #def.generals .. " 个")
        else
          fk.qWarning("[fk-skel] 皮肤定义读不了: " .. path .. " -> " .. tostring(def))
        end
      end
    end
  end
  return list
end

local SKINS = {}

-- ⚠⚠ 扫目录必须分**两个时点**做，这是实测出来的（两边都踩过）：
--
--   1. **加载阶段就要扫** —— 这个时点 `FileIO` 能拿到文件 ✓
--      （实测：加载阶段扫到 3 套；而放进 postLoad 后变成 **0 套** ✗，
--        日志原话：[fk-skel] 共 0 套皮肤就绪（postLoad 阶段…））
--      而且客户端侧的 QML 也需要**尽早**读到清单，所以这里立刻挂到 Fk 上 ✓
--
--   2. **postLoad 阶段只补"同名武将展开"** —— `Fk.same_generals` 要等所有武将包
--      加载完才完整 ✓（加载阶段展开会得到"武将 1 个" ✗）。
--      只补这一步，**不重新扫目录**（那时 FileIO 已经不可靠了 ✗）
--
-- QML 侧还有一层"包含匹配"兜底（见 qml/SkelStore.js skinsForGeneral），
-- 所以即使同名表拿不到，变体 id（ty_heg__lvlingqi 之类）也仍然认得出 ✓
local SKINS = scanSkins()
if type(Fk) == "table" then
  Fk.skel_skins = SKINS
end
fk.qInfo("[fk-skel] 共 " .. #SKINS .. " 套皮肤就绪（加载阶段）")

Fk:addPostLoadFunc(function()
  if type(Fk) == "table" and type(Fk.same_generals) == "table" then
    for _, def in ipairs(SKINS) do
      def.generals = expandGenerals(def.generals)
    end
    Fk.skel_skins = SKINS
    fk.qInfo("[fk-skel] postLoad 已补同名武将展开（清单 " .. #SKINS .. " 套）")
  else
    fk.qInfo("[fk-skel] postLoad：拿不到 same_generals，靠 QML 侧的包含匹配兜底")
  end
end)

--- 给 QML 用的清单（纯数据）
function SkelSkinList()
  return SKINS
end

return {
  extension,
}
