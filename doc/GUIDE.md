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
- [第十三章 专注计时器（Focus Timer）](#第十三章-专注计时器focus-timer)
- [第十四章 Git 版本控制](#第十四章-git-版本控制)
- [第十五章 外观与主题](#第十五章-外观与主题)
- [第十六章 进阶功能](#第十六章-进阶功能)
- [附录 A 完整键位速查表](#附录-a-完整键位速查表)
- [附录 B 常见问题排查](#附录-b-常见问题排查)

---

## 第一章 什么是 org-seq

### 1.1 一句话概括

org-seq 是一套 Emacs 配置，它把 Emacs 这个三十多岁的老牌编辑器改装成了一个称手的个人知识管理工作站——你在同一个窗口里写笔记、管理任务、与 AI 对话，而不必在七八个应用之间不停切换。

### 1.2 它能做什么

与其罗列功能清单，不如想象一下你完整的一天：

早上打开 Emacs，第一眼看到的是 GTD Dashboard，上面实时统计着今天该做的事、本周在等的回复、几个卡住的项目。你点进去处理待办，回到当天的 daily 笔记继续写工作流水。写着写着冒出一个值得单独存放的想法，你按两下键把它提取为一条独立的 Zettelkasten 笔记，org-roam 自动为它分配一个永久 ID，并在原来的 daily 里留下一条 `[[id:...]]` 链接。稍后这条新笔记会出现在反向链接面板里——提醒你它和过去哪些笔记产生了关联。

如果你想把它归类，可以按 `SPC n p a` 给它加一个 supertag（比如 `reading` 或 `concept`），这些 tag 不只是标签，而是 Tana 式的"数据库记录"——每个 tag 可以定义字段、在 dashboard 里跨 tag 聚合查询。下午你在读一篇长文，选中几段文字按 `SPC i s` 让 LLM 摘要；想翻译一段中文按 `SPC i l`；想让 AI 建议相关笔记按 `SPC i k`。所有这些交互都发生在 Emacs 里，所有输出都保留在你的 `.org` 文件里，没有 SaaS 订阅、没有 vendor lock-in、没有离线就断联的焦虑。

技术底座：**Zettelkasten 笔记网络**由 org-roam 驱动（双向链接 + 知识图谱）；**GTD 任务系统**是用 org-agenda + org-ql 自建的 dashboard；**结构化数据**由 org-supertag 提供，把标签变成带字段的数据库表格和看板；**性能层**由 org-node / org-mem 承担，让 3000+ 节点的索引从几分钟降到两秒；**AI 集成**通过 gptel 和 Claude Code 完成；**Vim 手感**由 Evil mode 保证；**版本控制**交给 Magit（几乎所有用过它的人都认为它是目前最好的 Git 界面）；**Markdown 文件**也能在同一个编辑器里流畅编辑，方便你从 Obsidian 或其他工具过渡过来。

### 1.3 核心理念

整个系统围绕三条简单原则：

1. **笔记用 `.org` 格式存在 `~/NoteHQ/00_Roam/` 下**——不是数据库，不是云端，而是人眼可读的纯文本文件。二十年后你的 Emacs 没了，这些 `.org` 文件依然能被任何文本编辑器打开。
2. **任务就写在笔记里**，用 `TODO` / `NEXT` / `DONE` 等状态词标记。不存在"任务系统"和"笔记系统"的分离——一件待办总有它的上下文，而最好的上下文就是写下它时的那段话。
3. **所有操作用键盘完成**，核心入口是空格键 `SPC`。按下 SPC 等半秒钟会弹出 which-key 菜单告诉你下一步可以按什么，不需要背诵键位表。

### 1.4 你的笔记库结构

```
~/NoteHQ/                          ← 笔记总目录
├── 00_Roam/                       ← 原子笔记层（org-roam 管理）
│   ├── daily/                     ← 每日笔记（思维流 + 任务录入）
│   ├── capture/                   ← 所有捕获的笔记（扁平，时间戳前缀）
│   ├── dashboards/                ← 查询入口文件（只放查询，不放数据）
│   ├── supertag-schema.el         ← 标签定义（跟笔记一起 git）
│   └── purpose.org / schema.org   ← AI 上下文文件
├── 10_Outputs/                    ← PARA：可交付的项目（论文、课件…）
├── 20_Practice/                   ← PARA：长期角色与责任域（教学、研究…）
├── 30_Library/                    ← PARA：被取用的素材库（PDF、数据集…）
├── 40_Archives/                   ← 已完成/暂停的内容
└── .orgseq/                       ← 个性化配置（类似 .vscode/）
    ├── ai-config.org              ← AI 服务配置
    └── capture-templates.el       ← 用户自定义捕获模板
```

目录前面的数字前缀（00/10/20/30/40）不是强迫症,它有一个具体的作用:让 dirvish 侧边栏按字母序排列时,**这些层级按"工作优先级"顺序显示**,而不是按英文字母。每天最常打开的 `00_Roam/` 永远在最上面,几乎不会动的 `40_Archives/` 沉到最下面。10 步的间隔给以后插入新层级留了余地(比如你哪天想加一个 `15_Inbox/` 就不用重新编号所有后面的层)。

**核心设计**:`00_Roam/` 内部是扁平的——分类靠 supertag 标签,不靠目录。PARA 四层存放产出物和素材。两层通过 `id:` 链接和 transclusion 通信。

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

部署脚本做的事情不算神秘：检查前置条件是否齐全、把已有的 `~/.emacs.d/` 备份一份（带时间戳，万一你不喜欢随时可以还原）、然后把仓库里的 `early-init.el` / `init.el` / `lisp/` 拷贝到 `~/.emacs.d/` 去。Bootstrap 脚本则负责在你的 home 目录下建出 `~/NoteHQ/` 的完整骨架——Roam 原子笔记层加上 PARA 四层。这两个脚本都是幂等的，可以安全地重复运行。

### 2.3 首次启动

第一次启动 Emacs 会比以后慢一些——它需要从网络下载几十个 elisp 包并在本地编译，过程大约 2 到 5 分钟，期间请保持网络稳定。下载完你会看到 Dashboard 启动界面，这就是大功告成。

有两件收尾工作值得顺手做一下：

```
;; 在 Emacs 里执行，下载 nerd-icons 字体文件
M-x nerd-icons-install-fonts

;; Windows 用户额外一步：找到刚下载的 .ttf 文件右键"安装"
;; （非 Windows 系统上 nerd-icons-install-fonts 会自动装好）

;; 第一次索引 org-supertag 的数据
M-x supertag-sync-full-initialize
```

### 2.4 配置 AI（可选但推荐）

AI 功能不是必需的——你完全可以把 org-seq 当作纯粹的 PKM 工具用。但如果你已经在用 Claude 或 ChatGPT 写东西，把它们搬到 Emacs 里会让你省下大量复制粘贴的时间。org-seq 通过 [OpenRouter](https://openrouter.ai) 统一接入各家模型（Claude、GPT、DeepSeek、Gemini 等），你只需要注册一个账号、拿一个 API key，就能在 `SPC i m` 菜单里随意切换模型，而不必为每家 API 单独开账户。

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

这一章是给第一次启动 Emacs 就觉得无从下手的人准备的。如果你读完前两章已经部署好了配置，打开 Emacs 后看到满屏陌生按键和陌生词汇，不要慌——接下来的十分钟足以让你避开所有最常见的坑，并且开始做一点真正有用的事情。

### 3.1 两种模式

org-seq 启用了 **Evil mode**，它在 Emacs 里模拟 Vim 的操作逻辑。这意味着你输入文字的时候，光标并不总是在"接受键盘输入"的状态——它随时处于某种"模式"中，而不同模式下同一个键会做完全不同的事。这听起来吓人，其实你只需要记住四种模式和一条逃生规则：

| 模式 | 含义 | 进入方式 | 光标外观 |
|------|------|---------|---------|
| **Normal** | 浏览和操作（默认） | `Esc` 或 `C-[` | 方块 |
| **Insert** | 输入文字 | `i`（光标前）/ `a`（光标后）/ `o`（下方新行） | 竖线 |
| **Visual** | 选中文本 | `v`（字符）/ `V`（行）/ `C-v`（块） | 高亮区域 |
| **Command** | 输入命令 | `:` | 底部命令行 |

> **逃生规则**：不管你在什么模式、不管屏幕上发生了什么奇怪的事情，按 `Esc` 总是能回到 Normal 模式。当你感到迷惑，先按 Esc，再想下一步。这就是为什么 Vim 用户的手指总是停在 Esc 上面。

### 3.2 空格键是你的入口

Normal 模式下按空格键 `SPC`，会在屏幕底部弹出一个菜单——这是 which-key 插件，它告诉你接下来可以按哪些键、每个键会触发什么功能。这意味着你**不需要预先背下任何键位**：每次按 SPC 等半秒钟，菜单会自己告诉你所有可能的下一步。

最常用的几个顶级入口长这样：

```
SPC         → 等 0.3 秒 → 弹出功能菜单
SPC SPC     → M-x（输入任意命令名称执行）
SPC .       → 打开文件
SPC ,       → 切换 buffer（已打开的文件）
SPC /       → 在项目中全文搜索
```

如果按完 SPC 之后的菜单里依然找不到你要的功能，还有一招兜底：按 `SPC c c` 打开 Casual 菜单，那是一个基于 Transient 的图形化命令面板，把当前上下文下所有可用操作都列出来了。记不住键就用 Casual，用多了自然就记住了键——这比硬背键位表高效得多。

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

Zettelkasten 是德语，字面意思是"卡片盒子"。它因社会学家 Niklas Luhmann 而闻名——这位一生写了 70 本书和 400 篇论文的学者，把自己的产出力归功于一个由 9 万张手写索引卡组成的笔记系统。每张卡只记一个想法，卡与卡之间通过编号互相指引，日积月累形成一张密密麻麻的思维地图。Luhmann 说过一句耐人寻味的话：他并不是"使用"这个卡片盒，而是和它**对话**。写作的时候，他只需要翻开盒子，跟着链接顺藤摸瓜，新的想法就自然冒出来了。

这个方法能有效，靠的是三个简单约定。第一，**原子化**——每条笔记只讲清楚一个想法，不多也不少。一条笔记如果同时讨论两件事，以后就很难被精确地链接到。第二，**链接**——想法之间靠显式的引用连成网络，而不是靠层级目录归类。一个想法可以出现在多个上下文里，多层级目录做不到这一点。第三，**涌现**——好的洞见不是你刻意"想出来"的，而是某一天你顺着一条链接翻到另一条意想不到的笔记时突然蹦出来的。系统越密集，涌现越频繁。

org-seq 把 Zettelkasten 的这三条原则落地成了一个三层架构，每一层只做自己擅长的事：

| 层 | 工具 | 它在做什么 |
|----|------|------|
| **图谱层** | org-roam | 管理节点、双向链接、反向链接、capture 模板——Zettelkasten 的原始形态 |
| **数据层** | org-supertag | 把标签变成带字段的数据库记录，提供表格和看板视图——借鉴 Tana 的思路 |
| **性能层** | org-node + org-mem | 异步索引，让 3000+ 节点的搜索和反向链接刷新从几分钟降到两秒 |

这三层不是层层叠加的抽象，而是分工合作的三个引擎。日常写笔记时你感觉不到它们的存在；当你的笔记库长到上千条、开始需要查询和聚合时，你会感谢底层有这些东西在默默工作。

### 8.2 创建笔记

```
SPC n c        → 新建笔记（弹出模板选择）
```

内置模板：

| 按键 | 类型 | 用途 |
|------|------|------|
| `d` | 默认 | 通用笔记（覆盖 80% 场景） |
| `r` | 阅读 | 文献/书籍笔记（TL;DR / Key points / Commentary） |

每条笔记自动获得一个唯一 ID（时间戳格式），存储在 `~/NoteHQ/00_Roam/capture/` 下。

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

GTD 全称 *Getting Things Done*，是 David Allen 在同名畅销书里提出的任务管理方法论。它的核心前提很朴素：**人脑是用来产生想法的，不是用来存储待办事项的**。每当你在脑子里反复提醒自己"别忘了给某某回邮件"，你就把本该用于思考的注意力分给了记忆——而且你还记不牢。Allen 的方案是把所有待办从脑子里"清空"到一个可信的外部系统，然后定期回顾它。

这套方法有五个环节：先**收集**所有待办到一个 inbox，然后**处理**每一条决定它的归宿（要做 / 委托 / 延后 / 丢弃），把需要做的**组织**到对应的列表里（今天 / 等待 / 某天），按上下文**执行**，最后定期**回顾**确保整个系统没有被遗忘。大多数 GTD 应用都只实现了其中三四个环节，org-seq 用 Org-mode 的 TODO 系统加上自建的 Dashboard 把整条链路都串起来了——而且因为一切都是纯文本文件，你可以随时用 grep 或自己的脚本审查系统的状态。

### 9.2 任务状态

Org-mode 允许你为任何一个标题前缀一个"状态关键词"，让它变成一个任务。org-seq 定义了七种状态，分成"开放"和"已关闭"两组：

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

大多数 AI 笔记应用把 AI 当作一个外挂工具——你需要切换到另一个窗口，复制内容过去，让 AI 回答完再复制回来。org-seq 的思路正好相反：AI 是你编辑器的原生命令之一，和"保存文件"、"切换 buffer"处于同一层。你在写笔记时选中一段文字按 `SPC i s`，AI 的摘要就出现在底部的结果窗口里；你想让它建议标签按 `SPC i t`；你想把一段中文翻译成英文按 `SPC i l`。没有窗口切换，没有复制粘贴，所有输出都保留在你的 `.org` 文件里可以随时回溯。

底层用的是 **gptel**——Emacs 社区目前最活跃的 LLM 客户端库。默认通过 OpenRouter 接入，这意味着你可以用同一个 API key 访问 DeepSeek、Claude、GPT、Gemini 等几十种模型，随时在 `SPC i m` 菜单里切换。所有 AI 相关的命令都挂在 `SPC i` 这个 leader 前缀下面——按 `SPC i` 等半秒钟 which-key 会把全部命令列给你看。

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

任何和 AI 频繁打交道的人都体会过这种疲劳：每次开新对话都要重新交代一遍自己是谁、研究什么、笔记体系如何组织。org-seq 用一个简单的机制解决了这个问题——它会自动把两个文件的内容注入到每次 AI 对话的系统提示中，让 AI **始终知道**你在做什么。

- `~/NoteHQ/00_Roam/purpose.org` 描述你的知识库目标和研究方向。例如"我是研究认知科学的博士生，当前关注元认知与学习迁移"。
- `~/NoteHQ/00_Roam/schema.org` 描述你的笔记类型约定和 tag 体系。例如"reading tag 记录文献，field 有 authors / year / topic"。

首次使用时按 `SPC i g` 会在 Roam 目录下创建这两个文件的骨架，你填入自己的内容即可。以后每次 `SPC i s` / `SPC i k` / `SPC i i` 的调用都会自动带上这段背景，不需要你重复输入。编辑完保存，下次调用自动生效——没有重启步骤，没有缓存刷新。

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
│ dirvish- │     Dashboard          │
│  side    │  (启动面板 + 最近文件)   │
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
│ dirvish- │                        │  Outline   │
│  side    │     主编辑区            │   (~20%)   │
│ (~15%)   │       (~65%)           ├────────────┤
│ 文件管理  │                        │  Terminal  │
│          │                        │   (~20%)   │
└──────────┴────────────────────────┴────────────┘
```

- **treemacs**（左）：稳定的项目/目录树侧边栏。用于浏览 NoteHQ 层级、展开折叠目录、定位当前文件。它负责“树”，而不是完整文件管理。
- **主编辑区**（中）：你的笔记/代码
- **Outline**（右上）：当前文件的大纲/标题列表，点击可跳转
- **Terminal**（右下）：内置终端（eshell）

### 12.3 布局控制键

```
SPC l l        → 启动/重建完整三栏布局
SPC l t        → 显示/隐藏 dirvish 侧栏
SPC l o        → 显示/隐藏 Outline 面板
SPC l e        → 显示/隐藏终端
SPC l d        → 切换到 Dashboard
SPC '          → 快速开关终端（最常用）
```

### 12.4 Dirvish 文件管理

Dirvish 替代了旧的 Treemacs，基于 dired 构建，提供现代文件管理体验：

```
SPC o f        → 全屏 dirvish（当前目录）
SPC o N        → 全屏 dirvish（NoteHQ 根目录）
SPC o d        → dired-jump（跳转到当前文件所在目录）
SPC f j        → 同上（Doom 约定）
```

在 dirvish / dired buffer 内：

```
RET            → 打开文件/进入目录
-              → 返回上级目录
a              → Quick-access 菜单（h/n/r/c/d/b/o/p/l/a 单键跳转）
TAB            → 展开/折叠子目录
s              → Quicksort 菜单（按名/大小/时间排序）
v              → VC 菜单（git 操作）
y              → Yank 菜单（复制路径）
f              → 文件信息菜单
C-o            → Casual 全局菜单（Transient）
M-t            → 切换布局（单栏/双栏/三栏预览）
M-j            → dirvish-fd-jump（快速定位目录）
```

所有 dired 原生键位（`C`、`R`、`D`、`m`、`u`、`*` 系列标记等）依然可用。dirvish 是 dired 的增强 UI，不是替代品。

### 12.5 窗口操作

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

## 第十三章 专注计时器（Focus Timer）

### 13.1 它为什么存在

假设你瞥了一眼时钟，14:17——你决定专心做一件事直到完成当前这段思路。大多数番茄钟会给你一个固定 25 分钟的片段，把你扔到 14:42 这个毫无意义的时刻。你大脑的节奏和钟表上的整点刻度是解耦的，你得在奇怪的时间结束，再盯着时钟算下一次什么时候开始——这种计算本身就破坏了专注。

这个功能模仿了 macOS 上的一款叫做 Vitamin-R 的付费软件，它的核心洞察是：**时间片段的结束点应该对齐到墙上时钟的整点刻度**，而不是随意的相对时长。你在 14:17 启动，它找到 10 到 30 分钟窗口内最近的一个整点（例如 14:30），把那个当作结束时间，告诉你"这次是 13 分钟的片段"。你自然地把 14:30 当作一个边界——时钟每次扫过整点时你的身体都会本能地感知到，这种感知是定时器无法替代的。

片段结束时，系统不只是通知你时间到了，它还会问你**这段感觉如何**——不集中、正常集中、还是心流。这个自评问题看起来微不足道，但它强制你每 15 分钟左右审视一次自己的状态，而审视本身就是干预——仅仅是"我要不要承认这段其实一直在走神"这个问题，就足以让第二个片段立刻更专注。

### 13.2 启动一个专注片段

把光标停在任何你想"从这里开始专注"的位置，按：

```
SPC a f        → 启动专注片段（使用自动对齐的时长）
C-u SPC a f    → 启动时自定义时长（默认值是自动对齐的结果）
```

Emacs 会在当前位置插入一行标记，类似这样：

```
[2026-04-10 Fri 14:17] focus started -- 13m planned (ends 14:30)
```

同时屏幕底部的 modeline 会出现一个实时倒计时 `[FOCUS 12:34]`，每秒更新。你可以继续写笔记、做事、切换 buffer——倒计时在后台运行，不打扰你。

### 13.3 片段结束时

到点了，Emacs 会响一声铃，然后在 minibuffer 弹出一行提问：

```
How did that feel?  (u) unfocused   (n) normal focus   (f) flow state :
```

按一个字母就行。系统会做三件事：

1. 把结果追加到原 buffer 的那行内联标记后面，变成：
   ```
   [2026-04-10 Fri 14:17] focus started -- 13m planned (ends 14:30) -> ended 14:30 (flow state)
   ```
2. 在 `~/NoteHQ/.orgseq/focus-log.org` 日志文件里追加一条结构化记录，带完整的时间戳、计划时长、实际时长、结果、上下文文件。
3. 清掉 modeline 的倒计时指示。

### 13.4 可视化：Focus Dashboard

```
SPC a F        → 打开 Focus Dashboard
```

会弹出一个文本界面，显示最近 14 天的专注历史：

```
FOCUS DASHBOARD
  log: ~/NoteHQ/.orgseq/focus-log.org
  range: last 14 days

Daily timeline
   legend: flow = █   normal = ▓   unfocused = ░

  2026-04-10 Fri  4 slices  58m total  84% focused  38m flow
    ██ ▓▓▓ █ ▓▓▓
  2026-04-09 Thu  3 slices  45m total  66% focused
    ▓▓▓ ░░░ ▓▓▓

Summary over 14 days
  flow          5 slices   71 min   41.0%
  normal        8 slices   85 min   49.1%
  unfocused     2 slices   17 min    9.8%
  total        15 slices  173 min
```

每一行是一天，色块代表那天的每个片段，宽度按实际分钟数缩放（每 5 分钟一格），颜色按结果区分：绿色 █ 是心流，蓝色 ▓ 是正常，灰色 ░ 是不集中。最下面是 14 天总计——你可以一眼看出自己本周是状态好还是状态差。

Dashboard 内部键位：

```
g              → 刷新
RET            → 打开原始日志文件（可以手动编辑）
s              → 在当前 buffer 启动新片段
q              → 退出
```

### 13.5 配置

所有参数都在 `M-x customize-group RET org-focus-timer` 里。最常调的几个：

| 变量 | 默认值 | 含义 |
|------|--------|------|
| `org-focus-min-duration` | 10 | 片段最短时长（分钟），系统不会把结束时间设得比这个更近 |
| `org-focus-max-duration` | 30 | 片段最长时长（分钟），系统不会把结束时间设得比这个更远 |
| `org-focus-round-to` | 15 | 对齐的整点粒度（15 = 每刻钟，5 = 每 5 分钟） |
| `org-focus-log-file` | `~/NoteHQ/.orgseq/focus-log.org` | 日志文件位置 |
| `org-focus-ring-bell-on-end` | t | 片段结束时是否响铃 |
| `org-focus-dashboard-days` | 14 | Dashboard 显示多少天的历史 |

如果你想换成 5 分钟边界、25 分钟的经典番茄风格：

```elisp
(setq org-focus-min-duration 20
      org-focus-max-duration 30
      org-focus-round-to 5)
```

### 13.6 为什么它有自己的目录

如果你翻一下 org-seq 的代码，会发现 `org-focus-timer` 不像其他功能那样住在 `lisp/init-*.el` 里，而是独占一个子目录：`packages/org-focus-timer/`。旁边只有一个薄薄的 `lisp/init-focus.el`（大约 60 行）负责引用它。

这个结构是有意为之的过渡形态。这个计时器对任何用 org-mode 的人都有价值——它不依赖 org-roam、不依赖 supertag、不依赖 org-seq 的任何路径约定，核心是纯粹的 elisp + 时间计算 + 文件读写。等到 API 和日志格式稳定下来之后，它会**毕业**成一个独立的 GitHub 项目，那时候 `init-focus.el` 会从当前的 `:load-path` 引用改成 `:vc` 引用，`packages/org-focus-timer/` 这个目录会被移出 org-seq。

在那之前，把源代码放在 org-seq 内部带来一个实用的好处：**迭代闭环更短**。你想改 `org-focus-timer.el` 的某段逻辑？直接编辑 `packages/org-focus-timer/org-focus-timer.el`，保存，`M-x eval-buffer`——下一次 `SPC a f` 就用上了新代码，不需要重新 deploy，不需要切换仓库。对于一个尚在打磨的功能，这种零摩擦的改动环境比"干净的包边界"更重要。

包和集成层之间有一条明确的分工：**所有 org-seq 特有的默认值**（日志文件指向 `~/NoteHQ/.orgseq/`、默认用 10/30/15 的 Vitamin-R 参数、键位绑定到 `SPC a f`）都住在 `lisp/init-focus.el` 里；**包本身**（`packages/org-focus-timer/`）只提供纯粹的函数和 defcustom，不知道 org-seq 的存在。这意味着等到它毕业的那天，你直接 `git mv packages/org-focus-timer/ ../org-focus-timer/` 就能把它剥离出来而不需要改任何一行代码。

如果你把 org-seq clone 到另一台机器并发现 `packages/` 没跟着复制过去，`M-x customize-group RET org-seq` 里有一个 `my/focus-timer-path` 可以指向你实际保存 `org-focus-timer.el` 的位置。

---

## 第十四章 Git 版本控制

### 14.1 Magit

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

### 14.2 其他 Git 快捷键

```
SPC g b        → Git blame（查看每行的提交历史）
SPC g l        → Git log（提交历史）
SPC g d        → Git diff（查看变更）
SPC g f        → Git 文件操作（多种选项）
```

---

## 第十五章 外观与主题

### 15.1 主题

默认主题是 **modus-operandi-tinted**（浅色主题），属于 Modus 主题家族——为可读性和无障碍设计的高对比度主题。

```
SPC t t        → 切换主题（从可用主题列表中选择）
```

已安装的主题家族：
- **Modus themes**：高对比度、无障碍（推荐）
- **Ef themes**：Daniel Mendler 的优雅主题集
- **Doom themes**：Doom Emacs 风格的主题集

### 15.2 字体

org-seq 配置了中英文混排：
- 英文/代码：Cascadia Code（如果安装了的话）
- 中文：LXGW WenKai Mono > Sarasa Fixed SC > Microsoft YaHei UI > SimHei（按优先级尝试）
- 中文字体会自动缩放以对齐英文（等宽对齐）

### 15.3 界面开关

```
SPC t l        → 显示/隐藏行号
SPC t w        → 显示/隐藏自动换行
SPC t o        → 显示/隐藏 Olivetti（居中）模式
SPC t f        → 全屏切换
SPC t i        → 显示/隐藏 org-modern 美化效果
```

### 15.4 Olivetti（居中阅读模式）

在 Org 文件中默认自动启用。它会把文本内容居中显示，两侧留白，让宽屏上的阅读体验接近纸质书。

文本宽度会根据窗口大小自适应调整（最小 88 字符，最大 140 字符）。

---

## 第十六章 进阶功能

### 16.1 Casual 菜单

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

### 16.2 Eval（执行 Elisp）

org-seq 基于 Emacs Lisp 构建，你随时可以执行 Elisp 代码来调试或扩展：

```
SPC e e        → 执行光标前的表达式
SPC e b        → 执行整个 buffer
SPC e r        → 执行选中区域
SPC e d        → 执行当前函数定义
```

### 16.3 Winner Mode（窗口布局撤销）

org-seq 默认启用了 Winner mode。如果你不小心搞乱了窗口布局：

```
C-c <left>     → 撤销上一次窗口变化
C-c <right>    → 重做窗口变化
```

### 16.4 Emacs Server

org-seq 自动启动 Emacs Server。这意味着你可以在命令行用 `emacsclient` 快速打开文件，而不需要启动新的 Emacs 实例：

```bash
emacsclient -c file.org        # 在已运行的 Emacs 中打开文件
emacsclient -c -a ""           # 连接已运行的 Emacs，如果没有则启动一个
```

Windows 用户可以使用仓库里的 `ec.cmd`（调用 `emacsclient.exe -c -a "runemacs.exe"`），前提是 `runemacs.exe` 在 PATH 中。

### 16.5 定制配置（customize-group）

org-seq 的所有用户可调参数都集中在 `org-seq` customization group。打开它：

```
M-x customize-group RET org-seq RET
```

主要可调项：

| 变量 | 含义 | 默认值 |
|------|------|--------|
| `my/note-home` | 笔记总目录 | `~/NoteHQ/` |
| `my/roam-dir` | 原子笔记层（org-roam + supertag + AI context 全部指向此处） | `~/NoteHQ/00_Roam/` |
| `my/orgseq-dir` | 个性化配置目录（.orgseq/） | `~/NoteHQ/.orgseq/` |
| `my/agenda-cache-ttl` | Agenda 文件缓存过期秒数 | `300` |
| `my/gtd-context-tags` | GTD 上下文标签列表 | `("@work" "@home" "@computer" "@errands" "@phone")` |
| `my/workspace-startup-delay` | 启动后开工作区的 idle 延迟（秒） | `0.3` |
| `my/ai-purpose-file` | AI 上下文 purpose.org 路径 | `<roam-dir>/purpose.org` |
| `my/ai-schema-file` | AI 上下文 schema.org 路径 | `<roam-dir>/schema.org` |
| `my/olivetti-body-width-*` | Org 居中阅读模式的宽度范围 | 88–140 |
| `my/markdown-body-width-*` | Markdown 居中阅读模式的宽度范围 | 84–120 |

修改后按 `C-x C-s` 保存到 `custom.el`，下次启动自动生效。也可以直接在 custom.el 里写：

```elisp
(custom-set-variables
 '(my/note-home (file-truename "~/Notes/"))
 '(my/gtd-context-tags '("@work" "@home" "@deep-work")))
```

**注意**：改了 `my/note-home` 后，派生路径 `my/roam-dir` 和 `my/orgseq-dir` 会跟随更新（它们的默认值通过 `expand-file-name` 依赖 `my/note-home`），但需要**重启 Emacs** 才能让所有模块重新计算路径。运行时改这些变量只影响变量本身，不影响已经传给 org-roam/org-mem/org-supertag 的派生值。

### 16.6 配置热重载

修改 `lisp/init-*.el` 任何一个模块后，你不必重启 Emacs。两种热重载方式：

- **单文件**：`M-x eval-buffer` 在你正在编辑的 `init-*.el` 里执行
- **全部模块**：`M-x load-file` 选择要重新加载的文件

常见的配置热重载场景：

| 修改内容 | 热重载方式 |
|---------|-----------|
| supertag schema（`~/NoteHQ/00_Roam/supertag-schema.el`） | `SPC n m T`（`my/reload-supertag-schema`） |
| capture 模板（`~/NoteHQ/.orgseq/capture-templates.el`） | `SPC n m C`（`my/reload-capture-templates`） |
| AI 后端（`~/NoteHQ/.orgseq/ai-config.org`） | 保存文件后下次 `M-x gptel` 会重新解析 |
| 单个 `init-*.el` 模块 | `M-x eval-buffer` |
| 所有 `init-*.el` 模块 | 重启 Emacs 最稳妥（或 `M-x restart-emacs`） |

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
| `SPC f j` | Dired jump（跳到当前文件目录） |
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
| `SPC l t` | 开关 dirvish 侧栏 |
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
| `SPC o D` | Dashboard |
| `SPC o a` | Agenda |
| `SPC o f` | Dirvish（全屏文件管理） |
| `SPC o d` | dired-jump（跳到当前文件目录） |
| `SPC o j` | dired（选目录打开） |
| `SPC o N` | Dirvish @ NoteHQ |
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

如果你从头读到这里，大概已经意识到 org-seq 的功能比你需要的多得多。这没关系——绝大多数用户永远不会用到附录 A 里一半的键位。关键不在于你学会了多少功能，而在于你**今天**就能开始用某几个功能做真正有用的事情。

下面这个四周学习路径只是一个建议，不是作业。每一周我们会聚焦一两个具体的工作流，让你把它们变成日常习惯，而不是试图同时吞下整套系统。

**第一周**让自己熟悉 Emacs 作为一个普通编辑器的操作——打开文件、保存、在 buffer 之间切换、学会 Evil 的基本动作（第四章和第五章讲的东西）。不要急着写笔记或管任务，光是学会不慌不忙地编辑文本就已经是一个不小的成就。感到迷惑的时候按 SPC 看菜单，或者按 `SPC h k` 然后按任何一个键让 Emacs 告诉你它是干什么的。

**第二周**开始写 daily 笔记（第八章 8.7）和简单的任务记录（第九章 9.3）。每天打开 Emacs 第一件事是 `SPC n d d` 写今日笔记，冒出任何待办就直接写成 `* TODO ...` 塞进去。不要担心格式，不要担心 tag，不要担心"以后怎么查找"——光是把想法从脑子转移到文件里，这一周就没白过。

**第三周**开始创建 Zettelkasten 原子笔记（第八章 8.2-8.5），学着建立链接和反向链接。从 daily 里挑两三个值得独立存在的想法，用 `SPC n c` 提升成新节点，用 `SPC n i` 在 daily 里插回链接。笔记还不需要很多——五到十条就够你第一次体会到"顺着链接跳来跳去"的乐趣。

**第四周**你可以尝试 AI 功能（第十章）和 GTD Dashboard（第九章 9.4）。这两块都是"如虎添翼"而非"不可或缺"——它们会让你前三周形成的习惯发挥得更好，但前三周的基础没打牢之前，提前用这些功能反而会让人感觉不踏实。

**四周之后**，supertag、transclusion、org-ql 这些高级功能可以按需探索——等到你真正遇到某个具体问题（"我想查所有读过但没写评论的书"、"我想在论文里引用某条笔记的原文"）再去学对应的功能，学习效率会比预先通读手册高得多。

如果你只记得住三个键，请记住这三个：

- **`Esc`** 让你从任何模式回到安全的 Normal 模式，感到迷惑就按它。
- **`SPC`** 是所有功能的入口——按了之后等半秒钟 which-key 菜单会告诉你下一步可以按什么。
- **`C-g`**（Ctrl+g）是 Emacs 的万能取消键——当你开始输入某个命令但反悔了，或者任何地方卡住了，按 C-g 取消。

剩下的东西，你会在使用中慢慢找到属于自己的节奏。祝你写作愉快。
