# Keepalive Workflow Design

## 目标

每月自动向 `main` 分支提交一次空 commit，保持仓库有活动记录。

## 方案

新增独立的 `.github/workflows/keepalive.yml`。它与现有的 EasyTier release sync 流程无关，避免保活逻辑受发布流程条件影响。

## 设计

- 使用 `0 16 1 * *`，即每月 1 日北京时间 `00:00`。
- 保留 `workflow_dispatch`，便于立即手动验证。
- 声明 `contents: write`，使用默认 `GITHUB_TOKEN` 推送。
- 使用 `github-actions[bot]` 身份创建固定消息为 `chore: keep repository active` 的空 commit。
- 明确推送到 `main`，不修改仓库文件。

## 失败行为

checkout、commit 或 push 任一步失败时，workflow 失败并保留日志；不增加重试、外部服务或额外依赖。

## 验证

实现后检查 YAML 结构、cron、写权限、空 commit 参数、目标分支和最终 git diff。
