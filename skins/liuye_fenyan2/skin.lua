-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 刘晔、焚焰天征2
--
-- 本文件由 tests/skinadd.py 生成 ✓
--   * 骨架名 / 动画名：**从无名杀注册表和素材探出**（不再手写 ✓）
--   * fit_* / comp_* / bg_fit_*：**spine_bounds.js 离线量出的真实画面边界** ✓
-- 取景/场上数值可进游戏按 Ctrl+J 微调，会存在自己的表里 ✓

return {
  name = "刘晔、焚焰天征2",
  generals = { "ty__liuye" },
  dir = "image/skins",

  -- ── 一期：头像 ──
  bg = "beijing",
  body = "daiji2",
  front = "",
  scale = 1.0,
  bg_scale = 0.4,
  front_scale = 1.0,
  body_idle = "play",
  bg_idle = "play",
  body_shown = "",
  bg_shown = "",

  -- ── 二期：取景（**离线量出的真实边界** ✓）──
  fit_w = 556, fit_h = 614, fit_cx = -9, fit_cy = -73,
  comp_w = 556, comp_h = 614, comp_cx = -9, comp_cy = -73,
  bg_fit_w = 1831, bg_fit_h = 1050, bg_fit_cx = 19, bg_fit_cy = 16,

  -- ── 三期：场上大动画 ──
  field_skel = "daiji2",

  -- ★ 攻击用**另一个骨架**（注册表 gongji 指定的）
  field_skel_card = "chuchang2",
  field_anim = "play2",
  field_card_anim = "gongji",
  field_height = 1.5,
  field_anchor = "center",
  field_dy = -0.1,
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",
  field_height_card = 1.528,
  field_height_enter = 2.27,

  -- ★ 形态自动切换（同组 = 互为形态；本套适用的条件见表里 form_when）
  --   hp_le_N / hp_gt_N … 体力条件
  --   skill_<技能名>        发动该技能后（事件驱动）
  --   default              兜底（其余条件都不成立时用它）
  form_group = "liuye_fenyan",
  form_when = "skill_poyuan",
  -- 出场动画（骨架名 = 出场动画所在的那个骨架 ✓）
  field_enter_skel = "chuchang",
  field_enter_anim = "play",
  face_mul = 1, face_dx = 0, face_dy = 0,
}
