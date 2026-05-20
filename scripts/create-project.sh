#!/usr/bin/env bash

set -euo pipefail

template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template_name="code-develop-harness-init"

usage() {
  cat <<EOF
用法: harness-init <项目名> [目标目录]

  项目名        新项目的名称（必填）
  目标目录      新项目创建在哪个目录下（可选，默认当前目录）

示例:
  harness-init my-app
  harness-init my-app ~/projects
EOF
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

project_name="$1"
target_parent="${2:-.}"
target_dir="${target_parent}/${project_name}"

if [[ -d "${target_dir}" ]]; then
  echo "错误: 目标目录已存在: ${target_dir}" >&2
  exit 1
fi

mkdir -p "${target_dir}"

rsync -a \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='dist' \
  --exclude='.tmp' \
  --exclude='tmp' \
  "${template_root}/" "${target_dir}/"

cd "${target_dir}"

git init --quiet

find . -type f \( -name '*.md' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sh' \) \
  -not -path './.git/*' \
  -exec perl -pi -e "s/${template_name}/${project_name}/g" {} +

echo ""
echo "新项目已创建: ${target_dir}"
echo ""
echo "下一步建议:"
echo "  cd ${target_dir}"
echo "  npm run ci                        # 验证仓库完整性"
echo "  补齐 docs/ARCHITECTURE.md          # 填入真实项目架构"
echo "  补齐 CODEOWNERS                    # 替换为真实的代码所有者"
echo "  git add -A && git commit -m 'init' # 创建初始提交"
