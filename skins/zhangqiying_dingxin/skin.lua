-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 张琪瑛、定心锁意
--
-- 本文件由 tests/skinadd.py 生成 ✓
--   * 骨架名 / 动画名：**从无名杀注册表和素材探出**（不再手写 ✓）
--   * fit_* / comp_* / bg_fit_*：**spine_bounds.js 离线量出的真实画面边界** ✓
-- 取景/场上数值可进游戏按 Ctrl+J 微调，会存在自己的表里 ✓

return {
  name = "张琪瑛、定心锁意",
  generals = { "zhangqiying" },
  dir = "image/skins",

  -- ── 一期：头像 ──
  bg = "BeiJing",
  body = "XingXiang",
  front = "",
  scale = 0.41,
  bg_scale = 0.275,
  front_scale = 0.41,
  body_idle = "DaiJi",
  bg_idle = "BeiJing",
  body_shown = "ChuChang",
  bg_shown = "",

  -- ── 二期：取景（**离线量出的真实边界** ✓）──
  fit_w = 2334, fit_h = 1570, fit_cx = -71, fit_cy = -131,
  comp_w = 2334, comp_h = 1570, comp_cx = -71, comp_cy = -131,
  bg_fit_w = 2019, bg_fit_h = 1254, bg_fit_cx = -82, bg_fit_cy = -39,

  -- ── 三期：场上大动画 ──
  field_skel = "XingXiang",
  field_anim = "TeShu",
  field_card_anim = "GongJi",
  field_height = 0.6,
  field_anchor = "center",
  field_dy = -0.1,
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",

  -- 出场动画（骨架名 = 出场动画所在的那个骨架 ✓）
  field_enter_skel = "XingXiang",
  field_enter_anim = "ChuChang",
  face_mul = 1, face_dx = 0, face_dy = 0,
}
