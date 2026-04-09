# org-seq 推荐工作流

本文档描述使用 org-seq 配置进行日常 PKM（个人知识管理）和 GTD（任务管理）的推荐工作流。

## 一、每日流程

### 1. 启动 Emacs

启动后自动进入 Dashboard，左侧 Treemacs 显示 NoteHQ 目录树，右侧 Dashboard 显示最近文件和快捷按钮。

### 2. 晨间回顾（2 分钟）

```
SPC a d    → 打开 GTD Dashboard
```

Dashboard 左侧面板显示各类别的实时计数：

- **Inbox** — 未处理的 fleeting 笔记数量
- **Today** — 今日到期/已排期的任务
- **Upcoming** — 未来已排期的任务
- **Anytime** — 可随时做的 NEXT 任务（无排期）
- **Waiting** — 等待他人的任务
- **Someday** — 将来也许做的任务
- **Projects** — 活跃项目列表（带健康度指示）

点击任意行或按 `RET`，右侧打开对应的详细视图。

**典型晨间操作**：
1. 点击 **Today** — 看看今天有什么要做的
2. 点击 **Inbox** — 处理昨天随手记下的东西
3. 快速浏览 **Projects** — 确认是否有 ● 标记的卡壳项目

### 3. Daily 笔记：思维流与任务录入

```
SPC n d d  → 创建/打开今日 daily note（capture 模式）
SPC n d t  → 直接跳转到今日 daily note（浏览模式）
```

Daily note 放在 `~/NoteHQ/Roam/daily/` 下，按日期命名。**Daily 同时承担两个职责**：

**职责 A：思维流捕捉**。一边做事一边记录进展、观察、临时想法。文字写法不严谨，可以是流水账、问句、断句。

**职责 B：任务录入入口**。日常 TODO 推荐直接在 daily 里就地写入，不需要先打断思路去 capture。agenda 会扫描整个 NoteHQ 树，所以 daily 里的任务会自动出现在 GTD Dashboard 各视图中。

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

任务类型区分：没有子任务 → 单条 TODO；有子任务 → PROJECT。

任务完成后不需要归档。daily 文件本身就是历史档案，`SPC a 6` Logbook 视图会自动汇总所有 DONE 状态的任务。

> **提示**：`SPC a c` 通用 org-capture 仍然可用，但 daily-first 是推荐流程 —— 任务的上下文（为什么要做、跟今天的什么思考有关）天然保留在同一个文件里。

### 4. 集中工作

进入工作状态后，常用操作：

```
SPC n f    → 找到要编辑的笔记
SPC l l    → 打开三栏工作区（treemacs + 编辑器 + outline/终端）
, s        → 给任务设置 schedule
, d        → 给任务设置 deadline
, q        → 单键状态选择器（n=NEXT i=进行中 w=等待 k=完成）
```

### 5. 晚间收尾

```
SPC a d    → 再看一眼 Dashboard
SPC n d d  → 在 daily note 里记一下今天做了什么
```

---

## 二、GTD 工作流

### 收集（Capture）

推荐在 daily 里直接写 TODO，这是最自然的方式。也可以用传统 capture 入口：

```
SPC n d d  → 在今日 daily note 中直接写入（推荐）
SPC a c    → 通用 org-capture（进入 Inbox）
SPC n c    → org-roam capture（创建新笔记节点）
```

### 处理（Process）

打开 Inbox 视图，逐条决定：

```
SPC a 0    → 打开 Inbox 视图
```

对每条 inbox 条目，决定其归宿：
- 设置状态：`, q` → 按 `n`（NEXT）、`i`（IN-PROGRESS）、`w`（WAITING）、`s`（SOMEDAY）、`k`（DONE）、`x`（CANCEL）、`p`（PROJECT）
- 归档到项目：`, r`（refile 到其他 heading）
- 设置日期：`, s`（schedule）或 `, d`（deadline）
- 添加上下文标签：`, t`（设置 @work、@home 等 tag）
- 不需要了：`, q` → 按 `x`（CANCELLED）

### 执行（Do）

根据上下文选择要做的事：

```
SPC a 3    → Anytime 视图（NEXT 且无排期 = 随时可做）
SPC a 1    → Today 视图（今天到期的任务）
SPC a 7    → 按上下文筛选（@work、@home 等）
```

执行完成后：
- `, q` → 按 `k`（标记 DONE）— 如果有子任务会询问是否批量完成
- DONE 的任务会自动下沉到同级底部

### 回顾（Review）

每周回顾：

```
SPC a w    → 打开 Weekly review 视图（GTD 侧）
SPC n v w  → 打开 Weekly review dashboard（PKM 侧）
```

Weekly review 显示：
- 过去 3 天 + 未来 3 天的日程
- 当前所有 IN-PROGRESS / NEXT / WAITING 任务
- 卡壳的项目（有子任务但没有 NEXT 的项目）
- Someday 列表（是否该激活某些？）

---

## 三、笔记工作流（Zettelkasten）

### 碎片提取 —— 当某条想法值得独立存在

写 daily 时如果某条内容值得作为独立笔记长期追溯，立刻执行：

1. `SPC n c` → 选 capture 模板（多数时候用 `d` default 即可）
2. 新节点文件落到 `Roam/capture/` 目录（扁平，时间戳前缀文件名）
3. 在下方弹出的 buffer 里编辑节点内容
4. `SPC n i` → 在 daily 原位置插入 `id:` 链接
5. `SPC n p p` → 添加 supertag，填字段
6. 关闭，回到 daily 继续

**分类由 tag 承担，不由目录承担**。除了 `daily/` 和 `dashboards/` 两个特殊子目录，Roam/ 完全扁平。

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
SPC n m t  → 编辑 tag schema（~/NoteHQ/Roam/supertag-schema.el）
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

新 dashboard 保存在 `~/NoteHQ/Roam/dashboards/` 下。每个文件是独立的 org 文件，用 `#+BEGIN: supertag-query` 动态块定义查询。

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

NoteHQ 分为两大区域：**Roam/（原子层）** 和 **PARA 层（产出/实践/资源/归档）**。两层通过 `id:` 链接和 `org-transclusion` 通信。

### 目录结构

```
~/NoteHQ/
├── Roam/                   ← 原子层 (org-roam 索引范围)
│   ├── daily/              ← 每日笔记
│   ├── dashboards/         ← 查询入口文件
│   └── capture/            ← 所有 capture 落地（扁平，时间戳前缀）
│
├── Outputs/                ← 有明确交付时刻的产出物（论文、课件、申请书…）
├── Practice/               ← 长期承担的角色与责任沉淀（教学、临床、研究方法…）
├── Library/                ← 被取用而非被维护的素材（PDF、BibTeX、数据集…）
└── Archives/               ← 已完成或停滞的内容（按年份归档）
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

1. **它会"完成"吗？** 能想象明确的完成时刻 → **Outputs/**
2. **你对它有外部义务吗？** 长期角色、有责任对象 → **Practice/**
3. **你会主动审阅它，还是只是取用它？** 主动审阅 → **Practice/**；只是取用 → **Library/**

不确定时默认放 Outputs/。Outputs 有更高的可见度，会被频繁打开。

### Roam 与 PARA 的交互

- 在 Outputs 的 manuscript.org 里用 `SPC n i` 引用 Roam 节点（id: 链接）
- 用 `org-transclusion` 把 Roam 节点的内容实时嵌入到 PARA 文档
- 项目完成后归档：把 `Outputs/your-project/` 移到 `Archives/2026-your-project/`
- 可复用的方法学和心得抽出来回流到 Practice/

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

### 通用

| 场景 | 键位 | 说明 |
|------|------|------|
| 不知道按什么 | `SPC` 等一下 | which-key 弹出 |
| 还是不知道 | `SPC c c` | Casual 全局菜单 |
