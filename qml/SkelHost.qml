// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelHost —— 对局内的宿主（UI 拓展包的页面）
//
// ⚠ 结构（改过一次，这里是最稳的那种）：
//   这一页**本身就是官方的对局界面**，我们的骨骼头像层只是它的一个子对象。
//
//   基础 UI 用**核心自带的默认对局页** `LunarLtk.Pages.Room`（不用太阳神那套
//   `lunarltk-qsgs-ui`）—— 用户明确要求"以默认 UI 为基础"。
//   它和官方 UI 包一样是模块导出的类型，直接当根类型用 ✓
//
//   为什么不写成 `Loader { source: 官方Room }`：
//     那样核心看到的"页"是一个空的 Item，官方 Room 变成页面里的一个子对象 ——
//     房间数据/布局是按"页"来给东西的，多一层间接就多一处没验证过的假设 ✗
//
//   我们**不改核心任何文件**，只是把默认对局页当基类用，再往上加自己的子对象。

import QtQuick
import Qt5Compat.GraphicalEffects

import Fk

import LunarLtk.Pages

import "SkelStore.js" as Store
import "SkelProbe.js" as Probe

Room {
  id: host

  // ⚠ 不能写成 `Store.skins()` 直接求值：宿主创建那一刻 `Lua` 还没就绪
  //   （实测日志：[fk-skel] 拿不到 Lua 对象，清单读不了 → 之后"清单 0 套皮肤"），
  //   靠每轮 refresh 里的 Store.init 才救回来。所以这里改成"由 refresh 填"。
  property var skins: []
  property string myGeneral: ""
  property string mySkinKey: ""
  property var myDef: null
  property var face: ({ mul: 1, dx: 0, dy: 0 })   // 二期：生效的取景值
  property bool ready: false
  property bool logged: false

  // ---- 遮罩 / 垫底用的几何（全部是 avatarBox 的**局部**坐标系）----
  //
  // 「要保护的区域」= 长在立绘窗口里、绝不能被皮肤盖住的东西。
  // 第一版只保护**两个位置固定**的：
  //   * areaSealed  → EquipArea     恒 103x53，位置不随内容变 ✓
  //   * picMarkArea → PicMarkArea   贴牌底、21px 高，位置不随内容变 ✓
  // 先不动 markArea / specialAreaItem：它们高度随内容变，会让遮罩需要重算 ——
  // 跑稳了再加（见 踩坑记录 第 25 条那五六轮的尸体）。
  property var patchRects: []      // 垫底矩形：盖掉这些区域的**原版立绘** ✗
  property var keepRects: []       // 遮罩保留区 = 立绘窗口 减去 patchRects
  property var protectList: ["areaSealed", "picMarkArea"]
  property bool geomLogged: false

  // ---- ★ 皮肤层的 z（唯一需要调的层序参数）----
  //
  // 用户的要求（原话）：「你用皮肤把立绘盖住，**其他图层还是什么都比皮肤那层高**就行」
  //
  // ⚠ 但"比皮肤高"这件事**不能靠给皮肤减 z 来做** ✗ —— 见下面的实测结论：
  //   * 立绘和标记在**同一个子树**里、而且都是 z=0
  //     （`MarkArea`/`PicMarkArea`/`markItem`/`photoMaskEffect` 全是 0；
  //       Photo 里能设 z 的只有 playerName(9) / 延时锦囊封印图(9) / HpBar 斜杠(-10)）
  //   * `roomArea` 自己**没有** z（Room.qml:48）
  //   * `avatarBox` 是**房间的兄弟**（另一个子树）
  //   ⇒ 它整层要么压在 `roomArea` 全部内容之上，要么沉在牌背之下，**没有夹层** ✗
  //
  //   实测确认：
  //     800 / 1 → 皮肤在最上 → **标记、装备全被盖住** ✗
  //     -1      → 沉到 `roomArea` 之下 → 被牌背(back)和立绘盖住，**皮肤看不见** ✗
  //
  //   ★ 所以现在固定 800（皮肤在最上、完整显示），
  //     而"标记要看得见"改用**路线甲**解决：把标记层搬到皮肤上面（见 markLayer）✓
  property real avatarZ: 800

  /// 取景生效值 = 清单里的默认值 **叠上**我们自己的微调
  ///   语义照抄当时钩子里的做法：mul 相乘、dx/dy 相加
  ///   （清单默认值是基准 —— 比如冰魄映雪那套 0.35 的推导 —— 微调随时可以清掉 ✓）
  // ══════════════════════════════════════════════════════════════════════
  // ★ 皮肤**形态自动切换**（如张琪瑛「九州春回」↔「九州春回2」）
  //
  //   需求（用户）：体力变化后，≤2 用形态2、>2 用形态1 ✓
  //
  //   实现要点：
  //     * `skin.lua` 里用**可选字段**声明（没写的皮肤行为完全不变 ✓）：
  //         form_group = "zqy_jiuzhou"   -- 同组 = 互为形态
  //         form_when  = "hp_le_2"       -- 本套适用的条件
  //     * **不改存档** ✓ 玩家选的仍是基础形态；生效形态按体力算
  //     * 只有生效形态真变了才重建头像层（`onSkinKeyChanged` ✓）
  //       `enterPlayed` 守卫 ⇒ 不会重播出场动画 ✓
  // ══════════════════════════════════════════════════════════════════════

  /// 我自己现在的体力（读不到就返回 null ⇒ 不切换，保持基础形态 ✓）
  ///
  /// 依据：核心 `Photo.qml:218` 就是用 `root.dataModel.hp` 拿体力的 ✓
  /// （`Probe.myPhoto()` 已经封装好"我是哪张武将牌" ✓）
  function selfHp() {
    try {
      var p = Probe.myPhoto(host)
      if (p && p.dataModel && typeof p.dataModel.hp === "number") return p.dataModel.hp
    } catch (e) { /* 进对局初期数据可能还没到 ✓ 不报错 */ }
    return null
  }

  /// 解析形如 `hp_le_2` 的条件 ✓（支持 le/lt/ge/gt/eq）
  function formMatches(cond, hp) {
    if (hp === null || hp === undefined || !cond) return false
    var m = ("" + cond).match(/^hp_(le|lt|ge|gt|eq)_(-?\d+)$/)
    if (!m) return false
    var n = parseInt(m[2], 10)
    var op = m[1]
    if (op === "le") return hp <= n
    if (op === "lt") return hp < n
    if (op === "ge") return hp >= n
    if (op === "gt") return hp > n
    return hp === n
  }

  /// 由"基础形态"和当前体力决议出**生效形态**的 key ✓
  ///   * 基础形态没写 `form_group` → 原样返回（**现有皮肤的路径完全不变** ✓）
  ///   * 同组里没有匹配的 / 体力读不到 → 也返回基础形态（安全退化 ✓）
  function resolveForm(baseKey, hp) {
    if (!baseKey) return baseKey
    var baseDef = Store.byKey(baseKey)
    if (!baseDef || !baseDef.form_group) return baseKey
    if (hp === null || hp === undefined) return baseKey
    var all = Store.skins()
    for (var i = 0; i < all.length; i++) {
      var d = all[i]
      if (("" + d.form_group) !== ("" + baseDef.form_group)) continue
      if (host.formMatches(d.form_when, hp)) {
        if (("" + d.key) !== ("" + baseKey)) {
          console.warn("[fk-skel] 形态切换：" + baseKey + " → " + d.key
            + "（体力 " + hp + " 满足 " + d.form_when + "）✓")
        }
        return d.key
      }
    }
    return baseKey
  }

  function faceOf(def, skinKey) {
    var mul = (def && def.face_mul !== undefined) ? (1 * def.face_mul) : 1
    var dx = (def && def.face_dx !== undefined) ? (1 * def.face_dx) : 0
    var dy = (def && def.face_dy !== undefined) ? (1 * def.face_dy) : 0
    var t = Store.tuneGet(Cpp, skinKey)
    if (t) {
      if (t.mul !== null && t.mul !== undefined) mul = mul * t.mul
      if (t.dx !== null && t.dx !== undefined) dx = dx + t.dx
      if (t.dy !== null && t.dy !== undefined) dy = dy + t.dy
    }
    return { mul: mul, dx: dx, dy: dy }
  }

  /// 只往"真的变了"时赋值 —— 避免每 400ms 触发 QML 重排 / layer.effect 重算
  function setIfChanged(prop, val) {
    var cur = host[prop]
    if (!cur || cur.length !== val.length) { host[prop] = val; return true }
    for (var i = 0; i < val.length; i++) {
      var a = val[i], b = cur[i]
      if (Math.abs((a.x || 0) - (b.x || 0)) > 0.5
          || Math.abs((a.y || 0) - (b.y || 0)) > 0.5
          || Math.abs((a.w || 0) - (b.w || 0)) > 0.5
          || Math.abs((a.h || 0) - (b.h || 0)) > 0.5) {
        host[prop] = val
        return true
      }
    }
    return false
  }

  /// 算「垫底矩形」与「遮罩保留区」。
  ///
  /// 遮罩用**矩形拼块**而不是"挖洞"：
  ///   OpacityMask 的语义是「maskSource 的不透明处**保留**内容」✓
  ///   → 所以保留区 = 立绘窗口 **减去** padding 矩形。
  ///   拼块法把"窗宽 x 局部高度"的整条都保留，只跳过 patch 覆盖的那几条 ——
  ///   比"整块大矩形挖小洞"少一种不确定性 ✓
  ///
  /// ⚠ 全部算在 avatarBox 的**局部**坐标系里（遮罩的坐标空间就是它）✓
  function computePatchGeom() {
    var box = { x: avatarBox.x, y: avatarBox.y, w: avatarBox.width, h: avatarBox.height }
    if (!(box.w > 0) || !(box.h > 0)) return
    var rs = null
    try { rs = Probe.protectRects(host, host, host.protectList) } catch (e) { rs = null }
    if (!rs) return

    // 场景坐标 → avatarBox 局部坐标；去掉太小的（<2px 不值得挖）
    var raw = []
    for (var i = 0; i < rs.length; i++) {
      var r = rs[i]
      if (!r || !r.ok) continue
      var x = r.x - box.x, y = r.y - box.y
      if (r.w < 2 || r.h < 2) continue
      raw.push({ x: x, y: y, w: r.w, h: r.h })
    }

    // ---- 保留区：沿 y 轴把"窗宽整条"按 patch 的上下边界切开 ----
    var ys = [0, box.h]
    for (var j = 0; j < raw.length; j++) {
      ys.push(Math.max(0, raw[j].y))
      ys.push(Math.min(box.h, raw[j].y + raw[j].h))
    }
    ys.sort(function (a, b) { return a - b })
    var keep = []
    for (var k = 0; k + 1 < ys.length; k++) {
      var y0 = ys[k], y1 = ys[k + 1]
      if (y1 - y0 < 1) continue
      var mid = (y0 + y1) / 2
      var covered = false
      for (var m = 0; m < raw.length; m++) {
        if (mid >= raw[m].y && mid <= raw[m].y + raw[m].h) { covered = true; break }
      }
      if (!covered) keep.push({ x: 0, y: y0, w: box.w, h: y1 - y0 })
    }

    var changed = host.setIfChanged("keepRects", keep)
    host.setIfChanged("patchRects", raw)

    if (changed && !host.geomLogged) {
      host.geomLogged = true
      var s1 = ""
      for (var a1 = 0; a1 < keep.length; a1++) {
        s1 += " [" + Math.round(keep[a1].x) + "," + Math.round(keep[a1].y)
          + " " + Math.round(keep[a1].w) + "x" + Math.round(keep[a1].h) + "]"
      }
      var s2 = ""
      for (var a2 = 0; a2 < raw.length; a2++) {
        s2 += " [" + Math.round(raw[a2].x) + "," + Math.round(raw[a2].y)
          + " " + Math.round(raw[a2].w) + "x" + Math.round(raw[a2].h) + "]"
      }
      console.warn("[fk-skel] 遮罩几何 窗口=" + Math.round(box.w) + "x"
        + Math.round(box.h) + " 保留区(" + keep.length + "):" + s1
        + "  垫底区(" + raw.length + "):" + s2)
    }
  }

  /// 把「要保护的区域」在**窗口坐标系**里的矩形打出来（诊断用，只打一次）。
  ///   —— 用它核对：`EquipArea` 该在 y≈114、`PicMarkArea` 该贴底；
  ///      以及它们在**牌面**里的横向范围（判断垫底块会不会盖到牌外的东西）
  function dumpProtectGeom() {
    var box = { x: avatarBox.x, y: avatarBox.y, w: avatarBox.width, h: avatarBox.height }
    if (!(box.w > 0)) return
    var rs = null
    try { rs = Probe.protectRects(host, host, host.protectList) } catch (e) { rs = null }
    if (!rs) { console.warn("[fk-skel] 保护区域探测失败"); return }
    var s = ""
    for (var i = 0; i < rs.length; i++) {
      var r = rs[i]
      var lx = r.x - box.x, ly = r.y - box.y
      s += "\n    " + r.name + (r.ok ? "" : "(×)")
        + " 窗口坐标[" + Math.round(lx) + "," + Math.round(ly)
        + " " + Math.round(r.w) + "x" + Math.round(r.h) + "]"
    }
    console.warn("[fk-skel] 保护区域明细" + s)
  }

  // ---- 我们自己的骨骼头像层 ----
  //
  // ⚠ 层位（实测过的结论 ✗）：
  //   * 这一层是**房间级的独立兄弟节点**（直接挂在页面上）✓
  //     —— 好处：坐标好算（`Probe.geom` 拿 photoMask 的几何）✓
  //   * 代价：它**整个盖在武将牌之上** ✗
  //   * 想把它改成"武将牌内、PicMarkArea 之下"试了**五六轮全部失败** ✗：
  //     插 children 中间的接口（`insertItem`/`children.insert`/`data.insert`）全不存在 ✗；
  //     靠 z 硬凑一定会夹错一边 ✗ —— 现已确证原因：
  //       武将牌内所有元素 z 都是 0，而 `avatarBox` 是房间的兄弟；
  //       Photo 里能设 z 的只有 playerName(9) / DelayedTrickArea 封印图(9) / HpBar 斜杠(-10)，
  //       `roomArea` 自身没有 z → z:1 就压住全部标记，z:-1 又沉到 Photo 背后 ✗
  //       **z 这条路从头到尾就是死的**，不是没调对值 ✓
  //   于是改成"**盖在上面 + 自己挖洞 + 垫底色**"（见下面 avatarBox 内部）：
  //     皮肤放在最上层，但在「要保护的区域」把自己挖掉，
  //     挖掉的地方由**垫底层**补一块不透明深色（免得露出原版立绘）✓
  Item {
    id: avatarBox
    visible: false
    // ★ 层序：皮肤在立绘之上、标记/装备之下（见上面 `avatarZ` 的注释 ✓）
    z: host.avatarZ

    // ══════════════════════════════════════════════════════════════════
    // 皮肤本体
    //
    // ⚠⚠ **换皮肤必须重建，绝不能改已有实例的文件路径** ✗
    //   实测：从冰魄映雪切到战场绝版 → 0.2 秒后崩 `FreeKill.exe 0x895e0` ✓
    //   原因：改 `SkeletonAnimation.atlasFile/skeletonDataFile` = 运行时换骨架 ✗，
    //        C++ 那条路处理"中途改配置"最脆弱 ✓ → 新建反而是最干净的 ✓
    //   做法：Loader + skinKey 变了就走 `sourceComponent` 换一遍 ✓
    //
    // ★★ 闸（防空路径建骨架）必须在**这里** —— 也就是 `SkelAvatar` 的**外面** ✗✗
    //
    //   两个要求**不矛盾**，关键是位置：
    //     * 要防空路径骨架 → 闸得让 `SkelAvatar` **根本不被实例化**
    //       （`Loader.active: false` 就不会实例化 `sourceComponent` ✓）
    //       因为 `visible: false` **拦不住构造** ✗ ——
    //       `SkeletonAnimation` 是 C++ 类型，**构造时就去加载骨架** ✓
    //     * 要保证预览重建不崩 → `SkelAvatar` **内部**的骨架必须**同步直接声明** ✗
    //       （给它套 Loader 会把创建推迟一帧 → 预览频繁重建时撞同一条崩溃 ✓）
    //   ⇒ 闸在外、同步在内 ✓
    Loader {
      id: avatarLoader
      anchors.fill: parent
      sourceComponent: avatarComp
      active: host.myDef !== null && host.myDef !== undefined

      property string skinKey: host.mySkinKey
      onSkinKeyChanged: {
        if (skinKey === "") return
        console.warn("[fk-skel] 重建头像层骨架 → " + skinKey)
        // ⚠⚠ 绝不能写 `active = false` ✗ —— 那是命令式赋值，
        //   会**永久破坏**上面 `active` 的绑定（闸就废了 ✓）
        //   改走 `sourceComponent`：先置 null 再补回 → 同样逼它重建 ✓
        var comp = avatarLoader.sourceComponent
        avatarLoader.sourceComponent = null
        Qt.callLater(function () { avatarLoader.sourceComponent = comp })
      }
    }

    // ★ Component 必须是 `avatarBox` 的**直接子对象** ✗✗
    //   （QML 的 id 是词法作用域，塞进别的 Item 里也能解析 ——
    //     但结构混乱之后每次改动都容易踩坑 ✓）
    Component {
      id: avatarComp
      SkelAvatar {
        id: avatar
        who: "宿主"
        // ★ 给宿主头像一个**可识别的名字** ✓
        //   谁在用：换肤面板要显示**和宿主同一套皮肤**时，
        //     **不能**再建一套骨架（同素材被 Spine 加载两次 → 崩 `0x89739` ✗），
        //     改成**镜像这一份**（`ShaderEffectSource` 取纹理，不碰贴图 ✓）
        objectName: "fkSkelHostAvatar"
        anchors.fill: parent
        rootPath: host.myDef
          ? (Cpp.path + "/packages/fk-skel/skins/" + host.myDef.key + "/" + (host.myDef.dir || "image/skins"))
          : ""
        bgName: host.myDef ? (host.myDef.bg || "") : ""
        bodyName: host.myDef ? (host.myDef.body || "") : ""
        bgScale: host.myDef ? (host.myDef.bg_scale || 0.12) : 0.12
        bodyScale: host.myDef ? (host.myDef.scale || 0.12) : 0.12
        bgIdle: host.myDef ? (host.myDef.bg_idle || "play") : "play"
        bodyIdle: host.myDef ? (host.myDef.body_idle || "play") : "play"
        // ★ "头像框内的入场动画"（骨架自带的那种 ✓）
        //   来源：`skin.lua` 的 `bg_shown` / `body_shown`
        //   ⚠ 与待机**相同**时传空 → 不触发（其它皮肤不受影响 ✓）
        bgEnter: (host.myDef && host.myDef.bg_shown
                  && host.myDef.bg_shown !== host.myDef.bg_idle)
                 ? host.myDef.bg_shown : ""
        bodyEnter: (host.myDef && host.myDef.body_shown
                    && host.myDef.body_shown !== host.myDef.body_idle)
                   ? host.myDef.body_shown : ""
        frameH: 664
        // 二期取景：清单默认 × 我们自己的微调（在 refresh() 里算好）
        // ★ 皮肤指定的 Spine 版本（0=Auto ✓）—— 见 SkelAvatar.qml 的说明
        spineVersion: (host.myDef && host.myDef.spine_version)
                        ? (1 * host.myDef.spine_version) : 0
        faceMul: host.face ? host.face.mul : 1
        faceDx: host.face ? host.face.dx : 0
        faceDy: host.face ? host.face.dy : 0
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // ★★★ 路线甲：把核心的「标记层」挪到皮肤**上面**
  //
  // 为什么必须这么做（这是整个问题的根源，实测+读码确认）：
  //   * 立绘和标记在**同一个子树**里（Room → roomArea → Photo → photoMaskEffect），
  //     而且**都是 z=0** → 它们之间不可能被外部插入任何东西 ✗
  //   * `avatarBox` 是**房间的兄弟**（另一个子树）→ 它整层要么全压在 Photo 之上
  //     （标记被盖 ✗），要么全沉在 Photo 之下（皮肤被牌背盖 ✗），**没有夹层** ✗
  //   ⇒ 所以只能**把标记本身搬到皮肤上面**，而不是想办法给皮肤找位置 ✓
  //
  // 搬运对象是 Photo **主动公开的别名**（`Photo.qml:34-35`）：
  //   `photo.markArea`    → MarkArea    （无图标记，文字）
  //   `photo.picMarkArea` → PicMarkArea （有图标记，图标）
  // 这两个是 Photo 自己导出的接口，比乱翻 children 稳 ✓
  //
  // ⚠ 搬运时**必须用 mapToItem 记下场景位置**再放回去 ✗：
  //   换了父对象以后，x/y 的含义从"Photo 局部"变成"新父局部"，
  //   直接照搬会错位；而且 Photo 在多人局会被**缩放** ✓
  // ══════════════════════════════════════════════════════════════════════
  Item {
    id: markLayer
    anchors.fill: parent
    z: 801                 // ★ 比 avatarBox(800) 高 → 标记画在皮肤上面 ✓
    // ⚠ 不加 clip：标记本来就长在牌面外一点（PicMarkArea 是 -4），裁了就缺一块 ✗
  }

  property bool marksAdopted: false

  /// 搬过来的层清单：[{ item, name }]
  ///   ★ 刻意用**显式引用**而不是"从 markLayer.children 里认类型" ✗
  ///     换父之后它们已经不在 Photo 树里了，再想按类型找回来很脆 ✓
  ///   位置不再存在这里 —— 见 `markBase`（相对窗口左上角的局部偏移）✓
  property var markItems: []

  /// 把两个标记层搬到 markLayer 里（只做一次）
  function adoptMarks() {
    if (host.marksAdopted) return true
    var p = Probe.myPhoto(host)
    if (!p) return false

    // ⚠ 不能用 `p.markArea` 直接取：`markArea` 既是别名又是 Photo 的一个**函数**
    //   （`Photo.qml:448 handleMarkAreaUpdate`），可能撞名。
    //   用 `Probe.markNodes` 走"先取别名、再判 shape、最后翻子对象"的路 ✓
    var nodes = null
    try { nodes = Probe.markNodes(p) } catch (e) { nodes = null }
    if (!nodes) return false
    if (!nodes.markArea && !nodes.picMarkArea && !nodes.equipArea
        && !nodes.specialArea && !nodes.saveme && !nodes.restIndicator) return false

    // ① 先把「窗口左上角」在房间里的坐标、以及**窗口尺寸**量出来 ✓
    //   ⚠ 基准用 `photoMask` 而不是 `Photo` 的原点 ✗：
    //     `Photo.qml:192` 的 `saveme` 是 `anchors.centerIn: root.photoMask`，
    //     它的位置是相对**窗口**的；用 Photo 原点当基准会差出窗口在牌里的偏移 ✓
    //   ⚠ 窗口尺寸必须现在量好 —— 下面算"居中/右下角"要用它 ✓
    var winW = 0, winH = 0
    var winTL = null
    try {
      var mask0 = null
      var node0 = p
      for (var d0 = 0; d0 < 8 && node0; d0++) {
        try { mask0 = node0.photoMask } catch (e) { mask0 = null }
        if (mask0 && mask0.width > 0) break
        node0 = node0.parent
      }
      if (mask0) {
        var m0 = mask0.mapToItem(host, 0, 0)
        winTL = { x: m0.x, y: m0.y }
        winW = mask0.width
        winH = mask0.height
      }
    } catch (e1) { winTL = null }
    if (!winTL) {
      try {
        var pt0 = p.mapToItem(host, 0, 0)
        winTL = { x: pt0.x, y: pt0.y }
        winW = p.photoMask ? p.photoMask.width : p.width
        winH = p.photoMask ? p.photoMask.height : p.height
      } catch (e2) { winTL = { x: 0, y: 0 } }
    }
    if (!(winW > 0)) winW = 103      // 兜底（就是标准窗口宽）
    if (!(winH > 0)) winH = 166      // 兜底（就是标准窗口高）

    var names = ["markArea", "picMarkArea", "equipArea",
                 "specialArea", "saveme", "restIndicator"]
    var items = []
    var localOffsets = {}      // name -> {x,y} 相对窗口左上角

    for (var i = 0; i < names.length; i++) {
      var it = nodes[names[i]]
      if (!it) continue
      var nm = names[i]

      // ★ ② 清掉 anchors —— `saveme` 的 `anchors.centerIn`（Photo.qml:192）
      //   会在换父后继续生效、覆盖我写的 x/y ✗
      //   ⚠ 解绑必须用 `null`（`undefined` 不解绑），而且要**无条件赋值** ✓
      try {
        if (it.anchors) {
          it.anchors.centerIn = null
          it.anchors.horizontalCenter = null
          it.anchors.verticalCenter = null
          it.anchors.left = null
          it.anchors.right = null
          it.anchors.top = null
          it.anchors.bottom = null
          it.anchors.fill = null
        }
      } catch (e0) { /* 没有 anchors 也不致命 */ }

      // ③ 量一个"测量值"做兜底（某些元素下面没有对应规则时用）
      var meas = null
      try {
        var p0 = it.mapToItem(host, 0, 0)
        meas = { x: p0.x - winTL.x, y: p0.y - winTL.y }
      } catch (e) { meas = null }

      // ④ 换父
      try {
        it.parent = markLayer
      } catch (e) {
        console.warn("[fk-skel] 标记层搬运失败(" + nm + "): " + e)
        continue
      }

      // ★★ ⑤ 按**源码里的定位规则**算出窗口局部偏移 —— 不再依赖测量 ✗
      //
      //   为什么必须这样（用户日志实测出来的）：
      //     `saveme局部(34,31)` 而**正确值是 (8.4, 12.5)** ——
      //     因为 Qt 的 anchors 效果是**延迟生效**的：
      //     我在"清锚之后"立刻 mapToItem，那一刻它还没按锚规则摆好 ✗
      //     ⇒ 测量在时间上根本不可靠 ✓
      //
      //   而这几个元素的规则我都读过源码、是确定的，**直接算**即可 ✓
      //
      // ⚠⚠ 用尺寸时必须乘 `scale` ✗✗ —— 第二次踩到的坑：
      //   实测 `saveme局部(28,15)`，而 `(103-48)/2 = 27.5 ≈ 28`
      //   → `it.width` 给的是**缩放前**的逻辑宽（48），
      //     而渲染出来的宽度是 `it.width * it.scale`（`Photo.qml:193` 写了 `scale: 0.75`）✓
      //   正确：`(103 - 115*0.75)/2 = 8.375` ≈ 期望的 8.4 ✓
      //   所以下面统一用 `it.width * scale` / `it.height * scale` 当**渲染尺寸** ✓
      var W = winW, H = winH
      var sc = 1
      try { sc = it.scale || 1 } catch (eSc) { sc = 1 }
      var cw = 0, ch = 0
      try {
        cw = it.width * sc          // 渲染宽（含 scale）
        ch = it.height * sc         // 渲染高（含 scale）
      } catch (e1) { cw = 0; ch = 0 }

      var off = null
      if (nm === "saveme") {
        // Photo.qml:192-193 `anchors.centerIn: root.photoMask` + `scale: 0.75`
        //   → 在窗口里**居中** ✓
        off = { x: (W - cw) / 2, y: (H - ch) / 2 }
      } else if (nm === "picMarkArea") {
        // Photo.qml:421-423 `anchors.top: parent.bottom` + `right: parent.right`
        //                  + `topMargin: -4`
        //   → 右上角贴"牌底边、牌右边"，再往上 4 ✓
        //   窗口局部：x = W - cw（右对齐），y = H - 4
        off = { x: W - cw, y: H - 4 }
      } else if (nm === "restIndicator") {
        // Photo.qml:94-95 `anchors.centerIn: root.photoMask` + `leftMargin: 15`
        //   → 居中后再右移 15 ✓
        off = { x: (W - cw) / 2 + 15, y: (H - ch) / 2 }
      } else {
        // markArea / equipArea / specialArea：在 Photo 里是显式 x/y（+ 底部锚），
        //   测量值与规则一致，**保留测量值**即可（它们不受"不可见"影响）✓
        off = meas
      }
      if (!off) off = { x: 0, y: 0 }

      // ★ 记下**规则名**而不只是数字：`saveme` 的宽高会随状态变
      //   （saveme.png 48px / surrender.png 115px），
      //   所以每轮都要**按规则重算**、不能把这次的数字固化 ✓
      localOffsets[nm] = { rule: (nm === "saveme" || nm === "picMarkArea"
                                  || nm === "restIndicator") ? nm : "measured",
                           x: off.x, y: off.y }
      try {
        it.x = winTL.x + off.x
        it.y = winTL.y + off.y
      } catch (e2) { /* 写不进去也不致命 */ }
      items.push({ item: it, name: nm })
    }
    if (items.length === 0) return false

    host.markItems = items
    host.marksAdopted = true
    // ★ 记下**局部偏移**：每轮的定位 = 窗口左上角的当前坐标 + 这里的偏移 ✓
    //   ⚠ 不再记"Photo 的绝对坐标"了 —— 那样只能做"位移跟随"，
    //     而且会把我"在元素不可见时量到的垃圾值"固化下来 ✗（实测就是这么错的）
    host.markBase = localOffsets
    var s = ""
    for (var k = 0; k < items.length; k++) {
      var o = localOffsets[items[k].name] || { x: 0, y: 0 }
      s += " " + items[k].name + "局部(" + Math.round(o.x) + ","
        + Math.round(o.y) + ")"
    }
    console.warn("[fk-skel] 标记层已搬到皮肤之上（路线甲）:" + s)
    // ★ 诊断：把这张牌子树里**所有带 source 的对象**列出来
    //   有了它就能直接看出：那张死亡图在不在、路径是什么、可见性如何 ✓
    //   ⚠ `nodes` 可能为 null（用户日志里的 `Cannot read property 'name' of null`
    //     就是这个）→ 必须挡一下 ✓
    try {
      var sl = (nodes && nodes._srcList) ? nodes._srcList : []
      console.warn("[fk-skel] 牌上所有图(" + sl.length + "): "
        + (sl.length ? sl.join("  ") : "（一个都没有）"))
    } catch (e3) { /* 诊断失败不影响功能 */ }
    return true
  }

  /// 每轮把搬过来的层摆到正确位置。
  ///
  /// ★★ 关键修正（用户日志实测出来的）：
  ///   第一版是"搬运那一刻量一次坐标、之后只按 Photo 的**位移量**平移" ✗ ——
  ///   实测日志：
  ///     `saveme 定位: x=51 映射后=(57,35) 牌面宽=131`
  ///     `saveme 定位: 期望 x=57 y=35 → 实读 x=57 y=35`   ← 写入是成功的
  ///   也就是说**写入没问题，是量错了**：
  ///     `saveme` 只在濒死/阵亡/投降时可见，搬它的时候它**还是不可见的**，
  ///     那时它的 anchors 没在生效 → 量到的是没意义的位置 (57,35)，
  ///     而这个值被**写死**了 → 等它真该出现时，位置就是错的 ✗
  ///
  ///   正确做法：**每轮都从 `photoMask` 现算**，算的是"相对窗口左上角的偏移"，
  ///   与元素当时可不可见无关 ✓
  ///     目标位置 = photoMask 在房间里的左上角 + 该元素的**局部偏移**
  ///   局部偏移在搬运时就记录下来（`mapToItem` 得到的是绝对坐标，
  ///   减去 photoMask 的绝对坐标 = 稳定的局部偏移）✓
  function applyMarkPositionsFromLayer() {
    var items = host.markItems
    if (!items || items.length === 0) return
    var p = Probe.myPhoto(host)
    if (!p) return
    var box = host.markBase          // { markArea:{x,y}, ... } 局部偏移
    if (!box) return
    // 窗口左上角在房间里的当前位置（每轮现算 → 扛住重排/缩放 ✓）
    var win = null
    try {
      var mask = null
      var node = p
      for (var d = 0; d < 8 && node; d++) {
        try { mask = node.photoMask } catch (e) { mask = null }
        if (mask && mask.width > 0) break
        node = node.parent
      }
      if (mask) {
        var tl = mask.mapToItem(host, 0, 0)
        win = { x: tl.x, y: tl.y, w: mask.width, h: mask.height }
      }
    } catch (e2) { win = null }
    if (!win) return
    if (!(win.w > 0)) win.w = 103
    if (!(win.h > 0)) win.h = 166

    for (var i = 0; i < items.length; i++) {
      var rec = items[i]
      if (!rec || !rec.item) continue
      var info = box[rec.name]
      if (!info) continue

      var ox, oy
      if (info.rule && info.rule !== "measured") {
        // ★ 按规则**每轮重算** —— 因为 `saveme` 的宽高会随状态变
        //   （saveme.png 48px / surrender.png 115px），把数字固化就会错 ✗
        var sc2 = 1
        try { sc2 = rec.item.scale || 1 } catch (eS) { sc2 = 1 }
        var cw2 = 0, ch2 = 0
        try { cw2 = rec.item.width * sc2; ch2 = rec.item.height * sc2 } catch (eW) { }
        if (info.rule === "saveme") {
          ox = (win.w - cw2) / 2
          oy = (win.h - ch2) / 2
        } else if (info.rule === "picMarkArea") {
          ox = win.w - cw2
          oy = win.h - 4
        } else if (info.rule === "restIndicator") {
          ox = (win.w - cw2) / 2 + 15
          oy = (win.h - ch2) / 2
        } else {
          ox = info.x; oy = info.y
        }
      } else {
        // 测量型（markArea / equipArea / specialArea）：它们在 Photo 里是显式 x/y，
        //   与可见性无关，测量值稳定 ✓
        ox = info.x; oy = info.y
      }

      var nx = win.x + ox
      var ny = win.y + oy
      // 连写两次：压过 anchors 可能存在的延迟赋值 ✓
      for (var r = 0; r < 2; r++) {
        try {
          rec.item.x = nx
          rec.item.y = ny
        } catch (e3) { break }
      }
    }
  }

  /// `markBase`：搬运时记录下来的**局部偏移**（相对 `photoMask` 左上角）
  ///   每轮的定位 = 窗口左上角当前坐标 + 这里的偏移 ✓
  ///   ⚠ 不要改回"记绝对坐标 + 按位移跟随" ✗ —— 那样会把
  ///     "元素不可见时量到的垃圾值"固化下来（实测踩过）
  property var markBase: ({})

  /// 每 400ms 对一次：我在场上的武将是谁、我选了哪张、头像框在哪
  function refresh() {
    Store.init(Cpp, Lua)      // 幂等，便宜；防止某次切换后注入丢失
    Probe.init(Cpp, Lua)
    // 清单也在这里补一次（宿主创建时 Lua 可能还没就绪，见 skins 属性的注释）
    if (!host.skins || host.skins.length === 0) {
      var sl = Store.skins()
      if (sl && sl.length > 0) {
        host.skins = sl
        console.warn("[fk-skel] 清单已就绪：" + sl.length + " 套")
      }
    }
    var g = Probe.myGeneral(host)          // host 本身就是房间
    // ⚠ 武将还没解析出来时**也要继续往下走**（不能 return ✗）：
    //   "把头像层挂进武将牌"这件事跟"我选了哪张皮肤"无关 ——
    //   每张牌装什么皮肤由它自己的 `dataModel.skin` 决定 —— 那一套已经回退了 ✗
    //   （回退理由见上面 avatarBox 的注释：挂进武将牌试了五六轮全失败 ✗）
    //   早退的后果：玩家在位、但我的武将数据还没到 → 层一直挂不上 ✗
    // ⚠ **每次都要重读存档**，不能只在"武将变了"时才读。
    //   否则你在换肤页选完新皮肤，这边武将没变 → 直接跳过 → 换了跟没换一样 ✗
    //   （这一路只管"我自己"：换肤面板的入口、出场动画，用的是 host.myDef ✓）
    if (g) {
      // ⚠ 区分两个值（形态切换的核心 ✗）：
      //   `skBase` = 存档里玩家选的（**基础形态**，永远不改 ✓）
      //   `sk`     = 按体力决议出的**生效形态**（对局中可能不同 ✓）
      //   没写 `form_group` 的皮肤：`resolveForm` 原样返回 ⇒ **行为完全不变** ✓
      var skBase = Store.get(Cpp, g)
      var sk = host.resolveForm(skBase, host.selfHp())
      if (g !== host.myGeneral || sk !== host.mySkinKey) {
        host.myGeneral = g
        host.mySkinKey = sk
        host.myDef = Store.byKey(sk)
        console.warn("[fk-skel] 我在场上的武将 = " + g
          + "，我选的骨骼皮肤 = " + (host.mySkinKey || "（没选）"))
        host.maybePlayEnter()    // 甲：进对局时我的角色带出场动画入场 ✓（每局一次 ✓）
      }
      // ⚠ 每轮都重算取景值（不是只在换皮肤时算）：
      //   二期在换肤面板里点 +/- 之后，这边要**立刻**跟着变 ✓
      var f = faceOf(host.myDef, host.mySkinKey)
      if (!host.face || host.face.mul !== f.mul
          || host.face.dx !== f.dx || host.face.dy !== f.dy) {
        host.face = f
        console.warn("[fk-skel] 取景 " + host.mySkinKey + " mul=" + f.mul
          + " dx=" + f.dx + " dy=" + f.dy)
      }
    }
    var geo = Probe.geom(host, host)       // ⚠ 基准 = 我们自己（层就挂在这个页面上）
    if (!geo) { avatarBox.visible = false; return }
    if (!host.logged) {
      host.logged = true
      console.warn("[fk-skel] 头像几何 窗口=" + Math.round(geo.winW) + "x"
        + Math.round(geo.winH) + "@(" + Math.round(geo.winX) + ","
        + Math.round(geo.winY) + ") mask=" + geo.found
        + " frameH=" + Math.round(geo.frameH))
    }
    avatarBox.x = geo.winX
    avatarBox.y = geo.winY
    avatarBox.width = geo.winW
    avatarBox.height = geo.winH
    // ★ 每轮都重算遮罩/垫底几何：
    //   座位表会重排（`arrangePhotos`）、多人局会缩放整张牌，
    //   `avatarBox` 的 x/y/w/h 一变，洞的位置就得跟着变 ✓
    //   （只在真的变了时才写属性，见 setIfChanged ✓ 静态时不触发重排 ✓）
    host.computePatchGeom()
    // ★★ 路线甲：把核心的标记层搬到皮肤之上（只搬一次 ✓）
    //    必须排在"几何已就绪"之后：搬运时要按房间坐标记下位置 ✓
    if (!host.marksAdopted) {
      host.adoptMarks()
    } else {
      host.applyMarkPositionsFromLayer()
    }
    // ⚠⚠ 只在**真的选中了一套皮肤**时才显示 ✗✗
    //
    //   原来这里是无条件 `avatarBox.visible = true` → 实测**直接崩溃** ✗：
    //     没选皮肤时 `myDef` 是 null（`Store.byKey("")` 返回 null ✓），
    //     而这一层里两个 Loader 会各自去建一个 `SkelAvatar`，
    //     它的 `rootPath` 是**空串** → `SkeletonAnimation` 拿到空 atlas/skel 路径 ✗
    //     日志证据（崩溃前同一秒）：
    //       `SkeletonAnimation::loadSkeletonAndAtlasData Error: Invalid AtlasFile: QUrl("")`  × 6
    //     然后 `FreeKill.exe 0xc0000005 @ 0x895e0`（Windows 事件日志 ✓）
    //   ⇒ 骨架**绝不能用空路径创建**，创建之前必须确认有皮肤 ✓
    if (!host.myDef) {
      avatarBox.visible = false
      return
    }
    if (!avatarBox.visible) {
      avatarBox.visible = true
      console.warn("[fk-skel] 开始显示骨骼皮肤「"
        + (host.myDef.name || host.mySkinKey) + "」")
    }
  }

  Timer {
    interval: 400
    repeat: true
    running: true
    onTriggered: host.refresh()
  }

  // 热键：Ctrl+J 打开换肤页（对局里也能换）
  // ⚠ 必须用**词法 id** `picker`，不能写 `host.picker`：
  //   QML 的 id 不是对象属性，`host.picker` 会得到 undefined →
  //   报 `TypeError: Cannot call method 'open' of undefined`（实测踩到）✗
  Shortcut {
    sequence: "Ctrl+J"
    onActivated: picker.open(host.myGeneral)
  }

  SkelPicker {
    id: picker
    anchors.centerIn: parent
    // ⚠ 尺寸上限必须够大 ✗ —— 原来写死 `860 x 460`，结果：
    //   ① 四行控件每行要 ~860 宽 → 左列被撑到 860 → 预览框变成"又宽又矮" ✗
    //   ② 高度 460 里，标题(~40) + 四行控件(~160) + 边距(32) = 232，
    //      留给预览只有 ~228 → 人物被缩得特别小 ✗（用户实测反馈）
    //   ⇒ 现在按屏幕比例给足空间，预览才是正常大小 ✓
    // ⚠ 高度上限必须**接近父容器** ✗ —— 实测日志：
    //     `面板=1056x538  祖先链: SkelHost=1200x626 ← …`
    //   → 原来写 `parent.height * 0.86` = **538**，而内容是
    //     `标题 40 + 预览 420 + 五行控件 + 边距 32 ≈ 680` → **溢出 142px** ✗
    //     （表现：底下几行控件被切在面板外 —— 用户截图 ✓）
    //   ⇒ 高度放宽到 0.95（几乎占满父容器），宽度保持 0.88 ✓
    width: Math.min(parent.width * 0.88, 1240)
    height: Math.min(parent.height * 0.95, 780)
    visible: false
    z: 950
    onClosed: host.refresh()
    // 三期：面板里的「试播大动画」按钮 → 转给宿主播
    onFieldRequested: host.playField()
    // 试播出场 ✓ —— 会读 `#enter` 那份微调 ✓，所以看到的=下一局入场的效果 ✓
    onEnterRequested: host.playField("field_enter")
  }

  // ---------------------------------------------------------------------
  // 三期：场上大动画（技能 / 伤害牌）
  //
  // 用当时**验证可用**的那份组件（SkelField = 原 FieldAnim）✓
  // 它是"自启动 + 播完淡出自销毁"的，所以每次播放**新建一个实例** ——
  // 当年就是这个模式（动态创建、播完自己 destroy），没崩过 ✓
  //
  // 现在先提供**手动入口 Ctrl+F**，用来确认它画得对；
  // 真实时机（自己发动技能 / 使用伤害牌）的接线是下一步：
  //   那需要在核心的时机事件上挂钩子 —— 那是当年唯一反复出问题的地方
  //   （钩子里碰别人的对象），所以单独一步做，不和渲染混在一起。
  // ---------------------------------------------------------------------
  /// 播一次场上大动画。
  ///   fieldKey: "field_anim"（技能，默认）| "field_card_anim"（伤害牌）
  ///
  /// 骨架选择：优先清单里该用途配的 field_skel / field_skel_card；
  /// 都没有就退回**人物骨架** —— 清河公主那套的场上动画（TeShu）就在人物骨架里 ✓
  /// 出场动画：每局只播一次 ✓（甲方案：进对局时我的角色带特效入场 ✓）
  property bool enterPlayed: false

  /// 在"解析出我选的皮肤"之后调用 ✓ —— 稍等片刻让棋盘铺开再播 ✓
  function maybePlayEnter() {
    if (host.enterPlayed) return
    if (!host.myDef || !host.myDef.field_enter_skel) return
    // ★★ 出场骨架**就是头像骨架**时 → 跳过场上那条路 ✗✗✗
    //
    //   为什么（实测 ✓）：有这么一类皮肤 —— **只有 `XingXiang.skel`**，
    //   它的**出场动画 `ChuChang` 长在头像骨架里** ✓
    //   （马云騄、辛宪英；清河公主的 `field_enter_skel` 本来就是空的）
    //
    //   这类皮肤的出场应该**在人物框内播、然后衔接待机** ✓
    //   （由 `SkelAvatar` 的 `bodyEnter` 负责 —— 宿主把 `body_shown` 传了进去 ✓）
    //
    //   如果**不跳过**，同一个骨架会在场上**再播一遍**，而且缩放会算得离谱 ✗：
    //     实测日志：`场上动画已创建: ChuChang 骨架=XingXiang 高度占比=16.465`
    //     —— 16.5 倍页面高（因为它没有独立出场骨架，`field_height` 也没配 ✓）
    //
    //   ⇒ 判据：`field_enter_skel === body` 就跳过 ✓
    //     有独立出场骨架的（`chuchang` ≠ `daiji2`）**照旧在场上播** ✓ 不受影响
    if ("" + host.myDef.field_enter_skel === "" + (host.myDef.body || "")) {
      host.enterPlayed = true
      console.warn("[fk-skel] 出场动画长在头像骨架里（" + host.myDef.field_enter_skel
        + "）→ 框内播，**跳过场上** ✓")
      return
    }
    host.enterPlayed = true
    console.warn("[fk-skel] 出场动画：稍后播放 " + host.myDef.field_enter_skel
      + "/" + (host.myDef.field_enter_anim || "play"))
    enterTimer.start()
  }

  Timer {
    id: enterTimer
    interval: 1000          // 等棋盘铺开一点再入场 ✓（观感更好 ✓）
    repeat: false
    onTriggered: host.playField("field_enter")
  }

  function playField(fieldKey) {
    var key = fieldKey || "field_anim"
    if (!host.myDef) {
      console.warn("[fk-skel] 场上动画：还没选骨骼皮肤")
      return
    }
    var d = host.myDef
    var skelName = (key === "field_card_anim")
      ? (d.field_skel_card || d.field_skel || "")
      : ((key === "field_enter")
         ? (d.field_enter_skel || "")
         : (d.field_skel || ""))
    // ⚠ 出场不能回退到 `d.body` ✗ —— 那是**待机**骨架（daiji2 ✓），不是出场骨架 ✓
    if (skelName === "" && key !== "field_enter") skelName = d.body || ""
    var animName = (key === "field_card_anim")
      ? (d.field_card_anim || d.field_anim || "")
      : ((key === "field_enter")
         ? (d.field_enter_anim || "play")
         : (d.field_anim || ""))
    if (skelName === "" || animName === "") {
      console.warn("[fk-skel] 场上动画：这套皮肤没配 " + key + "（骨架="
        + skelName + " 动画=" + animName + "，跳过）")
      return
    }
    // ★★★ 防"把**待机动画**当场上动画播" ✗✗✗
    //
    //   用户实测指出的错误 ✓：
    //     * 马云騄：发动技能后播的是**待机**（`DaiJi`）✗
    //     * 张春华：同样，发动技能后出现待机 ✗
    //
    //   根因（审计确认，4 套中招 ✓）：
    //     这类皮肤**没有独立的场上骨架**，配置里 `field_skel` 填的是**头像骨架**、
    //     `field_anim` 填的是**待机动画名** ——
    //       `luyi_shuli`         field_skel=daiji2     field_anim=play   (=idle)
    //       `mayunlu_shenian`    field_skel=XingXiang  field_anim=DaiJi  (=idle)
    //       `xinxianying_fengzhu`field_skel=XingXiang  field_anim=DaiJi  (=idle)
    //       `zhangchunhua_chuoyue`field_skel=daiji2    field_anim=play   (=idle)
    //     ⇒ 一发动技能就播待机，等于"什么都没发生 + 人物在场上跳待机" ✗
    //
    //   ⚠ 不能只看 `animName === idle`：
    //     有些皮肤（`zhangqiying_lianyan`/`_suinian`/`_zhulu`）的场上骨架是
    //     **独立的 `chuchang`**，动画名也叫 `play` —— 那是**真的场上动画** ✓
    //   ⇒ 判据 = **同一个骨架** 且 **同一个动画名** 才算"误配待机" ✓
    //     （`skelName === d.body` 且 `animName === d.body_idle`）
    if (key !== "field_enter"
        && "" + skelName === "" + (d.body || "")
        && "" + animName === "" + (d.body_idle || "")) {
      console.warn("[fk-skel] 场上动画：这套皮肤的 " + key + " 配成了**待机动画**"
        + "（骨架=" + skelName + " 动画=" + animName + "）→ **跳过** ✓"
        + "（要真播技能动画，得给它配一个别的动画名 ✓）")
      return
    }
    var comp = Qt.createComponent(Cpp.path + "/packages/fk-skel/qml/SkelField.qml")
    if (comp.status !== Component.Ready) {
      console.warn("[fk-skel] 场上动画组件加载失败: " + comp.errorString())
      return
    }
    var base = Cpp.path + "/packages/fk-skel/skins/" + d.key + "/"
      + (d.dir || "image/skins") + "/"
    // 场上动画微调（存在我们自己那张表的另一个键下：皮肤key + "#field" ✓）
    var ft = null
    // 出场动画用自己那份微调 ✓（键 `<皮肤>#enter` ✓）；技能/伤害牌仍是 `#field` ✓
    var tuneKey = (key === "field_enter") ? "#enter" : "#field"
    try { ft = Store.tuneGet(Cpp, d.key + tuneKey) } catch (e) { ft = null }
    var fmul = (ft && ft.mul !== null && ft.mul !== undefined) ? ft.mul : 1
    var fdx = (ft && ft.dx !== null && ft.dx !== undefined) ? ft.dx : 0
    var fdy = (ft && ft.dy !== null && ft.dy !== undefined) ? ft.dy : 0
    var baseH = (d.field_height !== undefined) ? (1 * d.field_height) : 0.5
    var baseDy = (d.field_dy !== undefined) ? (1 * d.field_dy) : 0
    var obj = comp.createObject(host, {
      atlasFile: base + skelName + ".atlas",
      skelFile: base + skelName + ".skel",
      animName: animName,
      idleName: "",
      heightRatio: baseH * fmul,
      // ⚠ `SkelField` 里是 `skel.x = centerX + offsetX` —— offsetX/Y 是**像素** ✗
      //   我们调的是"页面比例"（±0.02 = 2%），所以这里必须乘上页面宽/高 ✓
      //   （之前没乘 → 等于只挪 0.02 像素 → 位移看起来完全没反应 ✗）
      offsetX: host.width * fdx,
      offsetY: host.height * (baseDy + fdy),
      centerX: host.width / 2,
      centerY: host.height / 2,
      srcW: 0,   // 0 = 让骨架自己报 sourceSize（本包各骨架坐标系不同，写死会错 ✗）
      srcH: 0,
    })
    if (!obj) {
      console.warn("[fk-skel] 场上动画创建失败")
      return
    }
    // ⚠⚠ **必须显式调 start()**：
    //   这个组件在 Component.onCompleted 里只打一句"已创建"，
    //   真正"摆位 + 起播"在 start() 里（它内部会 beginAnim + layout，
    //   拿不到骨架尺寸还会重试 4 次）。
    //   实测漏了这行的症状：日志只有"场上动画已创建"，没有后面的"缩放/播放"，
    //   画面上什么都没有 ✗
    obj.start()
    console.warn("[fk-skel] 场上动画已创建: " + animName + " 骨架=" + skelName
      + " 高度占比=" + (baseH * fmul).toFixed(3)
      + " 左右=" + fdx.toFixed(3) + " 上下=" + (baseDy + fdy).toFixed(3)
      + "（含微调：大小x" + fmul.toFixed(2) + "）")
  }

  // ---------------------------------------------------------------------
  // 三期：时机驱动（自动播）
  //
  // 时机来自核心客户端的 **`Mediator` 单例**（官方事件流，只读 ✓）：
  //   command = "Animate"   data.type = "InvokeSkill" / "InvokeUltSkill"
  //   command = "MoveCards" data.merged[]（谁把哪张牌从手牌移到处理区 → 使用牌）
  //
  // ⚠ 为什么这条路是安全的：当年唯一反复把游戏搞崩的是"在回调里**碰别人的对象**"✗
  //   （改别人的属性 / 在别人的对象上挂子对象）。这里只**读事件数据**，
  //   拿到时机后走的是我们自己那套已经验证过的渲染 ✓ 不碰任何别人的对象 ✓
  //
  // ⚠ 只对**我自己**触发：我们的渲染层只画自己的头像/动画 ✓
  // ---------------------------------------------------------------------

  property int procArea: -1
  property int handArea: -1
  property bool areaQueried: false

  /// 牌区域常量（从 Lua 取，别写死）
  function queryAreas() {
    if (areaQueried) return
    areaQueried = true
    try { procArea = 1 * Lua.ev("Card and Card.Processing or -1") } catch (e) { procArea = -1 }
    try { handArea = 1 * Lua.ev("Card and Card.PlayerHand or -1") } catch (e) { handArea = -1 }
    console.warn("[fk-skel] 牌区域常量 处理区=" + procArea + " 手牌=" + handArea)
  }

  /// 牌的内部名（小写+下划线，如 slash / fire__slash）
  function cardNameOf(id) {
    if (id === undefined || id === null) return ""
    try {
      return "" + Lua.ev("(function() local c = Fk:getCardById(" + id
        + "); return c and c.name or '' end)()")
    } catch (e) {
      return ""
    }
  }

  /// 这张牌名在不在清单的 damage_cards 里
  function isDamageCard(name) {
    if (!name || !host.myDef) return false
    var list = "" + (host.myDef.damage_cards || "")
    var parts = list.split(",")
    for (var i = 0; i < parts.length; i++) {
      var s = parts[i].replace(/^\s+|\s+$/g, "")
      if (s !== "" && s === name) return true
    }
    return false
  }

  /// 核心事件 → 播不播
  function onGameCommand(command, data) {
    if (!data) return
    try { if (Config.replaying) return } catch (e) { /* 没这个字段就算了 */ }
    var me = Probe.selfId(Cpp, Lua)
    try {
      if (command === "Animate") {
        if (data.player !== me) return
        if (data.type === "InvokeSkill") {
          host.playField("field_anim")
        } else if (data.type === "InvokeUltSkill") {
          // 清单里没有单独的大招动画，退回技能动画（比什么都不播好）
          host.playField("field_anim")
        }
      } else if (command === "MoveCards") {
        host.checkDamageCards(data, me)
      }
    } catch (e) {
      // 事件处理异常必须隔离：绝不能拖垮别的动画/界面
      console.warn("[fk-skel] 事件处理异常（已隔离）: " + e)
    }
  }

  /// 自己把"会造成伤害的牌"从手牌用到处理区 → 播 field_card_anim
  function checkDamageCards(data, me) {
    queryAreas()
    if (!data.merged || procArea < 0) return
    if (me === undefined || me === null || me < 0) return
    var recs = data.merged
    for (var i = 0; i < recs.length; i++) {
      var r = recs[i]
      if (!r || r.toArea !== procArea) continue
      if (handArea >= 0 && r.fromArea !== handArea) continue   // 排除判定/牌堆来源
      if (r.from !== me) continue                             // 只认我自己出的牌
      var ids = r.ids || []
      for (var j = 0; j < ids.length; j++) {
        var nm = cardNameOf(ids[j])
        if (nm && isDamageCard(nm)) {
          console.warn("[fk-skel] 我自己使用了伤害牌 " + nm + " → 播场上动画")
          host.playField("field_card_anim")
          return
        }
      }
    }
  }

  Connections {
    target: Mediator     // 来自 Fk.Base，import Fk 已带出（Fk/qmldir: import Fk.Base auto）
    function onCommandGot(sender, command, data) {
      host.onGameCommand(command, data)
    }
  }

  Shortcut {
    // ⚠ **不能用 Ctrl+F**：核心 main.qml:68 把 Ctrl+F 绑成了"切换全屏"，
    //   我们的一按就被它吃掉（实测：按 Ctrl+F 后日志里连 playField 的一行都没有 ✗）。
    //   核心占用的还有 Escape / T / D / Return / Space / F11 / Ctrl+F / Alt+Return，
    //   所以这里挑 Ctrl+G。
    //   换肤页底部那个「试播大动画」按钮更可靠 —— 优先用按钮 ✓
    sequence: "Ctrl+G"
    onActivated: host.playField()
  }

  // ---------------------------------------------------------------------
  // 语音替换：由**独立拓展包** `fk-skel-voice` 提供 ✓（可单独启用/禁用 ✓）
  //
  // 这里只负责"把它接上"：
  //   * 包在 → 动态创建它的 VoiceHost ✓（语音功能生效 ✓）
  //   * 包不在 / 改名为 .disabled → 只打一行日志 ✓ **不影响换肤** ✓✓
  //
  // 为什么语音不做成自己注册 UI 包：一个桌游**只能选一个 UI 包** ✗
  //   → 所以语音包做成组件库，由本宿主按需加载 ✓
  // ---------------------------------------------------------------------
  property var voiceHost: null

  function installVoiceHost() {
    const p = Cpp.path + "/packages/fk-voice/qml/VoiceHost.qml"
    const comp = Qt.createComponent(p)
    if (comp.status !== Component.Ready) {
      console.warn("[fk-skel] 没装语音包 fk-skel-voice（或加载失败）→ 不接管语音 ✓"
        + " 这是可选的，换肤照旧 ✓")
      return
    }
    const o = comp.createObject(host, { room: host })
    if (!o) {
      console.warn("[fk-skel] 语音组件创建失败（跳过）")
      return
    }
    voiceHost = o
    console.warn("[fk-skel] 已接上语音包 fk-skel-voice ✓")
  }

  // ---------------------------------------------------------------------
  // 入口：左侧那排竖按钮上方的「换肤」按钮
  //
  // 只读核心按钮的几何（mapToItem 到我们自己），把尺寸/位置/字体抄过来 ——
  // 核心对象一个字节都不动 ✓
  // （往核心的布局容器里塞带 anchors 的子对象是未定义行为，会崩 ✗）
  //
  // ⚠ 这里用**词法 id** `pickerButton`，不写 `host.pickerButton`
  //   （QML 的 id 不是对象属性 ✗ —— 上一版就是这么报 TypeError 的）
  // ---------------------------------------------------------------------

  property bool buttonAligned: false

  SkelButton {
    id: pickerButton
    width: 60
    height: 24
    onPickRequested: picker.open(host.myGeneral)
  }

  /// 找左侧那排竖按钮里**最上面**的一个（只读 text 和几何）
  function findSideButton() {
    var labels = ["托管", "反选", "牌序", "聊天", "取消托管"]
    var best = null
    var bestY = 1e9
    var walk = function (item, depth) {
      if (!item || depth > 8) return
      var kids = []
      try { kids = item.children || [] } catch (e) { return }
      for (var i = 0; i < kids.length; i++) {
        var k = kids[i]
        var t = ""
        var ok = false
        try {
          t = "" + (k.text || "")
          ok = (k.width > 0 && k.height > 0 && k.visible !== false)
        } catch (e) { continue }
        if (ok && t && labels.indexOf(t) >= 0) {
          var p = null
          try { p = k.mapToItem(host, 0, 0) } catch (e) { p = null }
          if (p && p.y < bestY) { bestY = p.y; best = k }
        }
        walk(k, depth + 1)
      }
    }
    walk(host, 0)
    return best
  }

  /// 抄尺寸/位置/字体：和核心那四个一样大，正好排在它们上方
  function alignPickerButton() {
    var src = findSideButton()
    if (!src) return
    var p = null
    var w = 0
    var h = 0
    try {
      p = src.mapToItem(host, 0, 0)
      w = src.width
      h = src.height
    } catch (e) {
      return
    }
    if (!p || !(w > 0) || !(h > 0)) return
    if (!pickerButton.fontCopied) pickerButton.copyFontFrom(src)
    // 只在真的变了才写（避免每 500ms 触发重排）
    if (Math.abs(pickerButton.width - w) > 0.5) pickerButton.width = w
    if (Math.abs(pickerButton.height - h) > 0.5) pickerButton.height = h
    if (Math.abs(pickerButton.x - p.x) > 0.5) pickerButton.x = p.x
    var ny = p.y - h - 6
    if (Math.abs(pickerButton.y - ny) > 0.5) pickerButton.y = ny
    if (!host.buttonAligned) {
      host.buttonAligned = true
      console.warn("[fk-skel] 「换肤」按钮已对齐核心竖按钮："
        + Math.round(w) + "x" + Math.round(h) + "@(" + Math.round(p.x) + ","
        + Math.round(ny) + ") 字体=" + (pickerButton.fontCopied ? "已抄核心" : "默认"))
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: true
    onTriggered: host.alignPickerButton()
  }

  Component.onCompleted: {
    // ⚠ 换肤页在**对局里是子对象**，它自己的 onCompleted 会把 visible 置 true
    //   （那是给大厅「更多」当页面用的）→ 结果一进对局就自动弹出来 ✗
    //   子对象的 onCompleted 先于父对象执行，所以这里补一句把它收起来 ✓
    picker.visible = false
    // ⚠ 必须：两个 JS 是 .pragma library 文件，里面的全局对象不一定可见（见文件头）
    Store.init(Cpp, Lua)
    Probe.init(Cpp, Lua)
    host.installVoiceHost()     // 语音功能由独立包提供（不在也能跑 ✓）
    console.warn("[fk-skel] 宿主就绪：这一页就是官方对局界面 + 我们的骨骼头像层；清单 "
      + skins.length + " 套皮肤")
    refresh()
  }
}
