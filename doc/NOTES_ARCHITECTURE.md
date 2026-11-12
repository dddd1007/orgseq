# orgseq 笔记库架构

## 文档状态

> **这是一份设计规范文档，不是实现参考。**
>
> **2026-11-11 起，笔记库不再读取用户指定的本地目录。** 笔记库自动保存在 Emacs 目录下的 `notes/`（例如 `~/.emacs.d/notes/`，变量 `my/note-home`），多设备之间通过 `modules/notes/init-sync.el` 用 rclone 与 WebDAV、OneDrive 或 Google Drive 同步。本文档其余部分写作 `~/NoteHQ/` 的地方，均指这个笔记库；旧的 `~/NoteHQ/` 目录只在首次启动时被询问是否复制进来，不会被修改。存储、同步、视图、命令行与 MCP 见第十二节。
>
> 本文档记录 `~/NoteHQ/` 笔记库的**物理结构、tag 体系思路、capture 模板、dashboard 设计原则**与**生长原则**。这些内容是长期稳定的设计决策。
>
> **实现层面的事实**（函数名、加载顺序、键位、安装方式）请以下列源文件为准，因为它们随项目迭代而变化：
> - `modules/notes/init-org.el` — 路径常量 `my/note-home` / `my/roam-dir` / `my/orgseq-dir` / `my/types-file`（defcustom，属于 `org-seq` customize group）
> - `modules/notes/init-capture.el` 与 `kernel/orgseq-note.el` — 采集、capture 模板、Daily 命令
> - `kernel/orgseq-index.el` — 节点索引
> - 2026-11-12：org-roam 已从 org-seq 移除，下文凡提到 org-roam 的设计说明，现由节点索引、`init-capture` 和 `init-nodes` 承担。
> - `modules/notes/init-views.el` — 保存的视图（表格、列表、看板）、筛选语言、`orgseq-view` 动态块
> - `modules/notes/init-sync.el` — 笔记库的设备本地状态、旧库导入、rclone 同步
> - `core/orgseq-cli.el` 与 `bin/orgseq` — 命令行与 MCP 服务
> - `modules/notes/init-nodes.el` — 节点类型、字段、表格视图、review、dashboard 查询块、capture 模板合并、PARA 导航（函数前缀统一为 `my/`）
> - `~/NoteHQ/.orgseq/types.org` — 节点类型定义（用户数据，路径变量 `my/types-file`）
> - `modules/tools/init-dired.el` — dired + dirvish（文件管理与侧边栏）
> - `modules/editor/init-evil.el` — 所有 `SPC` leader key 绑定的唯一真相源
> - `scripts/bootstrap-notes.{sh,ps1}` — 笔记目录初始化与 NoteHQ/Codex 脚手架部署脚本（支持 `--update` 增量刷新）
> - `AGENTS.md` — 项目开发指南（模块加载顺序、设计决策、验证流程）
>
> 本文档中出现的代码片段仅作为**设计意图**说明。凡与源文件不一致之处，以源文件为准。

## 文档目的

本文档定义 `~/NoteHQ/` 笔记库的物理结构、tag 体系思路、capture 模板、dashboard 设计与生长原则，作为 org-seq 配置开发与数据初始化的依据。

这段设计文档基于一个核心承诺：**笔记系统应该跟随使用情况自然生长，而不是预先规划完整 schema**。下文的 properties、模板和 dashboard 都是按需采用的示例，不代表已经替用户迁移笔记。节点模型见第四节；Daily、PARA、GTD 保持现状。

---

## 一、设计原则

整个笔记库的物理结构和数据流向都可以从两条原则推导出来。

第一条：**把碎片想法和正式产出物物理分开存放**。原子笔记（一个想法一条）进入 `00_Roam/` 这个扁平目录，由节点索引负责检索和反向链接；正式产出物（论文、课件、申请书这类有明确交付时刻的东西）进入类 PARA 层级目录，文件结构反映可交付物自身的内在组织。两层之间通过 `[[id:...]]` 链接和 `org-transclusion` 通信，但不互相混杂。这条原则同时解决了两个常见痛点：一是当你的笔记库里混入 30 页的论文草稿，org-roam 的索引会开始变慢，搜索结果里也会出现大段无关的噪音；二是当你的项目目录里塞满未成形的想法碎片，你再也找不到"这个项目真正的可交付文件是哪几个"。分开存放让两类文件各得其所，也让两种工作模式（捕捉 vs. 打磨）保持清晰的边界。

第二条：**分类靠 tag，不靠新增类型目录**。`00_Roam/` 保留 `daily/`、`capture/` 和 `dashboards/` 等功能目录；默认独立笔记落在 `capture/`，Daily 标题也可持有自己的 Org ID。类别/主题可用标签，任务进度用 Org TODO，需要查询的附加信息用普通 Org properties，笔记间关系用 Org 链接。不是所有状态都该做成节点类型，也不要求记录时完成分类。

---

## 二、日常工作流

整个架构的存在理由只有一个：服务下面这个四阶段日常工作流。如果某个设计决策回答不了"它在这个工作流里起什么作用"，那它就不应该进入配置。读完这一节再回头看其他章节的具体决策——你会发现每一条都能回溯到这四个阶段中的某一个。

### 阶段 1：启动与定向 — Daily-first，GTD 辅助校准

Emacs 默认打开今天的 Daily Workspace，并在左侧显示只读的 14 日导航栏。先在今日 Daily 中落下当前上下文；需要制定或复核优先级时，再按 `SPC t d` 打开 GTD Dashboard。Daily 是默认入口和执行记录面，GTD 仍负责回答“今天优先推进什么”，二者不再要求人为先打开 GTD 才能开始工作。

### 阶段 2：执行与记录 — Daily 笔记作为思维流与任务录入入口

启动后已经位于当天的 Daily；也可随时按 `SPC d` 返回。这个文件同时承担两个职责：

**职责 A：思维流捕捉**。一边做事一边记录进展、观察、临时想法、半成形的洞察。文字写法不严谨，可以是流水账、问句、断句。每条记录前可以用时间戳标记（手动 `[2026-04-09 14:30]` 或 `SPC b j` 插入）。

**职责 B：任务录入入口**。日常 TODO 可以直接在 Daily 中就地写入。agenda 扫描 `00_Roam/`、`10_Outputs/` 和 `20_Practice/`，不扫描 Library 或 Archives；Daily 中的任务因此进入 GTD Dashboard，而不依赖节点类型。

任务类型按照是否有子任务进行区分：

- **没有子任务的事 → 单条 TODO**
- **存在子任务的条目 → PROJECT**

```org
* [2026-04-09 09:30] 启动
今天主要推进备课和论文修订。

* TODO 回邮件给某老师 :@office:

* PROJECT 准备应用心理统计 week 5 课件
** TODO 列大纲
** TODO 写引入案例
** NEXT 制作 PPT
** TODO 准备课堂练习

* TODO 给学生发本周作业反馈 :@office:
```

orgseq 的 GTD keyword 序列是 `PROJECT/TODO → NEXT → IN-PROGRESS → WAITING / SOMEDAY → DONE / CANCELLED`。`SPC t e` 一键切换状态，`SPC t d` 看到的 GTD Dashboard 会自动统计这些任务。

这个设计的好处：所有任务的"出生地"就是当时正在写的 daily 流水，任务的上下文（为什么要做、跟今天的什么思考有关）天然保留在同一个文件里。不需要先打断思路去 capture，再回头记笔记。

任务完成后不需要做任何归档动作。daily 文件本身就是历史档案，`SPC t l` Logbook 视图会自动汇总所有 DONE 状态的任务。

### 阶段 3：碎片提取 — 当某条想法值得独立存在

写 daily 时如果出现某条内容，你判断"这值得作为独立笔记长期追溯"，立刻执行：

1. 把光标停在那段内容（或要新建的word）上，按 `SPC n c` 选合适的 capture 模板（多数时候用 default 即可；有对应类型时在 `t` 组下选该类型）
2. capture 出一个新的 Roam 节点，文件落到 `00_Roam/capture` 目录，在 daily 原位置插入 `id:` 链接（`SPC n i`）
3. 从下方弹出buffer让我可以编辑这个节点内容
4. 需要时用 `SPC # t` 加类型，`SPC # f` 填字段，`SPC # e` 编辑任意 Org property；这些都是可选的后续操作，不是记录时必须填写的表单
5. 关闭，回到 daily 继续

如果那段内容已经写成文字，也可以选中它按 `SPC # p`：选区被提取为新笔记，daily 原位置留下指向新笔记的链接。


### 阶段 4：汇总与整理 — Dashboard 作为周期性 review 入口

每天结束、每周末、或某项工作收尾时，按 `SPC n v v` 选择 dashboard。它是**查询窗口**，由节点索引中已保存笔记渲染；org-seq 的打开入口刷新动态块，动态块本身不会持续自动刷新。另用 `SPC # r` 打开 review 表格，列出最近没有类型或没有链接的笔记。在 dashboard 和 review 里你做的事情：

- 看本周新增的笔记是否需要补充类型、字段或链接
- 看某个主题的所有相关碎片是否暗示着新的洞察
- 看哪些笔记之间应该建立链接但还没建立
- 决定哪些碎片足够成熟，可以晋升到 PARA 层成为正式产出物的素材

dashboard **永远不是录入入口**，永远只是窗口。任何想"在 dashboard 里写注释"的冲动都该被拒绝 —— 那些内容应该写到独立的 Roam 节点里。

---

## 三、物理结构

```
~/NoteHQ/
├── 00_Roam/                              ← 原子层 (节点索引范围)
│   ├── daily/                         ← 每日笔记 (唯一例外子目录)
│   ├── dashboards/                    ← 查询入口文件 (唯一例外子目录)
│   └── capture/20260409143022-*.org    ← 默认独立笔记,时间戳前缀文件名
│
├── 10_Outputs/                           ← PARA 产出层
│   └── _template/                     ← 项目目录模板,复制后改名使用
│
├── 20_Practice/                          ← PARA 实践层
│   └── _template/                     ← 实践域模板
│
├── 30_Library/                           ← PARA 资源层
│   ├── bibliography/
│   ├── datasets/
│   ├── snippets/
│   ├── references/
│   └── pdfs/
│
└── 40_Archives/                          ← 归档层
```

### 各层职责对照

| 层 | 用途 | 进入门槛 | 寿命 |
|---|------|---------|------|
| `00_Roam/capture` | 原子笔记、想法碎片、文献摘要、概念定义 | 低，鼓励大量录入 | 永久 |
| `00_Roam/daily/` | 当日意识流、工作流水、TODO 录入 | 极低，随便写 | 永久但低访问 |
| `00_Roam/dashboards/` | 查询定义文件 | 高，只放查询不放数据 | 长期 |
| `10_Outputs/` | 有明确交付时刻的产出物 | 中，每个目录是一份可交付物 | 1 周到 6 个月 |
| `20_Practice/` | 长期承担的角色与责任沉淀 | 中，每个目录是一个实践域 | 多年 |
| `30_Library/` | 被消耗的素材库，二进制、大段非原子材料 | 高，能原子化的都该去 Roam | 长期 |
| `40_Archives/` | 已完成或停滞的内容 | 无，按年份组织 | 永久 |

### 关键 elisp 配置

所有 NoteHQ 相关的路径都是 `modules/notes/init-org.el` 中 defcustom 形式的变量，通过 `M-x customize-group RET org-seq` 可见：

```elisp
;; init-org.el —— 所有路径的唯一真相源
(defcustom my/note-home   (file-truename "~/NoteHQ/")             ...)  ; 总根
(defcustom my/roam-dir    (expand-file-name "00_Roam/"   my/note-home) ...) ; 原子层
(defcustom my/orgseq-dir  (expand-file-name ".orgseq/" my/note-home) ...); 个性化配置

;; kernel/orgseq-index.el —— 节点索引读取 00_Roam/ 等层，缓存在 .cache/，不进笔记库

;; init-gtd.el —— agenda 跨 Roam + Outputs + Practice
;; daily 笔记里的 TODO/PROJECT 通过这个范围进入 GTD 视图
(my/agenda-files)  ; returns 00_Roam/ + 10_Outputs/ + 20_Practice/ (not 30_Library/ or 40_Archives/)

;; init-org.el —— 节点类型注册表放在 .orgseq/,不在 agenda 扫描范围内
(defcustom my/types-file (expand-file-name "types.org" my/orgseq-dir) ...)
```

**重要**：org-seq 内部**没有任何模块**应该硬编码 `~/NoteHQ/00_Roam/` 字符串——全部通过 `my/roam-dir` 或 `my/note-home` 派生。如果你在新写的模块里看到硬编码路径，请统一替换成变量。

### PARA 三层的判定测试

当一份内容拿不准放哪一层，依次回答 3 个问题：

1. **它会"完成"吗？** 能想象明确的完成时刻 → 倾向 `10_Outputs/`
2. **你对它有外部义务吗？** 长期角色、有责任对象 → 倾向 `20_Practice/`
3. **你会主动审阅它，还是只是取用它？** 主动审阅 → 倾向 `20_Practice/`；只是取用 → 倾向 `30_Library/`

不确定时默认放 `10_Outputs/`。Outputs 有更高的可见度，会被频繁打开；放进 Practice 容易被遗忘；放进 Library 容易过期。

---

## 四、节点模型与权威边界

2026-10-22 起，org-seq 不再使用 Supertag 和 TextUI。笔记结构直接建立在节点索引上（当时是 org-roam，2026-11-12 起 org-roam 已移除），由 `modules/notes/init-nodes.el` 提供类型、字段、表格视图和查询。设计参照 Tana 的 supertag 和 Fibery 的数据库，但不引入第二个数据库。

### 节点

节点是任何带 Org ID 的文件或标题。节点之间的关系是 `[[id:...]]` 链接。没有 ID 的标题不是节点；`SPC # p` 可以给当前标题补上 ID，使它成为原位节点。

### 类型：`.orgseq/types.org`

类型是一个 Org 标签、一组字段、若干公式和若干 capture 模板，相当于 Notion 的一个数据库或 Tana 的一个 supertag。所有类型定义在 `~/NoteHQ/.orgseq/types.org`（变量 `my/types-file`，在 `init-org.el` 中定义），每个一级标题定义一个类型：

```org
* Reading
:PROPERTIES:
:TYPE_TAG:    reading
:TYPE_KEY:    r
:TYPE_FIELDS: AUTHORS YEAR STATUS TOPIC:node
:STATUS_ALL:  queued reading read cited
:END:
** Summary
%?
** Key points
** My commentary
```

| 属性 | 含义 |
|---|---|
| `TYPE_TAG` | 类型对应的 Org 标签；省略时取标题名的小写形式 |
| `TYPE_KEY` | capture 键；生成的模板键为 `t` 加该字母（上例为 `tr`） |
| `TYPE_FIELDS` | 字段名，空格分隔；写成 `NAME:node` 的字段保存指向另一个节点的 `[[id:]]` 链接，其他字段种类见第十二节 |
| `NAME_ALL` | 字段 `NAME` 的可选值，沿用 Org 自身的 `KEY_ALL` 约定 |
| `FORMULA_NAME` | 公式列 `NAME`，在视图运行时计算，不写回笔记，见第十二节 |
| `TYPE_VIEW_*` | 该类型默认视图的布局、分组、排序、列、筛选和数量上限，见第十二节 |

标题正文就是该类型的默认 capture 模板，层级比定义处浅一级，`%?` 是光标落点。名为 `Template: 名称` 的二级子标题是另一个具名模板（相当于 Notion 数据库模板），它的正文比子标题浅两级；具名模板不属于默认模板，也不是类型，里面的属性抽屉不影响字段：

```org
* Reading
:PROPERTIES:
:TYPE_FIELDS: AUTHORS YEAR STATUS
:END:
** Summary
%?
** Template: Paper
*** Question
%?
*** Method and data
```

只有正文没有 `Template:` 子标题的旧 `types.org` 照常使用，含义不变。

`types.org` 放在 `.orgseq/`，不放在 `00_Roam/`：GTD agenda 扫描 `00_Roam/`、`10_Outputs/` 和 `20_Practice/`，模板里的 TODO 标题如果放在这些目录中会进入 agenda。文件不存在时 org-seq 自动创建一份带 Reading、Concept、Person 三个示例的起始文件。`SPC # T` 打开该文件，保存后类型立即重载（`my/node-types-reload`）。

### 应用类型与填写字段

- `SPC # t`（`my/node-set-type`）给光标所在节点加一个类型：文件节点写入 `#+filetags:`，标题节点写入标题标签；节点还没有 ID 时先补 ID。`my/node-add-empty-fields` 为非 nil（默认）时，同时为该类型的字段添加空 property，提示有哪些字段可填。
- `SPC # x`（`my/node-remove-type`）移除类型标签，已有字段值保留。
- `SPC # f`（`my/node-set-field`）设置字段。`NAME:node` 字段弹出节点选择器，写入 `[[id:...][标题]]`；其他字段从 `NAME_ALL` 或库中已经用过的值里补全，也可以输入新值。
- `SPC # e`（`org-set-property`）编辑任意 Org property。

应用类型后，Org 文本就是全部数据，例如：

```org
:PROPERTIES:
:ID:       example-reading-id
:AUTHORS:  Example Author
:YEAR:     2026
:STATUS:   reading
:TOPIC:    [[id:example-topic-id][一个主题]]
:END:
#+title: 一篇阅读笔记
#+filetags: :reading:
```

一个节点可以同时有多个类型。字段就是普通 Org property，不属于任何类型时也可以存在。

### 视图与回顾

- `SPC # v`（`my/node-view`）打开某个类型的视图，相当于 Notion 的数据库页面：`views.org` 里与类型同名的视图，没有时是该类型的默认视图（包括子类型的节点，字段和公式作为列）。加前缀参数（`C-u SPC # v`）时，可以在它和该类型的其他保存视图之间选择。视图内的按键见第十二节“视图”。
- `SPC # r`（`my/node-review`）列出最近 `my/node-review-days`（默认 14）天内修改过、没有类型或没有任何 id 链接（入链和出链都为 0）的笔记，不含带 `daily` 标签的笔记。列为标题、类型、入链数、出链数和修改日期。这是周回顾时的整理清单：给笔记加类型、建立链接，或者确认它保持为碎片。
- Dashboard 中的 `orgseq-query` 动态块按同样的条件生成 Org 表格，见第七节。

### 节点操作菜单

`SPC # #`（也是 `SPC n o` 和 `, # #`）打开 `my/node-action`，对应 Tana 的命令行。菜单内容随上下文变化：有选区时可提取为新笔记；不在节点内时可把标题变成节点；节点已有类型时可设置字段、移除类型、查看该类型的表格。另有插入链接、切换反向链接面板、复制节点链接、添加别名、编辑任意 property、新建类型笔记和打开 review。

`SPC # p`（`my/node-promote`）有两种行为：有选区时把选区提取为新笔记，原位置留下指向新笔记的链接，新笔记的 `Source` 小节链接回原节点；没有选区时给当前标题补 ID，使它原位成为节点，然后询问是否加类型。它不会把笔记移动到 PARA 目录。

### 单一权威

Org 文本是唯一权威。类型是标签，字段是 property，关系是 `[[id:]]` 链接。节点索引只是缓存，随时可以用 `M-x my/index-rebuild` 从 Org 文件重建；每次刷新只重读时间或大小变了的文件。

由此得到两条规则：

1. 视图、review 和 dashboard 读取数据库，反映已保存的文件，不反映未保存的缓冲区修改。对光标所在节点的命令（加类型、设字段）直接读缓冲区，所以对刚 capture、尚未索引的笔记也有效。
2. 备份覆盖 Org 文件和 `.orgseq/`（`types.org`、`capture-templates.el`）即可。数据库不需要备份。

心智模型是：**先写 Org → 需要引用时给它 ID → 逐步补类型、字段和链接 → 用表格视图和 review 回顾 → 由人确认概念与关系**。它与 Daily 的低摩擦捕捉相容，不要求把 PARA 或 GTD 改造成数据库。

### 旧 Supertag 数据

- 笔记里原有的 `#+filetags:` 和标题标签仍是普通 Org 标签。某个标签与 `types.org` 中的 `TYPE_TAG` 相同时，带该标签的笔记自动属于该类型。
- 原有 properties 原样保留，可以直接列入某个类型的 `TYPE_FIELDS`。
- 旧 dashboard 中的 `supertag-query` 动态块仍可渲染，支持 `(tag ...)`、`(property K V)`、`(recent-days N)` 和 `(and ...)` 四种形式；其他形式会在表格位置显示错误说明。新的 dashboard 应改用 `orgseq-query`。
- `supertag-schema.el`、`.supertag-metadata.eld` 和 Supertag 本地数据库不再被读取，可以作为档案保留。

---

## 五、Capture 模板

Capture 模板由三个来源按顺序合并（`my/reload-capture-templates`）：

1. **内置默认模板**：定义在 `modules/notes/init-capture.el`（`my/default-capture-templates`），只有一个 `d`（Default），落到 `00_Roam/capture/%<%Y%m%dT%H%M%S>-${slug}.org`，不带 filetag。这是部署时会被覆盖的部分，**不建议**修改。

2. **类型模板**：由 `types.org` 自动生成，归在 `t`（Typed note）组下，键为 `t` 加 `TYPE_KEY`（省略 `TYPE_KEY` 时取标签首字母，重复时追加数字）。目标文件同样在 `00_Roam/capture/`，文件头带 `#+filetags: :TYPE_TAG:`，正文取自类型标题的正文。新笔记创建后自动加上该类型的空字段。修改 `types.org` 并保存后，这部分模板随之更新。

3. **用户自由模板**：放在 `~/NoteHQ/.orgseq/capture-templates.el`，通过 `setq my/user-capture-templates` 定义，用于不需要字段和视图、只需要正文骨架的笔记。文件不存在时 `init-nodes.el` 创建一份带注释示例的骨架。以 `t` 开头的键保留给类型模板。

```elisp
;; ~/NoteHQ/.orgseq/capture-templates.el
(setq my/user-capture-templates
      '(("m" "Meeting" plain
         "* Attendees\n* Notes\n%?\n* Decisions\n"
         :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                            "#+title: ${title}\n")
         :unnarrowed t)
        ))
```

### 常用操作

- `SPC c` / `SPC n c` — 新建笔记，在 capture 菜单中选择模板
- `SPC # n`（`my/node-capture`）— 先选类型再输入标题，直接新建该类型的笔记
- `SPC # T`（`my/node-types-edit`）— 打开 `types.org`，保存即生效
- `SPC # c`（`my/edit-capture-templates`）— 打开 `capture-templates.el`
- `SPC # C`（`my/reload-capture-templates`）— 重载全部模板（无需重启 Emacs）
- 在 `~/NoteHQ/` 目录里让 Codex 按 `AGENTS.md` 约定帮你编写类型或模板

### 起步建议

**只需要 default 模板就够**。某类笔记反复需要固定字段、并且需要按字段查看和筛选时，在 `types.org` 中为它定义类型；只需要固定正文骨架时，在 `capture-templates.el` 中加一个自由模板。不要求每个标签都对应一个类型或模板。

---

## 六、`modules/notes/init-nodes.el` 模块职责

> **实现参考**：真实代码在 `modules/notes/init-nodes.el`，请以源文件为准。本节只说明模块的**设计职责**。

`init-nodes.el` 在节点索引之上提供类型、字段、视图和操作，并承担原 `init-supertag.el` 中与 Supertag 无关的职责：

1. **消费集中路径常量**：`my/types-file`、`my/capture-templates-file`、`my/dashboards-dir` 以及 PARA 各层路径全部在 `init-org.el` 中从 `my/note-home` 派生，本模块只通过 `defvar` 使用。

2. **类型注册表**：解析 `types.org`（`my/node-types`），文件缺失时创建起始文件（`my/node-types-ensure-file`），保存时重载（`my/node-types-reload`）。对应 `SPC # T`。

3. **Capture 模板合并**：内置默认模板、类型模板和用户模板按此顺序合并为 org-seq 的 capture 模板列表；`my/edit-capture-templates` / `my/reload-capture-templates` 对应 `SPC # c` / `SPC # C`。

4. **节点命令**：`my/node-set-type`、`my/node-remove-type`、`my/node-set-field`、`my/node-promote`、`my/node-capture-region-as-note`、`my/node-copy-id-link`、`my/node-capture`。

5. **查询**：`my/node-query` 按标签、字段值、修改天数筛选节点，并排序和截断。表格视图和 dashboard 动态块都用它。

6. **视图入口**：`my/node-view` 打开类型视图，交给 `init-views.el` 的 `my/view-show-type`；`my/node-review`（待整理笔记）使用本模块的 `my/node-view-mode` 表格。

7. **Dashboard 动态块**：`orgseq-query` 块的渲染函数，以及旧 `supertag-query` 块的兼容渲染。

8. **节点操作菜单**：`my/node-action`，对应 `SPC # #` / `SPC n o` / `, # #`。

9. **Dashboard 导航与创建**：
   - `my/dashboard-find`：从 `00_Roam/dashboards/` 选择一个 dashboard 打开并刷新所有动态块。对应 `SPC n v v`。
   - `my/dash-index` / `my/dash-review`：命名快捷方式。对应 `SPC n v i` / `SPC n v w`。
   - `my/dashboard-create`：提示名字和类型后生成带一个 `orgseq-query` 块的新 dashboard 文件。对应 `SPC # D`。
   - 需要更多快捷方式时，直接在 `00_Roam/dashboards/` 加文件，用 `my/dashboard-find` 访问即可，**不必再改 elisp**。

10. **PARA 层导航**：`my/find-in-outputs` / `my/find-in-practice` / `my/find-in-library` / `my/ripgrep-notehq`。对应 leader key：`SPC P o` / `SPC P p` / `SPC P l` / `SPC P g`。

11. **NoteHQ 目录结构 bootstrap**：`my/ensure-notehq-structure` 在启动完成后的空闲时间调用，幂等地创建 `00_Roam/daily/` / `00_Roam/capture/` / `00_Roam/dashboards/` / `10_Outputs/` / `20_Practice/` / `30_Library/` / `40_Archives/`。

### 加载顺序要求

`init-nodes.el` 依赖 `init-org`（路径常量）和 `init-capture`（默认 capture 模板），加载位置在 `init-pkm.el` 之后、`init-daily.el` 之前。完整链条见 `AGENTS.md` 的 "Load Order" 小节。

### 函数命名约定

所有函数统一用 `my/` 前缀（私有 helper 用 `my/module--helper` 双短横线）。**不使用** `orgseq/` 前缀——这是早期设计草稿的命名方案，已被统一为 `my/`。动态块名 `orgseq-query` 是 Org 动态块的名字，不是函数前缀。

---

## 七、Dashboard 起点

每个 dashboard 是 `~/NoteHQ/00_Roam/dashboards/` 下的独立 org 文件，只存查询定义。下面只给 3 个起点文件：一个总入口、一个 weekly review、一个按类型和状态分组的示例。**需要更多 dashboard 时按这个模式自己加**。

### `index.org`

```org
#+title: Dashboards Index
#+startup: showall

* 入口
  - [[file:weekly-review.org][Weekly review]] :: 周回顾入口
  - [[file:reading.org][Reading]] :: reading 类型查询示例

* 快捷键
  - ~SPC # t~ 给当前笔记加类型，~SPC # f~ 填字段
  - ~SPC # v~ 查看某个类型的全部节点
  - ~SPC # r~ 整理最近没有类型或链接的笔记
  - ~SPC # p~ 把选区提取为新笔记，或把标题变成节点
  - ~SPC n c~ 新建笔记
  - ~SPC # #~ 节点操作菜单
  - ~SPC P o/p/l~ PARA 导航 (10_Outputs/20_Practice/Library)

* 最近修改的 reading 节点
#+BEGIN: orgseq-query :type "reading" :sort "modified" :order desc :limit 10
#+END:

* 增加新 dashboard 的步骤
  1. SPC # D (my/dashboard-create) 生成带一个查询块的新 dashboard 文件
  2. 编辑 #+BEGIN: orgseq-query 块的参数
  3. SPC n v v (my/dashboard-find) 会自动列出此目录下的所有 .org 文件,
     无需再改 elisp 或加命名函数
```

### `weekly-review.org`

```org
#+title: Weekly Review
#+startup: content
#+description: 每周末打开,review 本周累积内容并整理

* 最近七天的节点
#+BEGIN: orgseq-query :recent-days 7 :sort "modified" :order desc :limit 50
#+END:

* Review checklist
  - [ ] SPC # r 列出的笔记是否需要补类型、字段或链接?
  - [ ] 是否有想法应该建立链接但还没建立?
  - [ ] daily 里的 TODO 是否都已经被推进或重新调度?
  - [ ] 是否有碎片足够成熟,应该晋升到 PARA Outputs?
  - [ ] types.org 中是否需要新增或修改某个类型?
```

### `reading.org`

```org
#+title: Reading Queue
#+startup: content
#+description: 按类型和 STATUS 字段分组查询的示例 dashboard。其他类型可以仿照这个文件创建。

* 待读
#+BEGIN: orgseq-query :type "reading" :where (("STATUS" "queued")) :columns ("AUTHORS" "YEAR" "TOPIC") :sort "YEAR"
#+END:

* 在读
#+BEGIN: orgseq-query :type "reading" :where (("STATUS" "reading")) :columns ("AUTHORS" "YEAR" "TOPIC")
#+END:

* 已读
#+BEGIN: orgseq-query :type "reading" :where (("STATUS" "read")) :columns ("YEAR" "TOPIC") :sort "YEAR" :order desc
#+END:
```

### 关于查询参数的说明

`orgseq-query` 的参数就是 `my/node-query` 的参数，另加 `:columns`：

| 参数 | 含义 |
|---|---|
| `:type` 或 `:tag` | 节点必须带的标签 |
| `:where` | `(("FIELD" "value") ...)`，每个字段值必须完全相等 |
| `:recent-days N` | 文件在最近 N 天内修改过 |
| `:sort` | `"title"`（默认）、`"modified"` 或某个字段名；两边都是数字时按数值比较 |
| `:order` | `asc`（默认）或 `desc` |
| `:limit N` | 最多 N 行 |
| `:columns` | 要显示的字段列表；省略时取该类型的全部字段 |

第一列总是链接到节点的标题。动态块以 `#+END:` 结束；在块上 `C-c C-c` 或 `org-update-all-dblocks` 刷新，org-seq 的 dashboard 打开入口也会刷新。结果来自节点索引，只反映已保存的文件。没有匹配节点时块内显示 `No matching nodes.`。

---

## 八、初始化种子文件

bootstrap 脚本应该创建以下种子文件，让用户启动后立刻有可读、可编辑的真实示例。每个文件都极简，目的只是演示模式。

### `00_Roam/daily/example-day.org` —— 示例 daily 笔记

```org
#+title: 2026-04-09
#+filetags: :daily:

* [2026-04-09 09:30] 启动
今天看了 GTD dashboard,主要推进备课和论文修订。

* TODO 回邮件给某老师 :@office:

* PROJECT 准备应用心理统计 week 5 课件
** TODO 列大纲
** TODO 写引入案例
** NEXT 制作 PPT

* [2026-04-09 10:15] 工作记录
写初稿时想到一个观点:[[id:placeholder-idea-1][示例想法]]
这条想法已经被提取为独立的 Roam 节点 (见上面的 id 链接),
留在这里只剩链接。

* [2026-04-09 11:40] 阅读
扫了一篇文章,觉得相关度高,提取为 reading 节点。

* TODO 给学生发本周作业反馈 :@office:

* [2026-04-09 14:20] 思维流水
下午临时想到的小事,只跟今天有关,不需要提取。
比如: 中午食堂的菜不错。某个 PPT 的字体要调大一号。
这些直接留在 daily 里。

* [2026-04-09 17:00] 收工
今天主要进展见上。明天的 NEXT 已加到 GTD inbox。
```

### `00_Roam/example-fragment.org` —— 示例 Roam 碎片

```org
:PROPERTIES:
:ID:       placeholder-idea-1
:CREATED:  [2026-04-09 10:15]
:END:
#+title: 示例想法

这是一条从 daily 中提取出来的独立笔记。
它代表一个值得长期追溯的想法。

最初记录于 [[file:daily/example-day.org][2026-04-09]] daily 笔记。

* COMMENT 后续操作
按 SPC # t 添加类型。
建议先用 default 模板的形式存在,等到积累了几条类似笔记
再考虑在 types.org 中为它们定义一个类型。
```

### `10_Outputs/_template/README.org` —— 项目目录模板

```org
#+title: 项目模板
#+description: 复制此目录,改名为具体项目目录后使用

Outputs 层每个子目录代表一个具体可交付物,有明确的开始和结束。
例如一篇论文、一份基金申请、一门课的本学期版本。

典型结构:

  ./manuscript.org    主交付物
  ./notes.org         项目相关的工作笔记
  ./bibliography.bib  本项目引用 (或链接到 30_Library/bibliography/master.bib)
  ./figures/          配图
  ./drafts/           历史草稿

完成后归档:
  mv ~/NoteHQ/10_Outputs/your-project-name ~/NoteHQ/40_Archives/2026-your-project-name

与 Roam 层的交互:
- 在 manuscript.org 里用 SPC n i 引用 Roam 节点 (id: 链接)
- 用 org-transclusion 把 Roam 节点的内容实时嵌入 manuscript
```

### `20_Practice/_template/README.org` —— 实践域模板

```org
#+title: 实践域模板
#+description: 复制此目录,改名为具体实践域后使用

Practice 层每个子目录代表一个长期承担的角色或责任领域。
不会"完成",会持续累积。

典型结构:

  ./philosophy.org     方法论与原则
  ./workflow.org       SOP 与工作流
  ./resources.org      持续维护的资源清单
  ./reflection.org     周期性反思 (按时间倒序追加)

与 Outputs 的关系:
- Practice 是长期沉淀,Outputs 是当前交付物
- Outputs 完成后,可复用的方法学和心得抽出来回流到 Practice
```

### `30_Library/README.org` —— Library 说明

```org
#+title: Library
#+description: 被消耗的素材库

Library 层存放被取用而非被维护的素材:
- bibliography/    BibTeX 文件
- datasets/        数据集
- snippets/        代码片段
- references/      大段非原子化的参考材料
- pdfs/            论文 PDF 原文

进入 Library 的判定: "我会主动审阅它,还是只是取用它?"
- 主动审阅 → 应该去 Practice
- 只是取用 → 留在 Library
- 能原子化的内容 → 应该去 Roam
```

---

## 九、Bootstrap 脚本

> **实现参考**：真实脚本在 `scripts/bootstrap-notes.sh`（Linux/macOS/Git Bash）和 `scripts/bootstrap-notes.ps1`（Windows PowerShell），请以源文件为准。

`bootstrap-notes.sh` / `bootstrap-notes.ps1` 的当前职责：

1. **创建目录骨架**：`00_Roam/daily/` / `00_Roam/capture/` / `00_Roam/dashboards/` / `10_Outputs/_template/` / `20_Practice/_template/` / `30_Library/{bibliography,datasets,snippets,references,pdfs}` / `40_Archives/` / `.orgseq/`。所有目录均幂等创建。
2. **扁平化历史子目录**：如果从旧版本升级并发现 `00_Roam/lit/` 或 `00_Roam/concepts/`，把里面的 `.org` 文件移动到 `00_Roam/` 根目录，然后删掉空子目录。
3. **部署 NoteHQ/Codex 脚手架**：把 `notehq/AGENTS.md` 拷贝到 `~/NoteHQ/AGENTS.md`。首次执行时只创建缺失文件，不覆写已有文件。
4. **增量更新模式**（`--update` / `-Update` flag）：当 org-seq 仓库里的 `notehq/*` 文件升级后，运行 `bash scripts/bootstrap-notes.sh --update` 或 `.\scripts\bootstrap-notes.ps1 -Update`，脚本会按内容比较，只覆写实际有变化的脚手架文件。用户内容（笔记、`types.org`、`capture-templates.el`、`ai-config.org`）**永远不会被触碰**。

### 首次执行后的下一步

脚本本身不会替你制定标签体系。跑完之后可以：

1. 先按现有 Daily/capture 写笔记，需要时再加类型和字段（参考 §4；`SPC # T` 编辑 `types.org`）
2. 在 `~/NoteHQ/00_Roam/dashboards/index.org` 写 dashboard 索引（参考 §7；`SPC # D` 创建）
3. （可选）把 Org 笔记和 `.orgseq/` 纳入版本控制；节点索引不需要纳入
4. 运行 `M-x my/index-rebuild` 为已有笔记建立索引

### 更新部署的 NoteHQ/Codex 脚手架

当 org-seq 仓库里的 `notehq/` 下脚手架文件有升级时：

```bash
# 从 org-seq 仓库根目录执行
bash scripts/bootstrap-notes.sh --update
# 或 Windows:
.\scripts\bootstrap-notes.ps1 -Update
```

脚本会：
- 对比源文件与已部署文件的 hash
- 只覆写实际有差异的文件（`[updated]`）
- 对内容一致的文件报告 `[unchanged]`，不产生 mtime 变动
- **永远不触碰** `.orgseq/types.org`、`.orgseq/capture-templates.el`、`.orgseq/ai-config.org`、任何笔记内容

---

## 十、与 Obsidian 的协作

Obsidian vault 直接指向 `~/NoteHQ/`（vault 根目录），不要单独指 `00_Roam/`。这样 Obsidian 能浏览全部内容（Roam 碎片 + PARA 产出物 + Library）。

### 职责边界

| 操作 | Emacs | Obsidian |
|------|-------|---------|
| 写新笔记（结构化捕捉）| 主入口 | 仅手机端临时捕捉 |
| 编辑普通 Org properties | 主入口 | 需支持 Org 的工具;不是隐藏数据库字段 |
| Dashboard 查询 | 打开入口/手动刷新 | 仅静态结果,不能执行 `orgseq-query` 动态块 |
| 全文搜索（快速翻阅）| `SPC P g` / `SPC /` | 启动更快 |
| 阅读已有笔记 | 是 | 是 |
| 长文写作 | 是 (org-mode) | 否 |
| 代码执行 | 是 (org-babel) | 否 |
| 跨设备同步 | git push/pull | Obsidian Sync E2EE |

**约定**：移动端临时输入不改变当前目录边界。`.md` 文件不会自动进入节点索引；回桌面后再决定是否转换成带 ID 的 `.org`。类型和字段都是 Org 文本，外部编辑器修改标签和 properties 就是修改全部数据；在 Emacs 中运行 `M-x my/index-rebuild`（或等下一次索引刷新）后修改进入查询结果。

---

## 十一、生长原则

笔记系统几乎没有办法被一次性设计完美。你不知道自己将来会写什么样的笔记，也不知道哪些 tag 和字段在实际使用中会变得重要——这些都要在真实使用中才能显现。因此这份架构文档给出的不是一个完整的 schema，而是一套**扩展决策的判断标准**：当你考虑增加什么、删除什么、提升什么的时候，回到这些原则来做决定。

### 关于 Org properties

**什么时候该加一个 property？** 当你反复需要查询一个信息时再加，优先沿用 Org 已有的 TODO、时间戳和链接。不同含义的状态可以用 `BOOK_STATUS` / `TASK_STATUS` 等不同键，必要时用 Org `KEY_ALL` 给出可选值。

**什么时候该停止维护？** 不再有查询用途就停止新增，不必为了改模型删除历史值。从某个类型的 `TYPE_FIELDS` 中去掉一个字段，不会删除笔记里已有的值；删除历史 properties 是独立的数据操作，应先备份并检查依赖查询。

### 关于 tag

**什么时候该定义一个新 tag？** 当一个主题反复出现并且确有检索用途时再建。可以把“积累几条同类记录后再整理”当作个人启发式，而不是经过验证的固定次数阈值。标签用于分类，正文骨架交给模板，不要求每个主题都有专门模板或 properties。

**什么时候把一个 tag 定义为类型？** 当这类笔记需要固定字段，并且你需要按字段查看、筛选或排序时，在 `types.org` 中为它定义类型，`TYPE_TAG` 写成已有的标签名，已有笔记随即属于该类型。只用于分类的标签不必定义为类型。

### 关于 Dashboard

**什么时候该加一个新 dashboard？** 当你发现自己每天都想看某个视图、但每次都要手动敲一遍 query 的时候。加 dashboard 时的节奏要**从小开始**——第一版只放 1-2 个查询块，跑一周之后看你真的每天打开它看什么，删掉不看的、补上缺失的。Dashboard 应当反映你**当下**的关注焦点，而不是一个一劳永逸的定义。六个月后你的关注焦点会变，你会想删掉旧 dashboard 重写新的——这是健康的，不是失败。

### 关于 PARA 子目录

**什么时候该建一个新的 Outputs 或 Practice 子目录？** Outputs 的子目录必须对应一个具体的交付时刻——论文的投稿日期、课程的开学、基金的截止。没有明确交付时刻的东西不属于 Outputs，属于 Practice 或 Library。Practice 的子目录必须对应一个**真实的**长期角色——你每周都会为它投入时间的那种。**不要为"将来可能做的事情"提前建目录**——那样 Outputs 会很快堆满几十个空壳子目录，每次你打开它都要在脑子里过滤掉一半的"幽灵项目"，心理成本高得惊人。

### 关于"晋升"决策

这套架构里有两个层级跃迁需要你做决策。

**从 daily 流水晋升到独立 Roam 节点**：判断问题是"这个想法将来可能在另一个**完全不同**的上下文里被引用吗？"如果是，就提升；如果不是（只是一次性的事务记录、或者只和今天相关的琐碎观察），就留在 daily 里不动——daily 本身就是档案，它们不会丢失，只是不会被从别的地方主动找到而已。

**从 Roam 碎片晋升到 Practice 沉淀**：判断问题是"我将来会**主动维护和审阅**它吗？"Practice 层的文件不是被动的档案，是你定期回头修改的活文档。如果一条笔记你写完就再也不会主动打开，它应该留在 Roam 而不是晋升到 Practice——晋升到 Practice 只会让 Practice 目录越来越像坟场。

### 关于版本控制与备份

保留 Org 文本和 `.orgseq/`（`types.org`、`capture-templates.el`）的版本历史，这就是完整的数据。节点索引是缓存，恢复或跨机迁移时用 `git checkout` 取回 Org 文件，再运行 `M-x my/index-rebuild` 重建。重命名类型标签前，先用 `SPC # v` 或 ripgrep 确认受影响的笔记。历史 `supertag-schema.el` 和 `.supertag-metadata.eld` 可以作为档案保留，但不再被读取。

---

## 十二、存储、同步、视图、命令行与 MCP（2026-11-11）

### 存储位置

笔记库是 Emacs 目录下的 `notes/`，由 org-seq 自己创建，位置固定，不需要选择文件夹，启动时也不询问任何问题。`ORG_SEQ_NOTE_HOME` 仍可覆盖这个位置，验证脚本用它隔离写入。设备本地的状态（同步基线、旧库提示是否已显示、命令行索引）放在 Emacs 目录的 `.cache/` 下，不进入笔记库，因为笔记库会在设备之间同步。

笔记库之外的内容只通过下面几条通道进出（2026-11-12 起）：

- 导入：`SPC n S i`（`my/storage-import`）或 `orgseq import DIR`，把一个文件夹复制进来。带有 `00_Roam/` 或 `.orgseq/` 的文件夹按层合并，其他文件夹整体放到 `30_Library/` 下的同名子目录。只复制笔记库里没有的文件，不覆盖已有文件，不改动来源。旧的 `~/NoteHQ/` 也走这条通道，存在且未导入时只在回显区提示一次，并一直显示在存储状态里。
- 导出：`SPC n S e`（`my/storage-export`）或 `orgseq export DIR`，把整个笔记库复制到一个带日期的新文件夹。
- 快照：`SPC n S b`（`my/storage-snapshot`）或 `orgseq snapshot`，把笔记库复制到 Emacs 目录之外的快照目录（Linux 为 `~/.local/share/org-seq/snapshots/`）。笔记库有改动的日子自动做一次，导入前和同步做全量比较前也各做一次，保留最近 `my/storage-snapshot-keep` 份（默认 10）。删除或替换 Emacs 目录不会同时丢掉笔记库和快照。
- 恢复：`my/storage-restore`（建议绑定 `SPC n S R`）或 `orgseq restore NAME --yes`，把整个笔记库恢复到某一份快照的状态；`orgseq snapshots` 列出快照。恢复前先给当前笔记库做一份快照，失败则不改动任何文件，所以恢复本身可以撤销（恢复那份撤销快照即可）。快照覆盖范围内的文件按快照覆盖，快照里没有的文件被删除，因此删除也是恢复的一部分；范围之外的 `org-roam.db`、`.git/`、字节码、锁文件和备份文件不动。恢复出的文件使用当前时间作为修改时间：同步用“较新者胜出”解决冲突，保留快照的旧时间会让远端副本在下次同步时把恢复结果盖掉。已打开且未修改的缓冲区会重新读取，被删除文件的缓冲区只给出提示。设置了同步远端时，下次同步会把恢复后的状态（包括删除）带到远端，建议先运行 `my/sync-preview`。
- 同步：见下一节。

`SPC n S t`（`my/storage-status`）显示位置、文件数、同步状态和快照；笔记库只有一份副本时 `M-x my/doctor` 给出警告。完整的分层和取舍见 [DESIGN.md](DESIGN.md)。

### 同步

同步引擎是 rclone 的双向同步（bisync），一套实现覆盖 WebDAV（坚果云、Nextcloud 等）、OneDrive 和 Google Drive。账号凭据由 rclone 保存在它自己的配置文件里，不进入仓库、`custom.el` 或笔记库。

- `SPC n S c`（`my/sync-setup`）选择网盘、登录、指定网盘上的文件夹。
- 第一次同步把两边合并，不删除任何一边的文件。之后启动后不久同步一次，并每隔 `my/sync-auto-interval` 分钟（默认 15）同步一次；`SPC n S s` 立即同步，`SPC n S p` 只预览。
- 同步单位是整个文件。两台设备改了同一个文件时，较新的一份生效，另一份保留在旁边，文件名带 `.conflict` 后缀；`SPC n S x` 列出这些冲突副本。
- 节点索引是本机缓存，不同步（旧库里残留的 `org-roam.db` 同样被跳过）；同步带来变化后自动刷新索引和类型定义。

### 类型（SuperTag）的扩充

- `TYPE_EXTENDS` 指定一个父类型（单继承）：子类型继承父类型的字段和可选值；查询或查看父类型时也包含子类型的节点。
- 字段类型：`NAME:node`（指向另一个节点的关系）、`NAME:nodes`（同一个属性里的多个 `[[id:]]` 链接，每个都参与路径列和汇总）、`NAME:date`、`NAME:number`、`NAME:check`、`NAME:url`（视图里可以点击，`mouse-1` 或 `C-c C-o` 打开）、`NAME:multi`（`NAME_ALL` 中的多个值，存在同一个属性里，用空格或逗号分隔，含空格的值加引号），其余为文本；有 `NAME_ALL` 的字段从可选值里选。之前写下的值照常读取：一个 `node` 字段里有多个链接时显示为逗号分隔的标题。
- 一个节点默认只属于一个类型（`my/node-single-type`）：再加一个类型时询问是否替换，原类型的字段值始终保留在节点上。已经带多个类型标签的笔记照常工作。
- 公式（`FORMULA_NAME`）随 `TYPE_EXTENDS` 继承，子类型可以用同名公式覆盖；具名模板和 `TYPE_VIEW_*` 不继承。

### 类型即数据库：默认视图

每个类型不需要定义就有一个视图：该类型（含子类型）全部节点的表格，列是类型的字段加公式，按修改时间倒序。打开方式：`SPC # v`、节点操作菜单里的“View all … nodes”、命令面板里每个 `#类型` 条目后面的 `#类型 view` 条目。类型标题上的可选属性改变默认视图，写法与 `views.org` 的 `VIEW_*` 相同：

| 属性 | 例子 |
|---|---|
| `TYPE_VIEW_LAYOUT` | `board`（`table`、`list`、`board`） |
| `TYPE_VIEW_GROUP` | `STATUS` |
| `TYPE_VIEW_SORT` | `YEAR desc, @title` |
| `TYPE_VIEW_COLUMNS` | `AUTHORS YEAR count(<-reading)` |
| `TYPE_VIEW_FILTER` | `(not (field "STATUS" "cited"))` |
| `TYPE_VIEW_LIMIT` | `200` |

`views.org` 里与类型同名的保存视图整体取代默认视图；在默认视图里按 `w` 保存（名字默认就是类型名）得到的正是这样的视图。

### 记录模板

- 新建某类型的笔记（`SPC # n`、视图里的 `+`、命令面板的 `#类型`、`/` 菜单的新节点链接）时，类型有具名模板就先问用哪一个，默认模板排在第一位。
- `my/node-capture` 的第四个参数是模板名（`default` 表示默认模板），非交互调用不提问，省略时用默认模板。
- 命令行：`orgseq add 标题 --type reading --template Paper`；MCP 的 `create_node` 有同名参数 `template`；`orgseq types --json` 列出每个类型的 `templates` 和 `formulas`。
- capture 菜单里具名模板排在所属类型后面，键是类型键加数字（`tr` 之后是 `tr2`、`tr3`），已有类型的键不因此改变。

### 汇总与公式

两者都在视图运行时从索引计算，从不写入 Org 文件，在视图里只读（在这样的列上按 `e` 会说明原因）。它们可以作为视图列、排序键、分组字段和筛选字段，`orgseq query --columns` 和 `orgseq-view` 动态块都会输出。

汇总列写成 `函数(路径)`，路径就是任意一种列写法：

| 写法 | 含义 |
|---|---|
| `count(<-reading)` | 链接到本节点的 reading 节点个数（含子类型） |
| `sum(<-task.HOURS)` / `avg(...)` | 这些节点 `HOURS` 的和 / 平均值，非数字的值跳过 |
| `min(...)` / `max(...)` | 全是数字时按数值，否则按文本 |
| `earliest(<-meeting.DUE)` / `latest(<-meeting.@modified)` | 值里的日期（`YYYY-MM-DD`，包括 Org 时间戳）中最早 / 最晚的一个 |
| `list(<-reading.@title)` | 去重后用逗号连接 |
| `count(TOPICS)` | 正向关系：`TOPICS` 字段里的链接个数 |

空集合时 `count` 和 `sum` 为 `0`，其他为空。路径 `<-task.HOURS` 本身也可以作为普通列，显示所有值。

公式是类型标题上的属性 `FORMULA_名称`，值是一个 s 表达式。它只被读取，不会作为 Lisp 执行，能用的只有下面这些：

```org
:FORMULA_LEFT:     (- BUDGET (sum <-task.HOURS))
:FORMULA_LOAD:     (if (> (count <-task) 5) "heavy" "light")
:FORMULA_WAITING:  (if (= STATUS "queued") (days (today) @created))
```

| 类别 | 写法 |
|---|---|
| 值 | 数字、`"文本"`；不加引号的名字是本节点的列（字段、`@created`、`TOPIC.AREA`、`<-task.HOURS`、其他公式） |
| 算术 | `+ - * /`、`(round x 位数)`、`(abs x)` |
| 比较 | `= != < > <= >=`，两边都是数字时按数值比较 |
| 逻辑 | `(if 条件 是 否)`、`and`、`or`、`not`、`(empty x)` |
| 文本 | `(concat a b ...)`、`(contains a b)` |
| 日期 | `(today)`、`(days a b)`：从日期 b 到日期 a 的天数 |
| 汇总 | `(count 路径)` 等，与汇总列相同 |

空字段的值为空：参与算术或日期计算时结果为空，`(or HOURS 0)` 提供默认值。结果为真、假时显示 `yes`、`no`。出错（除以零、不是数字、未知函数、公式写错、公式引用自身）时单元格显示 `#ERR: 原因`，视图的其他部分照常显示。公式名不要与字段名相同，相同时公式优先。

### 视图

视图是“查询加布局”，本身不存数据；在视图里改字段或移动卡片，改的是节点所在的 Org 文件。

- 布局：表格（每行一个节点，每列一个字段）、列表（每个节点一行）、看板（分组字段的每个取值一列，`H`/`L` 移动卡片即修改该字段；按 `@todo` 分组时修改 TODO 状态）。`v` 切换布局。
- 视图内按键：`RET` 打开，`e` 编辑光标所在字段，`t` 设 TODO，`+` 新建节点（自动带上视图的类型、筛选条件要求的字段值和光标所在的分组值），`/` 快速筛选，`G` 分组，`s` 排序，`F` 筛选条件，`c` 列，`w` 保存，`g` 刷新。
- 筛选条件：`(type "reading")`、`(tag "x")`、`(todo "NEXT")`、`(field "YEAR" > 2020)`、`(field "TOPIC" = current)`、`(field "TOPIC" empty)`、`(field "LABELS" has "method")`（多值字段、`nodes` 字段或 `<-tag` 中有一个值等于它；链接字段也可以写节点 ID）、`(field "count(<-reading)" > 2)`、`(modified-within 7)`、`(created-within 7)`、`(links-to ID)`、`(linked-from ID)`、`(under ID)`、`(title "x")`、`(text "x")`，用 `and`、`or`、`not` 组合。
- 列：字段名或公式名；多跳路径 `TOPIC.AREA`（沿 `TOPIC` 里的链接取目标节点的 `AREA`）；反向关系 `<-reading`（链接到本节点的 reading 节点）和 `<-reading.YEAR`；汇总 `count(<-reading)` 等（见上一节）；`@title @todo @tags @modified @created @in @out`。
- 保存的视图放在 `.orgseq/views.org`，每个一级标题一个视图，随笔记库同步。`SPC # v` 打开某类型的视图（见“类型即数据库”），`SPC n v o` 打开保存的视图，`SPC n v n` 新建。
- `orgseq-view` 动态块把视图嵌入任意笔记，筛选条件里的 `current` 指动态块所在的节点，例如在课程页里放“所属课程等于当前节点”的资料列表：

```org
#+BEGIN: orgseq-view :type "material" :filter (field "COURSE" = current) :layout list
#+END:
```

### 命令行与 MCP

`bin/orgseq` 不打开 Emacs 界面即可操作同一个笔记库：`add`、`daily`、`search`、`show`、`set`、`retype`、`append`、`types`、`views`、`query`、`sync`、`doctor`、`update`、`reindex`、`info`，加 `--json` 输出 JSON。`orgseq mcp` 以标准输入输出提供 MCP 服务，工具与命令行共用同一组 `my/api-*` 函数和同一条写入路径。

命令行和图形界面读同一个内核索引（Emacs 目录下 `.cache/index-<哈希>.db`，每个笔记库路径一个文件），由 Org 文件增量刷新，`orgseq reindex` 可整体重建。命令行不加载任何笔记包。
