-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 辛宪英、凤翥鸾回
--
-- 本文件由 tests/import_skins.js 从无名杀的素材**自动量出并生成** ✓
--   fit_* / comp_* / bg_fit_* 都是离线量出来的真实画面边界（不是猜的 ✓）
--   数值来源：tests/spine_probe.js 的边界测量（按动画姿势取并集 ✓）
-- 如需微调：进游戏按 Ctrl+J，用「取景」那几个按钮调，会存在自己的表里 ✓

return {
  name = "辛宪英、凤翥鸾回",
  generals = { "xinxianying" },
  dir = "image/skins",

  -- ── 一期：头像 ──
  bg = "BeiJing",
  body = "XingXiang",
  front = "",
  scale = 0.206,
  bg_scale = 0.275,
  front_scale = 0.206,
  body_idle = "DaiJi",
  bg_idle = "BeiJing",
  body_shown = "ChuChang",
  bg_shown = "",

  -- ── 二期：取景（离线量出的真实边界 ✓）──
  fit_w = 2441,
  fit_h = 1614,
  fit_cx = 189,
  fit_cy = 17,
  comp_w = 2441,
  comp_h = 1614,
  comp_cx = 190,
  comp_cy = 17,
  bg_fit_w = 1951,
  bg_fit_h = 1334,
  bg_fit_cx = 46,
  bg_fit_cy = -40,

  -- ── 三期：场上大动画 ──
  -- ⚠ 下面这些是**从素材量出来的参考值**，进游戏后按 Ctrl+J，用「场上动画」
  --   那几个按钮试播并微调（会存在自己的表里 ✓）
  field_skel = "XingXiang",
  field_anim = "TeShu",
  field_card_anim = "TeShu",
  field_height = 9.301,
  field_anchor = "center",
  field_dy = -0.1,
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",

  -- 出场动画
  --   ⚠ 骨架名要写**出场动画所在的那个骨架** ✗（两套风格不同，见脚本头部注释 ✓）
  field_enter_skel = "XingXiang",
  field_enter_anim = "ChuChang",
  face_mul = 1, face_dx = 0, face_dy = 0,
}
