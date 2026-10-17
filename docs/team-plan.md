# 团队协作计划（4 智能体分工）

> 生成：2026-10-03；更新：2026-10-17（记录实证状态）。
> 共享任务板通过 team_task_* 工具维护；本文件是给人看的状态镜像。

## 分工与写入范围

| 成员 | 职责 | 写入范围（约束） |
|---|---|---|
| **lead** | 任务拆分、代码合并审查、统一执行 flutter/dart/node 命令、GitHub API 推送与 CI 监控 | tool/、.github/、docs/、README.md、push_commit.js |
| **architect** | 架构契约、开发文档对齐、CHANGELOG | README.md、docs/、CHANGELOG.md、lib/shared/models.dart |
| **ui-developer** | 功能页面（features/）与共享组件 | lib/features/、lib/shared/ |
| **audio-engineer** | LX 源协议兼容（core/engine + JS 桥接 + 协议测试） | lib/core/、assets/polyfills/、tool/、test/ |
| **qa-integrator** | 测试盘点、CI 配置、构建监控 | test/、.github/、docs/TEST-REPORT.md |

## 环境约束（全员遵守）

- flutter/dart/node 命令统一由 lead 执行（避免 .dart_tool 竞争与沙箱管道问题）。
- 本地 Flutter 工具链不可用（DEV-NOTES §2.1）——Dart 层验证靠 CI，逻辑层靠 tool/verify/*.js Node 门禁。
- git/curl 无法直连 github.com；推送统一走 lead 的 push_commit.js（GitHub git database API）。
- 队友不推送、不改 lead 范围文件；写范围冲突时先在任务板留言。

## 任务状态（镜像自任务板，2026-10-17）

| 任务 | 负责人 | 状态 |
|---|---|---|
| task-1 文档对齐（DEV-NOTES/README/CHANGELOG/team-plan/models 结论） | architect | ✅ 由 lead 代完成（architect 多轮无响应，避免阻塞） |
| task-2 关于页 + 日志页（P0） | ui-developer | ✅ 完成（CI 实证） |
| task-3 LX 协议对齐（P1） | audio-engineer | ⏸ 挂起（缺口清单见 DEV-NOTES §2 #1/#2） |
| task-4 测试与 CI（含 continue-on-error 移除、build-web 金丝雀） | qa-integrator | ✅ 核心项完成（test 转正 + web 金丝雀就位；Dart 侧协议测试待 task-3） |

## 下一步（按优先级）

1. **P1 协议对齐**（task-3）：md5 encodeURIComponent 预处理、AES CBC/ECB 区分、rsaEncrypt、buffer.from 编码分支——等 audio-engineer 响应或 lead 代做。
2. **UI 移植**（PixelPlayer 风格，待用户确认）：按 `pixelplayer-study/UI-PORT-PLAN.md` U1→U4 分期，ui-developer 主刀。
