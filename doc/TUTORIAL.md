# org-seq 使用教程

> 写给从 Tana/Notion 迁移到 Emacs 的知识工作者
>
> 本教程假设你已完成 org-seq 的安装部署. 如需安装指南, 参见 [GUIDE.md](GUIDE.md).

---

## 目录

1. [核心概念 — 从 Tana 到 org-seq 的思维转换](#1-核心概念)
2. [日常启动与工作区](#2-日常启动与工作区)
3. [笔记的创建与链接 — Zettelkasten 工作流](#3-笔记的创建与链接)
4. [结构化知识 — Supertag 系统](#4-结构化知识--supertag-系统)
5. [任务管理 — GTD 系统](#5-任务管理--gtd-系统)
6. [AI 协作](#6-ai-协作)
7. [搜索与导航](#7-搜索与导航)
8. [写作与专注](#8-写作与专注)
9. [开发环境](#9-开发环境)
10. [日常工作流示例](#10-日常工作流示例)
11. [快捷键速查表](#11-快捷键速查表)

---

## 1. 核心概念

### 从 Tana 的世界观出发

Tana 的核心假设是"万物皆节点"——每一条记录都是一个可标记、可链接、可查询的实体。org-seq 保留这个假设，但用 Emacs 生态里更成熟的工具实现它。

**节点层**：Tana 的每个节点对应 org-roam 里的一个文件节点。org-roam 给每个节点生成全局唯一的 UUID（存在 `:ID:` 属性里），跨文件链接就靠这个 ID。一个文件可以有多个节点——文件头部是"文件节点"，每个带 ID 的 heading 是"段落节点"。

**Supertag 层**：Tana 的 Supertag（带字段的结构化标签）对应 org-supertag。你在 `supertag-schema.el` 里定义 tag 和它的字段类型，然后把 tag 挂到任意 heading 上，那个 heading 就获得了结构化元数据。字段类型包括 `:string`（文本）、`:number`（数字）、`:date`（日期）、`:options`（枚举）、`:node`（指向另一个节点的关联）。`:node` 类型就是 Notion 关系数据库的等价物。

**查询层**：Tana 的 Live Search 对应 org-ql 查询和 supertag dashboard。你可以用 SQL 式语法查询任意跨文件条件，结果呈现在 dashboard 文件的动态块里，打开时自动刷新。

**AI 层**：Tana 的 AI Command Node 对应 gptel 命令。区别在于 org-seq 把你的 `purpose.org`（知识库目标）和 `schema.org`（笔记结构规则）注入每一次 AI 请求的 system prompt，让模型真正"理解"你的知识库语境。

### 三层架构

```
org-supertag  ←  数据层（结构化字段、tag 关系）
org-roam      ←  图谱层（节点 ID、双向链接、搜索）
org-mem       ←  性能层（替代 org-roam 的慢速文件扫描）
```

org-mem 是关键。org-roam 扫描 3000 个节点需要近三分钟，org-mem 约两秒。org-mem 不是替代品——它在后台维护缓存，同时写入 org-roam 的 SQLite 数据库，让 org-roam-ui 图谱保持同步。这套组合让系统在大规模笔记库下依然流畅。

### NoteHQ 目录结构

目录用数字前缀排序，让侧栏按工作流优先级显示，而不是按字母顺序。

```
~/NoteHQ/
├── 00_Roam/               ← 原子笔记（Zettelkasten 节点）
│   ├── capture/           ← 新捕获的笔记落点
│   ├── daily/             ← 每日笔记（YYYY-MM-DD.org）
│   ├── dashboards/        ← 动态查询仪表盘（只读查询视图）
│   ├── purpose.org        ← 知识库目标（注入 AI system prompt）
│   ├── schema.org         ← 笔记结构规则（注入 AI system prompt）
│   └── supertag-schema.el ← Tag 定义文件
├── 10_Outputs/            ← PARA：有明确交付时刻的产出物
├── 20_Practice/           ← PARA：长期角色与责任
├── 30_Library/            ← PARA：参考素材
├── 40_Archives/           ← PARA：已完结内容
└── .orgseq/               ← 个人配置
    ├── ai-config.org      ← AI 后端与模型配置
    ├── capture-templates.el ← 自定义 capture 模板
    └── focus-log.org      ← 专注计时历史
```

GTD Agenda 扫描 `00_Roam/`、`10_Outputs/`、`20_Practice/` 三个目录，不扫描 `30_Library/` 和 `40_Archives/`。这个设计有意为之：参考素材和归档内容不应进入任务视图，制造噪音。

### PARA 的逻辑

PARA 是组织文件的骨架，Zettelkasten 是组织知识的骨架，二者分工不同。

- `00_Roam/`：原子笔记，每条笔记只讲一件事，有全局 ID，可以被任意文件引用
- `10_Outputs/`：一篇论文、一门课的讲义、一份报告——有明确交付时刻
- `20_Practice/`：教学、咨询、研究——持续的角色与职责
- `30_Library/`：文献 PDF、参考书——被取用但不产出的素材
- `40_Archives/`：项目完成后归档，保留但不活跃

日常工作流的路径是：`00_Roam/` 生长出想法 → 想法聚合进 `10_Outputs/` 项目 → 项目完成后进 `40_Archives/`。

---

## 2. 日常启动与工作区

### 连接 Daemon

orgseq 以 daemon 模式运行，服务器名称为 `org-seq`。

在 Linux/WSL2：

```bash
emacsclient -s org-seq -c
```

或使用随附的快捷脚本 `~/.emacs.d/ec`，它会在服务器未运行时自动启动 daemon，然后连接。

### 启动 Dashboard

连接后看到的第一个画面是 Dashboard。它垂直居中显示五个导航按钮：

| 按钮 | 跳转目标 |
|------|---------|
| Today | 今日 daily note |
| Find | Deft 全库搜索 |
| Tasks | GTD overview |
| Review | 周回顾视图 |
| Last File | 最近编辑的文件 |

随时可以用 `SPC l d` 回到 Dashboard。Dashboard 底部显示一条随机引用，包括 PKM 格言和快捷键提示，每次启动不同。

### 工作区布局

默认启动是轻量布局：treemacs 侧栏 + Dashboard。需要完整写作环境时，`SPC l l` 展开三栏布局：

```
┌──────────┬────────────────────────┬────────────┐
│ treemacs │                        │  outline   │
│ sidebar  │     主编辑区            │   (~20%)   │
│ (~15%)   │       (~65%)           ├────────────┤
│          │                        │  terminal  │
│          │                        │   (~20%)   │
└──────────┴────────────────────────┴────────────┘
```

常用布局操作：

| 键位 | 效果 |
|------|------|
| `SPC l l` | 打开完整三栏工作区 |
| `SPC l t` | 切换 treemacs 侧栏 |
| `SPC l h` | 侧栏聚焦并跳转到 NoteHQ 根目录 |
| `SPC l r` | 在 treemacs 中定位当前文件 |
| `SPC l o` | 切换 imenu-list 大纲侧栏 |
| `SPC l e` 或 `SPC '` | 切换底部 eshell 终端 |
| `SPC l =` | 重新平衡各栏比例 |

treemacs 侧栏的根目录是 `~/NoteHQ/`。在 treemacs 内，`TAB` 展开/折叠目录节点。

如果用 dirvish 浏览文件（`SPC o f` 打开），按 `a` 键弹出快速访问菜单，预设了 NoteHQ 各目录的跳转入口：`n` → NoteHQ 根、`r` → 00_Roam、`c` → capture、`d` → daily、`o` → Outputs、`p` → Practice。

### 视觉效果

heading 层级用可变宽度字体，字号从一级标题（1.4×）到六级标题（1.0×）渐变。正文用比例字体，代码块保持等宽字体（mixed-pitch 模式）。中英文混排时，pangu-spacing 自动在汉字与 Latin 字符间显示薄空格，不写入文件。

主题默认为 `modus-operandi-tinted`，WCAG AAA 对比度。切换主题用 `SPC t t`，从 modus、ef-themes、doom-themes 中交互选择。

---

## 3. 笔记的创建与链接

这是系统的核心。Zettelkasten 方法论的要义是：笔记不是文档，是可组合的原子单元。一条笔记只讲一件事，通过链接与其他笔记产生意义。

### 捕获：从想法到笔记

`SPC n c` 打开 capture 模板选择器。内置两个模板：

- `d`（default）：纯文本，文件落到 `capture/` 目录，时间戳命名
- `r`（reading）：带 TL;DR 和 Key points 骨架，自动加 `:reading:` filetag

选模板后进入编辑界面，写完用 `C-c C-c` 保存，`C-c C-k` 放弃。

如果你的日常有固定的捕获需求——比如文献阅读、实验记录、学生个案——在 `~/.orgseq/capture-templates.el` 里定义 `my/user-capture-templates`，格式与 `org-roam-capture-templates` 相同。`SPC n m c` 快速打开这个文件编辑，改完后 `SPC n m C` 重载，无需重启 Emacs。

### 每日笔记：工作流的入口

`SPC n d d` 打开今天的 daily note，文件不存在时自动创建，带 `:daily:` filetag。Daily note 是一天的思维起点——在这里记录零散想法、做决策、写日记，然后把值得保留的内容链接到永久笔记。

每日笔记支持三种 capture 子模板：`d`（默认条目，带时间）、`t`（任务，带 SCHEDULED）、`j`（日记，带时间戳）。用 `SPC n d c` 触发带模板的捕获写入当日文件。

翻看历史：`SPC n d y` 昨天、`SPC n d T` 明天、`SPC n d f` 按日期选择、`SPC n d p/n` 上一篇/下一篇。

### 查找笔记

`SPC n F` 打开 org-roam 节点搜索（模糊匹配），每个候选项显示：

```
[类型]        标题                    [反链数] [标签]
capture       Bayesian 模型的直觉解释    3      :statistics:
```

类型字段显示节点所在子目录（`capture`、`daily`、`roam` 等）。反链数告诉你这条笔记被多少其他笔记引用——在 Zettelkasten 里，反链多的笔记往往是知识图谱的枢纽节点。

Orderless 补全：输入时可以用空格分隔多个关键词，无需考虑顺序。"认知 贝叶斯" 和 "贝叶斯 认知" 会匹配到相同结果。

如果需要全文搜索，`SPC n f`（Deft）实时过滤整个 NoteHQ，`SPC P g` 调用 ripgrep 对 NoteHQ 全文搜索。

### 链接笔记

在任意 org 文件内，`SPC n i` 插入到另一个节点的链接。它调起同样的节点搜索界面，选中后插入 `[[id:UUID][标题]]` 格式的链接。这是 org-roam 双链的核心——链接用 ID 而不是文件名，重命名文件不会破坏链接。

如果你在浏览器里看到一篇文章想记录，把 URL 复制到剪贴板，然后 `SPC n L`（org-cliplink）会自动抓取页面标题并插入格式化链接。图片同理，`SPC n I` 从剪贴板粘贴图片并存为附件。

### 反链面板

`SPC n b` 切换右侧反链面板。这个面板显示所有链接到当前笔记的节点——是 Zettelkasten 图谱的局部视图。写完一条笔记后看反链，往往能发现意想不到的关联。

反链面板有两种查询方式：
- 直接反链（其他笔记里有指向当前节点的链接）
- 引用（其他笔记里 cite 了当前节点的 ref）

`SPC n B` 用 consult 界面浏览反链，可以模糊搜索。

### 图谱可视化

`SPC n g` 在浏览器里打开 org-roam-ui 图谱，展示整个知识库的节点与链接关系。这是宏观视角——当你想了解哪些领域的笔记密集、哪些概念是跨领域的桥梁时，图谱比文件列表更直观。

org-mem 确保图谱始终与实际文件同步：它写入 org-roam 的 SQLite 数据库，org-roam-ui 直接读取这个数据库。

### 内容嵌入（Transclusion）

`SPC n t a` 在当前位置插入 transclusion 块——语法是 `#+transclude: [[id:UUID]]`。开启 transclusion 模式（`SPC n t t`）后，这个块会渲染为被引用节点的实际内容，但不是拷贝，是实时嵌入。修改源节点，嵌入处自动更新。

这对应 Tana 的 inline reference。适合的场景：课程讲义里嵌入研究笔记的核心论点，实验方案文档里嵌入方法论笔记的某个段落。

### 节点操作菜单

`SPC n n`（或在 org buffer 内用 `, ,`）打开节点操作菜单——这是 Tana `/` 命令菜单的等价物。从任意 heading 触发，显示当前节点所有可用操作：

- 添加/删除/编辑 supertag
- 跳转到通过 `:node` 字段关联的节点
- 插入链接到另一个节点
- 切换反链面板
- 复制当前节点的 `[[id:...][标题]]` 链接到剪贴板
- 打开该 tag 的 dashboard
- 创建新笔记
- 把选中区域提取为新 Roam 节点（自动插入 source 链接）

"Extract region to new note" 特别有用：当一条笔记写得太长，选中某个段落，从菜单提取，它变成独立笔记，原位置自动替换为指向新笔记的链接。

---

## 4. 结构化知识 — Supertag 系统

### 核心思路

org-supertag 让 heading 获得结构化元数据。`#reading` tag 给一条笔记加上 authors、year、topic、status 字段，变成类似数据库记录的东西。多条带同样 tag 的笔记可以作为一个集合查询，在 dashboard 或看板视图里展示。

### 定义 Tag

Tag 定义写在 `~/NoteHQ/00_Roam/supertag-schema.el`，用 `SPC n m t` 打开编辑。

```elisp
;; 实体 tag：相对稳定的概念对象
(org-supertag-tag-create "topic"
  :fields '((:name "status"  :type :options :options ("active" "paused" "shelved"))
            (:name "started" :type :date)))

;; 事件 tag：流式输入，通过 :node 字段关联到实体
(org-supertag-tag-create "reading"
  :fields '((:name "authors"   :type :string)
            (:name "year"      :type :number)
            (:name "topic"     :type :node :ref-tag "topic")
            (:name "status"    :type :options :options ("queued" "reading" "read" "cited"))))

;; 实验记录
(org-supertag-tag-create "experiment"
  :fields '((:name "hypothesis" :type :string)
            (:name "method"     :type :string)
            (:name "topic"      :type :node :ref-tag "topic")
            (:name "status"     :type :options :options ("planned" "running" "done" "failed"))))

;; 课程
(org-supertag-tag-create "course"
  :fields '((:name "semester"   :type :string)
            (:name "students"   :type :number)
            (:name "status"     :type :options :options ("active" "completed" "archived"))))

;; 咨询个案（注意：建议加 GPG 加密，见下）
(org-supertag-tag-create "client"
  :fields '((:name "session"    :type :number)
            (:name "presenting" :type :string)
            (:name "status"     :type :options :options ("active" "closed" "referred"))))
```

关于 `#client` tag：咨询个案涉及个人隐私，建议把相关文件放在独立加密目录，配合 EasyPG（Emacs 内置 GPG 集成）对 `.org.gpg` 文件自动加解密。

`topic` 的 `:node` 字段类型创建了 reading → topic 的关系：每条阅读笔记指向一个主题节点，就像 Notion 关系数据库里的外键。

改完 schema 后，`SPC n m T` 重载 tag 定义，无需重启。

首次使用时需要建立初始索引：`SPC n p R`（`M-x supertag-sync-full-initialize`）。

### 给笔记打 Tag

光标在某个 heading 上：

- `SPC n p a`（或 `, # a`）：添加 supertag，从已定义的 tag 列表选择
- `SPC n p e`（或 `, # e`）：编辑当前节点的 tag 字段值
- `SPC n p x`（或 `, # x`）：移除 supertag
- `SPC n p l`：列出当前节点所有 tag 字段及值

上下文感知的快捷入口：`SPC n p p`（或 `, # #`，或在节点操作菜单里选 "Supertag quick action"）——当前 heading 没有 tag 时直接触发添加，有 tag 时列出字段操作选项。这是最高频的操作路径。

### 跟踪关联节点

`:node` 字段是关系数据库的灵魂。`SPC n p j`（或 `, # j`）跳转到当前节点通过 `:node` 字段关联的另一个节点。

例子：你在阅读一篇关于 N400 效应的论文，reading 节点的 topic 字段指向"语言认知"这个 topic 节点。按 `, # j` 直接跳到那个 topic 节点，在那里你能看到所有关联到"语言认知"的反链——包括其他阅读笔记、实验记录、课程材料。这就是 Notion 关系视图的 Emacs 实现。

### 看板视图

`SPC n p k` 打开看板视图（`supertag-view-kanban`）。按 tag 的 `:options` 字段分列显示节点，适合管理有状态流转的内容：阅读状态（queued → reading → read → cited）、实验状态、项目状态。

### Dashboard 查询

Dashboard 是只读的查询视图文件，存在 `dashboards/` 目录。

`SPC n m d` 新建 dashboard，输入名称后在 `dashboards/` 创建带 `supertag-query` 动态块骨架的 org 文件。`SPC n v v` 从 dashboards 目录列出所有 dashboard，选择后打开并自动刷新所有动态块。

常用 dashboard：
- `SPC n v i`：打开 index dashboard
- `SPC n v w`：打开周回顾 dashboard

---

## 5. 任务管理 — GTD 系统

### 状态机

org-seq 的任务状态形成一条流水线：

```
PROJECT → TODO → NEXT → IN-PROGRESS → WAITING / SOMEDAY
                                    ↓
                               DONE / CANCELLED
```

各状态的含义：

- `PROJECT`：有子任务的项目容器，本身不是可执行的动作
- `TODO`：已知需要做，但还没确定下一步是什么
- `NEXT`：清单上的下一个可执行动作，无阻碍，随时可做
- `IN-PROGRESS`：当前正在做
- `WAITING`：在等别人或某个条件，进入时记日志
- `SOMEDAY`：将来也许做，不排期
- `DONE`：完成，自动记录时间戳
- `CANCELLED`：放弃，记录原因

`SPC a e`（全局）或 `, q`（org buffer 内）打开单键状态选择器：

```
[n]NEXT  [i]IN-PROGRESS  [w]WAIT  [s]SOMEDAY  [k]DONE  [x]CANCEL  [p]PROJECT  [q]uit
```

`k`（DONE）会询问是否同时完成所有活跃子任务。DONE 和 CANCELLED 的任务自动下沉到同级列表底部，不妨碍你看到活跃任务。

`, h` 切换隐藏/显示已完成任务——写作时隐藏掉完成项，只看未完成的。

### GTD Dashboard

`SPC a d` 打开 GTD Dashboard（`*GTD*` buffer）——这是你的任务控制中心，实时显示各分区的任务计数：

| 分区 | 含义 |
|------|------|
| Inbox | fleeting tag 且无 TODO 状态——待处理的输入 |
| Today | 今日 SCHEDULED 或截止的非 SOMEDAY 任务 |
| Upcoming | 未来排期的任务 |
| Anytime | NEXT 状态且无日期——随时可做 |
| Waiting | WAITING 状态 |
| Someday | SOMEDAY 状态 |
| Logbook | 已完成 |

Projects 区块显示所有活跃项目及健康状态：`*` 表示卡壳（无 NEXT 子任务），`~` 表示有活跃子任务但无 NEXT，空白表示健康。

Contexts 区块按 `@work`、`@home`、`@computer`、`@errands`、`@phone` 显示各上下文的 NEXT 任务数。

在 Dashboard buffer 内按 `RET` 或点击任意行，在右侧窗口打开对应视图。`g` 刷新，`q` 关闭。

Dashboard 的查询和显示完全由 org-ql 驱动，每次打开时实时计算。

### Agenda 视图

| 键位 | 视图 |
|------|------|
| `SPC a n` | GTD Overview（今日 + 进行中 + NEXT + TODO + WAITING + SOMEDAY） |
| `SPC a p` | 项目视图（活跃项目 + 卡壳项目） |
| `SPC a w` | 周回顾（-3d 至 +3d 日程 + 进行中/等待 + 卡壳 + Someday） |
| `SPC a 0` | Inbox |
| `SPC a 1` | 今日 |
| `SPC a 3` | Anytime（NEXT 且无日程）|
| `SPC a 4` | Waiting |
| `SPC a 5` | Someday |
| `SPC a 6` | Logbook（DONE/CANCELLED，按时间倒序）|
| `SPC a u` | Upcoming（按 scheduled 分组）|
| `SPC a 7` | 按 context tag 过滤 NEXT 任务 |

### 排期与截止

在任意任务 heading 上：

- `, s`：设置 SCHEDULED 日期（弹出日历，选择后任务进入 Today 分区）
- `, d`：设置 DEADLINE 日期

设置后 GTD Dashboard 自动刷新（0.3 秒防抖）。

任务排期的基本规则：只有"计划今天做"或"有截止时间"的任务才进 SCHEDULED/DEADLINE，其他放 NEXT 分区、靠上下文驱动。过度排期会让 Agenda 失去意义。

### org-ql 自定义查询

`SPC n q s` 打开交互式 org-ql 查询。语法示例：

```lisp
;; 找出所有 NEXT 状态且带 @computer tag 的任务
(and (todo "NEXT") (tags "@computer"))

;; 找出本周截止的所有任务
(and (not (done)) (deadline :to +7d))

;; 找出有 :reading: filetag 且状态为 reading 的节点
(and (tags "reading") (property "status" "reading"))
```

---

## 6. AI 协作

### 配置

API key 写入 `~/.authinfo`（明文）或 `~/.authinfo.gpg`（GPG 加密）：

```
machine openrouter.ai login apikey password sk-or-YOUR-KEY
```

模型和后端在 `~/NoteHQ/.orgseq/ai-config.org` 里配置。默认后端是 OpenRouter，默认模型是 `deepseek/deepseek-chat-v3-0324`。文件里可以列出多个后端（OpenRouter、Ollama 等）和每个后端支持的模型列表。

`SPC i g` 初始化 `purpose.org` 和 `schema.org` 两个 AI 上下文文件（已存在则跳过）。

### Purpose + Schema 上下文注入

这是 org-seq AI 集成的核心机制。每次调用 `SPC i *` 命令时，系统自动把 `purpose.org` 和 `schema.org` 的内容（各取最多 2000 字符）拼入 AI 请求的 system prompt。

`purpose.org` 写什么：你的知识库目标、核心研究问题、覆盖的领域（计算认知神经科学、EEG/fMRI 方法、贝叶斯建模、心理咨询、教学……）。

`schema.org` 写什么：你用哪些 tag、各 tag 的字段语义、命名规范、链接规则。

有了这个上下文，AI 在建议 tag 时会优先推荐你已定义的 tag，在建议关联概念时会参考你的领域框架，在改写文字时会理解你的写作风格偏好。

### AI 命令

| 键位 | 效果 |
|------|------|
| `SPC i i` | 发送当前 buffer 或选区到 LLM，回答追加在后面 |
| `SPC i s` | 摘要当前 buffer 或选区，结果显示在底部侧窗 |
| `SPC i t` | 建议 3-5 个 `#+filetags:` 标签 |
| `SPC i k` | 建议 3-5 个相关概念（Zettelkasten 关联发现） |
| `SPC i l` | 翻译选区（中英互译，需先选中） |
| `SPC i p` | 改写/润色选区（gptel-rewrite 模式，可接受/拒绝 diff） |
| `SPC i r` | 改写选区（与 `SPC i p` 同，显示 diff） |
| `SPC i o` | 生成知识库概览报告 |
| `SPC i c` | 打开独立 AI 对话 buffer |
| `SPC i a` | 添加文件或 buffer 作为上下文 |
| `SPC i m` | 打开 gptel 菜单（切换模型、参数、预设） |
| `SPC i C` | 打开 Claude Code CLI Transient 菜单 |

`SPC i o`（知识库概览）收集 org-roam 的统计数据——总节点数、前 15 个高频 tag、最近 10 条笔记标题——发送给 LLM，生成包含四个部分的分析报告：主要知识领域、欠充分的主题、可能的意外关联、建议探索的方向。结果保存到 `00_Roam/overview.org`，带时间戳，覆盖写入。

### ob-gptel：笔记里的 AI 代码块

在 org 文件里写 gptel src block，相当于 Tana 的 prompt workbench——把 prompt 和结果保存在知识库里，可以重复运行、调整参数、积累提示词库。

```org
#+begin_src gptel :model deepseek/deepseek-chat-v3-0324
列举贝叶斯推断和频率主义检验在实验报告中的3个关键差异，
输出为 org-mode 列表格式。
#+end_src
```

光标在 src block 上，`C-c C-c`（或 `, b e`）执行，结果异步插入到 `#+RESULTS:` 块。

### Claude Code

`SPC i C` 打开 Claude Code Transient 菜单，`M-x claude-code` 在当前目录启动 Claude Code CLI 会话（使用 eat 终端模拟器）。适合需要 Claude 直接读写文件、执行代码的场景。

---

## 7. 搜索与导航

### 搜索入口

搜索有多个层次，从窄到宽：

**当前 buffer**：`SPC s s`（consult-line）在当前文件内增量搜索，`SPC s i` 按 heading 导航（imenu）。

**Roam 层**：`SPC n F` 搜节点标题（模糊，带元数据），`SPC n /` 对 `00_Roam/` 全文搜索（ripgrep）。

**全库**：`SPC n f`（Deft）实时过滤 NoteHQ 所有笔记，`SPC P g` 对整个 NoteHQ 全文搜索（ripgrep + consult）。

**结构化查询**：`SPC n q s`（org-ql）用逻辑表达式跨文件查询。

### Deft 的用法

`SPC n f` 打开 Deft 界面，直接开始输入，结果实时过滤。Deft 覆盖 `~/NoteHQ/` 的所有 `.org`、`.md`、`.txt` 文件（排除 `dashboards/` 和隐藏目录）。它读取文件内容而不是路径，适合靠关键词找笔记。

Deft 的摘要显示过滤掉了 org 关键字行（`#+KEYWORD:`）、`:PROPERTIES:` 块、`:END:` 标记——你看到的摘要是笔记的实际内容。

### PARA 层导航

在 PARA 各目录间快速跳转：

| 键位 | 目标 |
|------|------|
| `SPC P o` | `10_Outputs/`（项目产出）|
| `SPC P p` | `20_Practice/`（持续职责）|
| `SPC P l` | `30_Library/`（参考素材）|
| `SPC P g` | ripgrep 搜索全 NoteHQ |

### Buffer 切换

`SPC ,`（consult-buffer）列出所有打开的 buffer，模糊搜索切换。`SPC TAB` 切回上一个 buffer。`SPC f r` 打开最近访问文件列表。

### which-key

任何键位前缀输入后，等待 0.3 秒，which-key 弹出提示面板显示后续可用键位。不记得完整快捷键时，输入前缀等待提示。

---

## 8. 写作与专注

### Focus 计时器

`SPC a f` 启动专注片段计时——Vitamin-R 风格，工作在 10-30 分钟内，自动对齐到 15 分钟边界。计时结束时 Emacs 响铃，弹出质量评估：

```
(u) 不集中   (n) 正常   (f) 心流
```

评估结果记录在 `focus-log.org`，modeline 在片段运行期间显示剩余时间。`SPC a X` 取消当前片段（不记录结果）。

`SPC a F` 打开 14 天专注历史 Dashboard，按天显示彩色时间线：█ 心流 / ▓ 正常 / ░ 不集中，加上 14 天聚合统计。

`C-u SPC a f` 手动输入时长（默认值是自动对齐的结果）。

### 视觉写作环境

org-appear 让强调标记在光标移入时出现、移出时隐藏——正文看到的是渲染后的效果，不是 `*bold*` 这样的标记。

org-fragtog 对 LaTeX 片段做同样的事：光标移出 LaTeX 片段后自动渲染为 SVG 图像（需要 TeX 环境和 dvisvgm），移入时恢复源码编辑。

`SPC t m` 切换 mixed-pitch 模式：正文用比例字体，代码块和表格保持等宽字体。这对长文写作很重要——比例字体读起来更舒服，等宽字体保证代码和表格对齐正确。

### Org Babel

在 org 文件里执行代码块：

- `<el TAB`：插入 Elisp src block
- `<sh TAB`：插入 Shell src block
- `<py TAB`：插入 Python src block
- `C-c C-c`（或 `, b e`）：执行当前 src block
- `, b b`：执行 buffer 内所有 src block
- `, b t`：tangle（提取 src block 到对应文件）

执行不需要确认提示（`org-confirm-babel-evaluate = nil`）。结果写入 `#+RESULTS:` 块。

对于认知神经科学的数据分析场景：在笔记里写 Python 分析代码，直接执行，结果（包括图表路径）嵌在笔记里。这让分析过程和解释性文字住在同一个文件。

### Markdown 支持

`.md` 文件支持 Obsidian 风格的 `[[wiki links]]`，用于与 Obsidian 笔记库互操作。但 Markdown 文件不被 org-roam 索引。

| 键位 | 效果 |
|------|------|
| `, v` | 在 Markdown 源码和 EWW 实时预览之间切换 |
| `, c` | 用 pandoc 将当前 `.md` 转换为 `.org` 并切换 |
| `, p` | 在浏览器中预览（需 pandoc）|
| `, t` | 在光标位置插入目录 |

### 常用 Org 操作

| 键位 | 效果 |
|------|------|
| `, s` | 设置 SCHEDULED 日期 |
| `, d` | 设置 DEADLINE 日期 |
| `, r` | Refile（移动 heading 到另一位置） |
| `, a` | 归档当前子树 |
| `, t` | 设置 org 标签 |
| `, n` | 收窄到当前子树 |
| `, w` | 展宽（取消 narrow） |
| `, x` | 打开导出调度器 |
| `, k i/o` | 开始/停止时钟计时 |

---

## 9. 开发环境

### R

打开 `.R` 或 `.Rmd` 文件，ESS 自动加载。`M-x R` 启动 R 进程。代码发送：`C-c C-n`（行/region）、`C-c C-b`（整个 buffer）、`C-c C-c`（当前函数）。

`poly-R` 支持 `.Rmd` 和 `.qmd` 的多语言模式——Markdown 正文和 R 代码块用不同的模式渲染和编辑。

ESS 使用 RStudio 风格缩进，求值异步不阻塞（`nowait` 模式）。

### Python

打开 `.py` 文件，Python 模式自动加载。如果 `pyright-langserver` 或 `pylsp` 在 PATH 里，eglot LSP 自动启动，提供补全、跳转定义、类型提示。虚拟环境管理用 `M-x pyvenv-activate`。

在 org babel 里执行 Python：`<py TAB` 插入 Python src block，`C-c C-c` 执行。

### Julia

打开 `.jl` 文件，`julia-mode` 提供语法高亮和缩进。`M-x julia-repl` 启动 Julia REPL。

### LSP 备注

eglot 是 Emacs 29+ 内置的 LSP 客户端，轻量。对于 R，安装 R 包 `languageserver` 后在 R buffer 里 `M-x eglot-ensure` 手动启动。

---

## 10. 日常工作流示例

### 晨间启动

```
emacsclient -s org-seq -c    ← 连接 daemon，Dashboard 出现
```

1. 点击 "Tasks" 或 `SPC a d`，扫描 GTD Dashboard：
   - Inbox 有什么需要处理？
   - Today 有哪些计划任务？
   - Projects 有没有 `*` 卡壳的？

2. `SPC n d d` 打开今日 daily note，写下今天的工作意图，翻看昨天的链接：
   - `SPC n d y` 查看昨天
   - 把昨天的未完成想法链接到相关笔记

3. 选一个 NEXT 任务，`, q` → `i`，标记为 IN-PROGRESS，`SPC a f` 开始专注计时。

### 文献阅读

1. `SPC n c` → 选择 `r`（reading 模板），填写标题，文件落到 `capture/`

2. 读论文，在文件里记录关键概念，用 `SPC n i` 插入到现有相关笔记的链接

3. `, # a` 添加 `#reading` supertag，填写字段：
   - authors：作者列表
   - year：发表年份
   - topic：选择或新建对应的 topic 节点
   - status：`reading`

4. `SPC i s` 让 AI 摘要这篇笔记

5. `SPC i k` 让 AI 建议与现有笔记的关联，手动检查后用 `SPC n i` 添加有意义的链接

6. 读完后 `, # e` 把 status 改为 `read`

### 课程准备

1. `SPC P p` 导航到 `20_Practice/`，打开对应课程文件

2. `SPC a f` 开始专注计时

3. 写讲义，需要引用研究笔记时：
   - `SPC n t a` 插入 transclusion 嵌入对应笔记的段落
   - 或 `SPC n i` 插入链接

4. `, # a` 添加 `#course` supertag，填写学期和状态

5. 写完后 `SPC i p`（选中段落）让 AI 润色表达，在 diff 视图里决定接受还是拒绝

6. `SPC i i` 发送整节内容，请 AI 检查概念解释是否准确

### 每周回顾

1. `SPC a w` 打开周回顾 Agenda 视图：-3d 到 +3d 的日程、进行中任务、卡壳项目

2. `SPC n v w` 打开周回顾 dashboard，用 org-ql 查询总结本周的笔记活动

3. `SPC i o` 生成知识库概览，了解本周新增笔记在哪些领域聚集、哪些领域空白

4. 处理 Inbox：
   - `SPC a 0` 打开 Inbox 视图
   - 逐条审查带 `:fleeting:` 的笔记
   - 值得保留的：`, # a` 加 supertag，`, r` refile 到合适位置
   - 可以删除的：直接删掉

5. 检查 Projects 健康状态：卡壳的（`*`）找出原因，分解出下一步 NEXT 任务

---

## 11. 快捷键速查表

### 笔记操作（`SPC n`）

| 键位 | 效果 |
|------|------|
| `SPC n F` | 搜索笔记节点（模糊，显示类型+反链+标签）|
| `SPC n c` | Capture 新笔记 |
| `SPC n i` | 插入到另一个节点的链接 |
| `SPC n b` | 切换反链面板 |
| `SPC n g` | 打开 org-roam-ui 图谱 |
| `SPC n n` | 节点操作菜单（Tana `/ ` 命令等价）|
| `SPC n f` | Deft 全库搜索 |
| `SPC n /` | ripgrep 搜索 00_Roam |
| `SPC n a` | 给当前节点添加别名 |
| `SPC n r` | 给当前节点添加 ref（URL 等）|
| `SPC n L` | 从剪贴板粘贴 URL 并自动获取标题 |

### 每日笔记（`SPC n d`）

| 键位 | 效果 |
|------|------|
| `SPC n d d` | 今日 daily note |
| `SPC n d y` | 昨天 |
| `SPC n d T` | 明天 |
| `SPC n d f` | 按日期选择 |
| `SPC n d c` | capture 写入今日 daily |

### 内容嵌入（`SPC n t`）

| 键位 | 效果 |
|------|------|
| `SPC n t a` | 插入 transclusion 嵌入块 |
| `SPC n t t` | 切换 transclusion 渲染模式 |
| `SPC n t r` | 刷新 transclusion 块 |

### 任务管理（`SPC a`）

| 键位 | 效果 |
|------|------|
| `SPC a d` | GTD Dashboard |
| `SPC a n` | GTD Overview（复合 Agenda）|
| `SPC a p` | 项目视图 |
| `SPC a w` | 周回顾 |
| `SPC a f` | 开始专注计时 |
| `SPC a F` | 专注历史 Dashboard |
| `SPC a X` | 取消当前专注片段 |
| `SPC a e` | 状态选择器（全局）|
| `SPC a 0` | Inbox |
| `SPC a 1` | 今日 |
| `SPC a 3` | Anytime |
| `SPC a 4` | Waiting |
| `SPC a 5` | Someday |
| `SPC a 6` | Logbook |
| `SPC a u` | Upcoming |

### Org Buffer Local Leader（`,`）

| 键位 | 效果 |
|------|------|
| `, ,` | 节点操作菜单 |
| `, q` | 状态选择器 |
| `, s` | SCHEDULED 日期 |
| `, d` | DEADLINE 日期 |
| `, h` | 隐藏/显示已完成 |
| `, r` | Refile |
| `, a` | 归档 |
| `, t` | 设置标签 |
| `, n` | 收窄到子树 |
| `, w` | 展宽 |
| `, x` | 导出调度器 |
| `, l` | 插入链接 |
| `, e` | 设置预估耗时 |
| `, k i` | 开始时钟计时 |
| `, k o` | 停止时钟计时 |
| `, b e` | 执行 src block |
| `, b b` | 执行 buffer 所有 src block |
| `, b t` | Tangle src block |

### AI 命令（`SPC i`）

| 键位 | 效果 |
|------|------|
| `SPC i i` | 发送 buffer/选区到 LLM |
| `SPC i s` | 摘要 |
| `SPC i t` | 建议 filetags |
| `SPC i k` | 建议 Zettelkasten 关联 |
| `SPC i l` | 翻译选区（中英互译）|
| `SPC i p` | 润色选区 |
| `SPC i r` | 改写选区（diff 模式）|
| `SPC i o` | 生成知识库概览 |
| `SPC i c` | 打开 AI 对话 buffer |
| `SPC i a` | 添加上下文 |
| `SPC i m` | gptel 菜单（模型/参数）|
| `SPC i g` | 初始化 AI 上下文文件 |
| `SPC i C` | Claude Code CLI |

### Supertag（`SPC n p` / `, #`）

| 键位 | 效果 |
|------|------|
| `SPC n p p` / `, # #` | 上下文感知快捷菜单 |
| `SPC n p a` / `, # a` | 添加 supertag |
| `SPC n p e` / `, # e` | 编辑字段 |
| `SPC n p x` / `, # x` | 移除 supertag |
| `SPC n p j` / `, # j` | 跳转关联节点（:node 字段）|
| `SPC n p l` | 列出所有字段 |
| `SPC n p k` | 看板视图 |
| `SPC n p s` | 搜索 supertag 数据库 |
| `SPC n p R` | 重建 supertag 索引 |

### Schema 与 Dashboard 管理（`SPC n m` / `SPC n v`）

| 键位 | 效果 |
|------|------|
| `SPC n m t` | 编辑 supertag-schema.el |
| `SPC n m T` | 重载 tag 定义 |
| `SPC n m c` | 编辑 capture-templates.el |
| `SPC n m C` | 重载 capture 模板 |
| `SPC n m d` | 新建 dashboard |
| `SPC n v v` | 浏览并打开 dashboard |
| `SPC n v w` | 周回顾 dashboard |
| `SPC n v i` | index dashboard |

### 搜索（`SPC /`, `SPC s`, `SPC P`）

| 键位 | 效果 |
|------|------|
| `SPC /` | ripgrep 项目范围搜索 |
| `SPC P g` | ripgrep 搜索全 NoteHQ |
| `SPC s s` | 当前 buffer 内搜索 |
| `SPC s i` | imenu（heading 导航）|
| `SPC s o` | 大纲跳转 |
| `SPC n q s` | org-ql 结构化查询 |

### 工作区（`SPC l`）

| 键位 | 效果 |
|------|------|
| `SPC l l` | 打开完整三栏布局 |
| `SPC l t` | 切换 treemacs 侧栏 |
| `SPC l h` | 侧栏跳到 NoteHQ 根 |
| `SPC l r` | 在 treemacs 定位当前文件 |
| `SPC l o` | 切换大纲侧栏 |
| `SPC l e` | 切换终端 |
| `SPC l =` | 重新平衡窗口比例 |
| `SPC l d` | 切换到 Dashboard |

### PARA 导航

| 键位 | 效果 |
|------|------|
| `SPC P o` | 10_Outputs |
| `SPC P p` | 20_Practice |
| `SPC P l` | 30_Library |

### 文件与 Buffer

| 键位 | 效果 |
|------|------|
| `SPC ,` | 切换 buffer |
| `SPC TAB` | 切回上一个 buffer |
| `SPC f r` | 最近文件 |
| `SPC f f` | 打开文件 |
| `SPC b s` | 保存 buffer |
| `SPC b d` | 关闭 buffer |
| `SPC o f` | 打开 dirvish 文件管理 |
| `SPC '` | 切换终端 |

---

*本教程对应 org-seq 部署版本，键位从 `lisp/init-evil.el` 直接提取，与实际代码一致。配置修改参见 `M-x customize-group RET org-seq`。*
