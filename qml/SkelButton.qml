// SPDX-License-Identifier: GPL-3.0-or-later
//
// SkelButton —— 对局里左侧的「换肤」按钮
//
// 目标：和核心那排竖按钮（托管 / 反选 / 牌序 / 聊天）**长得一样**，
//       并且正好排在它们**上方**。点一下打开换肤页。
//
// 做法（沿用当时验证可用的那套）：
//   * **只读**核心按钮的几何（`mapToItem` 到我们自己的坐标系），
//     再把 width / height / x 抄过来，y 放在它们上方一格；
//   * **绝不**往核心的布局容器里塞子对象 —— 那是未定义行为，会崩 ✗
//   * 字体也尽量从核心按钮上抄（`textFont` / `font` 两种都试；抄不到就用默认）
//
// ⚠ 模块名必须是 `Fk.Components.Common`：MetroButton 在
//   freekill-core/Fk/Components/Common/ 下。以前写成 `Fk.Components.GameCommon`
//   时这个按钮**从来没加载成功过**（日志只有一行 `MetroButton is not a type`）✗

import QtQuick

import Fk
import Fk.Components.Common

MetroButton {
  id: root

  text: "换肤"

  /// 点一下 → 请宿主打开换肤页
  signal pickRequested()

  onClicked: root.pickRequested()

  /// 由宿主把核心按钮的字体抄过来（抄不到就是默认）
  property bool fontCopied: false

  function copyFontFrom(src) {
    if (!src) return
    // 核心按钮可能用 textFont（MetroButton 系列），也可能用 font
    try {
      if (src.textFont && src.textFont.pixelSize > 0) {
        root.textFont.pixelSize = src.textFont.pixelSize
        if (src.textFont.family) root.textFont.family = src.textFont.family
        if (src.textFont.bold !== undefined) root.textFont.bold = src.textFont.bold
        root.fontCopied = true
        return
      }
    } catch (e) { /* 换 font 再试 */ }
    try {
      if (src.font && src.font.pixelSize > 0) {
        root.textFont.pixelSize = src.font.pixelSize
        if (src.font.family) root.textFont.family = src.font.family
        if (src.font.bold !== undefined) root.textFont.bold = src.font.bold
        root.fontCopied = true
      }
    } catch (e) { /* 抄不到就用默认，不算错 */ }
  }

  z: 700
}
