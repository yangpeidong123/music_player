# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [SemVer](https://semver.org/)。

## [Unreleased]

### Added
- **关于页**（`lib/features/settings/about_page.dart`）：版本/构建号展示（package_info_plus）、开源致谢、免责声明。
- **应用内日志页**（`lib/features/settings/log_page.dart`）+ **LogService**（`lib/shared/services/log_service.dart`）：debugPrint 环形缓冲（500 条）、级别着色、一键复制导出；排障不再依赖 Logcat。
- **Node 逻辑门禁** `tool/verify/verify_lyrics_engine.js`：歌词引擎 14 用例（`test/lyrics_engine_test.dart` 断言的保真移植），本地无 Flutter SDK 也可验证核心逻辑；已挂入 CI 双端。
- **CI 观测位**：build-web 金丝雀 job（flutter_js 暂不支持 Web，上游解锁后转正）。
- **文档**：`docs/DEV-NOTES.md`（代码审查与架构笔记）、`docs/team-plan.md`（分工与状态镜像）、`docs/TEST-REPORT.md`（测试现状）。
- **PixelPlayer UI 移植方案**（仓库外 `pixelplayer-study/UI-PORT-PLAN.md`）：设计令牌、页面映射、动态取色/波浪进度条方案、U1~U4 里程碑。

### Fixed
- `tool/verify_bridge.js` RSA 用例偶发失败（`data too large for modulus`）：随机数据清最高位（`data[0] &= 0x7f`），本地 5/5 + CI 复跑稳定全绿。
- README 与实际结构 4 处不符（`features/lyrics/`、`models.dart`、android/windows 原生工程、settings 子页）——见 DEV-NOTES §1。

### Changed
- **CI `flutter test` 转正**：移除 `continue-on-error`（连续两次 CI 全绿后），测试失败不再被吞掉。
- CI 门禁前置：Android/Windows job 先跑 Node 双门禁（verify_bridge 28 用例 + verify_lyrics_engine 14 用例）再进 Flutter 流水线。

### Security
- 提醒：2026-10 会话中曾明文暴露 GitHub PAT，需在 GitHub Settings → Developer settings 撤销轮换（文档层面记录，token 本身不入库）。

## [1.0.1] - 2026-09-30（历史基线，源自上游）

- 跨平台音乐播放器初始版本：Flutter + Material 3，LX 音源协议（flutter_js 沙箱）、歌词同步、SQLite 持久化、Android/Windows CI。
