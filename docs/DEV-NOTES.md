# DEV-NOTES — 代码审查与架构笔记

> 审查范围：music-player-repo v1.0.1 全量（lib/ 24 文件 + test/ 2 文件 + tool/ 门禁 + CI）。
> 审查轮次：2026-10-03 静态审查 → 2026-10-17 CI 实证复核。
> 维护人：lead（代 architect task-1）。

## 1. 文档与实际结构差异（已全部在 README 修正）

| 差异点 | 文档声明 | 实际情况 | 处理 |
|---|---|---|---|
| `lib/features/lyrics/` | 结构图中存在 | 不存在；歌词视图在 player_page 内 `_buildLyricsView` | README 已删；拆页待 UI 移植方案 §2.4 |
| `lib/shared/models.dart` | 结构图 + task-1 要求创建 | 不存在；`MusicInfo` 定义于 `core/engine/source_engine.dart:74` | 结论见 §3 |
| `android/` `windows/` 原生工程 | 结构图声明入库 | 不入库；CI 用 `flutter create` 生成临时工程注入 lib/ | README 已注 |
| 设置页子页 | 未提及 | 已有 about_page / log_page（P0 交付） | README 已补 |

## 2. 潜在 bug 与技术债清单

| # | 位置 | 问题 | 严重度 | 状态 |
|---|---|---|---|---|
| 1 | `lib/core/engine/source_engine.dart` | Dart 侧协议缺口：md5 未 `encodeURIComponent` 预处理；AES 未分 CBC/ECB；缺 rsaEncrypt（报"未知操作"）——Node 基准 `official_preload.js` 已确认官方行为 | P1 | 待办（audio-engineer task-3） |
| 2 | `assets/polyfills/lx_bridge.js` | `utils.buffer.from` 缺 hex/utf-8/base64 分支 | P1 | 待办（task-3） |
| 3 | `lib/core/player/lyrics_engine.dart` | `parseMetadata` 正则 `\[(\w+)\s*:\s*([^\]]*)\]` 会把 `[00:05.00]` 的 `00` 误存为元数据键（`int.tryParse` 已兜底跳过，仅冗余写入） | P3 | 可忽略 |
| 4 | `tool/verify_bridge.js` RSA 用例 | 随机数据可顶满模长 → `data too large for modulus`（flaky）；修复 `data[0] &= 0x7f` 于 10-05 完成、10-17 补推送（commit 0f08f468） | 已修复 | ✅ CI 实证 |
| 5 | `flutter test` 曾 `continue-on-error: true` | 测试失败不可见 | P0 | ✅ 已于 2026-10-17 移除（test 两次 CI 全绿实证后转正） |
| 6 | `pubspec.yaml` | `package_info_plus` 已声明未使用（about_page 现已使用，依赖健康） | — | ✅ 已消除 |
| 7 | `pubspec.yaml` | `material_design_icons_flutter ^7.0.7296` 在 lib/ 零引用，可移除（architect 2026-10-18 审查补充） | P3 | 待清理任务 |
| 8 | `lib/core/storage/source_storage.dart` | 60 行死代码：lib/ 内零 import，save() 与 source_manager_page._importFromUrl 的加载验证重复（architect 2026-10-18 审查补充） | P3 | 待清理任务 |
| 9 | `lib/core/player/player_service.dart` `_tryNext()` | 重试语义 bug 预埋：`_maxRetries=3` 意为"整轮最多切 3 次"，但 `next()` → `_playAt` 每次切歌重置 `_retryCount=0`，连续失败实际无限跳曲；如需整轮语义须把计数移出 `_playAt`（architect 2026-10-18 审查补充） | P2 | 待修（建议随 P1 或独立小任务） |
| 10 | `lyrics_engine.dart` | `[offset:±ms]` 标签被跳过未应用到时间轴，属歌词打磨点 | P4 | 排队 |

## 2.1 附：本地工具链不可用根因（记录给后续会话）

- `flutter_tools.snapshot` 缺失 + dart 分析服务子进程管道被沙箱拦截 → 本地无法 `flutter pub get / analyze / test`。
- 结论：Dart 层验证完全依赖 GitHub Actions（Windows runner 实测 `flutter test` 全绿）；逻辑层用 `tool/verify/*.js` Node 门禁在本地兜底。

## 3. models.dart 结论（task-1 第 4 项）

**结论：不提取，维持现状。** 理由：
1. `MusicInfo` 唯一消费方是 `source_engine.dart` 自身的解析返回值 + `player_service.dart` 队列——扇出 = 2，提取收益低；
2. 提取会产生 `core→shared` 的新依赖方向，与「shared 不依赖 core」的分层纪律相反；
3. README 已如实标注模型真实位置。

若未来 web/桌面歌词模块需要 MusicInfo，再按「shared/models.dart 只放纯数据类、core 转为 import 方」执行。

## 4. 与《开发计划.md》差距映射（2026-10-03 计划）

| 计划条目 | 状态 |
|---|---|
| P0 关于页 + 日志页 | ✅ 完成（about_page.dart / log_page.dart / LogService，CI 实证） |
| P0 flutter test 转正 | ✅ 完成（移除 continue-on-error） |
| P1 源协议对齐 | ⏸ 进行中（audio-engineer 挂起；缺口清单见 §2 #1/#2） |
| P1 协议测试扩展 | ⏸ 部分（verify_bridge.js 28 用例在跑；Dart 侧协议测试待 task-3） |
| P2+（UI 移植 PixelPlayer 风格） | 📋 方案已出：`pixelplayer-study/UI-PORT-PLAN.md`（U1~U4 分期），待用户确认后开工 |

## 5. CI 实证记录

| 日期 | commit | 结果 |
|---|---|---|
| 2026-10-03 | e9858f30 等 3 个修复 commit | 全绿（run 37113503242） |
| 2026-10-17 | 6081587d（歌词 Node 门禁 + CI 挂载） | Android 因 verify_bridge 旧文件失败（修复漏推送） |
| 2026-10-17 | 0f08f468（补推 RSA flaky 修复） | **全绿**（run 39018118711）：analyze/test/双端构建全过 |
| 2026-10-17 | 2645f7f0（task-1 文档 + test 转正） | **全绿**（run 39020468647）：首个无 continue-on-error 的 run，test 成为硬门禁 |

## 6. PixelPlayer 学习归档

- 学习笔记：`pixelplayer-study/UI-STUDY-NOTES.md`（四截图 → 四页映射、设计系统拆解、按成本分层借鉴点）。
- 移植方案：`pixelplayer-study/UI-PORT-PLAN.md`（设计令牌、页面映射、取色/波浪条方案、U1~U4 里程碑）。
- 许可红线：PixelPlayer 为私有许可——只借鉴设计思路，不搬代码/资源。
