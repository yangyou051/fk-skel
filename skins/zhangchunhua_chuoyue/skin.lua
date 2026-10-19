-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 张春华、绰约多姿
--
-- 本文件由 tests/skinadd.py 生成 ✓
--   * 骨架名 / 动画名：**从无名杀注册表和素材探出**（不再手写 ✓）
--   * fit_* / comp_* / bg_fit_*：**spine_bounds.js 离线量出的真实画面边界** ✓
-- 取景/场上数值可进游戏按 Ctrl+J 微调，会存在自己的表里 ✓

return {
  name = "张春华、绰约多姿",
  generals = { "zhangchunhua" },
  dir = "image/skins",

  -- ── 一期：头像 ──
  bg = "beijing",
  body = "daiji2",
  front = "",
  scale = 0.88,
  bg_scale = 0.275,
  front_scale = 0.88,
  body_idle = "play",
  bg_idle = "play",
  body_shown = "",
  bg_shown = "",

  -- ── 二期：取景（**离线量出的真实边界** ✓）──
  fit_w = 303, fit_h = 420, fit_cx = 10, fit_cy = -78,
  comp_w = 303, comp_h = 420, comp_cx = 10, comp_cy = -78,
  bg_fit_w = 613, bg_fit_h = 835, bg_fit_cx = 14, bg_fit_cy = -26,

  -- ── 三期：场上大动画 ──
  field_skel = "",
  field_anim = "",
  field_card_anim = "",
  field_height = 0.6,
  field_anchor = "center",
  field_dy = -0.1,
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",

  -- 出场动画（骨架名 = 出场动画所在的那个骨架 ✓）
  field_enter_skel = "chuchang",
  field_enter_anim = "play",
  face_mul = 1, face_dx = 0, face_dy = 0,
}
