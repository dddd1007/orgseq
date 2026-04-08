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

### 3. 日记与随想

```
SPC n d d  → 创建/打开今日 daily note（capture 模式）
SPC n d t  → 直接跳转到今日 daily note（浏览模式）
```

Daily note 会自动放在 `~/NoteHQ/Roam/daily/` 下，按日期命名。支持三种 capture 模板：
- 默认（带时间戳的快速记录）
- Task（直接创建带 SCHEDULED 的 TODO）
- Journal（日记条目）

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

随时随地收集想法，不打断当前工作：

```
SPC a c    → 通用 org-capture（进入 Inbox）
SPC n c    → org-roam capture（创建新笔记节点）
SPC n d d  → 在今日 daily note 中快速记录
```

Inbox 使用 org-roam 的 `:fleeting:` 标签。带此标签且无 TODO 状态的条目会出现在 Dashboard 的 Inbox 计数中。

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
SPC a w    → 打开 Weekly review 视图
```

Weekly review 显示：
- 过去 3 天 + 未来 3 天的日程
- 当前所有 IN-PROGRESS / NEXT / WAITING 任务
- 卡壳的项目（有子任务但没有 NEXT 的项目）
- Someday 列表（是否该激活某些？）

---

## 三、笔记工作流（Zettelkasten）

### 创建笔记

```
SPC n c    → org-roam capture，选择模板：
             d = 默认笔记
             l = 文献笔记（带 Core Ideas / Methodology 结构）
             c = 概念笔记（带 Definition / Related Concepts 结构）
             f = 闪念笔记（立即完成，不打开编辑器）
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

**org-supertag**（全局 `SPC n s …`，或在 Org 里 `, # …`）：

```
SPC n s a  → 添加 supertag
SPC n s v  → 节点表格/视图
SPC n s s  → 数据库搜索
SPC n s k  → 看板
SPC n s r  → 立即同步（捕获后也会 idle 触发检查）
SPC n s R  → 首次或重建：`supertag-sync-full-initialize`
```

在 Org buffer 内也可用局部 leader：`, # a` 加标签、`, # v` 视图、`, # s` 搜索、`, # k` 看板、`, # c` 捕获。

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

## 四、AI 辅助工作流

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

## 五、Markdown 工作流

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

## 六、Casual 菜单（不确定按什么键时用）

当你忘记某个模式下有哪些操作可用时：

```
SPC c c    → 全局 Casual EditKit 菜单（任何 buffer 中可用）
C-o        → 当前模式的 Casual 菜单（在 Org Agenda / Dired / IBuffer / Info 等中）
```

Casual 会弹出一个 Transient 面板，列出当前模式下所有可用操作，按对应字母即可执行。

---

## 七、与其他工具共存

Roam 层与 org-node/org-mem 以 **纯 Org** 为主（已移除 md-roam）。Zettelkasten、反向链接与 supertag 元数据都依赖 `.org` 与 org-id。

若仍用 Obsidian 等工具指向 `~/NoteHQ/`：适合浏览目录中的 Org/Markdown；**主编辑与图谱闭环建议在 Emacs** 中完成，避免 Markdown 笔记不被 org-roam 索引。

---

## 八、常用键位速查

| 场景 | 键位 | 说明 |
|------|------|------|
| 找笔记 | `SPC n f` | org-roam 节点查找 |
| 写日记 | `SPC n d d` | 今日 daily note |
| 看任务 | `SPC a d` | GTD Dashboard |
| 今天做什么 | `SPC a 1` | Today 视图 |
| 处理 inbox | `SPC a 0` | Inbox 视图 |
| 改状态 | `, q` | 单键状态选择 |
| 搜 Roam 正文 | `SPC n /` | consult-ripgrep，限 Roam 目录 |
| 搜当前项目 | `SPC /` 或 `SPC s p` | ripgrep |
| AI 提问 | `SPC i i` | 发送到 LLM |
| AI 摘要 | `SPC i s` | 总结笔记 |
| 不知道按什么 | `SPC` 等一下 | which-key 弹出 |
| 还是不知道 | `SPC c c` | Casual 全局菜单 |
