# 团队自定义规范

此目录存放团队内部的编码规范和约定。这些规范是对 Skill 的补充，不是替代。

## 什么时候该在这里添加文件

- 某个约定是团队特有的，没有通用 skill 可覆盖。
- 某个 skill 的默认行为需要团队级别的覆盖或补充。
- 跨项目的内部编码约定需要统一落地。

## 文件命名约定

使用 `{语言或领域}-conventions.md` 格式，例如：

- `react-conventions.md`：React 组件和状态管理的团队约定。
- `api-conventions.md`：接口设计和错误处理的团队约定。
- `git-conventions.md`：分支策略和 commit message 的团队约定。
- `naming-conventions.md`：变量、函数、文件的命名规则。

## 编写建议

- 只写 skill 覆盖不到的内容，避免重复。
- 保持简短，规范越短越容易被遵守。
- 能变成机械检查的约束（lint 规则、CI 检查），就不要只停留在文档里。
