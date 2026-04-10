# orgseq 笔记库架构

## 文档状态

> **这是一份设计规范文档，不是实现参考。**
>
> 本文档记录 `~/NoteHQ/` 笔记库的**物理结构、tag 体系思路、capture 模板、dashboard 设计原则**与**生长原则**。这些内容是长期稳定的设计决策。
>
> **实现层面的事实**（函数名、加载顺序、键位、安装方式）请以下列源文件为准，因为它们随项目迭代而变化：
> - `lisp/init-org.el` — 路径常量 `my/note-home` / `my/roam-dir` / `my/orgseq-dir`（defcustom，属于 `org-seq` customize group）
> - `lisp/init-roam.el` — org-roam + org-node/org-mem + capture templates
> - `lisp/init-supertag.el` — supertag schema/capture templates/dashboard/PARA 导航（函数前缀统一为 `my/`）
> - `lisp/init-dired.el` — dired + dirvish（文件管理与侧边栏）
> - `lisp/init-evil.el` — 所有 `SPC` leader key 绑定的唯一真相源
> - `scripts/bootstrap-notes.{sh,ps1}` — 笔记目录初始化与 Claude Code 脚手架部署脚本（支持 `--update` 增量刷新）
> - `CLAUDE.md` — 项目开发指南（模块加载顺序、设计决策、troubleshooting）
>
> 本文档中出现的代码片段仅作为**设计意图**说明。凡与源文件不一致之处，以源文件为准。

## 文档目的

本文档定义 `~/NoteHQ/` 笔记库的物理结构、tag 体系思路、capture 模板、dashboard 设计与生长原则，作为 org-seq 配置开发与数据初始化的依据。

这段设计文档基于一个核心承诺：**笔记系统应该跟随使用情况自然生长，而不是预先规划完整 schema**。本文档只提供最小起点 —— 2 个示例 tag、2 个示例 dashboard、几条占位符笔记 —— 用户在真实使用中按需扩展。任何看起来"详尽完备"的初始配置都应该被视为反模式。

---

## 一、设计原则

整个笔记库的物理结构和数据流向都可以从两条原则推导出来。

第一条：**把碎片想法和正式产出物物理分开存放**。原子笔记（一个想法一条）进入 `Roam/` 这个扁平目录，由 org-roam 负责索引和反向链接；正式产出物（论文、课件、申请书这类有明确交付时刻的东西）进入类 PARA 层级目录，文件结构反映可交付物自身的内在组织。两层之间通过 `[[id:...]]` 链接和 `org-transclusion` 通信，但不互相混杂。这条原则同时解决了两个常见痛点：一是当你的笔记库里混入 30 页的论文草稿，org-roam 的索引会开始变慢，搜索结果里也会出现大段无关的噪音；二是当你的项目目录里塞满未成形的想法碎片，你再也找不到"这个项目真正的可交付文件是哪几个"。分开存放让两类文件各得其所，也让两种工作模式（捕捉 vs. 打磨）保持清晰的边界。

第二条：**分类靠 tag，不靠目录**。除了 `daily/`、`capture/` 和 `dashboards/` 这三个功能性子目录之外，`Roam/` 内部是完全扁平的——不存在 `literature/`、`concepts/`、`people/` 这样的层级。每一条原子笔记都落在 `Roam/capture/` 下，文件名只是时间戳前缀加 slug。一条笔记是什么类型、属于哪个主题、处于哪个状态，全部靠 supertag 承载。这条原则听起来有点激进，但它解决的是一个具体的认知摩擦：每次你写新笔记时不必决定"这应该放在哪个文件夹"。那个决定本身就足以让你打断思路、甚至因为犹豫而放弃记录。扁平目录把这个决策成本降到零——你只管写，分类的事情以后由 tag 和查询完成，而且 tag 可以多维度叠加（一条笔记可以同时是 `reading`、`topic:cognition`、`source:academic`），目录做不到这一点。

---

## 二、日常工作流

整个架构的存在理由只有一个：服务下面这个四阶段日常工作流。如果某个设计决策回答不了"它在这个工作流里起什么作用"，那它就不应该进入配置。读完这一节再回头看其他章节的具体决策——你会发现每一条都能回溯到这四个阶段中的某一个。

### 阶段 1：启动 — GTD 主导今日工作

打开 Emacs 的第一个动作不是打开笔记，也不是写东西——而是按 `SPC a d` 进入 GTD Dashboard，确认今天要推进的项目和具体任务。这个先后顺序很重要：**GTD 系统决定"今天做什么"，笔记系统不参与这个决策**。把"计划今天"和"写想法"分成两个独立动作，可以避免一个常见的陷阱——你本来打算 10 分钟计划一下今天，结果在笔记里东翻西找两个小时还没开始干活。

### 阶段 2：执行与记录 — Daily 笔记作为思维流与任务录入入口

按 `SPC n d d` 进入当天的 daily 笔记。这个文件同时承担两个职责：

**职责 A：思维流捕捉**。一边做事一边记录进展、观察、临时想法、半成形的洞察。文字写法不严谨，可以是流水账、问句、断句。每条记录前可以用时间戳标记（手动 `[2026-04-09 14:30]` 或 `SPC RET` 插入）。

**职责 B：任务录入入口**。日常 TODO 主要不通过单独的 `SPC a c` capture 入口，而是直接在 daily 笔记里就地写入。orgseq 的 agenda 已经扫描整个 `~/NoteHQ/` 树，所以 daily 里的任务会自动出现在 GTD Dashboard 各视图中。

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

orgseq 的 GTD keyword 序列是 `PROJECT/TODO → NEXT → IN-PROGRESS → WAITING / SOMEDAY → DONE / CANCELLED`。`SPC a e` 一键切换状态，`SPC a d` 看到的 GTD Dashboard 会自动统计这些任务。

这个设计的好处：所有任务的"出生地"就是当时正在写的 daily 流水，任务的上下文（为什么要做、跟今天的什么思考有关）天然保留在同一个文件里。不需要先打断思路去 capture，再回头记笔记。

任务完成后不需要做任何归档动作。daily 文件本身就是历史档案，`SPC a 6` Logbook 视图会自动汇总所有 DONE 状态的任务。

### 阶段 3：碎片提取 — 当某条想法值得独立存在

写 daily 时如果出现某条内容，你判断"这值得作为独立笔记长期追溯"，立刻执行：

1. 把光标停在那段内容（或要新建的word）上，按 `SPC n c` 选合适的 capture 模板（多数时候用 default 即可）
2. capture 出一个新的 Roam 节点，文件落到 `Roam/capture` 目录，在 daily 原位置插入 `id:` 链接（`SPC n i`）
3. 从下方弹出buffer让我可以编辑这个节点内容
4. 在新节点里按 `SPC n p p` 添加 supertag，填字段
5. 关闭，回到 daily 继续


### 阶段 4：汇总与整理 — Dashboard 作为周期性 review 入口

每天结束、每周末、或某项工作收尾时，按 `SPC n v v` 进入 dashboard index，挑相关 dashboard 打开。dashboard 是**只读的查询窗口**，利用org-supertag的功能自动渲染所有相关 supertag 节点的当前状态。在 dashboard 里你做的事情：

- 看本周新增的笔记是否需要补充字段或链接
- 看某个主题的所有相关碎片是否暗示着新的洞察
- 看哪些笔记之间应该建立链接但还没建立
- 决定哪些碎片足够成熟，可以晋升到 PARA 层成为正式产出物的素材

dashboard **永远不是录入入口**，永远只是窗口。任何想"在 dashboard 里写注释"的冲动都该被拒绝 —— 那些内容应该写到独立的 Roam 节点里。

---

## 三、物理结构

```
~/NoteHQ/
├── Roam/                              ← 原子层 (org-roam-directory)
│   ├── daily/                         ← 每日笔记 (唯一例外子目录)
│   ├── dashboards/                    ← 查询入口文件 (唯一例外子目录)
│   ├── supertag-schema.el             ← tag 定义,跟笔记一起 git
│   └── caputre/20260409143022-*.org   ← 全部扁平,时间戳前缀文件名
│
├── Outputs/                           ← PARA 产出层
│   └── _template/                     ← 项目目录模板,复制后改名使用
│
├── Practice/                          ← PARA 实践层
│   └── _template/                     ← 实践域模板
│
├── Library/                           ← PARA 资源层
│   ├── bibliography/
│   ├── datasets/
│   ├── snippets/
│   ├── references/
│   └── pdfs/
│
└── Archives/                          ← 归档层
```

### 各层职责对照

| 层 | 用途 | 进入门槛 | 寿命 |
|---|------|---------|------|
| `Roam/capture` | 原子笔记、想法碎片、文献摘要、概念定义 | 低，鼓励大量录入 | 永久 |
| `Roam/daily/` | 当日意识流、工作流水、TODO 录入 | 极低，随便写 | 永久但低访问 |
| `Roam/dashboards/` | 查询定义文件 | 高，只放查询不放数据 | 长期 |
| `Outputs/` | 有明确交付时刻的产出物 | 中，每个目录是一份可交付物 | 1 周到 6 个月 |
| `Practice/` | 长期承担的角色与责任沉淀 | 中，每个目录是一个实践域 | 多年 |
| `Library/` | 被消耗的素材库，二进制、大段非原子材料 | 高，能原子化的都该去 Roam | 长期 |
| `Archives/` | 已完成或停滞的内容 | 无，按年份组织 | 永久 |

### 关键 elisp 配置

所有 NoteHQ 相关的路径都是 `lisp/init-org.el` 中 defcustom 形式的变量，通过 `M-x customize-group RET org-seq` 可见：

```elisp
;; init-org.el —— 所有路径的唯一真相源
(defcustom my/note-home   (file-truename "~/NoteHQ/")             ...)  ; 总根
(defcustom my/roam-dir    (expand-file-name "Roam/"   my/note-home) ...) ; 原子层
(defcustom my/orgseq-dir  (expand-file-name ".orgseq/" my/note-home) ...); 个性化配置

;; init-roam.el —— org-roam 锁在 Roam/
(use-package org-roam
  :custom
  (org-roam-directory my/roam-dir)
  (org-roam-db-location (expand-file-name "org-roam.db" my/roam-dir))
  ...)

;; init-gtd.el —— agenda 跨 Roam + Outputs + Practice
;; daily 笔记里的 TODO/PROJECT 通过这个范围进入 GTD 视图
(my/org-roam-agenda-files)  ; returns Roam/ + Outputs/ + Practice/ (not Library/ or Archives/)

;; init-pkm.el / init-supertag.el —— org-supertag 同样锁在 Roam/
(setq org-supertag-sync-directories (list my/roam-dir))
```

**重要**：org-seq 内部**没有任何模块**应该硬编码 `~/NoteHQ/Roam/` 字符串——全部通过 `my/roam-dir` 或 `my/note-home` 派生。如果你在新写的模块里看到硬编码路径，请统一替换成变量。

### PARA 三层的判定测试

当一份内容拿不准放哪一层，依次回答 3 个问题：

1. **它会"完成"吗？** 能想象明确的完成时刻 → 倾向 `Outputs/`
2. **你对它有外部义务吗？** 长期角色、有责任对象 → 倾向 `Practice/`
3. **你会主动审阅它，还是只是取用它？** 主动审阅 → 倾向 `Practice/`；只是取用 → 倾向 `Library/`

不确定时默认放 `Outputs/`。Outputs 有更高的可见度，会被频繁打开；放进 Practice 容易被遗忘；放进 Library 容易过期。

---

## 四、Supertag Schema 起点

文件位置：`~/NoteHQ/Roam/supertag-schema.el`

下面只给两个 tag 作为示例，演示两种核心模式 —— 实体 tag 与事件 tag —— 以及它们之间通过 `:node` 字段关联。**不要把这两个 tag 当成"应该用的 tag"**，它们只是模式的示范。真实的 tag 应该在你写过几次某类笔记之后才创建。

```elisp
;;; supertag-schema.el --- User tag schema -*- lexical-binding: t; -*-
;;;
;;; 设计模式:
;;; - 实体 tag (entity): 被关联的对象,相对静态。例如一个长期主题、一个项目、一个人。
;;; - 事件 tag (event):  流式输入,通过 :node 字段挂到实体上。例如一次会议、一篇文献。
;;;
;;; 当前只有 2 个示范 tag。增加新 tag 的时机:
;;; 某类事情你已经用 default 模板记过 5 次以上,且发现它们有共同结构。
;;; 编辑后用 SPC n m T 重载,无需重启 Emacs。

(require 'org-supertag)

;; ----------------------------------------------------------------
;; 示例 1:实体 tag
;; topic — 一个长期关注的主题或领域
;; ----------------------------------------------------------------
(org-supertag-tag-create "topic"
  :fields '((:name "status"  :type :options :options ("active" "paused" "shelved"))
            (:name "started" :type :date)))

;; ----------------------------------------------------------------
;; 示例 2:事件 tag
;; reading — 文献/书籍/文章笔记,通过 topic 字段关联到 topic 实体
;; ----------------------------------------------------------------
(org-supertag-tag-create "reading"
  :fields '((:name "authors"   :type :string)
            (:name "year"      :type :number)
            (:name "topic"     :type :node :ref-tag "topic")    ; 关联字段
            (:name "status"    :type :options :options ("queued" "reading" "read" "cited"))))

(provide 'supertag-schema)
;;; supertag-schema.el ends here
```

### 扩展思路

当你在某个领域积累了足够多的笔记，发现某类事情值得专门定义结构时：

1. `SPC n m t` 打开 `supertag-schema.el`
2. 在合适的位置加新的 `org-supertag-tag-create` 块
3. 决定它是实体 tag 还是事件 tag。事件 tag 通常需要至少一个 `:node` 字段挂到某个实体
4. 字段宁少勿多，每个字段都该回答一个**你已经反复需要查询但当前 schema 答不出来**的问题
5. `SPC n m T` 重载

可能的扩展方向：临床工作的 client/session、教学的 course/lesson_prep/reflection、学生指导的 student/meeting、研究工作的 hypothesis/experiment/concept、健康追踪的 health_log。**但具体怎么定义字段、定义多少字段，请等到你真的写过 5 次再决定**。

---

## 五、Capture 模板

Capture 模板分两层：

1. **内置默认模板** — 定义在 `lisp/init-roam.el` 里，只有一个 `default`：落到 `Roam/capture/%<%Y%m%dT%H%M%S>-${slug}.org`，不带 filetag。这是 org-seq 开箱即用的最低起点，**不建议**修改仓库内这个默认模板，因为它是部署时会被覆盖的部分。

2. **用户自定义模板** — 放在 `~/NoteHQ/.orgseq/capture-templates.el`，通过 `setq my/user-capture-templates` 定义。`init-supertag.el` 首次启动时会创建这个文件的模板骨架（含注释好的示例 `reading` 模板）。用户模板与内置默认模板通过 `my/reload-capture-templates` 合并到 `org-roam-capture-templates`。

```elisp
;; ~/NoteHQ/.orgseq/capture-templates.el
(setq my/user-capture-templates
      '(;; 示例:带 tag 的笔记。其他 tag 类型按这个模式增加。
        ("r" "reading" plain
         "* TL;DR\n%?\n* Key points\n* My commentary\n"
         :target (file+head "capture/%<%Y%m%dT%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: :reading:\n")
         :unnarrowed t)

        ;; 继续添加你常用的类型:session / client / lesson / experiment...
        ))
```

### 常用操作

- `SPC n m c`（`my/edit-capture-templates`）— 打开 `~/NoteHQ/.orgseq/capture-templates.el`
- `SPC n m C`（`my/reload-capture-templates`）— 重载用户模板（无需重启 Emacs）
- Claude Code `/new-template` skill — 在 NoteHQ 目录里让 Claude 帮你快速生成新模板

### 起步建议

**只需要 default 模板就够**。当你决定为某类笔记建立独立的 supertag（例如 `lesson_prep`、`session`、`hypothesis`），**同时**在 `.orgseq/capture-templates.el` 加一个对应的 capture 模板，模板正文用 org 标题骨架引导你思考关键问题。

模板正文的设计原则：**标题骨架而非字段**。字段交给 supertag 处理（通过 `SPC n p a` 在节点上添加 tag 并弹出字段表单），模板只负责让你看到笔记应该展开的几个思考方向。

---

## 六、`lisp/init-supertag.el` 模块职责

> **实现参考**：真实代码在 `lisp/init-supertag.el`，请以源文件为准。本节只说明模块的**设计职责**。

`init-supertag.el` 是 supertag 相关基础设施的上层胶水层，提供以下五类职责：

1. **PARA 路径常量**：`my/outputs-dir` / `my/practice-dir` / `my/library-dir` / `my/archives-dir` / `my/dashboards-dir` / `my/schema-file`。这些常量从 `my/note-home`（`init-org.el` 中的 defcustom）派生。注意：`my/roam-dir` 本身定义在 `init-org.el`，因为 `init-roam.el` / `init-pkm.el` / `init-ai.el` 都要先于 `init-supertag.el` 加载并引用它。

2. **Schema 编辑与重载**：`my/edit-supertag-schema`（打开 `supertag-schema.el`）和 `my/reload-supertag-schema`（`load` 文件，无需重启）。对应 leader key：`SPC n m t` / `SPC n m T`。

3. **Capture 模板管理**：`my/edit-capture-templates` 和 `my/reload-capture-templates`。用户模板存在 `~/NoteHQ/.orgseq/capture-templates.el`，首次使用时由 `my/ensure-capture-templates-file` 创建带示例的文件。`init-roam.el` 中的默认模板和用户模板通过 `my/reload-capture-templates` 合并到 `org-roam-capture-templates`。对应 leader key：`SPC n m c` / `SPC n m C`。

4. **Supertag 快速操作**：`my/supertag-quick-action` 是上下文感知的弹出菜单——当前 heading 无 tag 时直接加 tag，有 tag 时列出 "加另一个 / 删除 / 编辑字段 / 跳转到关联节点" 四类动作。对应 leader key：`SPC n p p`（全局）和 `, # #`（org buffer 内）。

5. **Dashboard 导航与创建**：
   - `my/dashboard-find`：从 `Roam/dashboards/` 选择一个 dashboard 打开并刷新所有 dynamic blocks。对应 `SPC n v v`。
   - `my/dash-index` / `my/dash-review`：命名快捷方式。对应 `SPC n v i` / `SPC n v w`。
   - `my/dashboard-create`：提示名字后生成带骨架的新 dashboard 文件。对应 `SPC n m d`。
   - 需要更多快捷方式时，直接在 `Roam/dashboards/` 加文件，用 `my/dashboard-find` 访问即可，**不必再改 elisp**。

6. **PARA 层导航**：`my/find-in-outputs` / `my/find-in-practice` / `my/find-in-library` / `my/ripgrep-notehq`。对应 leader key：`SPC P o` / `SPC P p` / `SPC P l` / `SPC P g`。

7. **NoteHQ 目录结构 bootstrap**：`my/ensure-notehq-structure` 在模块加载时调用，幂等地创建 `Roam/daily/` / `Roam/capture/` / `Roam/dashboards/` / `Outputs/` / `Practice/` / `Library/` / `Archives/`。

### 加载顺序要求

`init-supertag.el` 的加载位置在 `init-pkm.el` 之后、`init-ai.el` 之前。完整链条见 `CLAUDE.md` 的 "Module Load Order" 小节。

### 函数命名约定

所有函数统一用 `my/` 前缀（私有 helper 用 `my/module--helper` 双短横线）。**不使用** `orgseq/` 前缀——这是早期设计草稿的命名方案，已被统一为 `my/`。

---

## 七、Dashboard 起点

每个 dashboard 是 `~/NoteHQ/Roam/dashboards/` 下的独立 org 文件，只存查询定义。下面只给 3 个起点文件：一个总入口、一个 weekly review、一个按 tag 查询的示例。**需要更多 dashboard 时按这个模式自己加**。

### `index.org`

```org
#+title: Dashboards Index
#+startup: showall

* 入口
  - [[file:weekly-review.org][🔄 Weekly review]] :: 周回顾入口
  - [[file:reading.org][📖 Reading]] :: reading tag 查询示例

* 快捷键
  - ~SPC n m t~ 编辑 tag schema
  - ~SPC n m T~ 重载 schema
  - ~SPC n c~  新建笔记 (按类型选模板)
  - ~SPC n p p~ 当前节点 tag/字段操作
  - ~SPC P o/p/l~ PARA 导航 (Outputs/Practice/Library)

* 增加新 dashboard 的步骤
  1. SPC n m d (my/dashboard-create) 生成带骨架的新 dashboard 文件
  2. 编辑 #+BEGIN: supertag-query 块定义查询
  3. SPC n v v (my/dashboard-find) 会自动列出此目录下的所有 .org 文件,
     无需再改 elisp 或加命名函数
```

### `weekly-review.org`

```org
#+title: Weekly Review
#+startup: content
#+description: 每周末打开,review 本周累积内容并整理

* 本周新增笔记 (Roam 全部)
#+BEGIN: supertag-query :where (within-days created 7) :columns (title tags created) :sort created
#+END

* Review checklist
  - [ ] 本周新增笔记是否需要补 supertag 字段?
  - [ ] 是否有想法应该建立链接但还没建立?
  - [ ] daily 里的 TODO 是否都已经被推进或重新调度?
  - [ ] 是否有碎片足够成熟,应该晋升到 PARA Outputs?
  - [ ] 是否需要新增/修改某个 supertag 定义?
```

### `reading.org`

```org
#+title: Reading Queue
#+startup: content
#+description: 按 tag 分组查询的示例 dashboard。其他 tag 类型可以仿照这个文件创建。

* 待读
#+BEGIN: supertag-query :tag reading :where (equal status "queued") :columns (title authors year topic) :sort year
#+END

* 在读
#+BEGIN: supertag-query :tag reading :where (equal status "reading") :columns (title authors year topic)
#+END

* 已读 (按 topic 分组)
#+BEGIN: supertag-query :tag reading :where (equal status "read") :group-by topic :columns (title year)
#+END
```

### 关于查询语法的说明

`supertag-query` dynamic block 的 `:where` 表达式语法以你装的 org-supertag 版本为准。如果某些谓词在当前版本不支持，先用最朴素的 `:tag tagname` 罗列全部，再手动按 `/` 过滤。**先让结构跑起来，再雕琢查询表达力**。

---

## 八、初始化种子文件

bootstrap 脚本应该创建以下种子文件，让用户启动后立刻有可读、可编辑的真实示例。每个文件都极简，目的只是演示模式。

### `Roam/daily/example-day.org` —— 示例 daily 笔记

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

### `Roam/example-fragment.org` —— 示例 Roam 碎片

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
按 SPC n p p 添加 tag。
建议先用 default 模板的形式存在,等到积累了 5 条类似笔记
再考虑为它们定义专门的 supertag。
```

### `Outputs/_template/README.org` —— 项目目录模板

```org
#+title: 项目模板
#+description: 复制此目录,改名为具体项目目录后使用

Outputs 层每个子目录代表一个具体可交付物,有明确的开始和结束。
例如一篇论文、一份基金申请、一门课的本学期版本。

典型结构:

  ./manuscript.org    主交付物
  ./notes.org         项目相关的工作笔记
  ./bibliography.bib  本项目引用 (或链接到 Library/bibliography/master.bib)
  ./figures/          配图
  ./drafts/           历史草稿

完成后归档:
  mv ~/NoteHQ/Outputs/your-project-name ~/NoteHQ/Archives/2026-your-project-name

与 Roam 层的交互:
- 在 manuscript.org 里用 SPC n i 引用 Roam 节点 (id: 链接)
- 用 org-transclusion 把 Roam 节点的内容实时嵌入 manuscript
```

### `Practice/_template/README.org` —— 实践域模板

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

### `Library/README.org` —— Library 说明

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

1. **创建目录骨架**：`Roam/daily/` / `Roam/capture/` / `Roam/dashboards/` / `Outputs/_template/` / `Practice/_template/` / `Library/{bibliography,datasets,snippets,references,pdfs}` / `Archives/` / `.orgseq/`。所有目录均幂等创建。
2. **扁平化历史子目录**：如果从旧版本升级并发现 `Roam/lit/` 或 `Roam/concepts/`，把里面的 `.org` 文件移动到 `Roam/` 根目录，然后删掉空子目录。
3. **部署 Claude Code 脚手架**：把 `notehq/CLAUDE.md`、`notehq/.claude/rules/*`、`notehq/.claude/skills/*` 拷贝到 `~/NoteHQ/` 对应位置。首次执行时只创建缺失文件，不覆写已有文件。
4. **增量更新模式**（`--update` / `-Update` flag）：当 org-seq 仓库里的 `notehq/*` 文件升级后，运行 `bash scripts/bootstrap-notes.sh --update` 或 `.\scripts\bootstrap-notes.ps1 -Update`，脚本会按 hash 比较，只覆写实际有变化的文件。用户内容（笔记、`supertag-schema.el`、`capture-templates.el`、`ai-config.org`）**永远不会被触碰**。

### 首次执行后的下一步

脚本本身不会替你写笔记或 schema。跑完之后你需要：

1. 在 `~/NoteHQ/Roam/supertag-schema.el` 写第一个 supertag（参考本文档 §4；或用 Claude Code 的 `/new-tag` skill 快速生成）
2. 在 `~/NoteHQ/Roam/dashboards/index.org` 写 dashboard 索引（参考本文档 §7；或用 `SPC n m d` / `/new-dashboard` skill 生成）
3. （可选）`cd ~/NoteHQ && git init && git add . && git commit -m 'initial structure'`——把笔记本身纳入版本控制
4. 在 Emacs 中运行 `M-x supertag-sync-full-initialize`（或 `SPC n p R`）完成 supertag 首次索引

### 更新部署的 Claude Code 脚手架

当 org-seq 仓库里的 `notehq/` 下任何文件（CLAUDE.md / rules / skills）有升级时：

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
- **永远不触碰** `Roam/supertag-schema.el`、`.orgseq/capture-templates.el`、`.orgseq/ai-config.org`、任何笔记内容

---

## 十、与 Obsidian 的协作

Obsidian vault 直接指向 `~/NoteHQ/`（vault 根目录），不要单独指 `Roam/`。这样 Obsidian 能浏览全部内容（Roam 碎片 + PARA 产出物 + Library）。

### 职责边界

| 操作 | Emacs | Obsidian |
|------|-------|---------|
| 写新笔记（结构化捕捉）| 主入口 | 仅手机端临时捕捉 |
| 编辑 supertag 字段 | 唯一方式 | 看不到 |
| Dashboard 查询 | 实时刷新 | 显示为静态文本 |
| 全文搜索（快速翻阅）| `SPC P g` / `SPC /` | 启动更快 |
| 阅读已有笔记 | 是 | 是 |
| 长文写作 | 是 (org-mode) | 否 |
| 代码执行 | 是 (org-babel) | 否 |
| 跨设备同步 | git push/pull | Obsidian Sync E2EE |

**约定**：手机端 Obsidian 只往 `Roam/` 写，不碰 `Outputs/` 和 `Practice/`。手机捕捉的 .md 文件回到桌面后由你决定是否转换为 .org 并加 supertag 字段。

---

## 十一、生长原则

笔记系统几乎没有办法被一次性设计完美。你不知道自己将来会写什么样的笔记，也不知道哪些 tag 和字段在实际使用中会变得重要——这些都要在真实使用中才能显现。因此这份架构文档给出的不是一个完整的 schema，而是一套**扩展决策的判断标准**：当你考虑增加什么、删除什么、提升什么的时候，回到这些原则来做决定。

### 关于 Schema 字段

**什么时候该加一个新字段？** 当你发现自己已经**反复需要查询某个信息但当前 schema 答不出来**的时候。比如你多次想查"上季度我和某某谈话的所有记录"，却发现 session tag 没有 date 字段——这时候就该加一个。**不要**因为"以后可能用得上"就预先加字段——闲置字段会带来持续的录入摩擦（每次新建节点都看到一个空表单）却几乎不会被填写，最终变成整个系统里最令人烦躁的部分。

**什么时候该删一个字段？** 规则同样简单：如果某个字段**两周内没填过三次**，立刻删掉它。已经录入的历史数据里的孤立值不影响你删除 schema 里的字段定义——org-supertag 容忍 schema 和数据不完全一致。宁愿砍得狠一点，总比让 schema 变成僵尸字段的博物馆强。

### 关于 tag

**什么时候该定义一个新 tag？** 当你已经用 default 模板记过至少 **5 条以上同类型笔记**，并且你发现这些笔记共享某种结构（比如都有 "核心观点 / 例子 / 反驳"），才考虑为它建一个专门的 tag。**先用，再结构化**，不要反过来——那些先设计 tag 体系再去写笔记的人，最后往往发现 70% 的 tag 从未被用过。

### 关于 Dashboard

**什么时候该加一个新 dashboard？** 当你发现自己每天都想看某个视图、但每次都要手动敲一遍 query 的时候。加 dashboard 时的节奏要**从小开始**——第一版只放 1-2 个查询块，跑一周之后看你真的每天打开它看什么，删掉不看的、补上缺失的。Dashboard 应当反映你**当下**的关注焦点，而不是一个一劳永逸的定义。六个月后你的关注焦点会变，你会想删掉旧 dashboard 重写新的——这是健康的，不是失败。

### 关于 PARA 子目录

**什么时候该建一个新的 Outputs 或 Practice 子目录？** Outputs 的子目录必须对应一个具体的交付时刻——论文的投稿日期、课程的开学、基金的截止。没有明确交付时刻的东西不属于 Outputs，属于 Practice 或 Library。Practice 的子目录必须对应一个**真实的**长期角色——你每周都会为它投入时间的那种。**不要为"将来可能做的事情"提前建目录**——那样 Outputs 会很快堆满几十个空壳子目录，每次你打开它都要在脑子里过滤掉一半的"幽灵项目"，心理成本高得惊人。

### 关于"晋升"决策

这套架构里有两个层级跃迁需要你做决策。

**从 daily 流水晋升到独立 Roam 节点**：判断问题是"这个想法将来可能在另一个**完全不同**的上下文里被引用吗？"如果是，就提升；如果不是（只是一次性的事务记录、或者只和今天相关的琐碎观察），就留在 daily 里不动——daily 本身就是档案，它们不会丢失，只是不会被从别的地方主动找到而已。

**从 Roam 碎片晋升到 Practice 沉淀**：判断问题是"我将来会**主动维护和审阅**它吗？"Practice 层的文件不是被动的档案，是你定期回头修改的活文档。如果一条笔记你写完就再也不会主动打开，它应该留在 Roam 而不是晋升到 Practice——晋升到 Practice 只会让 Practice 目录越来越像坟场。

### 关于 Schema 文件的版本控制

`supertag-schema.el` 放在 `Roam/` 内，和你的笔记一起 git commit。这意味着 schema 的演化历史和笔记的演化历史是**共同**的版本历史——某天你想知道"半年前我的 reading tag 有哪些字段"，直接 `git log` 就能查到。每次做**重大改动**前建议打一个 git tag（例如 `schema-2026-04`），方便回滚。所谓重大改动是指：删除字段、删除 tag、修改 `:type`、修改 `:options` 的可选值列表——任何会让已有数据变得"不合 schema"的改动。单纯添加新字段或新 tag 不算重大改动，不需要打 tag。
