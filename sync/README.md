# sync/ — 上游自动同步机制 / Upstream auto-sync

本仓库是 [`kangarooking/cangjie-skill`](https://github.com/kangarooking/cangjie-skill) 的自动镜像。
This repository is an automated mirror of `kangarooking/cangjie-skill`.

## 工作方式 / How it works

- GitHub Actions 每天自动运行一次（UTC 20:00 / 北京时间 04:00），也可在 Actions 页面手动触发。
- GitHub Actions runs daily (UTC 20:00) and can be triggered manually from the Actions tab.
- 每次运行会把上游最新内容镜像到本仓库根目录，并提交 `chore: sync upstream ...`。
- Each run mirrors the latest upstream content into the repository root and commits `chore: sync upstream ...`.
- `.github/` 与 `sync/` 目录受保护，不会被上游内容覆盖。
- The `.github/` and `sync/` directories are protected from being overwritten.

## 作者换仓库也能跟随 / Follow the author across repositories

发现顺序 / Discovery order：

1. `sync/upstream-url.txt` 记录的上次有效地址 / last known-good URL;
2. 已知地址 `github.com/kangarooking/cangjie-skill` / known candidate;
3. GitHub API：作者账号下含 `cangjie` 的仓库 / owner's repos containing `cangjie`;
4. GitHub 搜索：`cangjie-skill` 仓库 / global repository search;
5. 官网 `cangjie-skill.com` 解析出的仓库链接 / repository link parsed from the official site.

全部失败时保持仓库现有内容不变并报错，不会破坏已有内容。
If all discovery methods fail, the repository content is left untouched and the run fails loudly.

## 保活 / Keep-alive

上游无更新时，脚本每 7 天提交一次 `sync/last-check.txt` 心跳，避免 GitHub 在仓库 60 天无提交后自动停用定时工作流。
When upstream has no changes, a heartbeat is committed every 7 days so GitHub does not disable the scheduled workflow after 60 days without commits.

## 手动触发 / Manual trigger

Actions → **Sync upstream cangjie-skill** → *Run workflow*。也可在本地运行：

```bash
GH_TOKEN=<your-token> bash sync/sync-upstream.sh
```

## 本地技能库 / Local skill directory

本地安装的技能库同步脚本另行提供，逻辑与仓库镜像一致。
A local script for the installed skill directory is provided separately, using the same discovery logic.
