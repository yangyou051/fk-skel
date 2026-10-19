-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 张琪瑛、九州春回2
--
-- 这是我们**自己的**皮肤清单格式（不是官方 addSkinPackage 那一套）：
--   纯数据，只有字符串/数字，由 init.lua 在 postLoad 阶段读出来交给 QML。
--   scale 的量纲沿用官方那条公式：画面高 x scale / 175（175 是设计基准）。
--
-- 字段分三块：
--   一期：bg/body/front + scale + *_idle（头像渲染用）
--   二期：src_w/src_h + face_*（取景调节用）
--   三期：field_* + damage_cards（场上大动画用）

return {
  name = "张琪瑛、九州春回2",
  generals = { "zhangqiying" },
  dir = "image/skins",          -- 素材目录（相对本皮肤目录）

  -- ── 一期：头像 ──
  bg = "beijing",
  body = "daiji2",
  front = "",
  scale = 0.268,
  bg_scale = 0.124,
  front_scale = 0.268,
  body_idle = "play",
  bg_idle = "play",
  body_shown = "play",
  bg_shown = "",

  -- ── 二期：取景 ──
  -- ⚠ 刻意不写 src_w/src_h（原因见文件头）
  -- 实际画面边界（离线量出；预览「正好填满」靠它）
  fit_w = 971,
  fit_h = 579,
  fit_cx = -138,
  fit_cy = 22,
  -- 整体边界（背景∪人物）：预览「整体缩放」用这一组 ✓
  comp_w = 1849,
  comp_h = 1519,
  comp_cx = 16,
  comp_cy = 45,
  -- 背景层的实测边界（预览时背景「铺满」用它；人物用上面那组）
  bg_fit_w = 1849,
  bg_fit_h = 1519,
  bg_fit_cx = 16,
  bg_fit_cy = 45,
  -- 出场动画（每局开始播一次 ✓；素材里 chuchang = 出场 ✓）
  field_enter_skel = "chuchang",
  field_enter_anim = "play",
  face_mul = 1, face_dx = 0, face_dy = 0,

  -- ── 三期：场上大动画 ──
  probe_anims = "jineng,gongji",           -- 场上骨架里真实存在的动画名（离线验过）
  field_skel = "chuchang2",
  field_anim = "jineng",
  field_card_anim = "gongji",
  field_height = 1.5,            -- 骨架高度占页面高的比例
  field_anchor = "center",
  field_dy = -0.1,                -- 上移页面高的 10%，不压中间读条
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",

  -- ★ 形态自动切换（对局中按条件切到同组的另一套 ✓ 不改存档 ✓）
  --   form_group: 同组 = 互为形态；form_when: 本套适用的条件
  --   支持：hp_le_N / hp_lt_N / hp_ge_N / hp_gt_N / hp_eq_N
  form_group = "zqy_jiuzhou",
  form_when = "hp_le_2",
}
