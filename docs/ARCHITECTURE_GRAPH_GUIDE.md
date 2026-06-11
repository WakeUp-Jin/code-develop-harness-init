# 交互式架构依赖图谱 — 生成规范与提示词

这份规范教 Agent 为任意代码项目生成一份**单文件、零依赖、可交互**的架构依赖图谱。

> **产物格式约束：最终产物必须是一个 HTML 文件**（建议命名 `ARCHITECTURE_GRAPH.html`，放项目根目录或 docs/），纯 HTML + CSS + 原生 JS + 内联 SVG，双击浏览器可开、离线可用。本规范文档本身是 Markdown，但产物不是。

规范刻意写得非常细：**把创造题降为填空题**——渲染器、配色、交互逻辑全部由本规范 §8 的模板提供，Agent 只需要完成两件事：① 用脚本扫描出真实依赖数据；② 把数据填进固定的 Schema。能力一般的模型照着做也能产出同等质量的图谱。

成品参考：actspace-agent 项目根目录的 `ARCHITECTURE_GRAPH.html`（2026-06-10）。

---

## §1 产出形态：一个 HTML，三个 Tab

| Tab | 内容 | 回答的问题 |
|---|---|---|
| ① 大模块依赖图 | 顶层模块（包/目录级）之间的依赖关系，分层 SVG 图。点击节点 → 上游染蓝、下游染橙、依赖边变流动虚线，侧栏显示该模块的暴露面与内部流程 | 大模块之间谁依赖谁？每个模块对外暴露什么？ |
| ② 数据流动画 | 一次核心业务流程（如一次请求/一次对话 turn）的泳道步进动画：脉冲点沿链路移动，每步配文字说明「此刻传递的数据结构是什么、发生了什么转换」。播放/暂停/上一步/下一步/重置 | 数据怎么在层与层之间流动？在哪里发生协议转换？ |
| ③ 子系统内部图 | 每个重要子系统一张文件级依赖图（按钮切换），交互与大图一致。每张图配一句话点出该子系统的「结构模式」 | 小模块内部核心文件谁依赖谁？各文件暴露什么接口？ |

---

## §2 五条铁律（违反任何一条 = 重做）

1. **图必须来自真实扫描，禁止凭印象画**。动手画图前，必须先用脚本对源码做 import 静态扫描（脚本见 §3 Step 1）。每一条边、每一个权重都要有扫描数据背书。凭记忆或文档画出来的依赖图，错一条边就会误导读者，比没图更糟。图的页脚要标注扫描日期与扫描范围。
2. **箭头方向 = 依赖方向，全文唯一语义**。A → B 永远表示「A import 了 B」（A 依赖 B）。不允许混入「数据流向」「调用顺序」等其他语义的箭头（数据流单独放 Tab ② 表达）。线宽按 import 次数加权：`strokeWidth = min(1 + log2(w) × 0.75, 4)`。
3. **产物是单 HTML 文件、零外部依赖、双击可开**。纯 HTML + CSS + 原生 JS + 内联 SVG。禁止引入 d3 / mermaid / CDN 字体 / 任何网络请求。用户双击文件即可在浏览器中使用全部功能，离线可用。
4. **数据与渲染分离**。所有图 = 「JS 数据对象（nodes/edges/info）」+「一个通用渲染器函数」。禁止为每张图手写 SVG。这样架构变更后只需重新扫描、更新数据区，渲染逻辑零改动；多张子系统图共用同一套交互。
5. **交付前必须在浏览器里实际点过**。按 §9 验证清单逐项检查：节点点击高亮、侧栏内容、子图切换、动画步进。AI 生成的交互代码经常有 bug，没点过不算完成。

---

## §3 七步流程（按顺序执行）

### Step 1 / 扫描真实依赖（必须先做）

三类扫描：顶层依赖 · 子系统内部依赖 · 对外暴露符号。以下脚本以 TypeScript 项目为例（其他语言改 import 正则即可：Python 抓 `^from|^import`，Go 抓 `import (...)` 块，Java 抓 `^import`）。在项目根目录运行：

```python
import os, re, collections

# ========= 按项目修改这两行 =========
SRC_ROOT = "packages/your-package/src"     # 扫描根目录
IMPORT_RE = re.compile(r'from\s+"(\.[./]*[^"]+)"')   # 相对 import 正则
# ===================================

# ---- 扫描 A：顶层模块（src 下第一级目录/文件）之间的依赖 + 次数 ----
deps = collections.defaultdict(collections.Counter)
for dirpath, dirs, files in os.walk(SRC_ROOT):
    dirs[:] = [d for d in dirs if d not in ("test", "__tests__", "node_modules")]
    for f in files:
        if not f.endswith(".ts") or f.endswith(".test.ts"): continue
        p = os.path.join(dirpath, f)
        rel = os.path.relpath(p, SRC_ROOT)
        src_top = rel.split(os.sep)[0].replace(".ts", "")
        for m in IMPORT_RE.finditer(open(p, encoding="utf8").read()):
            target = os.path.normpath(os.path.join(dirpath, m.group(1)))
            trel = os.path.relpath(target, SRC_ROOT)
            if trel.startswith(".."): continue        # 跨包的另行统计
            tgt_top = trel.split(os.sep)[0].replace(".ts", "")
            if src_top != tgt_top:
                deps[src_top][tgt_top] += 1
print("==== 顶层模块依赖 ====")
for s in sorted(deps):
    print(f"{s:16s} -> " + ", ".join(f"{t}({c})" for t, c in deps[s].most_common()))

# ---- 扫描 B：某个子系统内部的文件级依赖（每个重要子系统跑一次）----
def filedeps(root, label):
    print(f"\n==== {label} 内部文件依赖 ====")
    edges = set()
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d != "test"]
        for f in files:
            if not f.endswith(".ts") or f.endswith(".test.ts"): continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root)
            for m in IMPORT_RE.finditer(open(p, encoding="utf8").read()):
                t = os.path.normpath(os.path.join(dirpath, m.group(1)))
                trel = os.path.relpath(t, root)
                if trel.startswith(".."): continue
                edges.add((rel.replace(".ts", ""), trel.replace(".ts", "")))
    for s, t in sorted(edges):
        if s != "index": print(f"  {s} -> {t}")

filedeps(os.path.join(SRC_ROOT, "engine"), "engine")   # 每个子系统一行

# ---- 扫描 C：外部消费者从本包导入了哪些符号（确定"对外暴露面"）----
CONSUMER_ROOT = "packages/consumer/src"
PKG_RE = re.compile(r'import\s+(?:type\s+)?\{([^}]+)\}\s+from\s+"@scope/pkg"', re.S)
symbols = set()
for dirpath, dirs, files in os.walk(CONSUMER_ROOT):
    for f in files:
        if not f.endswith(".ts"): continue
        for m in PKG_RE.finditer(open(os.path.join(dirpath, f), encoding="utf8").read()):
            for n in m.group(1).split(","):
                n = n.strip().split(" as ")[0].replace("type ", "").strip()
                if n: symbols.add(n)
print("\n==== 消费者导入的符号 ====")
print(", ".join(sorted(symbols)))
```

扫描结果就是后面所有图的**唯一事实来源**。把输出保留在对话/笔记里随时回查。

### Step 2 / 规划大图布局：层 = 依赖深度，三明治结构

- **分层规则**：被依赖越多、越基础的模块放越下层；只依赖别人不被依赖的（入口/装配层）放上层。从扫描 A 的结果推导：先找出「不依赖任何兄弟模块」的放底层（如类型/消息定义），逐层往上。
- **三明治**：最顶放「消费者横条」（如 desktop / 调用方），最底放「契约底座横条」（如 shared 类型包——人人依赖它时**不画 N 条边**，画成横跨整图的长条让所有列「坐在上面」，视觉即语义，只补 2-3 条代表边）。
- **同层 ≤ 5 个节点**，超了就拆层或合并次要模块（如把 4 个小工具文件合成一个 `storage/*` 节点）。
- **反向边处理**：扫描中出现的「下层 import 上层」（通常是仅类型引用）不要隐藏——标 `type:"typeonly"` 画虚线，并在节点 info 里解释为什么不是循环依赖。这种边往往是图中最有信息量的细节。

### Step 3 / 填大图数据

按 §4 的 Schema 把扫描 A 的结果填进 `bigGraph` 对象：

- 每条边带真实权重 `w`（import 次数）；权重 ≥ 4 的边渲染器会自动标 `×N`。
- 每个节点写 `info` 三件套（写法见 §6）：role / exports / flow。exports 优先取扫描 C 中真实被消费的符号。

### Step 4 / 填子系统内部图数据（挑 3-6 个最重要的子系统）

- 用扫描 B 的边列表填 `subGraphs`。文件太多时合并同目录小文件为一个节点（如 `briefs/*`）。
- 每张图的 `desc` 必须点出**结构模式**——一个比喻级别的总结：中枢式（一个装配点依赖所有子模块）/ 洋葱式（层层包裹）/ 管线式（A→B→C 流水线）/ 协议与品牌分离（薄壳+核心）……这是读者记住一张图的钩子。
- 编排/调度类中枢节点标 `hub:true`（渲染为橙底）。

### Step 5 / 写数据流动画（挑项目最核心的一条链路）

- 泳道 = 进程/层（3-5 条），节点 = 链路上的关键函数/动作（10-14 个），步骤 = 9-13 步。
- **每步 caption 必须写出「此刻传递的数据结构名」和「发生的转换」**，用 `<b>` 强调角色、`<code>` 标类型名。例：「**② Main · 装配**：`buildAgentConfig(input)` —— 前端参数 + env → 纯配置对象 `AgentConfig`，API Key 在这层注入，永不进 renderer」。
- 有循环的链路（如 LLM 工具循环）用回环边 + 单独一步说明，这是数据流动画最有价值的部分。

### Step 6 / 套模板组装

复制 §8 完整模板，替换三处数据区。模板中标注了 `/* ==== 数据区 1/2/3 ==== */` 的三个对象（bigGraph / subGraphs / turn 数据）。**只改数据区，不要改渲染器与 CSS**（除非项目名、标题文案）。

### Step 7 / 浏览器验证

按 §9 清单逐项点击检查，截图确认。

---

## §4 数据 Schema（渲染器的输入格式）

每张依赖图是一个 `graph` 对象，通用渲染器 `renderGraph(svgEl, graph, sidebarEl)` 负责布局（层内均布 + 贝塞尔边 + 箭头）、交互（点击高亮上下游 + 侧栏详情）：

```js
graph = {
  w: 1000, h: 760,            // SVG viewBox 尺寸（宽固定 1000，高按层数调）

  bands: [                     // 可选：横跨整图的长条（三明治的顶/底）
    { id: "desktop",           // 节点 id（侧栏标题用它）
      label: "packages/desktop（main 进程 · IPC 路由 / 装配）",
      sub: "消费 agent-core 64 个符号",   // 第二行小字
      y: 24, h: 50 },
  ],

  layers: [                    // 分层节点：每层一个 y，层内自动均布
    { y: 130, nodes: [
      { id: "engine",          // 唯一 id，也是 edges 的端点名
        label: "engine/",      // 节点主文字（mono 字体）
        sub: "执行引擎 · Bridge/Agent/Loop",  // 节点副文字
        w: 200 },              // 节点宽度（默认 150，文字长就加宽）
    ]},
  ],

  edges: [                     // 依赖边：from import 了 to
    { from: "engine", to: "context", w: 11 },         // w = import 次数（线宽/×N 标签）
    { from: "tools", to: "kairos", w: 2, type: "typeonly" },  // 仅类型引用 → 虚线
  ],

  info: {                      // 每个节点的侧栏详情（见 §6 写作规范）
    engine: {
      role: "执行引擎：一次 turn 的总指挥",       // 一句话职责
      hub: true,                                  // 可选：编排中枢 → 橙底
      exports: [                                  // 对外暴露（3-6 条，支持 HTML）
        "<code>runTurnWithAgent</code>（desktop 的入口）",
      ],
      flow: "bridge 接单 → agent 编排 → loop 双层循环 → 事件流回吐。",  // 内部流程一句话
    },
  },
}
```

Tab ② 动画的数据是四个数组：`turnLanes`（泳道）、`turnNodes`（节点：lane 序号 + y 坐标 + label）、`turnEdges`（连线，可标 `loop:true` 回环）、`turnSteps`（步骤：当前节点 + 点亮哪条边 + caption HTML）。格式见 §8 模板内注释。

---

## §5 配色与语义（暖纸编辑风，直接抄）

整套视觉的关键是：**颜色是语义的，不是装饰的**。蓝永远 = 上游/选中，橙永远 = 下游/中枢，绿永远 = 暴露面。底色是带暖调的纸色而非纯白，深色仅用于代码块。

| CSS 变量 / 色值 | 用途 |
|---|---|
| `--paper #faf8f4` | 页面底色（暖纸） |
| `--card #ffffff` | 卡片底 |
| `--card-tint #fbfaf6` | 节点默认底 |
| `--ink #1a1815` | 主文字（暖黑） |
| `--ink-soft #5c574e` | 正文/说明 |
| `--ink-faint #8a8478` | 辅助小字 |
| `--line #e6e1d7` | 边框 |
| `#d8d2c4` | 默认依赖边 |
| `--accent #2456e6` | 选中 / 上游 / 链接 |
| `--accent-soft #eef2fe` | 上游节点底 |
| `--warn #b4690e` | 下游 / 中枢 / 动画当前步 |
| `--warn-soft #fdf3e4` | 下游/中枢节点底 |
| `--good #1a7f4e` | 「对外暴露」标题 / 已完成步 |
| `--good-soft #e8f5ee` | 已完成步节点底 |
| `--bad #c0392b` | 铁律/错误提示 |
| `#f1ede4` 底 / `#6b3f12` 字 | 行内 code |
| `#211e19` 底 / `#e8e3d8` 字 | 代码块 |

交互配色语义：

- 选中节点的**上游**（它依赖的）：蓝底蓝边（`--accent-soft` / `--accent`）
- 选中节点的**下游**（依赖它的）与 hub 中枢：橙底橙边（`--warn-soft` / `--warn`）
- 流动虚线动画 = `stroke-dasharray: 7 5` + `dashoffset` 无限滚动（0.55s linear）

排版规则：

- **字体三件套**：标题用衬线（Songti SC / Noto Serif CJK SC），正文用系统无衬线（PingFang SC 等），节点/代码/标签用等宽（SF Mono / JetBrains Mono / Menlo）。禁止引入网络字体。
- **非选中状态全图浅灰细线**（#d8d2c4 / 1.4px），选中后才显色——这是高密度图保持可读的关键：默认安静，交互时聚焦。
- 未选中的无关节点和边降为 `opacity .28 / .12`，而不是隐藏——保留空间感。

---

## §6 内容写作规范（侧栏与说明文字）

### 节点 info 三件套

| 字段 | 写法 | 好的例子 |
|---|---|---|
| role | 一句话 = 职责 + 定位修饰。不超过 25 字 | 「执行引擎：一次 turn 的总指挥」「契约宪法：跨进程共享类型唯一来源」 |
| exports | 3-6 条，**真实符号名**用 `<code>` 包裹，括号补一句用途。优先列被外部真实消费的符号（扫描 C），不要把 index.ts 全部导出抄上去 | 「`createKairos` → `KairosController`（start/stop/wakeNow）」 |
| flow | 一句「A → B → C」流程链，写清内部处理顺序，含关键决策点。可以两三个短句，但不要成段 | 「manager 注册 → scheduler 权限三态 → guard 校验 → executor → truncator 裁剪」 |

### 其他文字规则

- **子图 desc 必须点出结构模式**（中枢式/洋葱式/管线式/薄壳+核心……），并用一句话讲清这个模式在这里意味着什么。
- **typeonly 虚线边必须在相关节点 info 里给出解释**：「对 X 的虚线 = 仅类型引用（XxxContext），不是循环依赖」。
- 数字要真实且带来源含义：「消费 64 个符号」「×23」都来自扫描，不许编。
- 页面 lede（开头导语）写清交互说明：箭头语义、线宽语义、点击行为、蓝橙含义。页脚标注扫描日期 + 「架构变更后请重新扫描更新本图」。
- 中文文案用「」引号；不用 emoji；不堆形容词。

---

## §7 万能提示词（直接粘给任意 Agent）

把下面整块复制给 Agent（连同 §8 模板一起给，或告诉它本规范文件的路径）：

```text
请为本项目生成一份交互式架构依赖图谱（产物必须是单个 HTML 文件，命名 ARCHITECTURE_GRAPH.html）。
严格按以下规范执行，不要自由发挥视觉与交互设计——渲染器和样式用我提供的模板，你只负责扫描数据与填充内容。

【五条铁律】
1. 所有依赖图必须来自真实 import 静态扫描，禁止凭印象/文档画图。先写脚本扫描，再画图。
   页脚标注扫描日期与范围。
2. 箭头方向 = 依赖方向（A→B 即 A import 了 B），全文唯一语义；线宽按 import 次数加权。
3. 产物是单 HTML 文件、零外部依赖（无 CDN/网络字体/图表库），双击浏览器可开，离线可用。
4. 数据与渲染分离：所有图 = JS 数据对象 + 模板里的通用渲染器 renderGraph()，禁止手写 SVG。
5. 交付前必须在浏览器实际点击验证（节点高亮/侧栏/子图切换/动画步进），有报错不许交付。

【执行步骤】
Step 1 扫描：写脚本统计三类数据——
  A. 顶层模块（src 第一级目录）两两之间的 import 次数（排除 test）；
  B. 每个重要子系统内部的文件级依赖边；
  C. 外部消费者从本包 import 的符号清单（确定真实对外暴露面）。
Step 2 布局：层=依赖深度（基础类型在底层、入口装配在上层）；消费者画顶部横条、
  人人依赖的契约/类型包画底部横条（不画 N 条边，画成底座）；同层≤5 节点；
  反向依赖（通常是仅类型引用）标 typeonly 虚线并在 info 里解释，不许隐藏。
Step 3 填大图数据（Schema 见模板注释）：每节点 info 三件套——
  role（一句话职责）、exports（3-6 条真实符号，code 包裹）、flow（A→B→C 流程链）。
Step 4 填子系统图（挑 3-6 个核心子系统）：每张图 desc 点出结构模式
  （中枢式/洋葱式/管线式/薄壳+核心…）；编排中枢节点标 hub:true。
Step 5 数据流动画：挑最核心的一条业务链路（一次请求/turn/构建），3-5 条泳道、
  9-13 步；每步 caption 必须写「此刻传递的数据结构名 + 发生的转换」；
  循环链路用回环边单独一步讲。
Step 6 组装：复制模板，只替换三处数据区（bigGraph / subGraphs / turn*），
  不改渲染器与 CSS。
Step 7 验证：浏览器逐项点过（含：切换子图后侧栏要重置为空态——这是已知易错点）。

【视觉规范（模板已内置，列出便于你检查）】
暖纸底色 #faf8f4；蓝 #2456e6 = 选中/上游；橙 #b4690e = 下游/中枢；
绿 #1a7f4e = 暴露面标题；默认边浅灰 #d8d2c4 细线，选中才显色 + 流动虚线动画；
无关元素降透明度而非隐藏；衬线标题 + 无衬线正文 + 等宽节点文字；
中文用「」引号，无 emoji。

【交付物】
ARCHITECTURE_GRAPH.html 一个文件 + 三张验证截图（大图选中态 / 动画中段 / 任一子图选中态）。
```

---

## §8 完整模板（复制后只改数据区）

下面是**可直接运行的完整单文件模板**：包含全部 CSS、通用渲染器、Tab 切换、点击高亮、侧栏、子图切换、动画播放器，并附一套迷你示例数据（三个数据区均有 `==== 数据区 N ====` 标记）。复制保存为 `ARCHITECTURE_GRAPH.html`，把示例数据换成扫描结果即可。

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>项目名 依赖图谱 — 交互式架构图</title>
<style>
  :root {
    --ink: #1a1815; --ink-soft: #5c574e; --ink-faint: #8a8478;
    --paper: #faf8f4; --card: #ffffff; --card-tint: #fbfaf6;
    --line: #e6e1d7; --line-soft: #efebe2;
    --accent: #2456e6; --accent-soft: #eef2fe;
    --good: #1a7f4e; --good-soft: #e8f5ee; --good-line: #cde8da;
    --warn: #b4690e; --warn-soft: #fdf3e4; --warn-line: #f0dcbd;
    --mono: "SF Mono", "JetBrains Mono", Menlo, Consolas, monospace;
    --sans: -apple-system, "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif;
    --serif: "Songti SC", "Noto Serif CJK SC", Georgia, serif;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: var(--paper); color: var(--ink); font-family: var(--sans); font-size: 15px; line-height: 1.7; }
  nav { position: sticky; top: 0; z-index: 100; background: rgba(250,248,244,.93); backdrop-filter: blur(8px);
    border-bottom: 1px solid var(--line); padding: 0 24px; display: flex; align-items: center; gap: 4px; }
  nav .brand { font-family: var(--mono); font-size: 12px; letter-spacing: 3px; color: var(--accent); font-weight: 700;
    padding-right: 18px; border-right: 1px solid var(--line); margin-right: 10px; }
  nav button { color: var(--ink-soft); font-size: 13px; background: none; border: none; padding: 13px 11px;
    border-bottom: 2px solid transparent; cursor: pointer; font-family: var(--sans); }
  nav button.active { color: var(--accent); border-bottom-color: var(--accent); font-weight: 600; }
  main { max-width: 1340px; margin: 0 auto; padding: 36px 28px 100px; }
  .kicker { font-size: 12px; letter-spacing: .22em; text-transform: uppercase; color: var(--accent); font-weight: 600; }
  h1 { font-family: var(--serif); font-size: 32px; font-weight: 700; margin-top: 8px; }
  .lede { color: var(--ink-soft); max-width: 880px; margin-top: 8px; font-size: 14.5px; }
  .lede code { font-family: var(--mono); font-size: .88em; background: #f1ede4; color: #6b3f12; padding: 1px 6px; border-radius: 4px; }
  .tabpane { display: none; } .tabpane.active { display: block; }
  .graph-wrap { display: grid; grid-template-columns: 1fr 320px; gap: 18px; align-items: start; }
  @media (max-width: 1000px) { .graph-wrap { grid-template-columns: 1fr; } }
  .graph-card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 14px; }
  .graph-card svg { width: 100%; height: auto; display: block; }
  .legend { display: flex; flex-wrap: wrap; gap: 16px; margin: 10px 4px 2px; font-size: 12px; color: var(--ink-soft); align-items: center; }
  .legend .sw { width: 14px; height: 14px; border-radius: 4px; border: 1px solid var(--line); display: inline-block; }
  .side { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 18px 20px; position: sticky; top: 64px; }
  .side .ph { font-size: 12px; letter-spacing: .14em; text-transform: uppercase; color: var(--ink-faint); font-weight: 700; margin-bottom: 10px; }
  .side .empty { color: var(--ink-faint); font-size: 13px; padding: 18px 0; text-align: center; }
  .side h3 { font-family: var(--mono); font-size: 16px; color: var(--accent); margin-bottom: 2px; }
  .side .role { font-size: 12.5px; color: var(--ink-faint); margin-bottom: 10px; }
  .side .blk { margin-top: 12px; }
  .side .blk .bt { font-size: 11.5px; letter-spacing: .08em; font-weight: 700; color: var(--ink-soft); text-transform: uppercase; margin-bottom: 5px; }
  .side .blk.exp .bt { color: var(--good); } .side .blk.flow .bt { color: var(--warn); }
  .side ul { list-style: none; }
  .side ul li { font-size: 12.5px; padding: 3px 0 3px 14px; position: relative; color: var(--ink-soft); }
  .side ul li::before { content: "·"; position: absolute; left: 2px; color: var(--accent); font-weight: 700; }
  .side ul li code, .side .blk p code { font-family: var(--mono); font-size: 11.5px; background: #f1ede4; color: #6b3f12; padding: 0 5px; border-radius: 3px; }
  .side .blk p { font-size: 12.5px; color: var(--ink-soft); }
  .side .deps { display: flex; flex-direction: column; gap: 4px; margin-top: 4px; }
  .side .deps .d { font-size: 12px; font-family: var(--mono); display: flex; align-items: center; gap: 6px; }
  .side .deps .d.up .arr { color: var(--accent); font-weight: 700; }
  .side .deps .d.down .arr { color: var(--warn); font-weight: 700; }
  .side .hint { margin-top: 14px; padding-top: 12px; border-top: 1px dashed var(--line); font-size: 11.5px; color: var(--ink-faint); }
  .gnode { cursor: pointer; }
  .gnode rect { fill: var(--card-tint); stroke: var(--line); stroke-width: 1.2; transition: all .18s; }
  .gnode text { font-family: var(--mono); font-size: 12.5px; font-weight: 600; fill: var(--ink); pointer-events: none; }
  .gnode .sub { font-size: 9.5px; font-weight: 400; fill: var(--ink-faint); }
  .gnode:hover rect { stroke: var(--accent); fill: var(--accent-soft); }
  .gnode.sel rect { stroke: var(--accent); stroke-width: 2; fill: var(--accent-soft); }
  .gnode.up rect { stroke: #2456e6; fill: #eef2fe; }
  .gnode.down rect { stroke: #b4690e; fill: #fdf3e4; }
  .gnode.dim { opacity: .28; }
  .gnode.band rect { fill: #f4f1e9; }
  .gedge { fill: none; stroke: #d8d2c4; stroke-width: 1.4; transition: opacity .18s, stroke .18s; marker-end: url(#arr); }
  .gedge.typeonly { stroke-dasharray: 4 4; }
  .gedge.dim { opacity: .12; }
  .gedge.up { stroke: #2456e6; stroke-width: 2.2; marker-end: url(#arrBlue); stroke-dasharray: 7 5; animation: dashflow .55s linear infinite; }
  .gedge.down { stroke: #b4690e; stroke-width: 2.2; marker-end: url(#arrWarn); stroke-dasharray: 7 5; animation: dashflow .55s linear infinite; }
  @keyframes dashflow { to { stroke-dashoffset: -12; } }
  .gw { font-family: var(--mono); font-size: 9px; fill: var(--ink-faint); }
  .player { display: flex; align-items: center; gap: 10px; margin: 12px 0 4px; flex-wrap: wrap; }
  .player button { font-family: var(--sans); font-size: 13px; padding: 7px 16px; border-radius: 99px;
    border: 1px solid var(--line); background: var(--card); color: var(--ink); cursor: pointer; }
  .player button.primary { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }
  .player .stepinfo { font-size: 13px; color: var(--ink-soft); } .player .stepinfo b { color: var(--accent); font-family: var(--mono); }
  .turn-caption { margin-top: 10px; background: var(--accent-soft); border: 1px solid #d7e1fb; border-radius: 10px;
    padding: 12px 18px; font-size: 13.5px; color: var(--ink-soft); min-height: 66px; }
  .turn-caption b { color: var(--accent); }
  .turn-caption code { font-family: var(--mono); font-size: 12px; background: rgba(255,255,255,.7); color: #6b3f12; padding: 0 5px; border-radius: 3px; }
  #turnsvg .lane { fill: #f4f1e9; stroke: var(--line); }
  #turnsvg .lane-label { font-family: var(--mono); font-size: 12px; font-weight: 700; fill: var(--ink-soft); }
  #turnsvg .tnode rect { fill: var(--card); stroke: var(--line); stroke-width: 1.2; transition: all .25s; }
  #turnsvg .tnode text { font-size: 11.5px; fill: var(--ink-soft); pointer-events: none; }
  #turnsvg .tnode.lit rect { fill: var(--warn-soft); stroke: var(--warn); stroke-width: 2; }
  #turnsvg .tnode.lit text { fill: var(--ink); font-weight: 600; }
  #turnsvg .tnode.done rect { fill: var(--good-soft); stroke: var(--good-line); }
  #turnsvg .tedge { fill: none; stroke: #d8d2c4; stroke-width: 1.6; marker-end: url(#tarr); }
  #turnsvg .tedge.lit { stroke: var(--warn); stroke-width: 2.4; stroke-dasharray: 8 5; animation: dashflow .4s linear infinite; }
  #turnsvg .pulse { fill: var(--accent); filter: drop-shadow(0 0 6px rgba(36,86,230,.55));
    transition: cx .55s cubic-bezier(.4,0,.2,1), cy .55s cubic-bezier(.4,0,.2,1); }
  .subbar { display: flex; gap: 8px; margin: 4px 0 16px; flex-wrap: wrap; }
  .subbar button { font-family: var(--mono); font-size: 12.5px; padding: 6px 16px; border-radius: 99px;
    border: 1px solid var(--line); background: var(--card); color: var(--ink-soft); cursor: pointer; }
  .subbar button.active { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }
  .subdesc { font-size: 13.5px; color: var(--ink-soft); margin-bottom: 12px; max-width: 980px; }
  .subdesc b { color: var(--ink); }
  .subdesc code { font-family: var(--mono); font-size: 12px; background: #f1ede4; color: #6b3f12; padding: 0 5px; border-radius: 3px; }
  .footnote { margin-top: 40px; padding-top: 18px; border-top: 1px solid var(--line); font-size: 12px; color: var(--ink-faint); }
</style>
</head>
<body>

<nav>
  <span class="brand">项目名</span>
  <button class="tabbtn active" data-tab="t1">① 大模块依赖图</button>
  <button class="tabbtn" data-tab="t2">② 数据流动画</button>
  <button class="tabbtn" data-tab="t3">③ 子系统内部图</button>
</nav>

<main>

<div class="tabpane active" id="t1">
  <div class="kicker">Dependency Graph · 真实 import 统计</div>
  <h1>大模块依赖图：谁依赖谁，一眼看清</h1>
  <p class="lede">数据来自 import 静态扫描（扫描日期填这里）。<b>箭头方向 = 依赖方向</b>（A → B 表示 A import 了 B），
    线越粗 import 次数越多。<b>点击任意节点</b>：蓝色 = 它依赖的（上游），橙色 = 依赖它的（下游）。</p>
  <div class="graph-wrap">
    <div>
      <div class="graph-card"><svg id="bigsvg"></svg></div>
      <div class="legend">
        <span><span class="sw" style="background:var(--accent-soft);border-color:var(--accent)"></span> 上游（它依赖的）</span>
        <span><span class="sw" style="background:var(--warn-soft);border-color:var(--warn)"></span> 下游（依赖它的）</span>
        <span>虚线 = 仅类型引用 · 空白处点击取消选中</span>
      </div>
    </div>
    <aside class="side" id="bigside"><div class="ph">节点详情</div><div class="empty">点击图中任意模块节点查看详情。</div></aside>
  </div>
</div>

<div class="tabpane" id="t2">
  <div class="kicker">Animated Data Flow</div>
  <h1>核心链路数据流</h1>
  <p class="lede">蓝色脉冲 = 正在流动的数据。每一步说明此刻传递的数据结构与发生的转换。</p>
  <div class="player">
    <button class="primary" id="btnPlay">▶ 播放</button>
    <button id="btnPrev">← 上一步</button>
    <button id="btnNext">下一步 →</button>
    <button id="btnReset">⟲ 重置</button>
    <span class="stepinfo">步骤 <b id="stepNow">0</b> / <b id="stepTotal">0</b></span>
  </div>
  <div class="graph-card"><svg id="turnsvg" viewBox="0 0 1000 560"></svg></div>
  <div class="turn-caption" id="turnCaption">点击「播放」或「下一步」开始。</div>
</div>

<div class="tabpane" id="t3">
  <div class="kicker">Inside Each Subsystem</div>
  <h1>子系统内部图：核心文件谁依赖谁</h1>
  <p class="lede">同样来自真实 import 扫描。点击文件节点看职责、暴露接口和上下游。</p>
  <div class="subbar" id="subbar"></div>
  <div class="subdesc" id="subdesc"></div>
  <div class="graph-wrap">
    <div><div class="graph-card"><svg id="subsvg"></svg></div></div>
    <aside class="side" id="subside"><div class="ph">文件详情</div><div class="empty">点击图中文件节点查看详情。</div></aside>
  </div>
</div>

<div class="footnote">数据来源：import 静态扫描（日期）。架构变更后请重新扫描更新本图。</div>

</main>

<script>
/* ════ 通用渲染器（不要改） ════ */
const NS = "http://www.w3.org/2000/svg";
function el(tag, attrs, parent) {
  const e = document.createElementNS(NS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(e);
  return e;
}
function renderGraph(svg, graph, sidebarEl) {
  svg.innerHTML = "";
  svg.setAttribute("viewBox", `0 0 ${graph.w} ${graph.h}`);
  const defs = el("defs", {}, svg);
  [["arr","#d8d2c4"],["arrBlue","#2456e6"],["arrWarn","#b4690e"]].forEach(([id,color])=>{
    const m = el("marker", {id, viewBox:"0 0 10 10", refX:9, refY:5, markerWidth:7, markerHeight:7, orient:"auto-start-reverse"}, defs);
    el("path", {d:"M0,0 L10,5 L0,10 z", fill:color}, m);
  });
  const pos = {};
  (graph.bands||[]).forEach(b => { pos[b.id] = { x:30, y:b.y, w:graph.w-60, h:b.h, cx:graph.w/2, cy:b.y+b.h/2 }; });
  graph.layers.forEach(layer => {
    const totalW = layer.nodes.reduce((s,n)=>s+(n.w||150),0);
    const gap = (graph.w - 60 - totalW) / (layer.nodes.length+1);
    let x = 30 + gap;
    layer.nodes.forEach(n => {
      const w = n.w || 150, h = n.h || 52;
      pos[n.id] = { x, y:layer.y, w, h, cx:x+w/2, cy:layer.y+h/2 };
      x += w + gap;
    });
  });
  const edgeEls = [];
  const gEdges = el("g", {}, svg);
  graph.edges.forEach(e => {
    const a = pos[e.from], b = pos[e.to];
    if (!a || !b) return;
    let d;
    if (Math.abs(a.cy - b.cy) < 4) {
      const lift = 38 + Math.abs(a.cx-b.cx)*0.06;
      d = `M ${a.cx} ${a.y} C ${a.cx} ${a.y-lift}, ${b.cx} ${b.y-lift}, ${b.cx} ${b.y}`;
    } else {
      const from = a.cy < b.cy ? {x:a.cx, y:a.y+a.h} : {x:a.cx, y:a.y};
      const to   = a.cy < b.cy ? {x:b.cx, y:b.y} : {x:b.cx, y:b.y+b.h};
      const my = (from.y + to.y)/2;
      d = `M ${from.x} ${from.y} C ${from.x} ${my}, ${to.x} ${my}, ${to.x} ${to.y}`;
    }
    const sw = e.w ? Math.min(1 + Math.log2(e.w)*0.75, 4) : 1.4;
    const path = el("path", {d, class:"gedge" + (e.type==="typeonly"?" typeonly":""), "stroke-width": sw.toFixed(1)}, gEdges);
    path.dataset.from = e.from; path.dataset.to = e.to;
    edgeEls.push(path);
    if (e.w && e.w >= 4) {
      const mx = (a.cx+b.cx)/2, my2 = (Math.abs(a.cy-b.cy)<4 ? a.y-(38+Math.abs(a.cx-b.cx)*0.06)*0.72 : (a.cy+b.cy)/2);
      el("text", {x:mx+4, y:my2-2, class:"gw"}, gEdges).textContent = "×"+e.w;
    }
  });
  const nodeEls = {};
  const gNodes = el("g", {}, svg);
  function makeNode(id, label, sub, p, band) {
    const g = el("g", {class:"gnode" + (band?" band":"")}, gNodes);
    g.dataset.id = id;
    const r = el("rect", {x:p.x, y:p.y, width:p.w, height:p.h, rx:8}, g);
    if (graph.info[id] && graph.info[id].hub) { r.style.fill = "var(--warn-soft)"; r.style.stroke = "var(--warn-line)"; }
    el("text", {x:p.cx, y: sub ? p.y+p.h/2-4 : p.y+p.h/2+4, "text-anchor":"middle"}, g).textContent = label;
    if (sub) el("text", {x:p.cx, y:p.y+p.h/2+13, "text-anchor":"middle", class:"sub"}, g).textContent = sub;
    nodeEls[id] = g;
  }
  (graph.bands||[]).forEach(b => makeNode(b.id, b.label, b.sub, pos[b.id], true));
  graph.layers.forEach(l => l.nodes.forEach(n => makeNode(n.id, n.label, n.sub, pos[n.id], false)));
  function clearSel() {
    Object.values(nodeEls).forEach(g => g.classList.remove("sel","up","down","dim"));
    edgeEls.forEach(p => p.classList.remove("up","down","dim"));
    sidebarEl.innerHTML = `<div class="ph">节点详情</div><div class="empty">点击图中任意节点查看详情。</div>`;
  }
  function select(id) {
    const ups = new Set(), downs = new Set();
    graph.edges.forEach(e => { if (e.from === id) ups.add(e.to); if (e.to === id) downs.add(e.from); });
    Object.entries(nodeEls).forEach(([nid,g]) => {
      g.classList.remove("sel","up","down","dim");
      if (nid === id) g.classList.add("sel");
      else if (ups.has(nid)) g.classList.add("up");
      else if (downs.has(nid)) g.classList.add("down");
      else g.classList.add("dim");
    });
    edgeEls.forEach(p => {
      p.classList.remove("up","down","dim");
      if (p.dataset.from === id) p.classList.add("up");
      else if (p.dataset.to === id) p.classList.add("down");
      else p.classList.add("dim");
    });
    const info = graph.info[id] || {};
    let html = `<div class="ph">节点详情</div><h3>${id}</h3><div class="role">${info.role||""}</div>`;
    if (info.exports && info.exports.length)
      html += `<div class="blk exp"><div class="bt">对外暴露</div><ul>` + info.exports.map(x=>`<li>${x}</li>`).join("") + `</ul></div>`;
    if (info.flow) html += `<div class="blk flow"><div class="bt">内部如何处理</div><p>${info.flow}</p></div>`;
    const upArr = [...ups], downArr = [...downs];
    if (upArr.length || downArr.length) {
      html += `<div class="blk"><div class="bt">依赖关系</div><div class="deps">`;
      upArr.forEach(u => html += `<div class="d up"><span class="arr">→</span>依赖 ${u}</div>`);
      downArr.forEach(d2 => html += `<div class="d down"><span class="arr">←</span>被 ${d2} 依赖</div>`);
      html += `</div></div>`;
    }
    html += `<div class="hint">蓝 = 上游 · 橙 = 下游 · 流动方向 = import 方向</div>`;
    sidebarEl.innerHTML = html;
  }
  gNodes.addEventListener("click", ev => {
    const g = ev.target.closest(".gnode");
    if (g) { ev.stopPropagation(); select(g.dataset.id); }
  });
  svg.addEventListener("click", ev => { if (!ev.target.closest(".gnode")) clearSel(); });
}

/* ════ 数据区 1：大模块依赖图（替换为扫描 A 的结果） ════ */
const bigGraph = {
  w: 1000, h: 480,
  bands: [
    { id:"app", label:"app（消费者 · 装配与入口）", sub:"消费 core N 个符号", y: 24, h: 50 },
    { id:"shared", label:"shared（契约底座 · 纯类型）", sub:"所有模块都坐在它上面", y: 408, h: 50 },
  ],
  layers: [
    { y: 130, nodes: [ { id:"engine", label:"engine/", sub:"执行引擎", w: 200 } ]},
    { y: 270, nodes: [
      { id:"service-a", label:"service-a/", sub:"示例服务 A", w: 170 },
      { id:"types", label:"types.ts", sub:"内部类型", w: 150 },
    ]},
  ],
  edges: [
    { from:"app", to:"engine" },
    { from:"engine", to:"service-a", w:8 },
    { from:"engine", to:"types", w:5 },
    { from:"service-a", to:"types", w:3 },
    { from:"service-a", to:"engine", w:1, type:"typeonly" },
    { from:"types", to:"shared" },
  ],
  info: {
    app: { role:"装配方与入口", exports:["IPC handlers / CLI 入口"], flow:"收请求 → 装配 → 调 engine → 回流。" },
    shared: { role:"契约宪法：跨模块共享类型唯一来源", exports:["核心事件/类型"], flow:"纯类型，人人依赖（图上只画代表边）。" },
    engine: { role:"执行引擎：核心编排", hub:true, exports:["<code>run()</code>（入口）"], flow:"接单 → 编排依赖 → 循环 → 事件流回吐。" },
    "service-a": { role:"示例服务", exports:["<code>doThing()</code>"], flow:"预处理 → 执行 → 归一化返回。对 engine 的虚线 = 仅类型引用，不是循环依赖。" },
    types: { role:"内部类型体系", exports:["<code>Message</code> 等"], flow:"判别联合 + helper。" },
  },
};

/* ════ 数据区 2：子系统内部图（替换为扫描 B 的结果，可多个） ════ */
const subGraphs = {
  engine: {
    desc: `<b>洋葱式结构</b>：外层翻译协议，内层纯函数循环。`,
    graph: {
      w: 1000, h: 360,
      layers: [
        { y: 28, nodes: [ { id:"bridge", label:"bridge.ts", sub:"协议翻译", w: 280 } ]},
        { y: 150, nodes: [ { id:"agent", label:"agent.ts", sub:"入口类", w: 220 } ]},
        { y: 272, nodes: [
          { id:"loop", label:"loop.ts", sub:"纯函数循环", w: 200 },
          { id:"types", label:"types.ts", sub:"域契约", w: 180 },
        ]},
      ],
      edges: [
        { from:"bridge", to:"agent" }, { from:"agent", to:"loop" },
        { from:"agent", to:"types" }, { from:"loop", to:"types" },
      ],
      info: {
        bridge: { role:"最厚的翻译层", hub:true, exports:["<code>runWithBridge()</code>"], flow:"内部事件 → 外部协议实时翻译。" },
        agent: { role:"入口类", exports:["<code>Agent.run()</code>"], flow:"编排依赖，委托 loop。" },
        loop: { role:"纯函数循环（心脏）", hub:true, exports:["<code>runLoop()</code>"], flow:"调模型 → 执行 → 回填 → 再调，直到完成。" },
        types: { role:"域类型契约", exports:["<code>Event</code> 判别联合"], flow:"纯类型。" },
      },
    },
  },
};

/* ════ 数据区 3：数据流动画（替换为项目核心链路） ════ */
const turnLanes = [
  { label:"入口", x: 20,  w: 300 },
  { label:"编排", x: 350, w: 300 },
  { label:"执行", x: 680, w: 300 },
];
const turnNodes = [   // lane = 泳道序号(0起)，y = 纵坐标
  { id:"n1", lane:0, y: 90,  label:"收到请求" },
  { id:"n2", lane:1, y: 90,  label:"装配依赖" },
  { id:"n3", lane:2, y: 90,  label:"执行核心逻辑" },
  { id:"n4", lane:2, y: 220, label:"产出结果" },
  { id:"n5", lane:0, y: 220, label:"返回响应" },
];
const turnEdges = [   // loop:true 画回环
  { from:"n1", to:"n2" }, { from:"n2", to:"n3" },
  { from:"n3", to:"n4" }, { from:"n4", to:"n3", loop:true }, { from:"n4", to:"n5" },
];
const turnSteps = [   // node=脉冲所在节点 edge=点亮的边序号(null 不亮) cap=说明(写数据结构名!)
  { node:"n1", edge:null, cap:`<b>① 入口</b>：收到 <code>RequestInput</code>。` },
  { node:"n2", edge:0, cap:`<b>② 装配</b>：<code>RequestInput</code> + 配置 → <code>Deps</code>。` },
  { node:"n3", edge:1, cap:`<b>③ 执行</b>：核心循环开始。` },
  { node:"n4", edge:2, cap:`<b>④ 产出</b>：每轮产出 <code>Event</code>。` },
  { node:"n3", edge:3, cap:`<b>⑤ 循环</b>：未完成则回到执行（回环箭头）。` },
  { node:"n5", edge:4, cap:`<b>⑥ 返回</b>：聚合为 <code>Result</code> 返回调用方。` },
];

/* ════ 初始化（不要改） ════ */
document.querySelectorAll(".tabbtn").forEach(b => {
  b.addEventListener("click", () => {
    document.querySelectorAll(".tabbtn").forEach(x => x.classList.remove("active"));
    document.querySelectorAll(".tabpane").forEach(x => x.classList.remove("active"));
    b.classList.add("active");
    document.getElementById(b.dataset.tab).classList.add("active");
  });
});
renderGraph(document.getElementById("bigsvg"), bigGraph, document.getElementById("bigside"));
const subbar = document.getElementById("subbar");
let currentSub = Object.keys(subGraphs)[0];
Object.keys(subGraphs).forEach(k => {
  const b = document.createElement("button");
  b.textContent = k + "/"; b.dataset.k = k;
  if (k === currentSub) b.classList.add("active");
  b.addEventListener("click", () => {
    currentSub = k;
    subbar.querySelectorAll("button").forEach(x => x.classList.toggle("active", x.dataset.k === k));
    showSub(k);
  });
  subbar.appendChild(b);
});
function showSub(k) {
  document.getElementById("subdesc").innerHTML = subGraphs[k].desc;
  const side = document.getElementById("subside");
  side.innerHTML = `<div class="ph">文件详情</div><div class="empty">点击图中文件节点查看详情。</div>`;  // 切图必须重置侧栏
  renderGraph(document.getElementById("subsvg"), subGraphs[k].graph, side);
}
showSub(currentSub);

(function initTurn() {
  const svg = document.getElementById("turnsvg");
  const defs = el("defs", {}, svg);
  const m = el("marker", {id:"tarr", viewBox:"0 0 10 10", refX:9, refY:5, markerWidth:7, markerHeight:7, orient:"auto-start-reverse"}, defs);
  el("path", {d:"M0,0 L10,5 L0,10 z", fill:"#d8d2c4"}, m);
  const NW = 150, NH = 42;
  turnLanes.forEach(l => {
    el("rect", {x:l.x, y:46, width:l.w, height:480, rx:10, class:"lane"}, svg);
    el("text", {x:l.x+l.w/2, y:32, "text-anchor":"middle", class:"lane-label"}, svg).textContent = l.label;
  });
  const npos = {};
  turnNodes.forEach(n => {
    const lane = turnLanes[n.lane];
    const x = lane.x + (lane.w-NW)/2;
    npos[n.id] = { x, y:n.y, cx:x+NW/2, cy:n.y+NH/2 };
  });
  const edgeEls = [];
  turnEdges.forEach(e => {
    const a = npos[e.from], b = npos[e.to];
    let d;
    if (e.loop) {
      d = `M ${a.cx+NW/2} ${a.cy} C ${a.cx+130} ${a.cy+30}, ${b.cx+130} ${b.cy-30}, ${b.cx+NW/2} ${b.cy}`;
    } else if (Math.abs(a.cy-b.cy) < 6) {
      const dir = b.cx > a.cx ? 1 : -1;
      d = `M ${a.cx+dir*NW/2} ${a.cy} L ${b.cx-dir*NW/2} ${b.cy}`;
    } else if (Math.abs(a.cx-b.cx) < 6) {
      const dir = b.cy > a.cy ? 1 : -1;
      d = `M ${a.cx} ${dir>0?a.y+NH:a.y} L ${b.cx} ${dir>0?b.y:b.y+NH}`;
    } else {
      const sy = b.cy > a.cy ? a.y+NH : a.y;
      d = `M ${a.cx} ${sy} C ${a.cx} ${(a.cy+b.cy)/2}, ${b.cx} ${(a.cy+b.cy)/2}, ${b.cx} ${b.cy>a.cy?b.y:b.y+NH}`;
    }
    edgeEls.push(el("path", {d, class:"tedge"}, svg));
  });
  const nodeEls = {};
  turnNodes.forEach(n => {
    const p = npos[n.id];
    const g = el("g", {class:"tnode"}, svg);
    el("rect", {x:p.x, y:p.y, width:NW, height:NH, rx:7}, g);
    el("text", {x:p.cx, y:p.cy+4, "text-anchor":"middle"}, g).textContent = n.label;
    nodeEls[n.id] = g;
  });
  const pulse = el("circle", {class:"pulse", cx:npos[turnSteps[0].node].cx, cy:npos[turnSteps[0].node].cy, r:7, opacity:0}, svg);
  let step = -1, timer = null;
  const total = turnSteps.length;
  document.getElementById("stepTotal").textContent = total;
  const cap = document.getElementById("turnCaption");
  function apply(s) {
    step = s;
    document.getElementById("stepNow").textContent = Math.max(0, step+1);
    Object.values(nodeEls).forEach(g => g.classList.remove("lit","done"));
    edgeEls.forEach(p => p.classList.remove("lit"));
    if (step < 0) { pulse.setAttribute("opacity", 0); cap.innerHTML = "点击「播放」或「下一步」开始。"; return; }
    for (let i = 0; i <= step; i++) nodeEls[turnSteps[i].node].classList.add(i === step ? "lit" : "done");
    const cur = turnSteps[step];
    if (cur.edge !== null) edgeEls[cur.edge].classList.add("lit");
    const p = npos[cur.node];
    pulse.setAttribute("opacity", 1); pulse.setAttribute("cx", p.cx); pulse.setAttribute("cy", p.cy);
    cap.innerHTML = cur.cap;
  }
  function next() { if (step < total-1) apply(step+1); else stop(); }
  function stop() {
    if (timer) { clearInterval(timer); timer = null; }
    document.getElementById("btnPlay").textContent = "▶ 播放";
  }
  document.getElementById("btnPlay").addEventListener("click", function() {
    if (timer) { stop(); return; }
    if (step >= total-1) apply(-1);
    this.textContent = "⏸ 暂停";
    next();
    timer = setInterval(() => { if (step >= total-1) stop(); else next(); }, 2600);
  });
  document.getElementById("btnNext").addEventListener("click", () => { stop(); next(); });
  document.getElementById("btnPrev").addEventListener("click", () => { stop(); if (step > -1) apply(step-1); });
  document.getElementById("btnReset").addEventListener("click", () => { stop(); apply(-1); });
  apply(-1);
})();
</script>

</body>
</html>
```

---

## §9 交付前验证清单

| # | 检查项 |
|---|---|
| 1 | 双击打开，浏览器控制台无报错（F12 看 Console） |
| 2 | 大图：点击任一节点 → 自己蓝边选中、上游蓝底、下游橙底、其余变淡；依赖边变流动虚线；侧栏出现 role/exports/flow/依赖清单 |
| 3 | 大图：点击空白处 → 取消选中、侧栏回到空态提示 |
| 4 | 子图：切换子系统按钮 → 图正确重绘，**侧栏重置为空态**（易错：残留上一张图的详情） |
| 5 | 动画：播放自动步进且能暂停；上一步/下一步/重置都正确；脉冲点位置与当前步骤节点一致；已完成节点变绿、当前节点橙色 |
| 6 | 动画每步 caption 都包含数据结构名（code 标签） |
| 7 | typeonly 虚线边在对应节点 info 中有解释 |
| 8 | 页脚有扫描日期与「架构变更后请重新扫描」提示 |
| 9 | 断网刷新页面，功能完好（验证零外部依赖） |
| 10 | 抽查 3 条边与源码 import 对照，确认无凭空边 |

---

本规范提炼自 actspace-agent 项目 `ARCHITECTURE_GRAPH.html`（2026-06-10）的实际制作流程。规范与模板自包含，可独立用于任何项目。
