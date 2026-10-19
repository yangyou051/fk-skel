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
  field_anchor = "center",
  field_dy = -0.1,
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",

  -- 出场动画（骨架名 = 出场动画所在的那个骨架 ✓）
  field_enter_skel = "chuchang",
  field_enter_anim = "play",
  face_mul = 1, face_dx = 0, face_dy = 0,
}
