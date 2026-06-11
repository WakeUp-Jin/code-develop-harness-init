## [2026-06-10 07:48] | Task: 统一项目定位术语为 Agent-first

### 🤖 Execution Context

- **Agent ID**: Cursor Agent
- **Base Model**: Fable 5
- **Runtime**: Cursor IDE

### 📥 User Query

> README 中"面向 Agent 协作开发的项目初始化模板"不够准确。这个仓库的设计理念是让开发者只和 Agent 交流、不手动进入项目编码来完成项目，harness 文档体系都是为此服务的。应该改为 CONTRIBUTING 里已有的 Agent-first（或 Agent Native）的说法。

### 🛠 Changes Overview

**Scope:** 仅文档（README、AGENTS.md）

**Key Actions:**

- **[统一术语]**: 将 README tagline 和 `AGENTS.md` 开头的"Agent 协作开发"改为 "Agent-first 开发"，与 `core-beliefs.md`、`CONTRIBUTING.md`、`REPO_COLLAB_GUIDE.md` 及 README badge 中已有的主导术语收口一致。
- **[说透工作模式]**: 在 README tagline 与「背景」核心理念中显式补充工作模式——人定方向、Agent 执行，开发者通过对话推进项目而不是手动编码。

### 🧠 Design Intent (Why)

"协作开发"暗示人和 Agent 一起写代码，与 `core-beliefs.md` 第一条原则（人来定方向，Agent 负责执行和推进）不符。仓库内 Agent-first 已是主导术语，选择收口到已有术语而非引入语义尚不稳定的新词（如 Agent Native），符合"持续整理和收口"的核心理念，改动面也最小。

### 📁 Files Modified

- `README.md`
- `AGENTS.md`
- `docs/histories/2026-06/20260610-0748-unify-agent-first-positioning.md`
