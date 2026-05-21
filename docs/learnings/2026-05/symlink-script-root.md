# Shell 脚本里的“脚本目录”不一定是真实目录

这次初始化脚手架的问题，暴露了一个很常见、也很容易忽略的点：当脚本是通过全局命令或软链接启动时，`$0` 或 `BASH_SOURCE[0]` 看到的常常只是**入口链接路径**，不一定是脚本文件本体的位置。

## 发生了什么

初始化命令 `code-harness-init` 由 `npm link` 暴露到 Node 的全局 `bin` 目录里。这个全局命令本身是一个 symlink，指向仓库里的 `scripts/create-project.sh`。

原来的脚本直接这样推导模板根目录：

```bash
template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

在“直接运行仓库内脚本”的场景下，这没问题。但在“执行全局命令”的场景下，`BASH_SOURCE[0]` 指向的是全局 `bin/code-harness-init` 这条链接，于是脚本就把 Node 安装目录当成模板根目录了。

结果就是：复制出来的新项目不是模板仓库，而是 `bin/`、`include/`、`lib/`、`share/` 这一套 Node 安装目录结构。

## 为什么这是个坑

- 很多脚手架脚本在本地开发时只会直接运行，容易误以为“脚本目录推导”已经足够稳。
- 一旦通过 `npm link`、Homebrew、系统 launcher 或其他包装器暴露命令，入口就可能变成 symlink。
- 这类 bug 看起来像“复制错了文件”，但真正出问题的是“定位模板根目录”的前置步骤。

## 更稳的做法

先沿着 symlink 一层层解析到真实脚本，再根据真实脚本的位置推导目录：

```bash
resolve_script_path() {
  local source_path="${BASH_SOURCE[0]}"

  while [[ -L "${source_path}" ]]; do
    local source_dir
    source_dir="$(cd -P "$(dirname "${source_path}")" && pwd)"
    source_path="$(readlink "${source_path}")"
    [[ "${source_path}" != /* ]] && source_path="${source_dir}/${source_path}"
  done

  cd -P "$(dirname "${source_path}")" && pwd
}
```

然后再做：

```bash
template_root="$(cd "$(resolve_script_path)/.." && pwd)"
```

这个模式的关键点有两个：

- `readlink` 取到的目标路径可能是相对路径，所以要基于当前链接所在目录做一次拼接。
- `cd -P` / `pwd` 用来拿到物理路径，避免中间目录本身也是链接时继续混淆。

## 什么时候该想到这个问题

如果脚本同时满足下面任意两条，就值得优先检查是否有 symlink 路径问题：

- 通过 `npm link`、全局 `bin`、Homebrew 或系统 PATH 触发。
- 脚本内部要“根据自身位置”去找模板、配置、资源文件。
- 本地直跑正常，但换一种安装或调用方式就开始复制错目录、读错文件。

## 自检问题

1. 你的脚本拿到的是“入口命令路径”，还是“真实脚本路径”？
2. `readlink` 返回的是绝对路径还是相对路径，代码有没有分别处理？
3. 如果把脚本做成全局命令再执行一次，资源定位还正确吗？
