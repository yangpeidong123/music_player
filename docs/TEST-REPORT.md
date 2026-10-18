# 测试现状报告（TEST-REPORT）

> 负责人：qa-integrator（task-4） · 更新：2026-10-05
> 本报告跟踪 music_player 的测试基线、CI 验证与构建监控状态。

---

## 1. 现有测试静态审查（基线）

### 1.1 文件清单

| 文件 | 行数 | 覆盖目标 | 测试数 |
|---|---|---|---|
| test/lyrics_engine_test.dart | 165 | lib/core/player/lyrics_engine.dart | 14 |
| test/source_engine_test.dart | 94 | lib/core/engine/source_engine.dart | 6 |
| 合计 | 259 | — | 20 |

### 1.2 lyrics_engine_test.dart 审查结论

**覆盖面（好）**：LyricParser 覆盖简单 LRC、空输入、元数据行跳过、单行多时间标签、乱序排序、元数据解析、`[tr:]` 翻译标签、`[roma:]` 罗马音标签、翻译+罗马音并存、翻译不泄漏进正文（10 个用例）；LyricsEngine 覆盖初始状态、loadLyrics、updatePosition 二分查找、getLine 偏移（4 个用例）。

**与实现核对结果**：逐条对照 lib/core/player/lyrics_engine.dart，全部断言与当前实现一致，无过期断言：

- 多时间标签 `[00:00.00][01:00.00]`：实现收集所有匹配并逐个建行，`allTimeRegex.allMatches` ✔
- 翻译/罗马音标签提取后不进 text：实现先捕获标签内容再 `replaceAll` 移除 ✔
- 毫秒补齐：`(m.group(3) ?? '0').padRight(3, '0')`，`.5` → 500ms ✔
- 元数据跳过正则含 ti/ar/al/by/offset/length（大小写不敏感）✔
- 二分查找语义：`position < 首行时间` 返回 -1；`>= 末行时间` 保持最后一行；区间内返回 `time <= position` 的最大索引 ✔（测试用例 6s→line1、12s→line2 与之一致）

**静态审查发现的小问题（不阻塞）**：

1. 实现中 `timeRegex` 与 `allTimeRegex` 是同一个正则定义了两次（lyrics_engine.dart:73-74），冗余但无害。
2. 解析器不会为"有时间标签但无正文"的行建行（`if (text.isEmpty) continue`），纯时间戳行被丢弃——目前无测试断言此行为，如需保留可后续补。
3. 测试未覆盖 `LyricState.lineAt` 边界（负 offset 大于 -currentIndex 等），已有 `getLine` 覆盖，风险低。

### 1.3 source_engine_test.dart 审查结论

**覆盖面**：SourceMeta 标准解析、缺失元数据、部分元数据（3 个）；MusicInfo toJson/fromJson roundtrip、stableId 平台前缀（2 个）；SourceCapabilities fromJson/supports/qualitys/availablePlatforms（1 个）。

**与实现核对结果**：

- `SourceMeta.fromScript` 正则 `@name\s+([^\n*]+)` 与块注释形态匹配 ✔
- `MusicInfo.fromJson` 对 img/interval/hash 的缺省处理与 roundtrip 断言一致 ✔
- `stableId` = `${source}_$id` ✔
- `SourceCapabilities.fromJson` 对 actions/qualitys 的 List cast ✔

**覆盖缺口（后续补齐方向，供 P1 对齐后回归）**：

1. MusicInfo `fromJson` 中 `interval: j['interval'] as int?` 在 JSON 里是 `240.0`（double）时会抛 cast 错误——roundtrip 测试走 Dart 侧 toJson（`interval ?? 0` 恒为 int）测不到该路径；建议补一条 `interval` 为 double/null 的健壮性用例。
2. `lrcId` getter、`RequestAction.name` 扩展、`SourceLoadException`/`SourceRequestException` toString 无测试。
3. SourceEngine 沙箱（bridge/crypto/request）属集成层，依赖 flutter_js 原生运行时，单元测试不覆盖；CI 已有 `tool/verify_bridge.js`（Node 侧 crypto 交叉对比）作为桥接回归防线，P1 还会加官方源脚本行为对照测试。

### 1.4 测试运行状态（基线）— ✅ 已回填（2026-10-17 CI 实证）

本地 Flutter 工具链不可用（flutter_tools.snapshot 缺失 + 沙箱拦截 dart 分析服务子进程，详见 DEV-NOTES §2.1），基线改由 **GitHub Actions Windows/Ubuntu runner 实证**：

| 日期 | run | 内容 | 结果 |
|---|---|---|---|
| 2026-10-03 | 37113503242 | analyze + test（continue-on-error 期） | ✅ 全绿 |
| 2026-10-17 | 39018118711 | analyze + test（continue-on-error 期） | ✅ 全绿 |
| 2026-10-17 | 2645f7f0 触发 run 39020468647 | analyze + **test 已转正（无 continue-on-error）** | ✅ 全绿（首个硬门禁 run） |

补充：Node 侧逻辑门禁 28+14=42 用例本地与 CI 双跑全绿；`flutter test` 20 用例（lyrics 14 + source_engine 6）随 CI 全绿通过。

---

## 2. CI 配置改造（.github/workflows/build.yml）

### 2.1 本轮变更（qa-integrator）

1. **build-android / build-windows 的 Run tests 步骤**：加注释标注 P0「测试转正」交接——是否移除 `continue-on-error: true` 等 lead 基线 `flutter test` 全绿结论出来后由 lead 确认移除（见《开发计划.md》P0）。当前先保留，避免基线尚未确认就引入红灯。
2. **新增 build-web job（金丝雀）**：
   - `flutter build web --release` + 上传 `web-release` artifact（保留 14 天）；
   - **job 级 `continue-on-error: true`**：pub.dev 已确认 flutter_js 0.8.7 **不支持 Web 平台**（仅 Android/iOS/Windows/Linux/macOS），`flutter build web` 预计失败。金丝雀设计让该 job 红了不影响 push 分支的整体 CI 状态，同时持续观测上游是否解锁 Web 支持；
   - 上游支持后：去掉 job 级 continue-on-error，并视需要把 build-web 加入 release job 的 needs（本轮按 lead 要求 **release needs 保持 [build-android, build-windows] 不变**，不阻塞发布）。

### 2.2 flutter test 的 continue-on-error 处置（P0「测试转正」）— ✅ 已完成

- 2026-10-17 由 lead 移除两处 `continue-on-error: true`（build-android / build-windows），commit 2645f7f0，依据连续两次 CI 全绿实证（见 §1.4）。测试失败从此阻断构建。
- 原「等 lead 基线结论」流程收口。

### 2.3 CI 配置静态检查

- 触发器：push(main)/tags(v*)/pull_request(main)/workflow_dispatch ✔
- build-android：verify_bridge → Java 17 → Flutter → pub get → analyze → test → 临时工程构建 APK（权限注入）→ 上传 artifact ✔
- build-windows：Flutter → pub get → analyze → test → 临时工程 → vcxproj 补丁 → 构建 → tar 打包 → 上传 artifact ✔
- build-web（新增）：Flutter → pub get → analyze → build web → 上传 artifact（金丝雀）✔
- release：needs=[build-android, build-windows]，仅 v* tag 触发，permissions contents: write ✔
- YAML 语法：缩进 2 空格一致，job/step 结构完整；**待 CI 实际运行验证**（Actions 结果见第 4 节）。

---

## 3. 新功能测试覆盖（等 task-2/3 完成）

- 状态：**进行中（其他成员并行开发）**。task-2（lib/features+shared 关于页+日志页）、task-3（lib/core P1 源协议兼容性 + tool + test）完成后，qa-integrator 检查新增测试覆盖、补缺口（若有）。
- 已知方向：audio-engineer 会在 test/ 下用不同文件名新增测试（互不覆盖）；P1 验收含官方源脚本行为对照测试（初始化+search 冒烟）。

---

## 4. Actions 构建监控 — ✅ 持续监控中（2026-10-18 回填）

| run | commit | Android APK | Windows EXE | Web 金丝雀 | 备注 |
|---|---|---|---|---|---|
| 37113503242 | e9858f30 | ✅ | ✅ | — | 2026-10-03 基线 |
| 39018118711 | 0f08f468 | ✅ | ✅ | ❌ 预期内 | Node 双门禁首挂 |
| 39020468647 | 2645f7f0 | ✅ | ✅ | ❌ 预期内 | **test 转正后首跑全绿** |

产物下载：https://github.com/yangpeidong123/music_player/actions（APK/EXE artifact 保留 30 天，web 14 天）。Web 金丝雀失败为 flutter_js 不支持 Web 的预期观测位，不计阻塞。

---

## 5. 结论与待办

| # | 事项 | 状态 |
|---|---|---|
| 1 | 基线测试静态审查（259 行 / 20 用例，与实现一致） | ✅ 完成 |
| 2 | build.yml 改造（build-web 金丝雀 job + 测试转正预注） | ✅ 完成（CI 已实证） |
| 3 | 基线 flutter analyze/test 结果回填 1.4 节 | ✅ 完成（run 39020468647 全绿） |
| 4 | continue-on-error 移除（测试转正） | ✅ 完成（2645f7f0，硬门禁首跑全绿） |
| 5 | 新功能测试覆盖检查/补缺口 | ⏳ 等 task-3（P1 协议） |
| 6 | Actions 构建结果监控与报告 | ✅ 持续监控中（§4） |
