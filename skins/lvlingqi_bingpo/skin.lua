-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- 吕玲绮、冰魄映雪
--
-- 这是我们**自己的**皮肤清单格式（不是官方 addSkinPackage 那一套）：
--   纯数据，只有字符串/数字，由 init.lua 在 postLoad 阶段读出来交给 QML。
--   scale 的量纲沿用官方那条公式：画面高 x scale / 175（175 是设计基准）。
--
-- 字段分三块：
--   一期：bg/body/front + scale + *_idle（头像渲染用）
--   二期：src_w/src_h + face_*（取景调节用）
--   三期：field_* + damage_cards（场上大动画用）

-- ─────────────────────────────────────────────────────────────────────
-- 这套皮肤的 scale 与「战场绝版」**不一样**，别照抄 0.12
-- ─────────────────────────────────────────────────────────────────────
-- 两套皮肤在无名杀里的配置完全相同（都是 daiji2 + scale 1.2 + shan "play3"），
-- 也就是作者把它们调成了同样的视觉大小。但两套骨架的坐标系尺度差了 3 倍：
--     daiji   (战场绝版用的) bounds 1457x1285, 画布 1564x1352
--     daiji2  (冰魄映雪用的) bounds  419x450,  画布  419x454
-- 而公式是 `层scale = scale × 画面高 / 175`（175 是固定设计基准），
-- 也就是 scale 是**绝对**的、不随骨架自己的画布归一化 → 想让两者视觉一样大：
--     0.12 × (1285 / 450) ≈ 0.343   （按 bounds 比）
--     0.12 × (1352 / 454) ≈ 0.357   （按画布高比）→ 取 0.35
--
-- 背景层单独给 bg_scale：bg 骨架 beijing 是 1744x875（比人物大得多），
-- 用 0.35 会把背景放大 4 倍成糊掉的一小块；按"刚好铺满"反推：
--     875 × s × 664/175 ≥ 664  →  s ≥ 0.20，留余量取 0.22
--
-- ⚠ 故意**不写** src_w / src_h：
--   它们会被当成场上动画的骨架尺寸（找不到对应层时回退用它），而本套导出各骨架
--   坐标系不同（daiji2 = 419x450，chuchang2 = 617x663），写了会让场上动画
--   按错的尺寸缩放 ✗ 不写时由骨架自己报 sourceSize，那才是对的 ✓

return {
  name = "吕玲绮、冰魄映雪",
  generals = { "lvlingqi" },
  dir = "image/skins",          -- 素材目录（相对本皮肤目录）

  -- ── 一期：头像 ──
  bg = "beijing",
  body = "daiji2",
  front = "",
  scale = 0.35,
  bg_scale = 0.22,
  front_scale = 0.35,
  body_idle = "play",
  bg_idle = "play",
  body_shown = "",
  bg_shown = "",

  -- ── 二期：取景 ──
  -- ⚠ 刻意不写 src_w/src_h（原因见文件头）
  -- 实际画面边界（离线量出；预览「正好填满」靠它）
  fit_w = 419,
  fit_h = 450,
  fit_cx = 76,
  fit_cy = -106,
  -- 整体边界（背景∪人物）：预览「整体缩放」用这一组 ✓
  comp_w = 1138,
  comp_h = 685,
  comp_cx = 157,
  comp_cy = 12,
  -- 背景层的实测边界（预览时背景「铺满」用它；人物用上面那组）
  bg_fit_w = 1811,
  bg_fit_h = 938,
  bg_fit_cx = 250,
  bg_fit_cy = 94,
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
