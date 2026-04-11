# org-seq 推荐工作流

这份文档描述的是用 org-seq 做个人知识管理和任务管理的推荐姿势。它不是功能手册——键位速查请看 README 或 GUIDE 附录——而是一份"一天之内你可能会怎么用它"的剧本。你不必照搬全部；最好的方式是先读完这份文档，然后挑两三个你最能用得上的习惯实际试一周，再决定保留什么、丢弃什么。

## 一、每日流程

### 1. 启动 Emacs

启动后你会看到一个轻量布局：左侧是 treemacs 侧栏，显示着你的 NoteHQ 目录树；右侧是 Dashboard，列出最近编辑过的文件和几个快捷入口按钮。这个布局会在首屏就让你看到两件事——最近在写什么，以及今天可以做什么。

### 2. 晨间回顾（2 分钟）

一天的第一件事不是打开任何一个具体的文件，而是看一眼 GTD Dashboard：

```
SPC a d    → 打开 GTD Dashboard
```

Dashboard 左侧的每一行都是一个视图入口，带着实时计算出来的任务数，让你一眼就知道各个篮子里堆了多少东西。**Inbox** 显示的是你昨天随手记下但还没有处理的 fleeting 想法；**Today** 是今天到期或已经排期的任务；**Upcoming** 是未来几天已经排期的任务；**Anytime** 是那些可以随时做、没有具体截止日期的 NEXT 行动；**Waiting** 列出你正在等别人做的事；**Someday** 是你暂时搁置、将来也许会做的事；**Projects** 则是当前所有活跃项目的列表，每个项目前面的符号（● / ~ / 空白）告诉你它的健康度——是有明确下一步、没有下一步、还是完全卡壳了。

点击任意一行或者在那行上按回车，右侧会打开对应的详细视图。

典型的晨间操作只需要三步。先点 **Today** 看看今天有什么要做——这是你今天大部分时间该聚焦的东西。然后点 **Inbox** 把昨天记下的零散想法逐一处理掉（决定每条是做、还是 refile 到某个项目、还是丢弃）。最后快速扫一遍 **Projects**，如果看到任何带 ● 标记的卡壳项目，就顺手给它添加一个 NEXT 子任务——让它重新"活过来"比积累一堆僵尸项目要轻松得多。

### 3. Daily 笔记：思维流与任务录入

接下来进入当天的 daily 笔记：

```
SPC n d d  → 创建/打开今日 daily note（capture 模式）
SPC n d t  → 直接跳转到今日 daily note（浏览模式）
```

这些文件放在 `~/NoteHQ/00_Roam/daily/` 下，以日期命名。Daily 笔记是这套系统里最"多功能"的一类文件，它同时承担两个看起来不相关但实际上高度互补的职责。

第一个职责是**思维流捕捉**：一边做事一边记录进展、观察、临时想法、未成形的疑问。这里的文字不需要严谨——可以是流水账、半截的句子、给自己的追问。重点是降低写作门槛，让想法在出现的瞬间就能被抓住。

第二个职责是**任务录入入口**。和大多数 GTD 教程推荐的"先用 capture 送进 inbox 再处理"不同，org-seq 鼓励你直接在 daily 笔记里就地写 TODO——因为 agenda 会扫描整个 NoteHQ 树，daily 里出现的任何带状态词的条目都会自动出现在 GTD Dashboard 的各个视图里。这个设计的好处是：任务的上下文（为什么要做它、它和今天正在思考的什么问题相关）天然地保留在同一个文件里，而不是变成一条孤零零的"inbox 条目"等待你以后费力回忆背景。

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

区分 TODO 和 PROJECT 的规则很简单——没有子任务的事情写作 TODO，有子任务的事情写作 PROJECT（在 `, q` 里按 `p` 可以把一条 TODO 升格成 PROJECT）。这样区分的好处是 GTD Dashboard 可以分别统计"纯待办"和"项目"，并在项目列表里提醒你哪些项目还没有 NEXT。

任务完成后你不需要做任何归档动作。daily 文件本身就是历史档案，DONE 的任务会留在原地，`SPC a 6`（Logbook 视图）会自动把所有状态为 DONE 的条目按时间倒序汇总起来——你想回顾"这周都完成了什么"时打开这个视图就够了。

> **关于 SPC a c**：传统的 `org-capture` 快捷键 `SPC a c` 依然可用，它会把内容送到专门的 inbox 文件里。但 daily-first 是推荐姿势——不是因为 capture 有什么不好，而是因为 inbox 处理本身就是一个额外的仪式感，很多人会在第三周就放弃它。把任务直接写在 daily 里，工作上下文自然保留，你不必"处理 inbox"也不会丢东西。

### 4. 集中工作

进入深度工作状态后，你会在笔记和任务之间频繁切换。几个常用的动作：

```
SPC n f    → 找到要编辑的笔记（org-roam 节点模糊查找，最常用的入口）
SPC l l    → 打开三栏工作区（dirvish 侧栏 + 编辑器 + outline/终端）
, s        → 给光标所在任务设置 schedule（计划开始日期）
, d        → 给光标所在任务设置 deadline（截止日期）
, q        → 弹出单键状态选择器（n=NEXT, i=进行中, w=等待, k=完成）
```

大多数人一天之内会反复按到 `SPC n f` 和 `, q`——前者是你进入任何笔记的最快路径，后者是你推进任务状态的最低摩擦方式。

### 5. 晚间收尾

一天结束前花两分钟收尾：

```
SPC a d    → 再看一眼 Dashboard，确认 Today 视图清空，Inbox 不积压
SPC n d d  → 回到 daily note，用几行字总结今天做了什么、明天要做什么
```

这个晚间动作不是强制仪式，但坚持下来会带来一个你意想不到的好处——第二天晨间回顾时，你的 daily 底部已经有了一段"昨天视角"的备忘，比空白开始一天要轻松得多。

---

## 二、GTD 工作流

完整的 GTD 方法论包括五个环节——收集、处理、组织、执行、回顾。下面分别说说每一环在 org-seq 里怎么落地，以及哪些 Allen 原版里的步骤因为 Emacs 的特殊性被简化或省略掉了。

### 收集（Capture）

GTD 教材通常会强调一个"无摩擦 inbox"——意思是你要能在 10 秒内把任何待办记下来，不受当前任务干扰。org-seq 提供了三条捕获路径，对应三种场景：

```
SPC n d d  → 在今日 daily note 中直接写入（推荐）
SPC a c    → 通用 org-capture（进入 Inbox）
SPC n c    → org-roam capture（创建新笔记节点）
```

### 处理（Process）

处理 inbox 的时候你需要逐条决定每个条目的归宿。打开 Inbox 视图：

```
SPC a 0    → 打开 Inbox 视图
```

对每一条，问自己五个问题：**这需要行动吗？不需要的就删掉或扔到 Library 作为参考资料。需要行动但两分钟就能搞完吗？当场做掉，直接标 DONE。需要但不是我来做？** 设状态为 WAITING 并加一条谁在等。**需要但得分几步？** 升格为 PROJECT 并拆子任务。**需要、只有一步、要花比较长时间？** 按 `, q` 选 NEXT，然后 `, t` 加上下文 tag（比如 `@work`），条件允许再 `, s` 或 `, d` 排个时间。`, r` 可以把条目 refile 到另一个 heading，例如把"学英语"从 inbox 移到你的"长期学习"项目下面。

这个过程听起来繁琐，熟练之后每条大约 5-15 秒——慢下来的往往是"要不要做"的决策，而不是按键操作本身。

### 执行（Do）

真正做事的时候，你需要根据当前的上下文（是在办公室还是家里、是有 30 分钟还是 2 小时、是专注状态还是间隙时间）挑一件任务推进。org-seq 提供了几个不同维度的筛选视图：

```
SPC a 3    → Anytime 视图（所有 NEXT 且没有排期，相当于"随时可做"池）
SPC a 1    → Today 视图（今天到期/排期的任务，最紧迫的一组）
SPC a 7    → 按上下文筛选，弹出 @work / @home / @computer 等标签选择
```

做完一件事后按 `, q` 再按 `k` 标记 DONE——如果这个任务下面还有未完成的子任务，org-seq 会问你是否连同子任务一起标完。DONE 的任务会自动下沉到同级列表的底部，让你的"未完成"条目始终在视线顶部。

### 回顾（Review）

Allen 把周回顾称为 GTD 系统的"秘密武器"——如果你跳过这一步，整个系统三个月内就会退化成一个积灰的待办列表。org-seq 提供两个层次的回顾视图：

```
SPC a w    → GTD 侧的周回顾视图（任务角度）
SPC n v w  → PKM 侧的周回顾 dashboard（笔记角度）
```

GTD 周回顾视图会同时显示过去三天和未来三天的日程（让你看到"刚刚发生了什么"和"马上要做什么"的全景）、所有当前正在进行的 IN-PROGRESS / NEXT / WAITING 任务、所有卡壳项目（有子任务但没有 NEXT 的）、以及 Someday 列表——让你有机会重新评估是否某个"以后再说"的想法现在可以激活了。建议每周挑固定时间做一次（周日晚上或周一早上都行），大约花 20-30 分钟。

---

## 三、笔记工作流（Zettelkasten）

### 碎片提取 —— 当某条想法值得独立存在

Zettelkasten 的核心动作不是"建立分类体系"，而是**识别哪些想法值得从流水里被捞出来**。你一天写下的 daily 可能有 90% 是临时的事务记录——这些就应该留在 daily 里，过两周再看就不值一读。但偶尔你会写下一个观察、一个比喻、一个问题的新提法，你会直觉地意识到"这东西以后我可能在完全不同的场景里还会想起它"——这就是一条值得独立存在的原子笔记。

识别出来之后，从 daily 里把它"提升"成独立节点的完整动作是这样的：

1. 按 `SPC n c` 打开 capture 模板选择菜单，大多数情况选 `d`（default）就够了——你不需要一开始就为每类笔记设计专门的模板。
2. 新节点会落到 `~/NoteHQ/00_Roam/capture/` 下，文件名是时间戳前缀加 slug（比如 `20260410T143022-atomic-notes-as-conversation.org`）。这个命名方案保证了两点：节点之间不会因为重名冲突，以及将来你可以用文件名时间戳回溯"某一周我写了哪些新东西"。
3. 屏幕下方会弹出一个窗口让你编辑新节点的正文——写几句话阐明这个想法就够了。不要在第一版就追求完美，原子笔记的价值来自数量积累而非单条完美。
4. 写完后回到原来的 daily 位置（可以 `C-x b` 切回去，或用 `SPC ,`），按 `SPC n i` 插入一个 `[[id:...]]` 链接指向新节点。这样以后你在 daily 里看到这条"已经被提升"的想法时，可以一键跳过去查看它演化成了什么样子。
5. 如果这条笔记属于某个已经定义好的 supertag 类别（比如你有 `concept` 或 `reading` tag），按 `SPC n p p` 给它加 tag 并填上相关字段。没有合适的 tag 就跳过这一步——tag 是后来长出来的，不是预先规划的。
6. 关闭 capture 窗口，回到 daily 继续写下一段。

这个过程你会做得越来越快。第一周可能每条都要想 2-3 分钟，一个月后大约每条 30 秒就能完成提取。重点是养成"看到值得的想法就提升"的本能反应——漏掉几条没关系，僵化的仪式才是真正的敌人。

**分类由 tag 承担，不由目录承担**。除了 `daily/`、`capture/`、`dashboards/` 三个特殊子目录，`00_Roam/` 完全扁平——没有什么 `literature/` / `concepts/` / `people/` 之类的层级。如果你发现自己在思考"这条笔记应该放在哪个目录"，那是旧的文件系统思维在捣乱——答案是"放在 capture/ 里，让 tag 告诉你它是什么"。

### Capture 模板

内置只有两个模板：

```
SPC n c → d = 默认笔记（无 tag 的纯笔记，覆盖 80% 场景）
          r = reading（文献/书籍笔记，带 TL;DR / Key points 骨架）
```

需要更多模板时：
```
SPC n m c  → 编辑 capture 模板文件（~/.orgseq/capture-templates.el）
SPC n m C  → 重载 capture 模板（无需重启 Emacs）
```

### 链接与发现

```
SPC n i    → 在当前位置插入到另一个笔记的链接
SPC n b    → 侧边栏显示当前笔记的 backlinks
SPC n g    → 在浏览器中打开 org-roam-ui 图谱
SPC n /    → 在 Roam 目录全文搜索（ripgrep）
SPC n q s  → 用 org-ql 进行结构化查询
SPC n q v  → org-ql 保存视图
```

### Supertag 操作

**全局键位 `SPC n p …`**：

```
SPC n p p  → 快速操作（context-aware 菜单：无 tag 时加 tag，有 tag 时选操作）
SPC n p a  → 添加 supertag
SPC n p e  → 编辑字段
SPC n p x  → 移除 tag
SPC n p j  → 跳转到关联节点
```

**Org buffer 内局部 leader `, # …`**：

```
, ##       → 快速操作（等同 SPC n p p）
, #a       → 添加 tag
, #e       → 编辑字段
, #x       → 移除 tag
, #j       → 跳转到关联节点
```

### Tag schema 维护

```
SPC n m t  → 编辑 tag schema（~/NoteHQ/00_Roam/supertag-schema.el）
SPC n m T  → 重载 tag schema（无需重启 Emacs）
```

增加新 tag 的时机：某类事情你已经用 default 模板记过 5 次以上，且发现它们有共同结构。

### Transclusion（内容嵌入）

```
SPC n t a  → 在当前位置添加一个 transclusion 链接
SPC n t t  → 开启/关闭 transclusion 模式（实时渲染嵌入内容）
```

### Daily Notes 导航

```
SPC n d d  → Capture today（写入）
SPC n d t  → Goto today（阅读）
SPC n d y  → 昨天的 daily note
SPC n d T  → 明天的 daily note
SPC n d p  → 上一篇 daily note
SPC n d n  → 下一篇 daily note
SPC n d f  → 按日期查找
```

---

## 四、Dashboard 与 Review 工作流

Dashboard 是**只读的查询窗口**，利用 org-supertag 自动渲染所有相关 tag 节点的当前状态。Dashboard 不是录入入口 —— 任何想"在 dashboard 里写注释"的冲动都该去新建独立的 Roam 节点。

### 查看 Dashboard

```
SPC n v v  → 打开 dashboard index（总入口，列出所有 dashboard）
SPC n v w  → Weekly review dashboard
SPC n v i  → Dashboard index
```

### 创建新 Dashboard

```
SPC n m d  → 创建新 dashboard
```

新 dashboard 保存在 `~/NoteHQ/00_Roam/dashboards/` 下。每个文件是独立的 org 文件，用 `#+BEGIN: supertag-query` 动态块定义查询。

### Review 操作

每天结束、每周末、或某项工作收尾时：

1. `SPC n v v` 进入 dashboard index
2. 挑相关 dashboard 打开
3. 在 dashboard 里做这些事情：
   - 看本周新增的笔记是否需要补充字段或链接
   - 看某个主题的所有相关碎片是否暗示着新的洞察
   - 看哪些笔记之间应该建立链接但还没建立
   - 决定哪些碎片足够成熟，可以晋升到 PARA 层成为正式产出物的素材

---

## 五、PARA 工作流

NoteHQ 分为两大区域：**00_Roam/（原子层）** 和 **PARA 层（产出/实践/资源/归档）**。两层通过 `id:` 链接和 `org-transclusion` 通信。

### 目录结构

```
~/NoteHQ/
├── 00_Roam/                   ← 原子层 (org-roam 索引范围)
│   ├── daily/              ← 每日笔记
│   ├── dashboards/         ← 查询入口文件
│   └── capture/            ← 所有 capture 落地（扁平，时间戳前缀）
│
├── 10_Outputs/                ← 有明确交付时刻的产出物（论文、课件、申请书…）
├── 20_Practice/               ← 长期承担的角色与责任沉淀（教学、临床、研究方法…）
├── 30_Library/                ← 被取用而非被维护的素材（PDF、BibTeX、数据集…）
└── 40_Archives/               ← 已完成或停滞的内容（按年份归档）
```

### PARA 导航

```
SPC P o    → 在 Outputs 中查找/打开文件
SPC P p    → 在 Practice 中查找/打开文件
SPC P l    → 在 Library 中查找/打开文件
SPC P g    → 在整个 NoteHQ 中 ripgrep 全文搜索
```

### 各层判定

拿不准放哪一层时，依次回答 3 个问题：

1. **它会"完成"吗？** 能想象明确的完成时刻 → **10_Outputs/**
2. **你对它有外部义务吗？** 长期角色、有责任对象 → **20_Practice/**
3. **你会主动审阅它，还是只是取用它？** 主动审阅 → **20_Practice/**；只是取用 → **30_Library/**

不确定时默认放 10_Outputs/。Outputs 有更高的可见度，会被频繁打开。

### Roam 与 PARA 的交互

- 在 Outputs 的 manuscript.org 里用 `SPC n i` 引用 Roam 节点（id: 链接）
- 用 `org-transclusion` 把 Roam 节点的内容实时嵌入到 PARA 文档
- 项目完成后归档：把 `10_Outputs/your-project/` 移到 `40_Archives/2026-your-project/`
- 可复用的方法学和心得抽出来回流到 20_Practice/

---

## 六、AI 辅助工作流

### 配置前提

在 `~/.authinfo` 中配置 OpenRouter API key：

```
machine openrouter.ai login apikey password sk-or-你的KEY
```

### 日常 AI 操作

```
SPC i i    → 发送当前 buffer/选区到 LLM，回答追加在后面
SPC i m    → 完整 AI 菜单（切换模型、参数、预设）
SPC i c    → 打开独立 AI 对话 buffer
SPC i r    → 改写选中区域（diff 模式，可接受/拒绝）
```

### PKM 专用 AI 命令

```
SPC i s    → 摘要当前笔记或选区
SPC i t    → 根据内容建议 org-roam filetags
SPC i l    → 翻译选区（中英互译）
SPC i k    → 基于当前笔记建议关联概念
SPC i p    → 润色选中文本的写作质量
```

### Org-babel AI 块

在 Org 笔记中嵌入可执行的 AI 查询：

```org
#+begin_src gptel :model deepseek/deepseek-chat-v3-0324
总结 Zettelkasten 方法论的核心原则
#+end_src
```

按 `C-c C-c` 执行，结果异步插入到 `#+RESULTS:` 块中。

---

## 七、Markdown 工作流

### 编辑

打开 `.md` 文件自动进入 GFM 模式，启用：
- 居中显示（visual-fill-column）
- 自适应宽度（随窗口调整）
- 隐藏 URL（只显示链接文本）

### Local leader 操作

```
, v    → 在源码和 live preview 之间切换
, p    → 在浏览器中预览
, e    → 导出（需要 pandoc）
, t    → 插入目录（Table of Contents）
, r    → 刷新目录
, l    → 插入链接
, o    → 切换 markup 显示/隐藏
```

---

## 八、Casual 菜单（不确定按什么键时用）

当你忘记某个模式下有哪些操作可用时：

```
SPC c c    → 全局 Casual EditKit 菜单（任何 buffer 中可用）
C-o        → 当前模式的 Casual 菜单（在 Org Agenda / Dired / IBuffer / Info 等中）
```

Casual 会弹出一个 Transient 面板，列出当前模式下所有可用操作，按对应字母即可执行。

---

## 九、与其他工具共存

Roam 层与 org-node/org-mem 以 **纯 Org** 为主（已移除 md-roam）。Zettelkasten、反向链接与 supertag 元数据都依赖 `.org` 与 org-id。

若仍用 Obsidian 等工具指向 `~/NoteHQ/`：适合浏览目录中的 Org/Markdown；**主编辑与图谱闭环建议在 Emacs** 中完成，避免 Markdown 笔记不被 org-roam 索引。

---

## 十、常用键位速查

### 核心操作

| 场景 | 键位 | 说明 |
|------|------|------|
| 找笔记 | `SPC n f` | org-roam 节点查找 |
| 写日记 | `SPC n d d` | 今日 daily note（推荐任务录入入口） |
| 新建笔记 | `SPC n c` | org-roam capture（d=默认, r=reading） |
| 插入链接 | `SPC n i` | 在当前位置插入 Roam 节点链接 |
| 看 backlinks | `SPC n b` | 侧边栏显示反向链接 |
| 搜 Roam 正文 | `SPC n /` | consult-ripgrep，限 Roam 目录 |
| 搜当前项目 | `SPC /` 或 `SPC s p` | ripgrep |

### GTD

| 场景 | 键位 | 说明 |
|------|------|------|
| 看任务 | `SPC a d` | GTD Dashboard |
| 今天做什么 | `SPC a 1` | Today 视图 |
| 处理 inbox | `SPC a 0` | Inbox 视图 |
| 随时可做 | `SPC a 3` | Anytime 视图 |
| 改状态 | `, q` | 单键状态选择 |

### Supertag（SPC n p）

| 场景 | 键位 | 说明 |
|------|------|------|
| 快速操作 | `SPC n p p` | context-aware 菜单 |
| 加 tag | `SPC n p a` | 添加 supertag |
| 编辑字段 | `SPC n p e` | 编辑 tag 字段 |
| 移除 tag | `SPC n p x` | 移除 tag |
| 跳转关联 | `SPC n p j` | 跳转到关联节点 |

### Supertag 局部 leader（Org buffer 内）

| 场景 | 键位 | 说明 |
|------|------|------|
| 快速操作 | `, ##` | 等同 SPC n p p |
| 加 tag | `, #a` | 添加 supertag |
| 编辑字段 | `, #e` | 编辑 tag 字段 |
| 移除 tag | `, #x` | 移除 tag |
| 跳转关联 | `, #j` | 跳转到关联节点 |

### Views / Dashboard（SPC n v）

| 场景 | 键位 | 说明 |
|------|------|------|
| Dashboard 总入口 | `SPC n v v` | 打开 dashboard index |
| 周回顾 | `SPC n v w` | Weekly review dashboard |
| Dashboard index | `SPC n v i` | 同 SPC n v v |

### Meta / 扩展（SPC n m）

| 场景 | 键位 | 说明 |
|------|------|------|
| 编辑 tag schema | `SPC n m t` | 打开 supertag-schema.el |
| 重载 tag schema | `SPC n m T` | 重载 tag 定义 |
| 编辑 capture 模板 | `SPC n m c` | 打开 capture-templates.el |
| 重载 capture 模板 | `SPC n m C` | 重载 capture 模板 |
| 新建 dashboard | `SPC n m d` | 创建新 dashboard |

### PARA 导航（SPC P）

| 场景 | 键位 | 说明 |
|------|------|------|
| Outputs | `SPC P o` | 查找/打开产出物 |
| Practice | `SPC P p` | 查找/打开实践域 |
| Library | `SPC P l` | 查找/打开资源库 |
| 全局搜索 | `SPC P g` | ripgrep 整个 NoteHQ |

### AI

| 场景 | 键位 | 说明 |
|------|------|------|
| AI 提问 | `SPC i i` | 发送到 LLM |
| AI 摘要 | `SPC i s` | 总结笔记 |
| AI 菜单 | `SPC i m` | 完整 AI 菜单 |

### 专注计时器（Vitamin-R 风格）

| 场景 | 键位 | 说明 |
|------|------|------|
| 启动专注片段 | `SPC a f` | 在当前点插入计时标记，自动对齐到最近整点（默认 15 分钟边界） |
| 自定义时长 | `C-u SPC a f` | 弹出时长输入框，默认值为自动对齐结果 |
| 中止当前片段 | `SPC a X` | 取消运行中的片段（不记录结果） |
| 专注 Dashboard | `SPC a F` | 打开近 14 天专注历史可视化 |

当计时结束时 Emacs 会响铃并弹出单键提示："这段感觉如何？(u) 不集中 (n) 正常 (f) 心流"。结果会同时追加到原 buffer 的内联标记和 `~/NoteHQ/.orgseq/focus-log.org` 日志文件。Modeline 在片段运行期间显示剩余时间。

Dashboard 按天展示彩色时间线（█ flow / ▓ normal / ░ unfocused），以及 14 天聚合统计（各状态的片段数、分钟数、占比）。日志是纯 org 格式，可以用 `org-ql` 或任何文本工具二次分析。

### Dirvish 文件管理（取代旧 Treemacs）

| 场景 | 键位 | 说明 |
|------|------|------|
| 开关侧栏 | `SPC l t` | treemacs（NoteHQ 根目录） |
| 全屏 dirvish | `SPC o f` | 当前目录 |
| 打开 NoteHQ | `SPC o N` | 全屏 dirvish 到 NoteHQ 根 |
| 跳到当前文件目录 | `SPC f j` 或 `SPC o d` | dired-jump |
| Quick-access 菜单 | 在 dirvish 内按 `a` | 一键跳 00_Roam/capture/daily/dashboards/10_Outputs/20_Practice/30_Library/... |
| 子目录展开 | 在 dirvish 内按 `TAB` | 在当前行原位展开/折叠 |
| Casual 菜单 | 在 dirvish 内按 `C-o` | Transient 菜单（所有 dired 操作） |

### 通用

| 场景 | 键位 | 说明 |
|------|------|------|
| 不知道按什么 | `SPC` 等一下 | which-key 弹出 |
| 还是不知道 | `SPC c c` | Casual 全局菜单 |
| 定制配置 | `M-x customize-group RET org-seq RET` | 所有用户可调参数（路径、宽度、TTL、context tags 等） |
