// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelAvatar —— **独立**的骨骼皮肤头像渲染（一期核心）
//
// 和官方那套的区别（每一处都是踩过的坑）：
//   * 官方：`SkinArea` + `SkinMedia`（= OpacityMask）→ 重骨架必崩；
//     我们：`import Spine` + `SkeletonAnimation`，**没有任何遮罩**，直接吃文件。
//   * 官方：一次给十几个格子各建一套骨架 → 崩；
//     我们：**一次只有这一处**（bg + body 两层）。
//   * 官方：皮肤要通过注册表解析；
//     我们：路径自己拼（`packages/fk-skel/skins/<key>/image/skins/<名字>.atlas`）。
//
// 缩放沿用官方那条公式的量纲：`骨架单位 x (skinScale x frameH / 175)`
//   —— 175 是设计基准，frameH 是官方那个"画面高"（默认 664）。
//   这样默认观感就和官方一致；要微调是二期"取景"的事。
//
// 定位假设（和 FieldAnim 一致）：骨架原点在画面中央 —— 这类手杀导出都是居中的。

import QtQuick
import Spine

Item {
  id: root

  // ★ 身份标签（诊断用：同一时刻可能有**两处** SkelAvatar 实例 ——
  //     宿主一份、换肤面板预览一份 ✓）
  //   ⚠⚠ **这个属性必须存在** ✗✗ —— `SkelPicker` 里写了 `who: "面板预览"`，
  //     而 QML 遇到"给不存在的属性赋值"会**整个组件加载失败**：
  //       `Cannot assign to non-existent property "who"`
  //       → `Type SkelPicker unavailable`
  //       → `SkelHost` 整页失效（对局界面什么都不画，只剩背景）✗
  //     （实测踩到过：恢复文件时配对错了版本 ✓）
  property string who: "?"

  property string rootPath: ""          // 皮肤目录（绝对路径，不含文件名）
  property string bgName: ""            // 背景骨架名（可空）
  property string bodyName: ""          // 人物骨架名（必填）
  property real bgScale: 0.12
  property real bodyScale: 0.12
  property string bgIdle: "play"
  property string bodyIdle: "play"
  // ★★ "头像框内的入场动画"（骨架**自带**、**不循环**的那种 ✓）
  //
  //   为什么需要它（用户指出 ✓）：有两类骨骼皮肤，出场动画在不同地方 ——
  //     ① 有独立 `chuchang.skel` 的（张春华、张琪瑛、吕玲绮 …）
  //        出场动画在自己的骨架里 → 走 `SkelHost.playField("field_enter")`
  //        在**场上**播 ✓（那是对的 ✓）
  //     ② 只有 `XingXiang.skel` 的（**马云騄、清河公主**）
  //        出场动画 `ChuChang` **就在头像骨架里自带** ✓
  //        → 应该**在人物框内播**，播完**衔接待机**（`DaiJi`）✓
  //        → 但当时代码**没有这条机制** ✗
  //          （骨架是同一个，所以看着像在框里，其实是场上那层 ✓）
  //
  //   ⚠ 留空 = 不播入场，直接待机（默认 ✓）
  //     其它皮肤的 `body_shown` 和待机相同 → 传进来也不触发 ✓
  property string bgEnter: ""
  property string bodyEnter: ""
  /// 本轮的入场动画是否已经播过（每建一次骨架只播一次 ✓）
  property bool enterPlayed: false
  /// 入场动画是什么时候开始的（毫秒；用于"超时兜底" ✓）
  ///   ⚠ 为什么要它：`isPlaying()` 对"**不循环且已播完**"的动画
  ///     在本实现里**可能一直返回 true** ✗（原注释就说它"首帧之前不可靠"）
  ///     → 只靠它判断"播完没"会**永远卡在入场** ✗（实测：停在结束帧 ✓）
  property double enterStartMs: 0
  /// 入场超时时长（毫秒）—— **纯兜底**，正常不会走到 ✓
  property int enterTimeoutMs: 20000
  /// 上一次"重置入场状态"时用的骨架标识（`rootPath + bodyName` ✓）
  ///   ⚠ 为什么需要：`bodyIdle` 的默认值就是 `"play"`，
  ///     组件刚建好时**就会触发一次 `onBodyNameChanged`** ✗
  ///     如果在那里无脑重置 `enterStartMs`，**超时计时起点会被反复清零** →
  ///     超时永远追不上 → 入场播完**停在结束帧** ✗（实测 ✓）
  ///   ⇒ 只有"骨架标识**真的变了**"才重置 ✓
  property string enterId: ""
  /// ★★ 入场阶段：0=未开始 / 1=入场中（等 `complete` 信号）/ 2=已完成 ✓
  ///
  ///   为什么用"信号"而不是轮询 `isPlaying()`（实测 ✓）：
  ///     * 日志：`isPlaying **一直为真**`（到 12 秒超时都没变假 ✗）
  ///     * API 枚举（132 个成员）：`animationDuration`/`skeleton`/`currentAnimation`
  ///       全 **undefined** ✗，**但有 `complete`** —— Spine 的**动画完成信号** ✓
  ///     * `SkelField.qml` **已在用它**（"一次性动画播完 → 淡出"）✓
  ///       `Connections { target: skel; function onComplete(trackIndex, loopCount) }`
  ///   ⇒ 轮询最快也只能等超时 → 用户看到"播完停住一段才切" ✗
  ///     信号则是**一播完立刻**触发 → 无缝衔接 ✓
  property int enterPhase: 0
  property real frameH: 664             // 官方"画面高"基准
  property bool debug: false

  // ── 二期：取景微调 ──
  //   语义照抄当时钩子里的做法：**mul 相乘、dx/dy 相加**（mul 是倍率，dx/dy 是比例）
  //   mul 作用在缩放上，dx/dy 作用在骨架原点的位置上（按画布宽/高的比例）
  property real faceMul: 1
  property real faceDx: 0
  property real faceDy: 0

  // ── ★ 预览专用变换（只影响"换肤面板左边那个预览框"，**不动对局取景** ✓）──
  //
  //   为什么需要独立一组（用户诉求 ✓）：
  //     预览原来用 `faceMul/Dx/Dy`（作者默认值），而面板上的微调写的是
  //     `<皮肤>` 那份（= **对局取景**）→ **调整完全不反映在预览里** ✗
  //     而用户想调的是"**预览框里看着满意**"，不应该牵动对局 ✓
  //   ⇒ 这组值由面板写进独立存档键 `<皮肤>#preview` ✓
  //     语义和 face* 一致（**mul 相乘、dx/dy 相加** ✓）
  property real prevMul: 1
  property real prevDx: 0
  property real prevDy: 0

  // ★★ Spine 运行时版本（**绕过 Auto 探测** ✓）★★
  //
  //   为什么需要（实测 ✓）：
  //     核心只设 `SpineVersion.Auto`，而 `Auto` **读不出 JSON 骨架的版本**
  //     → 日志报 `version: "unknown"` → 后台加载失败 → 预览空白 ✗
  //     而 FreeKill 编译了 9 套运行时（含 **spine-c-40**，且有 `SkeletonJson.c` ✓）
  //   ⇒ 皮肤配置里显式给版本，就能加载 **JSON 格式 / 非 Auto 版本**的素材 ✓
  //
  //   取值（整数，和 C++ 枚举一致）：0=Auto（默认 ✓，等价现状）
  //     36=V36  37=V37  38=V38  **40=V40**  41=V41  42=V42
  //   ⚠ 属性名是 **spineVersion**（小写 s 开头 ✓）—— QML 属性名首字母不能大写 ✗
  //     `SpineVersion` 那个是**枚举类型名**，两者不是一个东西 ✓
  property int spineVersion: SpineVersion.Auto

  // ★★ 合成值：`face*`（对局取景 / 作者默认）× `prev*`（预览微调）★★
  //
  //   语义和取景完全一致：**mul 相乘、dx/dy 相加** ✓
  //   这样"预览里调出来的画面"= "对局头像 + 同一组数"的真实效果 ✓
  //   （宿主只传 `face*`、`prev*` 恒为 1/0/0 → 对局不受影响 ✓）
  readonly property real faceMulK: faceMul * prevMul
  readonly property real faceDxT: faceDx + prevDx
  readonly property real faceDyT: faceDy + prevDy

  readonly property real baseScale: frameH / 175

  // ── 自动适配（预览用）──
  //
  // 为什么需要：三套皮肤的**骨架画布尺寸差很多**（daiji2 419x454 / daiji 1564x1352 /
  // XingXiang 2163x2096 …），用一个固定的 frameH 当基准，必然有的框里内容偏小留黑边 ✗
  //
  // 做法：让骨架画布**正好落进本框** ——
  //   缩放 = min(框宽 / 画布宽, 框高 / 画布高)
  //   取 min 保证两个方向都不裁 ✓；骨架原点是画布中心 ✓，
  //   所以 `x/y` 摆在框中心就是"位置正确" ✓
  //
  // `sourceSize` 是**异步**来的 → 这里写成绑定，它一到位就自动重算 ✓
  // （和场上动画那边同一个道理）
  property bool fitToBox: false

  // 实际画面边界（离线用 tests/spine_bounds.js 量的，写在清单里 ✓）
  //
  // ⚠ 为什么不用 `body.sourceSize`：它报的是**画布范围**（可能含大量空白）✗ ——
  //   实测战场绝版的 daiji 报 3488x2032，而实际画面只有 1457x1285 →
  //   按它适配会把画面缩成一小块 ✗（这个坑真踩过）
  property real fitW: 0
  property real fitH: 0
  property real fitCx: 0
  property real fitCy: 0

  // 背景层的实测边界（可选）。给了就让背景**铺满**（max，允许裁多余部分 ✓）
  property real bgFitW: 0
  property real bgFitH: 0
  property real bgFitCx: 0
  property real bgFitCy: 0

  // 整体边界（背景∪人物）：把两层当**一个整体**缩放，
  //   —— 相对构图原样保留 ✓，整体铺满预览框 ✓（用户提的做法，比各自适配干净）
  property real compW: 0
  property real compH: 0
  property real compCx: 0
  property real compCy: 0

  /// 整体缩放：`max` = 铺满（允许裁掉整体边缘的多余部分 ✓）
  ///   再乘安全余量：我们量的边界是**附件四边形**（不看像素 ✗），
  ///   背景图里常有透明区 → 四边形到边了、不透明像素还没到 ✗
  readonly property real fitMargin: 1.15

  readonly property real fitK: (fitToBox && compW > 0 && compH > 0
      && root.width > 0 && root.height > 0)
    ? (Math.max(root.width / compW, root.height / compH) * fitMargin)
    : -1

  /// 人物：**按宽度铺满**（"立绘式"取景）——
  ///   用户要求：可以裁掉一部分人物，但**必须露脸** ✓，而且人物大一些更好看 ✓
  ///   做法：宽度正好铺满（人物变大 ✓），**上边缘对齐框顶**（头/脸必定在框里 ✓），
  ///         多出来的从**底部**裁（脚/裙摆，立绘最自然的裁法 ✓）
  ///   若铺满后高度还不够（人物偏宽）→ 底部那条由背景补（bgCoverK 兜底 ✓）
  readonly property real fitBodyK: (fitToBox && fitW > 0 && root.width > 0)
    ? (root.width / fitW)
    : -1

  /// 立绘式取景时顶部留白（免得头发正好顶到边 ✓）
  readonly property real fitTopMargin: 6

  ///
  /// ⚠ 为什么背景要单独兜一层：有的皮肤**背景骨架比人物还小** ✗
  ///   （实测战场绝版：背景 1380x937 vs 人物 1454x1293）
  ///   → 整体铺满时背景够不到上下边 → 留黑边 ✗
  ///   冰魄映雪相反（背景比人物大）→ 本来就没问题 ✓
  ///   所以取 `max(整体缩放, 背景铺满)`：
  ///     背景够大 → 跟整体走（保持构图 ✓）
  ///     背景不够 → 单独放大到铺满（消黑边 ✓）
  readonly property real bgCoverK: (fitToBox && bgFitW > 0 && bgFitH > 0
      && root.width > 0 && root.height > 0)
    ? (Math.max(root.width / bgFitW, root.height / bgFitH) * fitMargin)
    : -1

  /// 背景：**铺满**（max，允许裁掉多余部分 ✓）——
  ///   只靠人物做不到"没有黑边"（人物必须完整，必然留空 ✗），
  ///   背景铺满之后黑边就没了 ✓
  ///
  /// ⚠ 再乘一个**安全余量** ——
  ///   我们量的"边界"是**附件四边形**的范围（`getBounds` 只看形状、不看像素 ✗），
  ///   而背景图里往往有大片透明区域 → 四边形到边了、不透明像素还没到 ✗
  ///   实测症状正是如此：背景"按量到的尺寸铺满"后，底部仍留一条黑 ✓
  ///   这个余量就是补这个差。觉得裁太多/太少，只改这一个数 ✓
  readonly property real fitBgMargin: 1.15

  readonly property real fitBgK: (fitToBox && bgFitW > 0 && bgFitH > 0
      && root.width > 0 && root.height > 0)
    ? (Math.max(root.width / bgFitW, root.height / bgFitH) * fitBgMargin)
    : -1

  /// 最终缩放：
  ///   * fitToBox（预览）→ 正好填满本框，**不叠取景微调**（取景改的是对局人物框 ✓）
  ///   * 否则（对局头像层）→ 官方那套 作者scale × frameH/175，**再乘取景倍率** ✓
  readonly property real effBodyScale: fitK > 0 ? fitK : (bodyScale * baseScale * faceMulK)
  /// 背景：跟随整体缩放；**但至少铺满**（背景比人物小时单独放大，消黑边 ✓）
  readonly property real effBgScale: fitK > 0
    ? Math.max(fitK, (bgCoverK > 0 ? bgCoverK : fitK))
    : (bgScale * baseScale * faceMulK)

  visible: rootPath !== "" && bodyName !== ""

  function fileOf(name, ext) {
    // ⚠ rootPath 为空时（切换皮肤的那一瞬间）**必须返回空串** ✗ ——
    //   否则会拼成 "/daiji2.atlas" 这种不存在的绝对路径 ✓
    //   → 日志里会留下一条吓人的 "加载骨架失败" ✗（其实无害且会自愈 ✓）
    if (root.rootPath === "") return ""
    return root.rootPath + "/" + name + "." + ext
  }

  function log(msg) {
    if (root.debug) console.warn("[fk-skel/avatar] " + msg)
  }

  // ---- 画布：**必须开 layer** ----
  //
  // 核心 SkinArea.qml:215 的原话：
  //   "QSGRenderNode 直接内联绘制时父级 clip / OpacityMask 对它不生效，需用 layer
  //    离屏成纹理。但 layer 默认按'逻辑尺寸'采样（不乘 DPR、也不超采样），
  //    在高分屏/放大显示时骨骼会糊；因此手动把 textureSize 设为逻辑尺寸的 2 倍做超采样。"
  //
  // 也就是说：没有这一层 layer，外面那个 `clip: true` 的头像框**根本裁不住骨架** ✗
  // ——骨架会以完整尺寸画出来（就是 FieldAnim 警告过的"巨型遮挡"那种）。
  Item {
    id: canvas
    anchors.fill: parent
    // ⚠⚠ 这里**不能**套 `prev*` 变换 ✗✗（第一版做错了，用户指出 ✓）
    //   套在画布外面 = 把**渲染结果**放大挪走（预览图被放大、还留空边），
    //   那**不是取景** ✗
    //   ⇒ `prev*` 必须叠进**骨架的缩放与定位**（见下面 `faceMulK/faceDxT/faceDyT`）✓
    layer.enabled: true
    layer.textureSize: Qt.size(width * 2, height * 2)   // 2 倍超采样，画面才锐

    // ---- 背景层（可选）----
    SkeletonAnimation {
      id: bg
      visible: root.bgName !== ""
      // ⚠ 定位照核心：x/y 是**骨架原点**的位置，不是"居中一个框"。
      //   核心是 `root.width * bgXOffset`（0.5 = 画面中心），这里画面就是画布本身。
      //   二期微调：dx/dy 是加在这个比例上的（0.1 = 挪动画布宽/高的 10%）
      // 背景按**它自己的**中心偏移摆 —— 因为它可能被单独放大到铺满（见 effBgScale）
      //   （用整体中心会让放大后的背景边界偏出去 ✗）
      x: (root.fitK > 0 && root.bgFitW > 0)
        ? (canvas.width / 2 - root.bgFitCx * root.effBgScale)
        : (canvas.width * (0.5 + root.faceDxT))
      y: (root.fitK > 0 && root.bgFitW > 0)
        ? (canvas.height / 2 - root.bgFitCy * root.effBgScale)
        : (canvas.height * (0.5 + root.faceDyT))
      atlasFile: root.bgName !== "" ? root.fileOf(root.bgName, "atlas") : ""
      skeletonDataFile: root.bgName !== "" ? root.fileOf(root.bgName, "skel") : ""
      spineVersion: root.spineVersion
    premultipliedAlapha: false
      scale: root.effBgScale
    }

    // ---- 人物层 ----
    SkeletonAnimation {
      id: body
      visible: root.bodyName !== ""
      // 立绘式取景：水平居中，**上边缘贴框顶**（脸必定在框里 ✓），多出的从底部裁 ✓
      //   `fitCy - fitH/2` = 人物边界的上边缘（相对骨架原点）✓
      x: root.fitBodyK > 0
        ? (canvas.width / 2 - root.fitCx * root.fitBodyK)
        : (canvas.width * (0.5 + root.faceDxT))
      y: root.fitBodyK > 0
        ? (root.fitTopMargin - (root.fitCy - root.fitH / 2) * root.fitBodyK)
        : (canvas.height * (0.5 + root.faceDyT))
      atlasFile: root.bodyName !== "" ? root.fileOf(root.bodyName, "atlas") : ""
      skeletonDataFile: root.bodyName !== "" ? root.fileOf(root.bodyName, "skel") : ""
      spineVersion: root.spineVersion
    premultipliedAlapha: false
      scale: root.fitBodyK > 0 ? root.fitBodyK : root.effBodyScale
    }
  }

  // 待机动画：`isPlaying()` 在首帧之前不可靠，所以定时重试几次（FieldAnim 的经验）。
  Timer {
    id: idleRetry
    interval: 250
    repeat: true
    running: root.visible
    property int left: 400
    /// 收到 `complete` 信号后调它 —— **立刻**设待机（不等下一轮 ✓）
    function enterDone() {
      if (root.bgName !== "" && root.bgIdle !== "") bg.setAnimation(0, root.bgIdle, true)
      if (root.bodyName !== "" && root.bodyIdle !== "") body.setAnimation(0, root.bodyIdle, true)
      console.warn("[fk-skel] 人物待机 " + root.bodyIdle
        + "（背景待机 " + root.bgIdle + "）—— 信号驱动 ✓")
      running = false      // 已切好，不用再重试 ✓
    }
    onTriggered: {
      if (left <= 0) { running = false; return }
      left--
      try {
        // ── 第一步：**入场动画**（骨架自带、不循环 ✓）──
        //   ★★ 关键：**没有入场动画时，绝不能进"入场中"阶段** ✗✗✗
        //
        //   为什么（实测踩到 ✓）：原来无脑 `enterPhase = 1`，
        //   然后去等 `complete` 信号 —— 可**根本没播任何动画**，
        //   信号永远不会来 → **永远到不了待机** →
        //   **所有没入场动画的皮肤都变成静态图** ✗
        //   （日志：`开始入场：bg=（无） body=（无）` 之后就没有下文 ✓）
        //   ⇒ 没有入场名 → **直接算"已完成"**，落到下面的待机 ✓
        if (root.enterPhase === 0 && root.bgEnter === "" && root.bodyEnter === "") {
          root.enterPhase = 2          // 没有入场 → 直接完成 ✓
        }
        if (root.enterPhase < 2) {
          var nowMs = Date.now()
          if (root.enterPhase === 0) {
            root.enterPhase = 1
            root.enterStartMs = nowMs
            console.warn("[fk-skel] 开始入场：bg=" + (root.bgEnter || "（无）")
              + " body=" + (root.bodyEnter || "（无）")
              + "（等 `complete` 信号 ✓ 超时兜底=" + root.enterTimeoutMs + "ms）")
            if (root.bgEnter !== "") {
              bg.setAnimation(0, root.bgEnter, false)
              console.warn("[fk-skel] 背景入场 " + root.bgEnter)
            }
            if (root.bodyEnter !== "") {
              body.setAnimation(0, root.bodyEnter, false)
              console.warn("[fk-skel] 人物入场 " + root.bodyEnter)
            }
          }
          // 纯兜底：`complete` 信号万一不来 ✓
          if ((nowMs - root.enterStartMs) >= root.enterTimeoutMs) {
            root.enterPhase = 2
            console.warn("[fk-skel] 入场：**超时兜底**（`complete` 一直没来 ✗）等了 "
              + Math.round(nowMs - root.enterStartMs) + "ms")
          } else {
            return          // ⚠ 入场期间不碰待机，等信号 ✓
          }
        }
        // ── 第二步：待机（循环 ✓）──
        //   ⚠ `isPlaying()` 在这里也可能不可靠（不循环动画刚切过来时）
        //     → 用 `enterPlayed` 这个**我们自己的状态**做闸，更稳 ✓
        if (root.bgName !== "" && root.bgIdle !== "") {
          bg.setAnimation(0, root.bgIdle, true)
        }
        if (root.bodyName !== "" && root.bodyIdle !== "") {
          body.setAnimation(0, root.bodyIdle, true)
        }
        console.warn("[fk-skel] 人物待机 " + root.bodyIdle
          + "（背景待机 " + root.bgIdle + "）")
        idleRetry.running = false        // 待机已设好 → 不用再重试 ✓
      } catch (e) {
        console.warn("[fk-skel] 设动画失败: " + e)
      }
    }
  }

  // ★★★ 入场动画**播完的信号** → **立刻**切待机 ✓（不轮询 ✗）
  //   参考 `SkelField.qml`（"一次性动画播完 → 淡出" ✓ 已验证可用）
  //   ⚠ 循环动画（`setAnimation(..., true)`）**不会**发 `complete` ✓
  //     所以这里只在"入场那种不循环动画"播完时触发 ✓
  Connections {
    target: body
    function onComplete(trackIndex, loopCount) {
      if (root.enterPhase !== 1) return        // 不在入场中 → 不管 ✓
      root.enterPhase = 2
      console.warn("[fk-skel] 人物入场**播完的信号**到了 → 立刻转待机 ✓"
        + "（入场用了 " + Math.round(Date.now() - root.enterStartMs) + "ms）")
      idleRetry.enterDone()
    }
  }
  Connections {
    target: bg
    function onComplete(trackIndex, loopCount) {
      if (root.enterPhase !== 1) return
      root.enterPhase = 2
      console.warn("[fk-skel] 背景入场**播完的信号**到了 → 立刻转待机 ✓")
      idleRetry.enterDone()
    }
  }

  // 换了骨架就重新起一轮"待机动画"重试。
  // ⚠ 必须写 `idleRetry.left`，不能写裸的 `left`：
  //   `left` 是**上面那个 Timer 的属性**，不是本组件的属性；QML 的作用域解析
  //   不会把子对象的属性带进本组件 → 裸写会抛 ReferenceError，而且
  //   **同一段处理函数里剩下的语句会被一起中断**（`restart()` 就不会执行）✗
  /// 骨架变了才重置"入场状态" ✓
  ///   ⚠ 不能只看 `onBodyNameChanged`：`bodyIdle` 的默认值 `"play"` 会让它
  ///     在组件刚建好时就触发一次，把超时计时起点清零 ✗
  ///   ⇒ 用 **骨架标识**（`rootPath + bodyName`）判断"是不是真的换了骨架" ✓
  function syncEnterState() {
    var id = "" + root.rootPath + "|" + root.bodyName
    if (id === root.enterId) return        // 还是同一套骨架 → 不重置 ✓
    root.enterId = id
    root.enterPlayed = false
    root.enterPhase = 0
    root.enterStartMs = 0
    idleRetry.left = 400          // 400×250ms = 100s（远超 12s 超时 ✓）
    idleRetry.restart()
    console.warn("[fk-skel/avatar] 骨架变了 → 重置入场状态（" + root.who + "）")
  }

  onRootPathChanged: root.syncEnterState()
  onBodyNameChanged: root.syncEnterState()
  Component.onCompleted: root.syncEnterState()
}
