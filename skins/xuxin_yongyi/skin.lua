-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 徐馨、慵仪闲趣
--
-- 本文件由 tests/skinadd.py 生成 ✓
--   * 骨架名 / 动画名：**从无名杀注册表和素材探出**（不再手写 ✓）
--   * fit_* / comp_* / bg_fit_*：**spine_bounds.js 离线量出的真实画面边界** ✓
-- 取景/场上数值可进游戏按 Ctrl+J 微调，会存在自己的表里 ✓

return {
  name = "徐馨、慵仪闲趣",
  generals = { "xuxin" },
  dir = "image/skins",

  -- ── 一期：头像 ──
  bg = "beijing",
  body = "daiji",
  front = "",
  scale = 0.4,
  bg_scale = 0.275,
  front_scale = 0.4,
  body_idle = "play",
  bg_idle = "play",
  body_shown = "",
  bg_shown = "",

  -- ── 二期：取景（**离线量出的真实边界** ✓）──
  fit_w = 1455, fit_h = 864, fit_cx = -21, fit_cy = 11,
  comp_w = 1455, comp_h = 864, comp_cx = -21, comp_cy = 11,
  bg_fit_w = 1625, bg_fit_h = 878, bg_fit_cx = -109, bg_fit_cy = 17,

  -- ── 三期：场上大动画 ──
  field_skel = "daiji2",
  field_anim = "play",
  -- ★ 攻击用**另一个骨架**（注册表原文：gongji → chuchang / play）
  --   技能走 daiji2（601x335），攻击走 chuchang（1059x592）—— 两者尺度不同，
  --   所以必须分开指定骨架，否则攻击会用技能骨架播 ✗
  field_skel_card = "chuchang",
  field_card_anim = "play",
  field_height = 1.5,
  -- ★★ 攻击 / 出场**单独的高度**（注册表给的三个 scale 本来就不一样 ✓）
  --
  --   注册表（lib/dynamicSkin.js:45719-45740）：
  --     teshu   (技能) scale 1.29  × 骨架高 335 = 432
  --     gongji  (攻击) scale 0.87  × 骨架高 592 = 515
  --     chuchang(出场) scale 0.46  × 骨架高 592 = 272
  --
  --   为什么必须乘骨架高：`SkelField.qml:226` 是
  --     `skel.scale = 页高 × heightRatio / 骨架高`
  --   也就是 heightRatio 控制的是**整个画面在屏幕上的高度**。
  --   同一 heightRatio 下，601x335 和 1059x592 两个骨架画面高相同，
  --   但**人物占比不同** ⇒ 看起来一大一小 ✗
  --
  --   以技能 1.5 为基准换算：
  --     攻击 = 1.5 × (515/432) = 1.788
  --     出场 = 1.5 × (272/432) = 0.944
  field_height_card = 1.788,
  field_height_enter = 0.944,
  field_anchor = "center",
  field_dy = -0.1,
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",

  -- 出场动画（骨架名 = 出场动画所在的那个骨架 ✓）
  field_enter_skel = "chuchang",
  field_enter_anim = "play",
  face_mul = 1, face_dx = 0, face_dy = 0,
}
