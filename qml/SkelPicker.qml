// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelPicker —— 换肤页（大厅「更多」里的入口 + 对局里 Ctrl+J）
//
// 只列**我们自己的**骨骼皮肤（清单来自 init.lua 扫 skins/ 的结果）——
// 官方那些图片/视频皮肤归官方的换肤界面，两边不混。
//
// 一次只渲染**一张**预览（官方那个弹窗一屏建十几个预览，正是它崩的原因）。

import QtQuick
import QtQuick.Layouts

import Fk
import Fk.Widgets as W

import "SkelStore.js" as Store

W.PageBase {
  id: root

  property string general: ""

  signal closed()
  /// 三期：请求宿主试播一次场上大动画
  ///   （做成信号而不是直接调用：这个面板在大厅「更多」里也会用，那时没有宿主 ✓）
  signal fieldRequested()
  /// 出场动画的试播 ✓（和"试播大动画"同一套机制 ✓，只是换骨架和微调那份 ✓）
  signal enterRequested()

  /// 底色：W.PageBase 在大厅外不画背景，自己铺一块，字才看得见
  Rectangle {
    anchors.fill: parent
    color: "#F00E0E12"
    radius: 8
    border.width: 2
    border.color: "#8A6A2F"
  }

  function open(generalId) {
    root.general = "" + (generalId || "")
    var list = Store.skinsForGeneral(root.general)
    model = list
    var cur = Store.get(Cpp, root.general)
    if (cur === "" && list.length > 0) cur = list[0].key
    selectedKey = cur
    // ★ 显式安排重建（**不能**只靠 onSelectedKeyChanged ✓）
    root.schedulePreview()
    visible = true
    // 诊断：把"武将（版本）"的实际结果打一行 ——
    //   版本名的中文来自翻译表（Lua.tr），哪些包注册了翻译得实测；
    //   显示不对的话，对着这一行加映射就行 ✓
    for (var i = 0; i < list.length; i++) {
      console.warn("[fk-skel] 标签 " + list[i].name + " → " + root.generalsLabel(list[i]))
    }
  }

  // ⚠ 这三个属性**必须在这里声明** ✗
  //   （`open()` / `defOf()` / 界面都在用它们；
  //     我曾误删过一段把它们一起删掉 → 校验器立刻报"没有 property 声明" ✓）
  property var model: []
  property string selectedKey: ""
  property string status: ""

  /// 预览**实际显示**哪一套（由 `schedulePreview()` 维护，不直接跟 selectedKey ✓）
  ///   ⚠ 为什么不直接跟：**改活骨架的文件路径会崩**（当时原文的注释写明过 ✓），
  ///     必须"销毁旧的 + 建新的" ✓
  property string previewKey: ""

  /// ★ 安排一次"**重建预览**"：先销毁旧骨架、下一帧再建 ✓
  ///
  ///   ⚠⚠ 必须是**函数**，不能只靠 `onSelectedKeyChanged` 兜 ✗✗
  ///     `open()` 里会设 `selectedKey`；若设的值**和之前相同**
  ///     （例如你上次就选的这套 → 存档里就是它 ✓），
  ///     **QML 不发"变化"信号** → handler 不跑 → `previewKey` 永远空
  ///     → **预览框空着** ✓（实测踩到）
  ///   ⇒ 所以 `open()` **显式调用**它 ✓
  ///
  ///   ⚠ 单帧内"空→非空"会被 QML 合并 → 必须放到**下一帧** ✓
  function schedulePreview() {
    var k = root.selectedKey
    root.previewKey = ""                       // ① 销毁旧骨架 ✓
    Qt.callLater(function () {
      if (root.selectedKey !== k) return       // 期间又换了就不管 ✓
      root.previewKey = k                       // ② 下一帧重建 ✓
    })
  }

  // 用户点列表切换时走这里 ✓
  onSelectedKeyChanged: root.schedulePreview()

  function defOf(key) {
    for (var i = 0; i < model.length; i++) {
      if ("" + model[i].key === "" + key) return model[i]
    }
    return null
  }

  // -------------------------------------------------------------------------
  // 二期：取景微调
  //
  // 语义照抄当时钩子里的做法：**mul 相乘、dx/dy 相加**。
  // 清单里的 face_* 是基准，微调叠在它上面；"回到默认"= 把微调清掉 ✓
  //
  // ⚠ QML 不会追踪 JS 对象内部的变化，所以用一个计数器 tuneRev 触发重新求值
  //   （绑定里先读一下 tuneRev，它一变整条绑定就会重算）
  // -------------------------------------------------------------------------

  property int tuneRev: 0

  function bumpTune() { root.tuneRev = root.tuneRev + 1 }

  /// 清单里的默认取景值
  function defFace() {
    var d = root.defOf(root.selectedKey)
    return {
      mul: (d && d.face_mul !== undefined) ? (1 * d.face_mul) : 1,
      dx: (d && d.face_dx !== undefined) ? (1 * d.face_dx) : 0,
      dy: (d && d.face_dy !== undefined) ? (1 * d.face_dy) : 0,
    }
  }

  /// 生效值 = 默认 叠上 微调
  function effFace() {
    var b = root.defFace()
    var t = Store.tuneGet(Cpp, root.selectedKey)
    var mul = b.mul, dx = b.dx, dy = b.dy
    if (t) {
      if (t.mul !== null && t.mul !== undefined) mul = mul * t.mul
      if (t.dx !== null && t.dx !== undefined) dx = dx + t.dx
      if (t.dy !== null && t.dy !== undefined) dy = dy + t.dy
    }
    return { mul: mul, dx: dx, dy: dy }
  }

  function effMulText() { return (1 * root.effFace().mul).toFixed(2) }
  function effDxText() { return (1 * root.effFace().dx).toFixed(3) }
  function effDyText() { return (1 * root.effFace().dy).toFixed(3) }

  /// 把一个武将 id 显示成「武将名（版本）」—— 别把文件夹名直接摆给用户看 ✗
  ///   lvlingqi          → 吕玲绮（标准）
  ///   ol__lvlingqi      → 吕玲绮（OL）
  ///   mobile__lvlingqi  → 吕玲绮（手机版）
  /// 版本名优先查翻译表（`Lua.tr`）；查不到就原样用前缀（至少比裸 id 好读）
  function generalLabel(id) {
    var s = "" + id
    var base = s
    var ver = ""
    var i = s.indexOf("__")
    if (i > 0) {
      ver = s.substring(0, i)
      base = s.substring(i + 2)
    }
    var name = base
    try {
      var t = Lua.tr(base)
      if (t && ("" + t) !== "" && ("" + t) !== base) name = "" + t
    } catch (e) { /* 查不到就用 id */ }
    var verText = "标准"
    if (ver !== "") {
      verText = ver
      try {
        var tv = Lua.tr(ver)
        if (tv && ("" + tv) !== "" && ("" + tv) !== ver) verText = "" + tv
      } catch (e) { /* 同上 */ }
    }
    return name + "（" + verText + "）"
  }

  /// 这张皮肤适配的武将（中文标签，逗号分隔）
  function generalsLabel(def) {
    var gs = (def && def.generals) ? def.generals : []
    var out = []
    for (var i = 0; i < gs.length; i++) out.push(root.generalLabel(gs[i]))
    return out.join("、")
  }

  /// 调一格：kind = "mul" / "dx" / "dy"；up = 增/减
  function tuneStep(kind, up) {
    if (!root.selectedKey) return
    var t = Store.tuneGet(Cpp, root.selectedKey)
    var m = (t && t.mul !== null && t.mul !== undefined) ? t.mul : 1
    var x = (t && t.dx !== null && t.dx !== undefined) ? t.dx : 0
    var y = (t && t.dy !== null && t.dy !== undefined) ? t.dy : 0
    if (kind === "mul") {
      m = up ? (m * 1.05) : (m / 1.05)
    } else if (kind === "dx") {
      x = up ? (x + 0.02) : (x - 0.02)
    } else {
      y = up ? (y + 0.02) : (y - 0.02)
    }
    Store.tuneSet(Cpp, root.selectedKey, m, x, y)
    root.bumpTune()
  }

  /// 回到默认（把微调清空 —— 清单里的基准值保持不变）
  function tuneReset() {
    if (!root.selectedKey) return
    Store.tuneSet(Cpp, root.selectedKey, null, null, null)
    root.bumpTune()
  }

  // -------------------------------------------------------------------------
  // 三期的场上大动画微调（技能 / 伤害牌）
  //
  // 和取景同一套机制 ✓，只是存在**另一个键**下（`皮肤key + "#field"`）——
  // 这样不用改表结构 ✓，两套参数互不干扰 ✓
  //
  // 语义（和宿主实际用的完全一致，见 SkelHost.playField ✓）：
  //   mul → 乘在 `field_height` 上（大小 ✓）
  //   dx/dy → 加在 `offsetX/offsetY` 上，单位是**页面宽/高的比例**（左右/上下 ✓）
  //   清单里的 `field_dy`（默认 -0.1 = 上移 10%）是基准，显示的是**合计值** ✓
  // -------------------------------------------------------------------------

  /// 后缀：技能/伤害牌用 "#field" ✓，出场用 "#enter" ✓（同一张表 ✓ 不用改结构 ✓）

  // ══════════════════════════════════════════════════════════════════
  // ★★ 预览专用微调（`<皮肤>#preview`）★★
  //
  //   为什么独立一份（用户诉求 ✓）：
  //     预览原来用作者默认的 `face_mul/dx/dy`，面板上的调整写的是
  //     `<皮肤>` 那份（= **对局取景**）→ **调整完全不反映在预览里** ✗
  //     而用户要调的是"**预览框里看着满意**"，不该牵动对局 ✓
  //   ⇒ 独立键 `<皮肤>#preview`，语义和取景一致（mul 相乘 / dx·dy 相加 ✓）
  //     存在同一张表 `fk_skel_tune` 里，**不用改库结构** ✓
  // ══════════════════════════════════════════════════════════════════

  /// 预览微调用的存档键
  function prevKeyOf() {
    return root.selectedKey ? (root.selectedKey + "#preview") : ""
  }
  /// 预览微调的**生效值**（没调过就是 1 / 0 / 0 ✓）
  function effPrevMul() {
    var _r = root.tuneRev
    var t = Store.tuneGet(Cpp, root.prevKeyOf())
    return (t && t.mul !== null && t.mul !== undefined) ? (1 * t.mul) : 1
  }
  function effPrevDx() {
    var _r = root.tuneRev
    var t = Store.tuneGet(Cpp, root.prevKeyOf())
    return (t && t.dx !== null && t.dx !== undefined) ? (1 * t.dx) : 0
  }
  function effPrevDy() {
    var _r = root.tuneRev
    var t = Store.tuneGet(Cpp, root.prevKeyOf())
    return (t && t.dy !== null && t.dy !== undefined) ? (1 * t.dy) : 0
  }
  function effPrevMulText() { return (1 * root.effPrevMul()).toFixed(2) }
  function effPrevDxText() { return (1 * root.effPrevDx()).toFixed(3) }
  function effPrevDyText() { return (1 * root.effPrevDy()).toFixed(3) }

  /// 步进一次（kind: mul / dx / dy ✓；up 表示加还是减 ✓）
  ///   ⚠ 步长比取景**大一点**：预览是给人"看着调"的，细步太慢 ✓
  function prevStep(kind, up) {
    if (!root.selectedKey) return
    var k = root.prevKeyOf()
    var t = Store.tuneGet(Cpp, k)
    var m = (t && t.mul !== null && t.mul !== undefined) ? t.mul : 1
    var x = (t && t.dx !== null && t.dx !== undefined) ? t.dx : 0
    var y = (t && t.dy !== null && t.dy !== undefined) ? t.dy : 0
    if (kind === "mul") m = up ? (m * 1.06) : (m / 1.06)
    else if (kind === "dx") x = up ? (x + 0.02) : (x - 0.02)
    else y = up ? (y + 0.02) : (y - 0.02)
    Store.tuneSet(Cpp, k, m, x, y)
    root.bumpTune()
    root.status = "预览取景：" + root.effPrevMulText() + " / "
      + root.effPrevDxText() + " / " + root.effPrevDyText()
  }
  /// 重置预览微调
  function prevReset() {
    if (!root.selectedKey) return
    Store.tuneSet(Cpp, root.prevKeyOf(), null, null, null)
    root.bumpTune()
    root.status = "预览取景已重置"
  }

  function fieldKeyOf(sfx) {
    return root.selectedKey ? (root.selectedKey + (sfx || "#field")) : ""
  }

  function effFieldFace(sfx) {
    var d = root.defOf(root.selectedKey)
    var tune = Store.tuneGet(Cpp, root.fieldKeyOf(sfx))
    var mul = 1
    var dx = 0
    var dy = (d && d.field_dy !== undefined) ? (1 * d.field_dy) : 0
    if (tune) {
      if (tune.mul !== null && tune.mul !== undefined) mul = mul * tune.mul
      if (tune.dx !== null && tune.dx !== undefined) dx = dx + tune.dx
      if (tune.dy !== null && tune.dy !== undefined) dy = dy + tune.dy
    }
    return { mul: mul, dx: dx, dy: dy }
  }

  function effFieldMulText(sfx) { return (1 * root.effFieldFace(sfx).mul).toFixed(2) }
  function effFieldDxText(sfx) { return (1 * root.effFieldFace(sfx).dx).toFixed(3) }
  function effFieldDyText(sfx) { return (1 * root.effFieldFace(sfx).dy).toFixed(3) }

  function fieldStep(kind, up, sfx) {
    var k = root.fieldKeyOf(sfx)
    if (!k) return
    var t = Store.tuneGet(Cpp, k)
    var m = (t && t.mul !== null && t.mul !== undefined) ? t.mul : 1
    var x = (t && t.dx !== null && t.dx !== undefined) ? t.dx : 0
    var y = (t && t.dy !== null && t.dy !== undefined) ? t.dy : 0
    if (kind === "mul") m = up ? (m * 1.05) : (m / 1.05)
    else if (kind === "dx") x = up ? (x + 0.02) : (x - 0.02)
    else y = up ? (y + 0.02) : (y - 0.02)
    Store.tuneSet(Cpp, k, m, x, y)
    root.bumpTune()
    root.status = (sfx === "#enter")
      ? "出场动画微调已改 —— 下一局入场时生效"
      : "场上动画微调已改 —— 点「试播大动画」立刻看效果"
  }

  function fieldReset(sfx) {
    var k = root.fieldKeyOf(sfx)
    if (!k) return
    Store.tuneSet(Cpp, k, null, null, null)
    root.bumpTune()
    root.status = (sfx === "#enter") ? "出场动画微调已重置" : "场上动画微调已重置"
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 12

    // ---- 标题 ----
    RowLayout {
      Layout.fillWidth: true
      Text {
        text: "骨骼皮肤"
        font.family: "LiSu"
        font.pixelSize: 26
        font.bold: true
        color: "#E4D5A0"
        style: Text.Outline
        styleColor: "black"
      }
      Text {
        Layout.leftMargin: 10
        Layout.fillWidth: true
        // 同上：Text 的 implicitWidth 就是文字宽度，不置 0 也会顶出弹窗 ✗
        Layout.minimumWidth: 0
        elide: Text.ElideRight
        color: "#D8D8D8"
        font.pixelSize: 15
        text: root.general !== ""
          ? (Lua.tr(root.general) + " 可用 " + model.length + " 套")
          : ("全部 " + model.length + " 套（对局里按你的武将自动筛选）")
      }
      W.ButtonContent {
        text: "关闭"
        Layout.preferredWidth: 90
        onClicked: { root.visible = false; root.closed() }
      }
    }

    // ---- 预览 + 列表 ----
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 14

      // 预览：一次只有一张
      //
      // ★★★ 这里**必须是"直接子对象"**，不要 Loader / Component ✗✗✗
      //
      //   依据（会话记录里的原文 `tests/snapshots/orig_PICKER_QML.txt` ✓）：
      //     张琪瑛那批皮肤能用的时候，预览就是这么写的 ——
      //     `SkelAvatar` **直接**是预览框的子对象 ✓
      //
      //   为什么这个差别是**致命的**：
      //     * 直接子对象：面板**构造**时 `selectedKey` 还是空串 →
      //       `SkelAvatar.visible = false`（且有 `fileOf` 空路径守卫）→
      //       **骨架不建** ✓；只有用户**打开面板**（`open()` 设了 key）
      //       才会建预览骨架 —— 那时对局已经在跑 ✓
      //     * 套 `Loader + Component`：**面板一被构造**就把骨架建出来了 ✗
      //       —— 正好撞在"对局启动中"这个最脆弱的时刻 →
      //       `FreeKill.exe 0xc0000005 @ 0x895e0`（实测追踪日志 ✓）
      //
      //   ⚠ 所以"换皮肤要重建预览"这件事，**当年就没做**（直接改属性）✓
      //     我后来为了"避免运行时换骨架"加的 Loader，反而是崩因 ✓
      Rectangle {
        id: previewBox
        Layout.preferredWidth: 260
        Layout.fillHeight: true
        // ★★ 关键：**允许被压缩** ✗✗ ——
        //   原来只有 `Layout.fillHeight: true`，`implicitHeight` 撑得很大，
        //   于是加一行控件就**溢出面板**（按钮被顶出 ✓ 实测踩到）
        //   ⇒ 显式给一个较小的 minimumHeight，让布局有余量时优先压缩预览框，
        //     而不是把下面的按钮挤出去 ✓（用户要求：**预览框大小不变**，
        //     那是在"行数不变"的情况下；这里只是给布局一个弹性余量 ✓）
        Layout.minimumHeight: 120
        color: "#14141A"
        radius: 6
        border.width: 1
        border.color: "#555555"
        clip: true

        // ★★★ 换皮肤时必须**重建骨架**，绝不能改活骨架的文件路径 ✗✗✗
        //
        //   依据（当时原文的注释 ✓）：
        //     > ⚠⚠ 预览必须"重建"，绝不能改已有骨架的文件路径 ✗
        //     >   实测：在列表里点另一张皮肤 → 预览的 `SkeletonAnimation` 被改
        //     >   …而**列表每点一下预览就换一次**，撞上的概率高得多
        //   用户实测也印证：**打开面板不崩、切换皮肤才崩** ✓
        //   而且**只有补上 `who` 之后才出现** —— 在那之前 `SkelAvatar` 缺 `who`
        //   会**加载失败**，预览里没有活骨架，这条路走不到 ✓
        //
        //   ⇒ 用外层 `Loader.active` 做"销毁/重建"：
        //       `previewKey` 由 `schedulePreview()` 维护（先空、下一帧再填 ✓）
        Loader {
          id: previewLoader
          anchors.fill: parent
          anchors.margins: 6
          // 闸：**清单里真有这一套**才构造（防空路径建骨架 ✓）
          active: root.previewKey !== "" && root.defOf(root.previewKey) !== null
          sourceComponent: previewComp
        }

        Component {
          id: previewComp
          SkelAvatar {
            id: preview
            who: "面板预览"
            anchors.fill: parent
            anchors.margins: 6
            frameH: 664
            // ⚠ 用 `previewKey`（已确认存在）→ 路径**一定非空** ✓
            rootPath: {
              var d = root.defOf(root.previewKey)
              return d ? (Cpp.path + "/packages/fk-skel/skins/" + d.key + "/"
                          + (d.dir || "image/skins")) : ""
            }
            bgName: root.defOf(root.previewKey) ? (root.defOf(root.previewKey).bg || "") : ""
            bodyName: root.defOf(root.previewKey) ? (root.defOf(root.previewKey).body || "") : ""
            bgScale: root.defOf(root.previewKey) ? (root.defOf(root.previewKey).bg_scale || 0.12) : 0.12
            bodyScale: root.defOf(root.previewKey) ? (root.defOf(root.previewKey).scale || 0.12) : 0.12
            bgIdle: root.defOf(root.previewKey) ? (root.defOf(root.previewKey).bg_idle || "play") : "play"
            bodyIdle: root.defOf(root.previewKey) ? (root.defOf(root.previewKey).body_idle || "play") : "play"
            // ★ 预览专用微调（独立存档键 `<皮肤>#preview` ✓ 不动对局取景 ✓）
            // ★ 预览也要用它 —— 否则 JSON 素材的预览是空白 ✓
            spineVersion: (root.defOf(root.previewKey)
                           && root.defOf(root.previewKey).spine_version)
                          ? (1 * root.defOf(root.previewKey).spine_version) : 0
            prevMul: 1 * root.effPrevMul()
            prevDx: 1 * root.effPrevDx()
            prevDy: 1 * root.effPrevDy()
          }
        }
      }

      // 列表（名字卡片，不做缩略图墙）
      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        // ⚠⚠ **必须显式给 minimumWidth: 0**：
        //   QML 布局里 `Layout.minimumWidth` 默认等于子项的 `implicitWidth`，
        //   而 **ListView 的 implicitWidth 是"内容宽度"** —— 里面每行都限宽了也没用 ✗，
        //   ListView 自己仍会报一个很宽的隐式宽度 → 变成整行的**最小宽度** →
        //   布局压不下去 → 整列溢出，按钮和「关闭」全被顶出去 ✗（实测踩到）
        Layout.minimumWidth: 0
        Layout.preferredWidth: 260
        clip: true
        spacing: 8
        model: root.model

        delegate: Rectangle {
          required property var modelData
          width: ListView.view.width
          height: 40
          radius: 6
          color: ("" + modelData.key === root.selectedKey) ? "#3A3220" : "#1C1C22"
          border.width: ("" + modelData.key === root.selectedKey) ? 2 : 1
          border.color: ("" + modelData.key === root.selectedKey) ? "gold" : "#555555"

          Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            Text {
              width: parent.width
              elide: Text.ElideRight
              // 只留名字 ✓ —— 原来下面还有一行"这张皮肤适配了哪些版本的武将"，
              // 那是画蛇添足 ✗（用户明确要求去掉 ✓）；"✓ 当前"挪到名字后面就够 ✓
              text: modelData.name
                + (("" + modelData.key === Store.get(Cpp, root.general)) ? "　✓ 当前" : "")
              font.pixelSize: 15
              font.bold: true
              color: "white"
            }
          }

          W.TapHandler {
            onTapped: {
              root.selectedKey = modelData.key
              root.status = ""
            }
          }
        }
      }
    }

    // ══════════════════════════════════════════════════════════════════
    // ★ 预览取景微调（**只影响左边预览框**，不动对局取景 ✓）
    //
    //   为什么单独一行（用户诉求 ✓）：
    //     * 以前那行「预览」其实写的是**取景**（对局头像）→ 调整不反映在预览里 ✗
    //     * 用户要调的是"预览框里看着满意"，不该牵动对局 ✓
    //   ⇒ 独立存档键 `<皮肤>#preview`，本行只动它 ✓
    //   ⚠ 紧凑尺寸（按钮 36 / 文字 60·64）是为了**不被顶出面板** ✗✗
    //     面板高度受 `SkelHost` 硬约束（`parent.height * 0.95`）✓
    // ══════════════════════════════════════════════════════════════════
    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: "预览"
        color: "#E4D5A0"
        font.pixelSize: 14
        Layout.minimumWidth: 0
      }
      W.ButtonContent {
        text: "−"
        Layout.preferredWidth: 36
        Layout.maximumWidth: 36
        Layout.minimumWidth: 36
        enabled: root.selectedKey !== ""
        onClicked: root.prevStep("mul", false)
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.prevStep("mul", false)
        }
      }
      Text {
        Layout.preferredWidth: 60
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 12
        text: "大小 " + root.effPrevMulText()
      }
      W.ButtonContent {
        text: "＋"
        Layout.preferredWidth: 36
        Layout.maximumWidth: 36
        Layout.minimumWidth: 36
        enabled: root.selectedKey !== ""
        onClicked: root.prevStep("mul", true)
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.prevStep("mul", true)
        }
      }
      W.ButtonContent {
        text: "←"
        Layout.preferredWidth: 36
        Layout.maximumWidth: 36
        Layout.minimumWidth: 36
        enabled: root.selectedKey !== ""
        onClicked: root.prevStep("dx", false)
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.prevStep("dx", false)
        }
      }
      Text {
        Layout.preferredWidth: 64
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 12
        text: "左右 " + root.effPrevDxText()
      }
      W.ButtonContent {
        text: "→"
        Layout.preferredWidth: 36
        Layout.maximumWidth: 36
        Layout.minimumWidth: 36
        enabled: root.selectedKey !== ""
        onClicked: root.prevStep("dx", true)
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.prevStep("dx", true)
        }
      }
      W.ButtonContent {
        text: "↑"
        Layout.preferredWidth: 36
        Layout.maximumWidth: 36
        Layout.minimumWidth: 36
        enabled: root.selectedKey !== ""
        onClicked: root.prevStep("dy", true)
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.prevStep("dy", true)
        }
      }
      Text {
        Layout.preferredWidth: 64
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 12
        text: "上下 " + root.effPrevDyText()
      }
      W.ButtonContent {
        text: "↓"
        Layout.preferredWidth: 36
        Layout.maximumWidth: 36
        Layout.minimumWidth: 36
        enabled: root.selectedKey !== ""
        onClicked: root.prevStep("dy", false)
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.prevStep("dy", false)
        }
      }
      W.ButtonContent {
        text: "重置"
        Layout.preferredWidth: 56
        Layout.maximumWidth: 56
        Layout.minimumWidth: 56
        enabled: root.selectedKey !== ""
        onClicked: root.prevReset()
      }
      Item { Layout.fillWidth: true }
    }

    // ---- 二期：取景微调（针对当前选中的这张皮肤，存进我们自己的表）----
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: "取景"
        color: "#E4D5A0"
        font.pixelSize: 14
        Layout.minimumWidth: 0
      }
      W.ButtonContent {
        text: "−"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.tuneStep("mul", false)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.tuneStep("mul", false)
        }
      }
      Text {
        Layout.preferredWidth: 74
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "大小 " + root.effMulText()
      }
      W.ButtonContent {
        text: "＋"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.tuneStep("mul", true)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.tuneStep("mul", true)
        }
      }
      W.ButtonContent {
        text: "←"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.tuneStep("dx", false)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.tuneStep("dx", false)
        }
      }
      Text {
        Layout.preferredWidth: 80
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "左右 " + root.effDxText()
      }
      W.ButtonContent {
        text: "→"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.tuneStep("dx", true)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.tuneStep("dx", true)
        }
      }
      W.ButtonContent {
        text: "↑"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.tuneStep("dy", false)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.tuneStep("dy", false)
        }
      }
      Text {
        Layout.preferredWidth: 80
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "上下 " + root.effDyText()
      }
      W.ButtonContent {
        text: "↓"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.tuneStep("dy", true)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.tuneStep("dy", true)
        }
      }
      W.ButtonContent {
        text: "重置"
        Layout.preferredWidth: 70
        Layout.maximumWidth: 70
        Layout.minimumWidth: 70
        enabled: root.selectedKey !== ""
        onClicked: root.tuneReset()
      }
      Item { Layout.fillWidth: true }
    }

    // ---- 三期：场上大动画的取景（技能 / 伤害牌）----
    //
    // 单开一行（不跟「取景」挤一起 ✓），并且每个按钮**三样宽度都锁死** ✓
    // —— 上次就是因为只写了 preferredWidth，`ButtonContent` 那约 100px 的
    //    隐式宽度把整排顶出了弹窗 ✗（见踩坑记录第 18 条）
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: "场上动画"
        color: "#E4D5A0"
        font.pixelSize: 14
        Layout.minimumWidth: 0
      }
      W.ButtonContent {
        text: "−"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("mul", false)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("mul", false)
        }
      }
      Text {
        Layout.preferredWidth: 74
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "大小 " + root.effFieldMulText()
      }
      W.ButtonContent {
        text: "＋"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("mul", true)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("mul", true)
        }
      }
      W.ButtonContent {
        text: "←"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dx", false)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dx", false)
        }
      }
      Text {
        Layout.preferredWidth: 80
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "左右 " + root.effFieldDxText()
      }
      W.ButtonContent {
        text: "→"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dx", true)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dx", true)
        }
      }
      W.ButtonContent {
        text: "↑"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dy", false)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dy", false)
        }
      }
      Text {
        Layout.preferredWidth: 80
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "上下 " + root.effFieldDyText()
      }
      W.ButtonContent {
        text: "↓"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dy", true)
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dy", true)
        }
      }
      W.ButtonContent {
        text: "重置"
        Layout.preferredWidth: 70
        Layout.maximumWidth: 70
        Layout.minimumWidth: 70
        enabled: root.selectedKey !== ""
        onClicked: root.fieldReset()
      }
      Item { Layout.fillWidth: true }
    }
    // ---- 三期补：出场动画的取景（每局入场时 ✓）----
    //
    // 单开一行（不跟「取景」挤一起 ✓），并且每个按钮**三样宽度都锁死** ✓
    // —— 上次就是因为只写了 preferredWidth，`ButtonContent` 那约 100px 的
    //    隐式宽度把整排顶出了弹窗 ✗（见踩坑记录第 18 条）
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: "出场动画"
        color: "#E4D5A0"
        font.pixelSize: 14
        Layout.minimumWidth: 0
      }
      W.ButtonContent {
        text: "−"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("mul", false, "#enter")
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("mul", false, "#enter")
        }
      }
      Text {
        Layout.preferredWidth: 74
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "大小 " + root.effFieldMulText("#enter")
      }
      W.ButtonContent {
        text: "＋"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("mul", true, "#enter")
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("mul", true, "#enter")
        }
      }
      W.ButtonContent {
        text: "←"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dx", false, "#enter")
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dx", false, "#enter")
        }
      }
      Text {
        Layout.preferredWidth: 80
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "左右 " + root.effFieldDxText("#enter")
      }
      W.ButtonContent {
        text: "→"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dx", true, "#enter")
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dx", true, "#enter")
        }
      }
      W.ButtonContent {
        text: "↑"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dy", false, "#enter")
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dy", false, "#enter")
        }
      }
      Text {
        Layout.preferredWidth: 80
        horizontalAlignment: Text.AlignHCenter
        color: "white"; font.pixelSize: 13
        text: "上下 " + root.effFieldDyText("#enter")
      }
      W.ButtonContent {
        text: "↓"
        Layout.preferredWidth: 46
        Layout.maximumWidth: 46
        Layout.minimumWidth: 46
        enabled: root.selectedKey !== ""
        onClicked: root.fieldStep("dy", true, "#enter")
        // 按住不放就连发 ✓（计时器只在按住时跑；轻点则恰好一次 ✓）
        Timer {
          interval: 110
          repeat: true
          running: parent ? (parent.down === true) : false
          onTriggered: root.fieldStep("dy", true, "#enter")
        }
      }
      W.ButtonContent {
        text: "重置"
        Layout.preferredWidth: 70
        Layout.maximumWidth: 70
        Layout.minimumWidth: 70
        enabled: root.selectedKey !== ""
        onClicked: root.fieldReset("#enter")
      }
      Item { Layout.fillWidth: true }
    }

    // ---- 底部 ----
    RowLayout {
      Layout.fillWidth: true
      spacing: 12
      Text {
        Layout.fillWidth: true
        // ⚠ 允许收缩到 0：不然这行文字自己的隐式宽度会参与布局，
        //   把右边那几个按钮顶出弹窗 ✗（实测被顶出去过）
        Layout.minimumWidth: 0
        elide: Text.ElideRight
        color: root.status !== "" ? "#9FD8A8" : "#CFCFCF"
        font.pixelSize: 13
        text: root.status !== ""
          ? root.status
          : (model.length === 0
             ? "没有可用的骨骼皮肤"
             : "选中后点「换上」——对局中立即生效")
      }
      // 三期：试播场上大动画。
      // 做成**按钮**而不是只靠热键 —— 热键会被核心占用（实测 Ctrl+F 是核心的
      // "全屏切换"，我的热键被它吃掉，日志里一行都没有 ✗）。按钮不会冲突 ✓
      W.ButtonContent {
        text: "试播出场"
        Layout.preferredWidth: 120
        Layout.maximumWidth: 120
        Layout.minimumWidth: 120
        enabled: root.selectedKey !== ""
        onClicked: root.enterRequested()
      }
      W.ButtonContent {
        text: "试播大动画"
        Layout.preferredWidth: 140
        Layout.maximumWidth: 140
        Layout.minimumWidth: 140
        enabled: root.selectedKey !== ""
        onClicked: root.fieldRequested()
      }
      W.ButtonContent {
        text: "换上"
        Layout.preferredWidth: 120
        Layout.maximumWidth: 120
        Layout.minimumWidth: 120
        // 大厅里没有"当前武将"，所以只要选了皮肤就能点（武将取这张皮肤声明的那些）
        enabled: root.selectedKey !== ""
        onClicked: {
          var d = root.defOf(root.selectedKey)
          if (!d) return
          // ⚠ **要写进这张皮肤声明的每一个武将 id**，而且**必须带上 `root.general`**：
          //   * 清单里的 generals（postLoad 已用 Fk.same_generals 展开）
          //   * 当前这个武将 id —— 对局里它就是**场上那个变体 id**
          //     （ty_heg__lvlingqi 之类），而头像层读存档用的正是这个 id ✗
          //   只写基础 id 的话，症状是"界面显示已换上，进对局纹丝不动" ✗
          var gens = (d.generals || []).slice()
          if (root.general !== "" && gens.indexOf(root.general) < 0) {
            gens.push(root.general)
          }
          if (gens.length === 0) return
          for (var i = 0; i < gens.length; i++) Store.set(Cpp, gens[i], root.selectedKey)
          root.status = "已换上「" + (d.name || root.selectedKey)
            + "」（写了 " + gens.length + " 个武将 id）"
        }
      }
    }
  }

  /// 自己是不是**在大厅里**（= 往上找不到 `SkelHost`）✓
  ///
  ///   ★★★ 这个判断是**防崩的关键** ✗✗✗
  ///
  ///   崩因链（追踪日志 + 原文对照得到 ✓）：
  ///     ① 对局界面**也会构造** `SkelPicker`（它是 `SkelHost` 的子对象 ✓）
  ///     ② 而下面那段 `Component.onCompleted` 是给**大厅入口**写的 ✗
  ///        —— 它在对局里**也跑了** → `open("")` → `visible = true`、
  ///        `selectedKey` 变成"清单第一套"（按名字排 = `luyi_shuli` ✓）
  ///     ③ → 预览骨架在**"对局启动中"**就被建出来
  ///        → `FreeKill.exe 0xc0000005 @ 0x895e0`（追踪日志实录 ✓）
  ///
  ///   证据：追踪日志里预览骨架出现在 `[GameStart]` 之后、
  ///     `清单已就绪` 之前，而且**从来没有** `建 SkelAvatar[宿主]` ✓
  ///     （宿主那时 `myDef` 还是 null ✓）
  ///   而且当时的原文（`tests/snapshots/orig_PICKER_QML.txt`）
  ///     **没有**这段 `Component.onCompleted` —— 又是后来加的 ✓
  ///
  ///   ⇒ 大厅才做全量初始化；**对局里什么都不做**，等用户按 Ctrl+J ✓
  function inLobby() {
    var n = root.parent
    for (var i = 0; i < 14 && n; i++) {
      try {
        if (n.myDef !== undefined && n.skins !== undefined) return false   // 找到宿主 → 对局
      } catch (e) { /* 不是它 */ }
      n = n.parent
    }
    return true
  }

  // 大厅「更多」里打开这个页面时，open() 不会被调用 —— 自己初始化成全量列表，
  // 否则用户看到的是一句"没有可用的骨骼皮肤" ✗
  //
  // ⚠ 但**对局里绝对不能这么做**（见上面 `inLobby()` 的说明）✗✗
  Component.onCompleted: {
    if (!root.inLobby()) return      // ★ 对局里：交给 Ctrl+J / 按钮 ✓
    // ⚠ 大厅里没有 SkelHost，注入得自己做（见 SkelStore.js 顶部说明）
    Store.init(Cpp, Lua)
    root.open("")
  }

  Shortcut {
    sequence: "Esc"
    enabled: root.visible
    onActivated: { root.visible = false; root.closed() }
  }
}
