// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelField —— 场上的骨骼大动画（三期）
//
// 这份组件是从当时**验证可用**的那份 FieldAnim 原样搬过来的 ✓
// （场上铺满、按高度比例缩放、播完淡出自销毁；当年技能/伤害牌触发时没崩过）
// 只改了两处：
//   1. 宿主：不再由当年的钩子动态创建，改由 SkelHost.playField() 创建（挂在 SkelHost 上）；
//   2. 名字：FieldAnim → SkelField。
//
// 用法（SkelHost.playField）：
//   Qt.createComponent(...SkelField.qml) 然后 createObject(host, {...})
//   —— 它是**自启动**的（内部重试计时器 running: true），播完自己 destroy() ✓
//   srcW/srcH 传 0 让它用骨架自己报的 sourceSize：
//   本包三套皮肤的场上骨架坐标系各不相同，写死尺寸会让缩放错掉 ✗
//
import QtQuick
import Spine

Item {
  id: root

  anchors.fill: parent
  z: 998                      // 与核心 bigAnim(999) 同层，但不抢弹窗

  property string atlasFile: ""
  property string skelFile: ""

  // ★ Spine 运行时版本（0=Auto ✓）—— 见 SkelAvatar.qml 的说明
  property int spineVersion: SpineVersion.Auto
  property string animName: ""
  property string idleName: ""

  /// 骨架画面高度占页面高度的比例
  property real heightRatio: 0.5
  /// 骨架自身的单位尺寸（由 SkinAnimHook 从头像框里的实例读出来传进来；
  /// 拿不到时再退回 SkeletonAnimation.sourceSize，两者都没有就干脆不播 ——
  /// 绝不能用"兜底缩放"，那会把 8518 单位的画面放大成三万像素宽的巨型遮挡）
  property real srcW: 0
  property real srcH: 0
  /// 画面中心要对准的位置（页面坐标）
  property real centerX: width / 2
  property real centerY: height / 2
  property real offsetX: 0
  property real offsetY: 0
  /// 背景压暗程度（0 = 不压）
  property real maskOpacity: 0
  property int fadeMs: 350

  property bool started: false
  property bool done: false

  signal finished()

  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: root.maskOpacity
    visible: opacity > 0.001
  }

  SkeletonAnimation {
    id: skel
    atlasFile: root.atlasFile
    skeletonDataFile: root.skelFile
    spineVersion: root.spineVersion
      premultipliedAlapha: false
    visible: false
  }

  // 独立重试：isPlaying() 在首帧更新前不可靠，每隔 250ms 再挑一次，直到成功
  Timer {
    id: animRetry
    interval: 250
    repeat: true
    running: true
    property int left: 12
    onTriggered: {
      if (root.animDone) {
        stop();
        return;
      }
      left = left - 1;
      if (left <= 0) {
        stop();
        console.warn("[fk-skel/field] 场上骨架始终挑不到动画名，放弃（显示初始姿势）");
        return;
      }
      root.beginAnim();
    }
  }
  Connections {
    target: skel
    // 骨架是异步加载的：加载成功后如果还没摆好位置，就再算一次
    function onSkeletonLoadFinished(ok) {
      if (!root.started) return;
      if (ok) root.beginAnim();          // 加载完成 -> 现在挑动画才有效
      if (!skel.visible && root.layout()) {
        skel.visible = true;
        safety.start();
      }
    }
    // 一次性动画播完 -> 淡出
    function onComplete(trackIndex, loopCount) {
      root.finish();
    }
  }

  NumberAnimation {
    id: fadeOut
    target: root
    property: "opacity"
    to: 0
    duration: root.fadeMs
    onStopped: {
      root.finished();
      root.destroy();
    }
  }

  Timer {
    id: safety
    interval: 9000
    repeat: false
    onTriggered: root.finish()
  }

  /// 场上骨架的动画名候选（逗号分隔，由皮肤 probe_anims 传入）。
  /// 现在只作**参考**：beginAnim 直接用配置里声明的名字播。
  property string probeList: ""

  // ⚠ 这里曾经有个 pickAnim()：用 clearTrack + 反复 setAnimation 去"探测"真名。
  //   已删除，原因有两条，别再写回来：
  //     1) 它是**破坏性**的：clearTrack 会销毁 Spine 的 track entry，
  //        C++ 侧若仍持有该指针，下一次 update 就是 use-after-free，
  //        崩在 Qt6Qml.dll、崩溃偏移固定（和 SkinAnimHook 里那段探测同一个坑）。
  //        而场上动画**每触发一次技能/伤害牌就跑一次**，等于反复踩。
  //     2) 它已经是死代码：beginAnim 早就不用探测结果了，直接播 animName；
  //        名字写错时 C++ 会报 `Animation is not found`，照日志改 skin.lua 即可。

  property bool animDone: false

  /// 骨架数据加载完成之后再挑动画；挑不到就 setToSetupPose，保证"看得见"
  function beginAnim() {
    if (animDone) return;
    // animDone 只在成功时置位（之前无条件锁定 -> 一次失败就永久没动画）
    const use = animName;   // 不再依赖探测结果（探测在首帧前不可靠，曾导致静止）
    if (use) {
      animDone = true;
      skel.setAnimation(0, use, false);
      if (idleName) skel.addAnimation(0, idleName, true);
    } else {
      console.warn("[fk-skel/field] 场上骨架没有任何可用动画名，恢复初始姿势显示（至少看得见）");
      try { AppUtil.showToast("场上骨架没有可用动画名（候选都不对）"); } catch (e) { }
      try {
        skel.setToSetupPose();
      } catch (e) {
      }
    }
  }

  function start() {
    if (started) return;
    if (atlasFile === "" || skelFile === "" || animName === "") {
      console.warn("[皮肤动画] 场上动画参数不全，跳过：" + atlasFile + " / " + skelFile + " / " + animName);
      root.finalize();
      return;
    }
    started = true;
    // 必须等骨架加载完成再挑动画：加载过程中探测必然全部失败
    if (true) {   // 总是先试一次：缓存命中时数据其实已就绪
      beginAnim();
    } else {
      console.warn("[fk-skel/field] 场上骨架未加载完，等加载完成后再挑动画");
    }
    // 先摆好位置再显示；尺寸拿不到就多试几次
    if (!layout()) {
      retry.left = 4;
      retry.start();
      return;
    }
    skel.visible = true;
    safety.start();
  }

  Timer {
    id: retry
    property int left: 4
    interval: 200
    repeat: true
    onTriggered: {
      root.beginAnim();   // isPlaying 需至少一帧更新后才可靠：借布局重试多次挑动画
      if (root.layout()) {
        skel.visible = true;
        safety.start();
        stop();
        return;
      }
      left = left - 1;
      if (left <= 0) {
        stop();
        console.warn("[皮肤动画] 场上动画拿不到骨架尺寸，放弃播放（避免出现巨型遮挡）");
        root.finalize();
      }
    }
  }

  /// 骨架单位尺寸：优先用外面传进来的，其次问 SkeletonAnimation 要
  function sourceSizeOf() {
    if (srcW > 0 && srcH > 0) return { w: srcW, h: srcH };
    try {
      const s = skel.sourceSize;
      if (!s || !(s.width > 0) || !(s.height > 0)) return null;
      if (!(s.width / s.height > 0.1 && s.width / s.height < 10)) return null;
      return { w: s.width, h: s.height };
    } catch (e) {
      return null;
    }
  }

  /// 按骨架真实尺寸缩放到 heightRatio × 页面高，并把画面中心对准 center。
  /// 返回 false 表示尺寸还没拿到，调用方应该重试或放弃。
  function layout() {
    const src = sourceSizeOf();
    if (!src) return false;
    skel.scale = (height * heightRatio) / src.h;
    skel.x = centerX + offsetX;
    skel.y = centerY + offsetY;
    console.warn("[皮肤动画] 场上动画 " + animName + " 缩放=" + skel.scale.toFixed(4)
      + " 骨架单位=" + Math.round(src.w) + "x" + Math.round(src.h)
      + " 高度占比=" + heightRatio.toFixed(3));
    return true;
  }

  function finish() {
    if (done) return;
    done = true;
    safety.stop();
    fadeOut.start();
  }

  /// 参数不全等异常情况：不淡出，直接收尾
  function finalize() {
    if (done) return;
    done = true;
    safety.stop();
    finished();
    destroy();
  }

  Component.onCompleted: {
    console.warn("[皮肤动画] 场上动画已创建: " + animName);
  }
}
