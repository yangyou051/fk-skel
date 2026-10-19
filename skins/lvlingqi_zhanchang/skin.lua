-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 吕玲绮、战场绝版
--
-- 这是我们**自己的**皮肤清单格式（不是官方 addSkinPackage 那一套）：
--   纯数据，只有字符串/数字，由 init.lua 在 postLoad 阶段读出来交给 QML。
--   scale 的量纲沿用官方那条公式：画面高 x scale / 175（175 是设计基准）。
--
-- 字段分三块：
--   一期：bg/body/front + scale + *_idle（头像渲染用）
--   二期：src_w/src_h + face_*（取景调节用）
--   三期：field_* + damage_cards（场上大动画用）

-- 待机骨架用 daiji（不是 daiji2）：取景参数是针对它调好的，
-- daiji2 位置不同会裁到腿。
--
-- scale 是本套唯一的缩放旋钮：骨架单位(3854)远大于设计基准(175)，
-- 所以必须远小于 1。**显式写出来**，不依赖全局默认。
--
-- src_w / src_h 必须写（3854x2035）：取景面板**拿不到** spine 的 sourceSize，
-- 只能靠这两个数算"渲染尺寸上限"；不写就会出现"面板按不夹算、对局按夹了算"
-- → 预览调好、进对局又不一样 ✗

return {
  name = "吕玲绮、战场绝版",
  generals = { "lvlingqi" },
  dir = "image/skins",          -- 素材目录（相对本皮肤目录）

  -- ── 一期：头像 ──
  bg = "beijing",
  body = "daiji",
  front = "",
  scale = 0.12,
  bg_scale = 0.12,
  front_scale = 0.12,
  body_idle = "play",
  bg_idle = "play",
  body_shown = "play",
  bg_shown = "play",

  -- ── 二期：取景（我们自己的渲染器/面板读）──
  src_w = 3854,
  src_h = 2035,
  -- 实际画面边界（离线量出；预览「正好填满」靠它）
  fit_w = 1457,
  fit_h = 1285,
  fit_cx = 44,
  fit_cy = 98,
  -- 整体边界（背景∪人物）：预览「整体缩放」用这一组 ✓
  comp_w = 1508,
  comp_h = 1293,
  comp_cx = 19,
  comp_cy = 103,
  -- 背景层的实测边界（预览时背景「铺满」用它；人物用上面那组）
  bg_fit_w = 1376,
  bg_fit_h = 936,
  bg_fit_cx = -47,
  bg_fit_cy = -33,
  -- 自带语音的技能（语音包据此上报 ✓）
  voices = { "guowu", "shenwei", "wushuang", "zhuangrong" },
  -- 出场动画（每局开始播一次 ✓；素材里 chuchang = 出场 ✓）
  field_enter_skel = "chuchang",
  field_enter_anim = "play",
  face_mul = 1, face_dx = 0, face_dy = 0,

  -- ── 三期：场上大动画 ──
  probe_anims = "jineng,gongji",           -- 场上骨架里真实存在的动画名（离线验过）
  field_skel = "chuchang2",
  field_skel_card = "chuchang2",
  field_anim = "jineng",
  field_card_anim = "gongji",
  field_height = 1.5,            -- 骨架高度占页面高的比例
  field_anchor = "center",
  field_dy = -0.1,                -- 上移页面高的 10%，不压中间读条
  damage_cards = "slash,fire__slash,thunder__slash,duel,fire_attack,savage_assault,archery_attack,drowning",
}
