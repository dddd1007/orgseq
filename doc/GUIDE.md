# org-seq 完全上手指南

> 本指南面向 Emacs 初学者，从零开始介绍 org-seq 配置的全部功能。即使你从未用过 Emacs，也可以按照本文一步步上手。

---

## 目录

- [第一章 什么是 org-seq](#第一章-什么是-org-seq)
- [第二章 安装与首次启动](#第二章-安装与首次启动)
- [第三章 生存指南——最关键的 10 分钟](#第三章-生存指南最关键的-10-分钟)
- [第四章 编辑器基础](#第四章-编辑器基础)
- [第五章 文件与 Buffer 管理](#第五章-文件与-buffer-管理)
- [第六章 搜索与导航](#第六章-搜索与导航)
- [第七章 Org-mode——你的超级文档格式](#第七章-org-mode你的超级文档格式)
- [第八章 笔记系统（Zettelkasten）](#第八章-笔记系统zettelkasten)
- [第九章 任务管理（GTD）](#第九章-任务管理gtd)
- [第十章 AI 助手](#第十章-ai-助手)
- [第十一章 Markdown 支持](#第十一章-markdown-支持)
- [第十二章 工作区布局](#第十二章-工作区布局)
- [第十三章 Git 版本控制](#第十三章-git-版本控制)
- [第十四章 外观与主题](#第十四章-外观与主题)
- [第十五章 进阶功能](#第十五章-进阶功能)
- [附录 A 完整键位速查表](#附录-a-完整键位速查表)
- [附录 B 常见问题排查](#附录-b-常见问题排查)

---

## 第一章 什么是 org-seq

### 1.1 一句话概括

org-seq 是一套 **Emacs 配置**，把 Emacs 变成一个集笔记、任务管理、AI 辅助于一体的**个人知识管理工作站**。

### 1.2 它能做什么

| 能力 | 说明 |
|------|------|
| **Zettelkasten 笔记** | 基于 org-roam 的双向链接笔记网络，可视化知识图谱 |
| **GTD 任务管理** | 收集→处理→执行→回顾的完整闭环，带实时计数面板 |
| **结构化数据** | org-supertag 把标签变成数据库表格，支持看板视图 |
| **AI 集成** | 调用 LLM 做摘要、翻译、标签建议、关联发现 |
| **Vim 键位** | 通过 Evil mode 提供完整的 Vim 编辑体验 |
| **Markdown 支持** | 实时预览、导出、目录生成 |
| **Git 集成** | Magit——被广泛认为是最好的 Git 界面 |
| **居中排版** | Olivetti 模式让文档在宽屏上也舒适阅读 |

### 1.3 核心理念

```
笔记在 ~/NoteHQ/Roam/ 里，用 .org 格式
任务也在笔记里，用 TODO/DONE 等状态标记
所有操作用键盘完成，核心入口是 SPC（空格键）
```

### 1.4 你的笔记库结构

```
~/NoteHQ/                          ← 笔记总目录
├── Roam/                          ← 原子笔记层（org-roam 管理）
│   ├── daily/                     ← 每日笔记（思维流 + 任务录入）
│   ├── capture/                   ← 所有捕获的笔记（扁平，时间戳前缀）
│   ├── dashboards/                ← 查询入口文件（只放查询，不放数据）
│   ├── supertag-schema.el         ← 标签定义（跟笔记一起 git）
│   └── purpose.org / schema.org   ← AI 上下文文件
├── Outputs/                       ← PARA：可交付的项目（论文、课件…）
├── Practice/                      ← PARA：长期角色与责任域（教学、研究…）
├── Library/                       ← PARA：被取用的素材库（PDF、数据集…）
├── Archives/                      ← 已完成/暂停的内容
└── .orgseq/                       ← 个性化配置（类似 .vscode/）
    ├── ai-config.org              ← AI 服务配置
    └── capture-templates.el       ← 用户自定义捕获模板
```

**核心设计**：Roam/ 内部是扁平的——分类靠 supertag 标签，不靠目录。PARA 四层存放产出物和素材。两层通过 `id:` 链接和 transclusion 通信。

---

## 第二章 安装与首次启动

### 2.1 前置条件

| 软件 | 要求 | 用途 | 安装方式 (Windows) |
|------|------|------|-----------|
| **Emacs** | 29+ | 编辑器本体 | `winget install GNU.Emacs` 或 MSYS2 构建 |
| **Git** | 任意版本 | 版本控制 + Magit | `winget install Git.Git` |
| **ripgrep** | 任意版本 | 全文搜索 | `winget install BurntSushi.ripgrep` |
| **fd** | 任意版本 | 文件查找 | `winget install sharkdp.fd` |
| **SQLite** | 内置于 Emacs 29+ | org-roam 数据库 | 无需额外安装 |

**验证 Emacs 版本和功能**（启动 Emacs 后按 `M-:` 输入）：

```elisp
(emacs-version)                ;; 应 >= 29
(sqlite-available-p)           ;; 应返回 t
(native-comp-available-p)      ;; 建议 t（MSYS2 构建才有）
```

> **注意**：`M-:` 是按住 Alt 再按冒号 `:`，这是 Emacs 的"执行表达式"快捷键。

**推荐字体**：

- 英文：[Cascadia Code](https://github.com/microsoft/cascadia-code)（微软出品等宽字体）
- 中文：[LXGW WenKai Mono](https://github.com/lxgw/LxgwWenKai)（霞鹜文楷等宽）

下载 .ttf 文件后右键"安装"即可。

### 2.2 部署配置

```powershell
# 1. 克隆仓库
git clone <repo-url> ~/CodeProject/org-seq
cd ~/CodeProject/org-seq

# 2. 运行部署脚本（会备份已有配置）
.\deploy.ps1

# 3. 初始化笔记库目录结构
.\scripts\bootstrap-notes.ps1

# Linux/macOS 用户：
# ./deploy.sh
# ./scripts/bootstrap-notes.sh
```

部署脚本会检查前置条件、备份已有配置、部署到 `~/.emacs.d/`。
Bootstrap 脚本会创建 `~/NoteHQ/` 的完整目录结构（Roam + PARA 四层）。

### 2.3 首次启动

首次启动 Emacs 会自动：
1. 从网络下载并安装所有包（需要稳定网络，约 2-5 分钟）
2. 创建 `~/NoteHQ/.orgseq/ai-config.org` 和 `capture-templates.el`
3. 显示 Dashboard 启动界面

**首次启动后额外操作**：

```
;; 安装图标字体（在 Emacs 中执行）
M-x nerd-icons-install-fonts

;; Windows 用户：找到下载的 .ttf 文件，右键 → 安装

;; 初始化 org-supertag 索引
M-x supertag-sync-full-initialize
```

### 2.4 配置 AI（可选但推荐）

org-seq 通过 [OpenRouter](https://openrouter.ai) 统一接入各种 AI 模型（Claude、GPT、DeepSeek 等），只需一个 API key。

**第一步：获取 Key**

注册 OpenRouter 账号 → 进入 Keys 页面 → 创建一个 API key。

**第二步：保存 Key**

创建或编辑 `~/.authinfo` 文件（纯文本），加入一行：

```
machine openrouter.ai login apikey password sk-or-你的KEY
```

> 安全提示：如果想加密保存，把文件命名为 `~/.authinfo.gpg`，Emacs 会在读取时自动解密。

**第三步（可选）：自定义模型和后端**

编辑 `~/NoteHQ/.orgseq/ai-config.org`，你可以：
- 修改 `DEFAULT_MODEL` 切换默认模型
- 在模型列表中添加/删除模型
- 添加新的后端（如本地 Ollama）

```org
* Settings
:PROPERTIES:
:DEFAULT_BACKEND: OpenRouter
:DEFAULT_MODEL: anthropic/claude-sonnet-4
:END:
```

---

## 第三章 生存指南——最关键的 10 分钟

如果你只有 10 分钟，记住这些就够了。

### 3.1 两种模式

org-seq 使用 **Evil mode**——在 Emacs 里模拟 Vim。这意味着你的光标始终处于某种"模式"中：

| 模式 | 含义 | 进入方式 | 光标外观 |
|------|------|---------|---------|
| **Normal** | 浏览和操作（默认） | `Esc` 或 `C-[` | 方块 |
| **Insert** | 输入文字 | `i`（光标前）/ `a`（光标后）/ `o`（下方新行） | 竖线 |
| **Visual** | 选中文本 | `v`（字符）/ `V`（行）/ `C-v`（块） | 高亮区域 |
| **Command** | 输入命令 | `:` | 底部命令行 |

> **最重要的键**：按 `Esc` 可以从任何模式回到 Normal 模式。不确定当前状态时就按 `Esc`。

### 3.2 空格键是你的入口

在 Normal 模式下，按 **SPC**（空格键）会弹出一个菜单（which-key），显示所有可用的下一步操作。

```
SPC         → 等 0.3 秒 → 弹出功能菜单
SPC SPC     → M-x（输入任意命令名称执行）
SPC .       → 打开文件
SPC ,       → 切换 buffer（已打开的文件）
SPC /       → 在项目中全文搜索
```

**不知道按什么键？按 SPC 等一下看菜单。还不行？按 `SPC c c` 打开 Casual 菜单。**

### 3.3 最常用的操作

```
基本操作：
  SPC .       → 打开文件
  SPC f s     → 保存文件
  SPC b d     → 关闭当前文件
  SPC q q     → 退出 Emacs

笔记操作：
  SPC n f     → 查找/打开笔记
  SPC n c     → 新建笔记
  SPC n d d   → 写今日日记

任务操作：
  SPC a d     → 任务仪表盘
  SPC a c     → 快速记一条待办

搜索：
  SPC /       → 全文搜索
  SPC s s     → 搜索当前文件
```

### 3.4 退出方式汇总

| 想退出什么 | 按什么 |
|-----------|--------|
| 退出插入模式 | `Esc` |
| 关闭弹出窗口/菜单 | `q` 或 `Esc` |
| 关闭当前 buffer | `SPC b d` |
| 退出 Emacs | `SPC q q` |
| 取消正在输入的命令 | `C-g`（Ctrl+g）|

> `C-g` 是 Emacs 的万能取消键。任何时候卡住了，按 `C-g` 取消当前操作。

---

## 第四章 编辑器基础

### 4.1 Evil (Vim) 操作速成

#### 移动

```
h j k l        ← ↓ ↑ →（字符级）
w / b          → 前/后跳一个单词
0 / $          → 行首 / 行尾
gg / G         → 文件开头 / 文件结尾
C-u / C-d      → 向上/向下翻半页
{ / }          → 上一段 / 下一段
```

#### 编辑

```
i              → 进入插入模式（光标前）
a              → 进入插入模式（光标后）
o / O          → 下方/上方新建一行并进入插入模式
x              → 删除光标下字符
dd             → 删除整行
yy             → 复制整行
p              → 粘贴
u              → 撤销
C-r            → 重做
.              → 重复上一次操作
```

#### 组合操作（Vim 的精髓）

Vim 的操作遵循 `动词 + 名词` 的语法：

```
dw             → 删除一个单词（d=delete, w=word）
d$             → 删除到行尾
ciw            → 修改光标下的单词（c=change, i=inner, w=word）
ci"            → 修改双引号内的内容
yaw            → 复制一个单词（包括空格）
dat            → 删除一个 HTML/org 标签块
```

#### 搜索与替换

```
/关键词         → 向下搜索（按 n 下一个，N 上一个）
?关键词         → 向上搜索
*              → 搜索光标下的单词
SPC s r        → 查找替换
SPC s R        → 正则查找替换
```

### 4.2 Insert 模式下的特殊键

在插入模式中，`M-SPC`（Alt+空格）代替 `SPC` 作为 leader 键，可以访问所有 SPC 开头的功能。

### 4.3 帮助系统

Emacs 有极为完善的自带帮助：

```
SPC h f        → 查找某个函数的文档
SPC h v        → 查找某个变量的文档
SPC h k        → 按一个键，显示它绑定了什么命令
SPC h m        → 当前模式的完整文档
SPC h a        → 模糊搜索命令/函数
SPC h i        → Info 手册（Emacs 百科全书）
SPC h p        → 查看某个包的信息
```

> **小技巧**：忘了某个键是干什么的？按 `SPC h k` 然后按那个键，Emacs 会告诉你。

---

## 第五章 文件与 Buffer 管理

### 5.1 什么是 Buffer

在 Emacs 中，每打开一个文件就会创建一个 **buffer**（缓冲区）。Buffer 是文件在内存中的副本。你可以同时打开很多 buffer，在它们之间快速切换，而不需要关闭再打开。

### 5.2 文件操作

```
SPC .          → 打开文件（支持模糊匹配）
SPC f f        → 同上
SPC f r        → 打开最近编辑的文件
SPC f s        → 保存当前文件
SPC f S        → 另存为
SPC f R        → 重命名当前文件
SPC f D        → 删除当前文件
SPC f y        → 复制当前文件路径到剪贴板
SPC f d        → 按文件名搜索（fd 驱动，极快）
SPC f p        → 直接打开 init.el（编辑配置）
```

### 5.3 Buffer 操作

```
SPC ,          → 切换 buffer（模糊匹配，最常用）
SPC b b        → 同上
SPC b d        → 关闭当前 buffer
SPC b s        → 保存当前 buffer
SPC b S        → 保存所有 buffer
SPC b n        → 新建空 buffer
SPC b r        → 重新加载（放弃修改，从硬盘重新读取）
SPC b l        → 列出所有 buffer（ibuffer，可批量操作）
SPC b p        → 上一个 buffer
SPC b N        → 下一个 buffer
SPC TAB        → 快速切换到上一个 buffer（来回切换两个文件）
SPC b m        → 给当前位置设置书签
SPC RET        → 跳转到书签
```

### 5.4 补全系统（Vertico）

org-seq 使用 Vertico 补全框架。任何需要你输入选择的地方（打开文件、切换 buffer、执行命令），都会弹出一个垂直列表：

```
C-j / C-k      → 在候选项中上下移动
RET            → 确认选择
C-g            → 取消
TAB            → 补全到公共前缀
```

你可以输入多个空格分隔的关键词进行模糊匹配。例如输入 `init ai` 可以匹配到 `init-ai.el`。这得益于 **Orderless** 补全样式。

---

## 第六章 搜索与导航

### 6.1 全文搜索

org-seq 的搜索由 **ripgrep**（rg）驱动，速度极快：

```
SPC /          → 在项目目录中搜索（实时显示结果）
SPC s p        → 同上
SPC n /        → 在 Roam 笔记目录中搜索
SPC s s        → 在当前 buffer 中搜索（consult-line）
SPC s i        → 搜索当前文件的函数/标题（imenu）
SPC s o        → 搜索当前文件的大纲/标题（outline）
SPC s b        → 搜索书签
SPC s f        → 按文件名搜索（fd 驱动）
```

### 6.2 项目导航

```
SPC p p        → 切换到另一个项目
SPC p f        → 在项目中查找文件
SPC p s        → 在项目中全文搜索
SPC p b        → 切换项目内的 buffer
```

### 6.3 Embark——上下文操作

**Embark** 是补全列表中的"右键菜单"。在任何补全候选项上：

```
C-.            → 打开操作菜单（可对候选项执行各种操作）
C-;            → 智能操作（自动选择最合适的操作）
```

例如：在 `SPC f r`（最近文件）列表中，光标停在某个文件上按 `C-.`，可以选择"删除"、"复制路径"、"在另一个窗口打开"等操作。

---

## 第七章 Org-mode——你的超级文档格式

### 7.1 什么是 Org-mode

Org-mode 是 Emacs 的杀手级功能。它是一种**纯文本标记语言**，同时也是：
- 文档编辑器（类似 Markdown，但更强大）
- 任务管理器（TODO/DONE 状态机）
- 日程表（计划、截止日期、时间戳）
- 电子表格（内置公式计算）
- 代码执行器（org-babel，支持几十种语言）
- 导出引擎（PDF、HTML、LaTeX、Markdown…）

### 7.2 Org 文件基本语法

```org
#+TITLE: 我的笔记标题
#+FILETAGS: :concept:emacs:

* 一级标题
这是正文内容。

** 二级标题
- 无序列表项 1
- 无序列表项 2

*** 三级标题
1. 有序列表
2. 第二项

*粗体*  /斜体/  ~代码~  =逐字=  +删除线+

[[https://example.com][链接文字]]

#+begin_src python
print("Hello from org-babel!")
#+end_src
```

### 7.3 在 Org 中导航

在 org 文件中，标题可以折叠/展开：

```
TAB            → 折叠/展开当前标题（循环切换）
S-TAB          → 全局折叠/展开（所有标题）
```

org-seq 默认启动时显示所有标题但折叠内容（`content` 模式），让你一眼看到文档结构。

### 7.4 Local Leader 键（逗号 `,`）

在 Org buffer 中，**逗号 `,`** 是本地 leader 键，提供当前模式专属操作：

**基本操作：**

```
, r            → 把当前条目移动到其他位置（refile）
, a            → 归档（移到 archive 文件）
, t            → 设置标签
, p            → 设置属性
, e            → 设置预估耗时
, x            → 导出（弹出导出选项面板）
```

**链接：**

```
, l            → 插入链接
, L            → 存储链接（先存储，后面用 , l 粘贴）
```

**时间：**

```
, s            → 设置计划日期（Schedule）
, d            → 设置截止日期（Deadline）
, i            → 插入时间戳
, I            → 插入非活动时间戳（不出现在日程中）
```

**视图：**

```
, n            → 缩窄视图到当前子树（专注模式）
, w            → 还原为完整视图
, h            → 隐藏/显示已完成的任务
, c            → 切换复选框状态
```

**时钟（计时功能）：**

```
, k i          → 开始计时
, k o          → 停止计时
, k g          → 跳转到正在计时的条目
, k r          → 生成计时报告
, k c          → 取消当前计时
```

**Babel（代码执行）：**

```
, b e          → 执行当前代码块
, b b          → 执行整个文件的代码块
, b t          → Tangle（提取代码块到独立文件）
```

### 7.5 Org-modern 视觉增强

org-seq 使用 **org-modern** 让 Org 文件更美观：
- 标题使用 ◉ ○ ◈ ◇ ⁕ 作为项目符号
- 关键字（TODO、DONE 等）使用彩色标签样式
- 时间戳使用更清晰的格式
- 列表项使用现代化的点符号

这些都是纯显示效果，不改变文件内容。切换开关：`SPC t i`。

---

## 第八章 笔记系统（Zettelkasten）

### 8.1 什么是 Zettelkasten

Zettelkasten（卡片盒笔记法）的核心思想：
1. **原子化**：每条笔记只包含一个想法
2. **链接**：笔记之间通过链接形成网络
3. **涌现**：好的想法从链接的网络中涌现出来

org-seq 的三层 PKM 架构实现了这个方法论：

| 层 | 工具 | 作用 |
|----|------|------|
| **图谱层** | org-roam | 节点、链接、反向链接、模板 |
| **数据层** | org-supertag | 把标签变成数据库，表格视图，看板 |
| **性能层** | org-node + org-mem | 异步索引，毫秒级搜索 |

### 8.2 创建笔记

```
SPC n c        → 新建笔记（弹出模板选择）
```

内置模板：

| 按键 | 类型 | 用途 |
|------|------|------|
| `d` | 默认 | 通用笔记（覆盖 80% 场景） |
| `r` | 阅读 | 文献/书籍笔记（TL;DR / Key points / Commentary） |

每条笔记自动获得一个唯一 ID（时间戳格式），存储在 `~/NoteHQ/Roam/capture/` 下。

**添加更多模板**（如咨询记录、学生信息等）：

```
SPC n m c      → 打开模板配置文件（~/.orgseq/capture-templates.el）
               编辑后保存
SPC n m C      → 热重载，立即生效
```

模板文件里已有 session（咨询记录）、client（来访者）、student（学生）的注释示例，取消注释即可启用。

### 8.3 查找和打开笔记

```
SPC n f        → 查找笔记（模糊匹配标题和标签，最常用）
SPC n /        → 在笔记内容中全文搜索（ripgrep 驱动）
SPC n ?        → consult 增强搜索（支持实时预览）
```

`SPC n f` 的搜索界面支持 Orderless 模糊匹配：输入 `emacs config` 可以匹配标题为 "Emacs 配置指南" 的笔记。

### 8.4 建立链接

在一条笔记中引用另一条笔记：

```
SPC n i        → 插入链接到另一条笔记
```

这会弹出笔记选择器，选中后在光标处插入一个 `[[id:xxx][标题]]` 链接。点击链接可以跳转到目标笔记。

### 8.5 反向链接（Backlinks）

这是 Zettelkasten 的核心功能。当笔记 A 链接到笔记 B 时，在笔记 B 中可以看到"谁链接到了我"。

```
SPC n b        → 在侧边栏显示当前笔记的反向链接
SPC n B        → 通过 consult 浏览反向链接（带预览）
SPC n l        → 浏览正向链接（当前笔记链接了谁）
```

### 8.6 知识图谱

```
SPC n g        → 在浏览器中打开 org-roam-ui 交互图谱
```

这会启动一个本地 Web 服务，在浏览器中展示你所有笔记的节点和连接关系——一张可交互的知识地图。

### 8.7 Daily Notes（每日笔记）

每日笔记是你的数字日记本和临时收集箱：

```
SPC n d d      → 快速写入今日笔记（capture 模式，写完自动保存）
SPC n d t      → 直接打开今日笔记浏览
SPC n d y      → 打开昨天的笔记
SPC n d T      → 打开明天的笔记
SPC n d p      → 上一篇日记
SPC n d n      → 下一篇日记
SPC n d f      → 按日期查找
SPC n d c      → 选择日期并 capture
```

Daily capture 有三种模板：
- `d`：默认（带时间戳的快速记录）
- `t`：任务（自动创建带日期的 TODO）
- `j`：日记（带时间戳的日记条目）

### 8.8 org-supertag（结构化数据）

org-supertag 把 Org 文件中的标签变成数据库表格。例如给一个笔记加上 `reading` 标签，就可以自动出现"作者"、"年份"、"状态"等字段。

**最常用的操作——快速操作菜单**：

```
SPC n p p      → 上下文感知菜单（自动判断当前节点有无标签）
               如果没有标签 → 直接进入添加标签流程
               如果已有标签 → 弹出选项：添加/移除/编辑字段/跳转关联
```

**全部 supertag 操作**：

```
SPC n p p      → 快速操作（最常用）
SPC n p a      → 添加标签
SPC n p e      → 编辑字段
SPC n p x      → 移除标签
SPC n p j      → 跳转到关联节点
SPC n p k      → 看板视图
SPC n p s      → 搜索 supertag 数据库
```

在 Org buffer 中也可以用 local leader：

```
, ##           → 快速操作（同 SPC n p p）
, #a           → 添加标签
, #e           → 编辑字段
, #x           → 移除标签
, #j           → 跳转关联
```

**标签定义**（schema）管理：

```
SPC n m t      → 编辑 supertag-schema.el（定义标签和字段）
SPC n m T      → 热重载 schema（改完立即生效）
```

**首次使用需要初始化**：`M-x supertag-sync-full-initialize`

### 8.9 Dashboard 视图

Dashboard 是只读的查询窗口，用来汇总和回顾你的笔记状态。

```
SPC n v v      → 选择并打开一个 dashboard
SPC n v w      → 打开每周回顾 dashboard
SPC n v i      → 打开 dashboard 索引
SPC n m d      → 创建新的 dashboard
```

### 8.10 PARA 层导航

PARA（Projects-Areas-Resources-Archives）是产出物的组织框架：

```
SPC P o        → 打开 Outputs/（可交付项目：论文、课件…）
SPC P p        → 打开 Practice/（长期角色：教学、研究…）
SPC P l        → 打开 Library/（素材库：PDF、数据集…）
SPC P g        → 全库 ripgrep 搜索（跨 Roam + PARA 所有层）
```

### 8.11 Transclusion（内容嵌入）

Transclusion 允许你在一条笔记中**实时嵌入**另一条笔记的内容——不是复制，是"活的引用"：

```
SPC n t a      → 在当前位置添加 transclusion
SPC n t t      → 开启/关闭 transclusion 渲染
SPC n t m      → 打开 transclusion 操作菜单
SPC n t r      → 刷新所有 transclusion
```

### 8.12 org-ql（结构化查询）

org-ql 让你用类 SQL 语法查询笔记：

```
SPC n q s      → 输入查询条件搜索
SPC n q v      → 使用保存的视图
```

例如查询"过去 7 天创建的、带有 concept 标签的笔记"。

---

## 第九章 任务管理（GTD）

### 9.1 GTD 是什么

GTD（Getting Things Done）是 David Allen 提出的任务管理方法论：

```
收集 → 处理 → 组织 → 执行 → 回顾
```

org-seq 用 Org-mode 的 TODO 系统完整实现了这套流程。

### 9.2 任务状态

每个任务（标题前有关键词的条目）可以处于以下状态：

```
开放状态：                              关闭状态：
PROJECT   → 项目（包含子任务）           DONE       → 已完成
TODO      → 待办（尚未决定何时做）       CANCELLED  → 已取消
NEXT      → 下一步行动（可以开始做）
IN-PROGRESS → 进行中
WAITING   → 等待他人
SOMEDAY   → 将来也许做
```

### 9.3 快速改变任务状态

在任何 Org 标题上按：

```
, q            → 打开状态选择器
```

然后按一个字母即可：

| 按键 | 切换到 | 含义 |
|------|--------|------|
| `n` | NEXT | 这是下一步行动 |
| `i` | IN-PROGRESS | 正在做 |
| `w` | WAITING | 在等别人 |
| `s` | SOMEDAY | 以后再说 |
| `k` | DONE | 搞定了 |
| `x` | CANCELLED | 不做了 |
| `p` | PROJECT | 这是个项目 |
| `q` | 退出 | 什么都不做 |

> 标记为 DONE 时，如果有子任务，会询问是否一起完成。完成的任务会自动下沉到同级底部，保持列表整洁。

### 9.4 GTD Dashboard

Dashboard 是你的任务管理中心：

```
SPC a d        → 打开/关闭 GTD Dashboard
```

Dashboard 显示：

```
┌─ GTD Dashboard ──────────────────────────────────┐
│  Inbox      3     ← 未处理的闪念笔记              │
│  Today      5     ← 今天到期/已排期的任务          │
│  Upcoming   8     ← 未来已排期的任务               │
│  Anytime   12     ← 可随时做的 NEXT 任务           │
│  Waiting    4     ← 等待他人的任务                  │
│  Someday    7     ← 将来也许做的任务               │
│  Logbook   42     ← 已完成/已取消的任务            │
│                                                    │
│  Projects                                          │
│    写论文          ← 健康（有 NEXT 子任务）          │
│  ● 装修计划        ← ● 卡壳（没有 NEXT 子任务）     │
│  ~ 学英语          ← ~ 无下一步                     │
│                                                    │
│  Contexts                                          │
│    @work     3    ← 工作场景下的 NEXT 任务数         │
│    @home     2    ← 家里可做的 NEXT 任务数           │
│    @computer 5    ← 需要电脑的 NEXT 任务数           │
└──────────────────────────────────────────────────┘
```

点击任意行（或按 `RET`）打开对应的详细视图。按 `g` 刷新数据。

### 9.5 GTD 完整工作流

#### 收集

随时随地快速记录想法，不打断当前工作：

```
SPC a c        → 通用 capture（进入 Inbox）
SPC n c        → 创建一条新笔记
SPC n d d      → 在今日日记中快速记录
```

#### 处理

打开 Inbox，逐条决定每一项的去处：

```
SPC a 0        → 打开 Inbox 视图
```

对每条 inbox 条目：
- `, q` → `n`：这要做，标记为 NEXT
- `, s`：排个日期
- `, t`：加上 @work/@home 等上下文标签
- `, r`：移到某个项目下面
- `, q` → `x`：不需要了，取消

#### 执行

根据当前场景选择要做的事：

```
SPC a 1        → Today（今天要做的）
SPC a 3        → Anytime（NEXT 且无排期 = 随时可做）
SPC a 7        → 按上下文筛选（弹出选择：@work、@home…）
SPC a u        → 即将到来（按天分组的排期任务）
```

#### 回顾

```
SPC a w        → 打开 Weekly Review 视图
```

每周回顾内容包括：
- 过去 3 天和未来 3 天的日程
- 所有 IN-PROGRESS / NEXT / WAITING 任务
- 卡壳的项目（有子任务但没有 NEXT）
- Someday 列表（是否该激活某些？）

### 9.6 所有 Agenda 视图一览

| 键位 | 视图 | 内容 |
|------|------|------|
| `SPC a d` | Dashboard | 实时计数面板 + 项目 + 上下文 |
| `SPC a n` | GTD Overview | 综合视图（Today + NEXT + IN-PROGRESS + WAITING） |
| `SPC a p` | Projects | 活跃项目 + 卡壳项目 |
| `SPC a w` | Weekly Review | 3天回顾 + 3天展望 + 全部活跃任务 |
| `SPC a 0` | Inbox | 带 :fleeting: 标签的未处理条目 |
| `SPC a 1` | Today | 今天到期/排期的任务 |
| `SPC a u` | Upcoming | 未来排期任务（按天分组） |
| `SPC a 3` | Anytime | NEXT 且无排期 |
| `SPC a 4` | Waiting | 等待中的任务 |
| `SPC a 5` | Someday | 将来也许做 |
| `SPC a 6` | Logbook | 已完成/已取消 |
| `SPC a 7` | Context | 按 @work/@home 等筛选 |

---

## 第十章 AI 助手

### 10.1 概述

org-seq 通过 **gptel** 集成 AI。默认通过 OpenRouter 接入，你可以使用 DeepSeek、Claude、GPT、Gemini 等各种模型。

所有 AI 命令的 leader 键是 `SPC i`。

### 10.2 基础对话

```
SPC i c        → 打开 AI 对话 buffer（独立的聊天窗口）
SPC i i        → 把当前 buffer 内容或选区发送给 AI，回答追加在后面
SPC i m        → AI 菜单（切换模型、调整参数、选择预设）
SPC i r        → 改写选中区域（AI 提供修改建议，可逐一接受/拒绝）
SPC i a        → 添加上下文文件（让 AI 参考更多内容）
```

### 10.3 PKM 专属 AI 命令

这些命令专为笔记管理设计：

| 键位 | 功能 | 说明 |
|------|------|------|
| `SPC i s` | 摘要 | 将当前笔记或选区交给 AI 生成结构化摘要 |
| `SPC i t` | 标签建议 | AI 阅读笔记内容，建议 3-5 个 filetags |
| `SPC i l` | 翻译 | 选中文本中英互译（自动判断语言方向） |
| `SPC i k` | 关联发现 | AI 分析笔记，建议 3-5 个可能相关的概念/笔记 |
| `SPC i p` | 润色写作 | 改善选中文本的表达质量 |
| `SPC i o` | 知识库概览 | 分析整个知识库，生成主题/空白/建议报告 |

> 结果会显示在底部的 `*AI Result*` 窗口中。

### 10.4 AI 上下文系统

org-seq 会自动把两个文件的内容注入到每次 AI 对话的系统提示中：

- `~/NoteHQ/Roam/concepts/purpose.org`：你的知识库目标和研究方向
- `~/NoteHQ/Roam/concepts/schema.org`：笔记类型和标签约定

这意味着 AI 始终"了解"你的知识管理体系，无需每次手动解释。

```
SPC i g        → 创建/确认这两个上下文文件存在
```

编辑这两个文件来定制 AI 的行为。例如在 purpose.org 中写上"我是一个研究认知科学的博士生"，AI 在分析你的笔记时就会带着这个背景。

### 10.5 Org-babel AI 代码块

在 Org 笔记中，你可以嵌入可执行的 AI 查询：

```org
#+begin_src gptel :model deepseek/deepseek-chat-v3-0324
解释 Zettelkasten 方法论中"原子性"原则的含义
#+end_src
```

把光标放在代码块中，按 `C-c C-c`（或 `, b e`）执行。AI 的回答会异步插入到 `#+RESULTS:` 块中。

这让你可以在笔记中保留 AI 问答的完整记录。

### 10.6 修改 AI 配置

AI 的后端和模型配置存储在 `~/NoteHQ/.orgseq/ai-config.org` 中（纯文本 org 文件）：

```org
* Settings
:PROPERTIES:
:DEFAULT_BACKEND: OpenRouter
:DEFAULT_MODEL: deepseek/deepseek-chat-v3-0324
:END:

* Backends

** OpenRouter
:PROPERTIES:
:TYPE: openai-compatible
:HOST: openrouter.ai
:ENDPOINT: /api/v1/chat/completions
:STREAM: t
:AUTH_HOST: openrouter.ai
:END:

- deepseek/deepseek-chat-v3-0324
- anthropic/claude-sonnet-4
- google/gemini-2.5-flash
- openai/gpt-4o-mini
```

想换默认模型？改 `DEFAULT_MODEL`。想加本地模型？加一个 Ollama 后端：

```org
** Ollama
:PROPERTIES:
:TYPE: ollama
:HOST: localhost:11434
:STREAM: t
:END:

- llama3
- mistral
```

API 密钥**不在这个文件里**，而是在 `~/.authinfo.gpg` 中（加密存储，更安全）。

---

## 第十一章 Markdown 支持

### 11.1 概述

org-seq 完整支持 Markdown 编辑，与 Obsidian 互操作（wiki 链接、GFM）。Markdown 文件**不被 org-roam 索引**——PKM 图谱和反向链接仅限 Org 文件。打开 `.md` 文件会自动启用：

- GFM（GitHub Flavored Markdown）模式
- 居中显示 + 自适应宽度
- 代码块语法高亮
- 标题缩放显示
- URL 自动隐藏（只显示链接文字）
- 数学公式渲染
- Wiki 链接支持

### 11.2 Markdown Local Leader 键

在 Markdown 文件中，逗号 `,` 是 local leader：

```
, v            → 切换实时预览（在 Emacs 内预览渲染效果）
, p            → 在浏览器中预览
, e            → 导出（需要 pandoc）
, t            → 自动生成目录（Table of Contents）
, r            → 刷新目录
, l            → 插入链接
, o            → 切换 markup 符号的显示/隐藏
```

---

## 第十二章 工作区布局

### 12.1 默认启动布局

启动 Emacs 后自动进入轻量布局：

```
┌──────────┬────────────────────────┐
│ Treemacs │     Dashboard          │
│ (文件树)  │  (启动面板 + 最近文件)   │
└──────────┴────────────────────────┘
```

Dashboard 显示：
- ASCII art 标题
- 最近编辑的 5 个文件
- 快捷按钮：Today / Find / Tasks / Review / Last File
- 底部随机名言

### 12.2 完整三栏布局

需要深度工作时，切换到三栏布局：

```
SPC l l        → 启动完整工作区
```

```
┌──────────┬────────────────────────┬────────────┐
│ Treemacs │                        │  Outline   │
│  (~15%)  │     主编辑区            │   (~20%)   │
│  文件树   │       (~65%)           ├────────────┤
│          │                        │  Terminal  │
│          │                        │   (~20%)   │
└──────────┴────────────────────────┴────────────┘
```

- **Treemacs**（左）：文件目录树，可以浏览和打开文件
- **主编辑区**（中）：你的笔记/代码
- **Outline**（右上）：当前文件的大纲/标题列表，点击可跳转
- **Terminal**（右下）：内置终端（eshell）

### 12.3 布局控制键

```
SPC l l        → 启动/重建完整三栏布局
SPC l t        → 显示/隐藏 Treemacs 侧栏
SPC l o        → 显示/隐藏 Outline 面板
SPC l e        → 显示/隐藏终端
SPC l d        → 切换到 Dashboard
SPC '          → 快速开关终端（最常用）
```

### 12.4 窗口操作

```
SPC w v        → 垂直分割（左右两个窗口）
SPC w s        → 水平分割（上下两个窗口）
SPC w d        → 关闭当前窗口
SPC w m        → 最大化当前窗口（关闭其他所有窗口）
SPC w =        → 平均分配所有窗口大小

窗口间跳转：
SPC w h/j/k/l  → 跳转到 左/下/上/右 的窗口

调整窗口大小：
SPC w > / <    → 增加/减少宽度
SPC w + / -    → 增加/减少高度
```

---

## 第十三章 Git 版本控制

### 13.1 Magit

org-seq 集成了 **Magit**——被广泛认为是现有最好的 Git 界面。所有 Git 操作的入口：

```
SPC g g        → 打开 Magit Status（核心界面）
```

在 Magit Status 中，你可以看到所有未提交的变更。常用操作：

```
s              → Stage（暂存）当前文件/hunk
u              → Unstage（取消暂存）
c c            → 开始写 commit message（C-c C-c 确认提交）
P p            → Push 到远程
F p            → Pull 从远程
b b            → 切换分支
l l            → 查看 log
```

> Magit 有自己的完整帮助系统：在 Magit 界面中按 `?` 可以看到所有操作。

### 13.2 其他 Git 快捷键

```
SPC g b        → Git blame（查看每行的提交历史）
SPC g l        → Git log（提交历史）
SPC g d        → Git diff（查看变更）
SPC g f        → Git 文件操作（多种选项）
```

---

## 第十四章 外观与主题

### 14.1 主题

默认主题是 **modus-operandi-tinted**（浅色主题），属于 Modus 主题家族——为可读性和无障碍设计的高对比度主题。

```
SPC t t        → 切换主题（从可用主题列表中选择）
```

已安装的主题家族：
- **Modus themes**：高对比度、无障碍（推荐）
- **Ef themes**：Daniel Mendler 的优雅主题集
- **Doom themes**：Doom Emacs 风格的主题集

### 14.2 字体

org-seq 配置了中英文混排：
- 英文/代码：Cascadia Code（如果安装了的话）
- 中文：LXGW WenKai Mono > Sarasa Fixed SC > Microsoft YaHei UI > SimHei（按优先级尝试）
- 中文字体会自动缩放以对齐英文（等宽对齐）

### 14.3 界面开关

```
SPC t l        → 显示/隐藏行号
SPC t w        → 显示/隐藏自动换行
SPC t o        → 显示/隐藏 Olivetti（居中）模式
SPC t f        → 全屏切换
SPC t i        → 显示/隐藏 org-modern 美化效果
```

### 14.4 Olivetti（居中阅读模式）

在 Org 文件中默认自动启用。它会把文本内容居中显示，两侧留白，让宽屏上的阅读体验接近纸质书。

文本宽度会根据窗口大小自适应调整（最小 88 字符，最大 140 字符）。

---

## 第十五章 进阶功能

### 15.1 Casual 菜单

当你不确定当前模式下有什么操作可用时，**Casual** 提供 Transient 菜单面板：

```
SPC c c        → 全局 EditKit 菜单（任何地方都能用）
SPC c a        → Agenda 操作菜单
SPC c d        → Dired（文件管理器）操作菜单
SPC c b        → 书签操作菜单
SPC c s        → 搜索操作菜单
```

在特定模式下按 `C-o` 也会弹出对应的 Casual 菜单：
- Org Agenda 中按 `C-o` → Agenda 操作面板
- Dired 中按 `C-o` → 文件管理操作面板
- ibuffer 中按 `C-o` → Buffer 管理面板
- Info 中按 `C-o` → 文档导航面板

### 15.2 Eval（执行 Elisp）

org-seq 基于 Emacs Lisp 构建，你随时可以执行 Elisp 代码来调试或扩展：

```
SPC e e        → 执行光标前的表达式
SPC e b        → 执行整个 buffer
SPC e r        → 执行选中区域
SPC e d        → 执行当前函数定义
```

### 15.3 Winner Mode（窗口布局撤销）

org-seq 默认启用了 Winner mode。如果你不小心搞乱了窗口布局：

```
C-c <left>     → 撤销上一次窗口变化
C-c <right>    → 重做窗口变化
```

### 15.4 Emacs Server

org-seq 自动启动 Emacs Server。这意味着你可以在命令行用 `emacsclient` 快速打开文件，而不需要启动新的 Emacs 实例：

```bash
emacsclient -c file.org        # 在已运行的 Emacs 中打开文件
emacsclient -c -a ""           # 连接已运行的 Emacs，如果没有则启动一个
```

---

## 附录 A 完整键位速查表

### 顶级快捷键（Normal 模式下按 SPC）

| 键位 | 功能 |
|------|------|
| `SPC SPC` | M-x（执行任意命令） |
| `SPC .` | 打开文件 |
| `SPC ,` | 切换 buffer |
| `SPC /` | 项目全文搜索 |
| `SPC TAB` | 切换到上一个 buffer |
| `SPC RET` | 跳转到书签 |
| `SPC '` | 开关终端 |

### SPC a — 日程与 GTD

| 键位 | 功能 |
|------|------|
| `SPC a d` | GTD Dashboard |
| `SPC a a` | Agenda 调度器 |
| `SPC a n` | GTD 综合视图 |
| `SPC a p` | 项目视图 |
| `SPC a w` | 每周回顾 |
| `SPC a u` | 即将到来 |
| `SPC a c` | Capture |
| `SPC a e` | 状态选择器 |
| `SPC a 0` | Inbox |
| `SPC a 1` | Today |
| `SPC a 3` | Anytime |
| `SPC a 4` | Waiting |
| `SPC a 5` | Someday |
| `SPC a 6` | Logbook |
| `SPC a 7` | 上下文筛选 |
| `SPC a r` | 刷新 agenda 缓存 |

### SPC b — Buffer

| 键位 | 功能 |
|------|------|
| `SPC b b` | 切换 buffer |
| `SPC b d` | 关闭 buffer |
| `SPC b s` | 保存 |
| `SPC b S` | 保存全部 |
| `SPC b n` | 新建 |
| `SPC b r` | 重载 |
| `SPC b l` | 列表 (ibuffer) |
| `SPC b m` | 设书签 |
| `SPC b p` | 上一个 |
| `SPC b N` | 下一个 |

### SPC f — 文件

| 键位 | 功能 |
|------|------|
| `SPC f f` | 打开文件 |
| `SPC f r` | 最近文件 |
| `SPC f s` | 保存 |
| `SPC f S` | 另存为 |
| `SPC f R` | 重命名 |
| `SPC f D` | 删除 |
| `SPC f y` | 复制路径 |
| `SPC f d` | 按名搜索 (fd) |
| `SPC f p` | 打开配置 |

### SPC g — Git

| 键位 | 功能 |
|------|------|
| `SPC g g` | Magit Status |
| `SPC g b` | Git Blame |
| `SPC g l` | Git Log |
| `SPC g d` | Git Diff |
| `SPC g f` | 文件操作 |

### SPC h — 帮助

| 键位 | 功能 |
|------|------|
| `SPC h f` | 函数文档 |
| `SPC h v` | 变量文档 |
| `SPC h k` | 按键文档 |
| `SPC h m` | 模式文档 |
| `SPC h i` | Info 手册 |
| `SPC h p` | 包信息 |
| `SPC h a` | 模糊搜索 |

### SPC i — AI

| 键位 | 功能 |
|------|------|
| `SPC i i` | 发送到 LLM |
| `SPC i m` | AI 菜单 |
| `SPC i c` | 聊天 buffer |
| `SPC i r` | 改写区域 |
| `SPC i a` | 添加上下文 |
| `SPC i s` | 摘要 |
| `SPC i t` | 标签建议 |
| `SPC i l` | 翻译 |
| `SPC i k` | 关联发现 |
| `SPC i p` | 润色 |
| `SPC i o` | 知识库概览 |
| `SPC i g` | 初始化上下文文件 |
| `SPC i C` | Claude Code CLI 菜单 |

### SPC l — 布局

| 键位 | 功能 |
|------|------|
| `SPC l l` | 完整三栏 |
| `SPC l t` | 开关 Treemacs |
| `SPC l o` | 开关 Outline |
| `SPC l e` | 开关终端 |
| `SPC l d` | Dashboard |

### SPC n — 笔记

| 键位 | 功能 |
|------|------|
| `SPC n f` | 查找笔记 |
| `SPC n c` | 新建笔记 |
| `SPC n i` | 插入链接 |
| `SPC n b` | 反向链接面板 |
| `SPC n /` | 全文搜索 |
| `SPC n g` | 知识图谱 |
| `SPC n a` | 添加别名 |
| `SPC n r` | 添加引用 |
| `SPC n l` | 正向链接 |
| `SPC n B` | 反向链接 (consult) |
| `SPC n ?` | 搜索 (consult) |

### SPC n d — 每日笔记

| 键位 | 功能 |
|------|------|
| `SPC n d d` | 写今天 |
| `SPC n d t` | 看今天 |
| `SPC n d y` | 昨天 |
| `SPC n d T` | 明天 |
| `SPC n d f` | 按日期查找 |
| `SPC n d c` | 按日期 capture |
| `SPC n d p` | 上一篇 |
| `SPC n d n` | 下一篇 |

### SPC n p — Supertag

| 键位 | 功能 |
|------|------|
| `SPC n p p` | 快速操作（上下文感知菜单） |
| `SPC n p a` | 添加标签 |
| `SPC n p e` | 编辑字段 |
| `SPC n p x` | 移除标签 |
| `SPC n p l` | 列出字段 |
| `SPC n p j` | 跳转关联 |
| `SPC n p k` | 看板 |
| `SPC n p s` | 搜索 |
| `SPC n p S` | 同步状态 |
| `SPC n p r` | 立即同步 |
| `SPC n p R` | 完全重建索引 |

### SPC n v — 视图 / Dashboard

| 键位 | 功能 |
|------|------|
| `SPC n v v` | 选择并打开 dashboard |
| `SPC n v w` | 每周回顾 |
| `SPC n v i` | Dashboard 索引 |

### SPC n m — 扩展中心

| 键位 | 功能 |
|------|------|
| `SPC n m t` | 编辑 tag schema |
| `SPC n m T` | 重载 tag schema |
| `SPC n m c` | 编辑 capture 模板 |
| `SPC n m C` | 重载 capture 模板 |
| `SPC n m d` | 创建新 dashboard |

### SPC n t — Transclusion

| 键位 | 功能 |
|------|------|
| `SPC n t a` | 添加嵌入 |
| `SPC n t t` | 开关渲染 |
| `SPC n t m` | 操作菜单 |
| `SPC n t r` | 刷新 |

### SPC n q — 查询

| 键位 | 功能 |
|------|------|
| `SPC n q s` | 搜索 |
| `SPC n q v` | 保存视图 |

### SPC o — 打开

| 键位 | 功能 |
|------|------|
| `SPC o t` | 终端 |
| `SPC o d` | Dashboard |
| `SPC o a` | Agenda |
| `SPC o f` | Treemacs |
| `SPC o e` | Emacs 目录 |

### SPC P — PARA 层导航

| 键位 | 功能 |
|------|------|
| `SPC P o` | Outputs（可交付项目） |
| `SPC P p` | Practice（长期角色） |
| `SPC P l` | Library（素材库） |
| `SPC P g` | 全库 Ripgrep |

### SPC p — 项目

| 键位 | 功能 |
|------|------|
| `SPC p p` | 切换项目 |
| `SPC p f` | 项目内找文件 |
| `SPC p s` | 项目内搜索 |
| `SPC p b` | 项目 buffer |

### SPC s — 搜索

| 键位 | 功能 |
|------|------|
| `SPC s s` | 搜索当前 buffer |
| `SPC s p` | 搜索项目 |
| `SPC s i` | Imenu |
| `SPC s o` | 大纲 |
| `SPC s b` | 书签 |
| `SPC s f` | 按文件名 |
| `SPC s r` | 查找替换 |
| `SPC s R` | 正则替换 |

### SPC t — 开关

| 键位 | 功能 |
|------|------|
| `SPC t t` | 切换主题 |
| `SPC t l` | 行号 |
| `SPC t w` | 自动换行 |
| `SPC t o` | Olivetti |
| `SPC t f` | 全屏 |
| `SPC t i` | Org-modern |

### SPC w — 窗口

| 键位 | 功能 |
|------|------|
| `SPC w v` | 垂直分割 |
| `SPC w s` | 水平分割 |
| `SPC w d` | 关闭窗口 |
| `SPC w m` | 最大化 |
| `SPC w h/j/k/l` | 上下左右跳转 |
| `SPC w =` | 均分大小 |
| `SPC w > / <` | 调宽度 |
| `SPC w + / -` | 调高度 |
| `SPC w o` | 切换窗口 |

### SPC e — 执行 Elisp

| 键位 | 功能 |
|------|------|
| `SPC e e` | 执行表达式 |
| `SPC e b` | 执行 buffer |
| `SPC e r` | 执行选区 |
| `SPC e d` | 执行函数 |

### SPC c — Casual 菜单

| 键位 | 功能 |
|------|------|
| `SPC c c` | 全局 EditKit |
| `SPC c a` | Agenda 菜单 |
| `SPC c d` | Dired 菜单 |
| `SPC c b` | 书签菜单 |
| `SPC c s` | 搜索菜单 |

### Org Local Leader（逗号 `,`）

| 键位 | 功能 |
|------|------|
| `, r` | Refile |
| `, a` | 归档 |
| `, t` | 设标签 |
| `, p` | 设属性 |
| `, e` | 设耗时 |
| `, x` | 导出 |
| `, l / , L` | 插入/存储链接 |
| `, s` | Schedule |
| `, d` | Deadline |
| `, i / , I` | 时间戳 |
| `, q` | 状态选择器 |
| `, h` | 隐藏/显示已完成 |
| `, n / , w` | 缩窄/还原 |
| `, c` | 切换复选框 |
| `, ##` | Supertag 快速操作 |
| `, #a/e/x/j` | 添加/编辑字段/移除/跳转 |
| `, k i/o/g/r/c` | 时钟操作 |
| `, b e/b/t` | Babel 操作 |

### Markdown Local Leader（逗号 `,`）

| 键位 | 功能 |
|------|------|
| `, v` | 预览切换 |
| `, p` | 浏览器预览 |
| `, e` | 导出 |
| `, t` | 生成目录 |
| `, r` | 刷新目录 |
| `, l` | 插入链接 |
| `, o` | 切换 markup 显示 |

### 全局键（不需要 SPC）

| 键位 | 功能 |
|------|------|
| `C-x b` | 切换 buffer |
| `C-j / C-k` | Vertico 上下选择 |
| `C-.` | Embark 操作菜单 |
| `C-;` | Embark 智能操作 |
| `M-y` | 粘贴历史 |
| `M-s l` | 搜索当前 buffer |
| `M-s r` | 搜索项目 |
| `M-s o` | 搜索大纲 |
| `C-c n f` | 查找笔记 |
| `C-c n i` | 插入笔记链接 |
| `C-c n c` | 新建笔记 |
| `C-c n l` | 反向链接面板 |
| `C-c n j` | 今日日记 |
| `C-c t a` | 添加 transclusion |
| `C-c t t` | 开关 transclusion |
| `C-g` | 万能取消 |
| `C-o` | 模式专属 Casual 菜单 |

---

## 附录 B 常见问题排查

| 症状 | 检查方法 | 解决方案 |
|------|---------|---------|
| org-roam 不启动 | `M-: (sqlite-available-p)` | 必须返回 `t`，需要 Emacs 29+ 且编译时启用了 SQLite |
| 没有 native-comp | `M-: (native-comp-available-p)` | 需要 MSYS2 构建的 Emacs（性能优化，非必须） |
| 中文字体显示异常 | `M-: (font-family-list)` | 确认字体名称正确安装；安装 LXGW WenKai Mono |
| ripgrep 未找到 | `M-: (executable-find "rg")` | `winget install BurntSushi.ripgrep` |
| fd 未找到 | `M-: (executable-find "fd")` | `winget install sharkdp.fd` |
| 启动很慢 | `M-x esup` | 查看启动耗时分析 |
| org-node 缓存过旧 | `M-x org-mem-reset` | 强制全量重扫 |
| org-roam-ui 图谱不完整 | 检查 `org-mem-roamy-do-overwrite-real-db` | 应为 `t` |
| supertag 数据丢失 | `M-x supertag-sync-full-initialize` | 一次性全量重建 |
| supertag 字段不同步 | `M-x supertag-sync-check-now` | 手动触发同步 |
| AI 命令报错 "No API key" | 检查 `~/.authinfo` | 确认有 `machine openrouter.ai login apikey password sk-or-XXX` |
| Transient 版本太旧 | 检查 `package-install-upgrade-built-in` | 确认为 `t` |
| 图标显示为方块 | `M-x nerd-icons-install-fonts` | Windows 需右键安装 .ttf |
| which-key 不弹出 | 按 SPC 后等 0.3 秒 | 确认在 Normal 模式（不是 Insert） |
| 窗口布局搞乱了 | `C-c <left>` | Winner mode 撤销窗口变化 |

---

## 写在最后

org-seq 的功能很多，但你不需要一次学会所有东西。建议的学习路径：

1. **第一周**：掌握基本编辑（第四章）+ 文件操作（第五章）+ `SPC` 菜单
2. **第二周**：开始用 Daily Notes 写日记（第八章 8.7）+ 简单的任务管理（第九章 9.3）
3. **第三周**：创建 Zettelkasten 笔记（第八章 8.2-8.5）+ 链接和反向链接
4. **第四周**：尝试 AI 功能（第十章）+ GTD Dashboard（第九章 9.4）
5. **之后**：探索 supertag、transclusion、org-ql 等高级功能

**最重要的三个键**：
- `Esc` — 回到安全的 Normal 模式
- `SPC` — 打开功能菜单
- `C-g` — 取消任何操作

祝你使用愉快！
