## [2026-05-21 14:21] | Task: 修复全局初始化命令复制错误目录

### 🤖 Execution Context

- **Agent ID**: `codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex desktop + zsh (Darwin)`

### 📥 User Query

> `code-harness-init actspace-agent` 之后生成的不是模板仓库内容，而是出现了 `bin`、`lib`、`share` 等目录，希望排查原因并修复初始化脚本。

### 🛠 Changes Overview

**Scope:** `scripts`, `docs/histories`, `docs/learnings`

**Key Actions:**

- **[修复脚本路径解析]**: 更新 `scripts/create-project.sh`，在通过 `npm link` 暴露的全局命令入口下，先解析 symlink 的真实脚本路径，再推导模板根目录。
- **[补充知识沉淀]**: 记录这次问题的成因、修复方式和可迁移的 shell 路径解析经验，减少后续脚手架脚本重复踩坑。

### 🧠 Design Intent (Why)

问题的根因不是复制逻辑本身，而是脚本把全局命令的 symlink 路径误当成模板仓库根目录来推导，导致复制了 Node 安装目录。修复入口路径解析比重写复制流程更小、更稳，也能同时兼容仓库内直跑和全局命令调用两种使用方式。

### 📁 Files Modified

- `scripts/create-project.sh`
- `docs/histories/2026-05/20260521-1421-fix-init-template-root.md`
- `docs/learnings/2026-05/symlink-script-root.md`
