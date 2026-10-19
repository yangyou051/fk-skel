-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 清河公主、魅影萦心
--
-- 这是我们**自己的**皮肤清单格式（不是官方 addSkinPackage 那一套）：
--   纯数据，只有字符串/数字，由 init.lua 在 postLoad 阶段读出来交给 QML。
--   scale 的量纲沿用官方那条公式：画面高 x scale / 175（175 是设计基准）。
--
-- 字段分三块：
--   一期：bg/body/front + scale + *_idle（头像渲染用）
--   二期：src_w/src_h + face_*（取景调节用）
--   三期：field_* + damage_cards（场上大动画用）

-- 出场动画就在同一个骨架里（ChuChang），待机 DaiJi。
-- 场上动画用骨架自带的 TeShu（技能/伤害牌同一个）。
-- src_w/src_h 来自这套骨架的画布（8518x3350，很大），取景算上限要用。

return {
  name = "清河公主、魅影萦心",
  generals = { "qinghegongzhu" },
  dir = "image/skins",          -- 素材目录（相对本皮肤目录）

  -- ── 一期：头像 ──
  bg = "BeiJing",
  body = "XingXiang",
  front = "",
  scale = 0.12,
  bg_scale = 0.12,
  front_scale = 0.12,
  body_idle = "DaiJi",
  bg_idle = "BeiJing",
  body_shown = "ChuChang",
  bg_shown = "ChuChang",

  -- ── 二期：取景（我们自己的渲染器/面板读）──
  src_w = 8518,
  src_h = 3350,
  -- 实际画面边界（离线量出；预览「正好填满」靠它）
  fit_w = 2161,
  fit_h = 2096,
  fit_cx = -138,
  fit_cy = -234,
  -- 整体边界（背景∪人物）：预览「整体缩放」用这一组 ✓
  comp_w = 2167,
  comp_h = 2451,
  comp_cx = -136,
  comp_cy = -57,
  -- 背景层的实测边界（预览时背景「铺满」用它；人物用上面那组）
  bg_fit_w = 1775,
  bg_fit_h = 1020,
  bg_fit_cx = 48,
  bg_fit_cy = -13,
  face_mul = 1, face_dx = 0, face_dy = 0,

  -- ── 三期：场上大动画 ──
  probe_anims = "jineng,gongji",           -- 场上骨架里真实存在的动画名（离线验过）
  field_anim = "TeShu",
  field_card_anim = "TeShu",
  field_height = 1.5,            -- 骨架高度占页面高的比例
  field_anchor = "center",
  field_dy = -0.1,                -- 上移页面高的 10%，不压中间读条
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",
}
