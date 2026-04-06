# 从零构建 Windows Emacs PKM 系统完全指南

**核心结论: 在 Windows 上构建以 org-roam 为核心的个人知识管理系统完全可行, 但需要注意三个关键点 -- MSYS2 是获取 native-comp 支持的最佳途径, Emacs 29+ 内置 SQLite 彻底解决了 org-roam 在 Windows 上的头号痛点, 以及 `set-fontset-font` 配合 `face-font-rescale-alist` 是实现中英文混排的标准方案.** 本指南覆盖从安装到 PKM 工作流的完整配置链路, 包含可直接使用的 elisp 代码片段, 所有 Windows 特有的坑点均以 ⚠️ 标记醒目标注. 全文按实施顺序组织, 可作为逐步执行的规范文档.

---

## 第一步: 获取 Emacs 29+ 并配置 Windows 环境

### 选择正确的 Emacs 构建版本

**⚠️ Windows 关键事实: GNU FTP 官方 Windows 二进制包不包含 native-comp 支持.** native-comp 需要 libgccjit 运行时, 这意味着需要打包整个 GCC 工具链, 官方构建刻意排除了它.

获取带 native-comp 的 Emacs 有三条路径:

- **MSYS2 (推荐)**: 在 MSYS2 MINGW64 shell 中执行 `pacman -S mingw-w64-x86_64-emacs`, 自带 native-comp 支持. 还需安装 `pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-libgccjit`, 并将 `C:\msys64\mingw64\bin` 加入 Windows PATH.
- **社区预编译版本**: emacs-w64 项目 (https://git.sr.ht/~mplscorwin/emacs-w64) 提供带 native-comp 的预构建二进制, 但仍需 MSYS2 中的 libgccjit.
- **GNU FTP 官方版本 (不含 native-comp)**: `https://ftp.gnu.org/gnu/emacs/windows/emacs-29/` 或 `emacs-30/`, 提供 `.exe` 安装器和 `.zip` 免安装版. 如果不需要 native-comp, 这是最简单的选择.

安装后在 Emacs 中验证: `M-: (native-comp-available-p)` 应返回 `t`. 同时验证 SQLite: `M-: (sqlite-available-p)` 应返回 `t` (org-roam 必需).

### HOME 目录与配置路径

**⚠️ 务必显式设置 HOME 环境变量.** Windows 上 Emacs 按以下顺序查找 HOME: 环境变量 `HOME` → 注册表 `HKCU\SOFTWARE\GNU\Emacs\HOME` → `%APPDATA%` → `C:\`. 最佳做法是:

1. 打开 "编辑系统环境变量" → 新建用户变量: `HOME` = `C:\Users\<用户名>`
2. 将 `.emacs.d/` 放在该目录下
3. 这确保 `~` 扩展行为与 Unix 一致

### Windows 特有性能调优

```elisp
(when (eq system-type 'windows-nt)
  ;; 进程通信: Windows 进程创建比 Unix fork() 慢得多
  (setq read-process-output-max (* 1024 1024))  ; 1MB, 默认 4096 远远不够
  (setq w32-pipe-read-delay 0)                   ; Emacs 27+ 已默认为 0, 显式确认
  (setq w32-pipe-buffer-size (* 64 1024))        ; 64KB pipe 缓冲

  ;; 编码: 统一使用 UTF-8
  (prefer-coding-system 'utf-8-unix)
  (setq-default buffer-file-coding-system 'utf-8-unix))
```

---

## 第二步: early-init.el 与启动优化

Doom Emacs 的启动速度秘诀核心在于三个技术: **GC 抑制**, **file-name-handler-alist 清空**, 和 **UI 元素预阻止**. early-init.el 在 GUI 初始化之前加载 (https://www.gnu.org/software/emacs/manual/html_node/emacs/Early-Init-File.html), 是执行这些优化的理想位置.

```elisp
;;; early-init.el --- -*- lexical-binding: t; -*-

;; 1. GC 抑制: 启动期间将阈值设为最大值, 避免任何 GC 暂停
(setq gc-cons-threshold most-positive-fixnum  ; 2^61 bytes
      gc-cons-percentage 0.6)

;; 2. 清空 file-name-handler-alist: 每次 load/require 都会检查此列表的正则
;;    启动期间不需要压缩文件处理和 TRAMP, 清空后显著加速
(defvar my--file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist my--file-name-handler-alist)))

;; 3. UI 阻止: 在 default-frame-alist 中设置, 阻止元素被创建
;;    比在 init.el 中用 (tool-bar-mode -1) 更好 -- 后者先创建再销毁, 会闪烁
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq inhibit-startup-screen t
      inhibit-startup-message t)

;; 4. Native-comp 设置
(setq native-comp-async-report-warnings-errors 'silent
      native-comp-jit-compilation t)

;; 5. Windows 特定
(when (eq system-type 'windows-nt)
  (setq w32-pipe-read-delay 0))
```

启动完成后恢复合理的 GC 参数:

```elisp
;; 在 init.el 中添加
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)  ; 16MB
                  gc-cons-percentage 0.1)))
```

**关于 GCMH 包的注意**: EmacsConf 2023 的 GC 专题演讲 (https://emacsconf.org/2023/talks/gc/) 发现 gcmh 可能引起问题 -- 其定时器本身会产生垃圾, 导致 GC 最终运行时出现长暂停. 直接设置 `gc-cons-threshold` 为 **16-32MB** 是更稳妥的方案.

### 启动性能测量工具

```elisp
;; ESUP: 逐表达式启动时间分析 (https://github.com/jschaf/esup)
(use-package esup :ensure t :commands esup)
;; 用法: M-x esup

;; benchmark-init: 按包统计加载时间 (https://github.com/dholm/benchmark-init-el)
(use-package benchmark-init
  :ensure t :demand t
  :config
  (benchmark-init/activate)
  (add-hook 'after-init-hook #'benchmark-init/deactivate))
;; 用法: M-x benchmark-init/show-durations-tabulated

;; 快速检查基线启动时间 (命令行):
;; emacs -q --eval="(message \"%s\" (emacs-init-time))"
```

---

## 第三步: 包管理与 init.el 骨架结构

### package.el 优于 straight.el

**对于 ~200 行的配置, 使用 package.el.** Emacs 29 内置 use-package, 并新增 `package-vc-install` 支持从 Git 仓库安装包, 填补了 straight.el 最大的差异化优势. straight.el 增加的引导代码和构建缓存复杂度在小配置中得不偿失. 如果将来需要从 GitHub 安装未上架 MELPA 的包 (如 org-supertag), 可用 `package-vc-install` 或 Emacs 30+ 的 `:vc` 关键字.

```elisp
;;; init.el --- -*- lexical-binding: t; -*-

;; ---- 包管理 ----
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; ---- use-package (Emacs 29+ 内置) ----
(require 'use-package)
(setq use-package-always-ensure t    ; 自动安装缺失的包
      use-package-always-defer t     ; 默认延迟加载
      use-package-expand-minimally t ; 更快的宏展开
      use-package-verbose nil)

;; ---- 模块加载路径 ----
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; ---- 分离 custom-file ----
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))
```

### 文件组织策略

**起步阶段用单文件 init.el + early-init.el**, 当 init.el 超过 300 行时拆分为模块:

```
~/.emacs.d/
├── early-init.el          ; GC, UI 抑制, native-comp
├── init.el                ; 包管理引导 + require 各模块
├── custom.el              ; Customize 自动生成的变量 (分离)
└── lisp/
    ├── init-evil.el       ; Evil + 按键绑定
    ├── init-completion.el ; Vertico 全家桶
    ├── init-org.el        ; Org-mode + org-roam
    ├── init-ui.el         ; 字体, 主题, modeline
    └── init-pkm.el        ; 扩展 PKM 工具
```

每个模块文件末尾必须有 `(provide 'init-MODULE)`, init.el 中用 `(require 'init-MODULE)` 加载.

---

## 第四步: Evil Mode 与 SPC Leader 键体系

### evil + evil-collection 核心配置

evil-mode (https://github.com/emacs-evil/evil) 提供 Vim 模态编辑; evil-collection (https://github.com/emacs-evil/evil-collection) 为 100+ 个 Emacs 模式补充 Evil 键绑定 (dired, magit, help 等).

```elisp
(use-package evil
  :ensure t
  :demand t  ; Evil 必须立即加载, 不能 defer
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil      ; ⚠️ evil-collection 要求此项为 nil
        evil-want-C-u-scroll t        ; C-u 上滚 (Vim 行为)
        evil-want-C-i-jump nil        ; 释放 C-i 给 org-mode 的 TAB
        evil-want-Y-yank-to-eol t
        evil-undo-system 'undo-redo   ; Emacs 28+ 原生 undo/redo
        evil-split-window-below t
        evil-vsplit-window-right t)
  :config
  (evil-mode 1)
  (evil-global-set-key 'motion "j" 'evil-next-visual-line)
  (evil-global-set-key 'motion "k" 'evil-previous-visual-line))

(use-package evil-collection
  :after evil
  :ensure t
  :config (evil-collection-init))
```

### general.el 实现 SPC Leader 键

general.el (https://github.com/noctuid/general.el) 是 Emacs 中 leader key 方案的终极解决方案, 功能远超 evil-leader. 配合 which-key 提供按键提示:

```elisp
(use-package general
  :ensure t
  :demand t
  :config
  (general-evil-setup t)

  ;; 主 leader: SPC (normal/visual), M-SPC (insert/emacs)
  (general-create-definer my/leader-keys
    :states '(normal insert visual emacs)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "M-SPC")

  ;; 局部 leader: , (用于模式特定绑定)
  (general-create-definer my/local-leader-keys
    :states '(normal insert visual emacs)
    :keymaps 'override
    :prefix ","
    :global-prefix "M-,"))

(use-package which-key
  :ensure t
  :demand t
  :init (which-key-mode)
  :config (setq which-key-idle-delay 0.3))
```

### Doom 风格 SPC 按键分组设计

以下是完整的 leader key 映射方案, 参考 Doom Emacs 的分组逻辑并适配 PKM 工作流:

```elisp
(my/leader-keys
  ;; 顶层快捷键
  "SPC" '(execute-extended-command :wk "M-x")
  "."   '(find-file :wk "查找文件")
  ","   '(consult-buffer :wk "切换 buffer")
  "/"   '(consult-ripgrep :wk "项目搜索")
  "TAB" '(evil-switch-to-windows-last-buffer :wk "上一个 buffer")

  ;; SPC b — Buffer
  "b"   '(:ignore t :wk "buffer")
  "bb"  '(consult-buffer :wk "切换")
  "bd"  '(kill-current-buffer :wk "关闭")
  "bs"  '(save-buffer :wk "保存")

  ;; SPC f — 文件
  "f"   '(:ignore t :wk "文件")
  "ff"  '(find-file :wk "打开文件")
  "fr"  '(consult-recent-file :wk "最近文件")
  "fs"  '(save-buffer :wk "保存")
  "fp"  '((lambda () (interactive) (find-file user-init-file)) :wk "配置文件")

  ;; SPC w — 窗口
  "w"   '(:ignore t :wk "窗口")
  "wv"  '(evil-window-vsplit :wk "纵分")
  "ws"  '(evil-window-split :wk "横分")
  "wd"  '(delete-window :wk "关闭")
  "wm"  '(delete-other-windows :wk "最大化")
  "wh"  '(evil-window-left :wk "←")
  "wj"  '(evil-window-down :wk "↓")
  "wk"  '(evil-window-up :wk "↑")
  "wl"  '(evil-window-right :wk "→")

  ;; SPC s — 搜索
  "s"   '(:ignore t :wk "搜索")
  "ss"  '(consult-line :wk "当前 buffer")
  "sp"  '(consult-ripgrep :wk "项目全文")
  "si"  '(consult-imenu :wk "imenu")
  "so"  '(consult-outline :wk "大纲")

  ;; SPC n — 笔记 (PKM 核心)
  "n"   '(:ignore t :wk "笔记")
  "nf"  '(org-roam-node-find :wk "查找笔记")
  "ni"  '(org-roam-node-insert :wk "插入链接")
  "nc"  '(org-roam-capture :wk "新建笔记")
  "nb"  '(org-roam-buffer-toggle :wk "反向链接")
  "nd"  '(org-roam-dailies-capture-today :wk "今日日记")
  "ng"  '(org-roam-ui-mode :wk "图谱可视化")
  "ns"  '(my/org-roam-rg-search :wk "全文搜索笔记")

  ;; SPC p — 项目
  "p"   '(:ignore t :wk "项目")
  "pp"  '(project-switch-project :wk "切换项目")
  "pf"  '(project-find-file :wk "项目文件")

  ;; SPC g — Git
  "g"   '(:ignore t :wk "git")
  "gg"  '(magit-status :wk "magit")

  ;; SPC h — 帮助
  "h"   '(:ignore t :wk "帮助")
  "hf"  '(describe-function :wk "函数")
  "hv"  '(describe-variable :wk "变量")
  "hk"  '(describe-key :wk "按键")

  ;; SPC t — 开关
  "t"   '(:ignore t :wk "开关")
  "tt"  '(consult-theme :wk "切换主题")
  "tl"  '(display-line-numbers-mode :wk "行号")

  ;; SPC q — 退出
  "q"   '(:ignore t :wk "退出")
  "qq"  '(save-buffers-kill-emacs :wk "退出 Emacs"))
```

### evil-org: 解决 org-mode 兼容性

evil-org (https://github.com/Somelauw/evil-org-mode) 是 Evil + org-mode 的粘合层, 解决了几个核心冲突: **TAB 被 evil-jump-forward 劫持** (无法折叠/展开), **o/O 不创建新标题**, **M-h/j/k/l 与 org 结构操作的映射**.

```elisp
(use-package evil-org
  :ensure t
  :after org
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar))
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))
```

---

## 第五步: Vertico 补全框架全家桶

这套现代补全栈全部基于 Emacs 标准的 `completing-read` API (与 Helm/Ivy 的私有 API 不同), 意味着它与 **所有** 使用 completing-read 的命令自动兼容, 包括 org-roam. 五个包均在 **GNU ELPA**, 代码量极小 (Vertico 仅约 600 行), 无原生依赖, **在 Windows 上无任何问题**.

```elisp
;; ---- Vertico: 垂直补全 UI ----
(use-package vertico
  :ensure t
  :init (vertico-mode)
  :config
  (setq vertico-count 15
        vertico-cycle t
        vertico-resize nil)
  :bind (:map vertico-map
         ("C-j" . vertico-next)
         ("C-k" . vertico-previous)))

;; Vertico 文件导航增强 (内置扩展)
(use-package vertico-directory
  :after vertico :ensure nil
  :bind (:map vertico-map
         ("RET" . vertico-directory-enter)
         ("DEL" . vertico-directory-delete-char)
         ("M-DEL" . vertico-directory-delete-word))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; ---- Orderless: 空格分隔的模糊匹配 ----
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion)))))

;; ---- Consult: 增强搜索/导航命令 ----
(use-package consult
  :ensure t
  :bind (("C-x b" . consult-buffer)
         ("M-y"   . consult-yank-pop)
         ("M-s l" . consult-line)
         ("M-s r" . consult-ripgrep)
         ("M-s o" . consult-outline))
  :config
  ;; ⚠️ Windows: 路径分隔符必须设为 /
  (setq consult-ripgrep-args
        "rg --null --line-buffered --color=never --max-columns=1000 --path-separator / --smart-case --no-heading --with-filename --line-number --search-zip")
  ;; ⚠️ Windows: find.exe 冲突, 用 fd 替代
  (setq consult-find-args "fd --color=never --full-path"))

;; ---- Marginalia: 补全候选项的丰富注解 ----
(use-package marginalia
  :ensure t
  :init (marginalia-mode))

;; ---- Embark: 上下文操作 (右键菜单概念) ----
(use-package embark
  :ensure t
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)))

(use-package embark-consult
  :ensure t
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; ---- 历史持久化 (Vertico 的关键伴侣) ----
(use-package savehist
  :init (savehist-mode))
```

**⚠️ Windows 外部依赖**: `consult-ripgrep` 需要 ripgrep (`rg.exe`). 安装方式: `winget install BurntSushi.ripgrep.MSVC` 或 `scoop install ripgrep`. `consult-find` 建议用 fd (`winget install sharkdp.fd`). 安装后在 Emacs 中验证: `M-: (executable-find "rg")`.

**与 org-roam 的集成**: org-roam 的 `org-roam-node-find` 和 `org-roam-node-insert` 使用标准 completing-read, Vertico **自动接管**无需配置. 全文搜索笔记库的自定义命令:

```elisp
(defun my/org-roam-rg-search ()
  "用 consult-ripgrep 搜索 org-roam 目录."
  (interactive)
  (consult-ripgrep org-roam-directory))
```

---

## 第六步: Org-mode 大纲编辑器核心配置

Org-mode 内置于 Emacs, 是整个 PKM 系统的基础层. 以下配置专注于 **大纲优先 (outliner-first)** 的工作流:

```elisp
(use-package org
  :ensure nil  ; 内置
  :config
  ;; 视觉缩进 (不修改文件, 仅显示效果)
  (setq org-startup-indented t
        org-indent-indentation-per-level 2)

  ;; 启动时显示到二级标题
  (setq org-startup-folded 'content)

  ;; 隐藏多余的星号
  (setq org-hide-leading-stars t)

  ;; 折叠符号
  (setq org-ellipsis " ⤵")  ; 替代品: " ▼" " …"

  ;; 编辑行为
  (setq org-return-follows-link t
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-catch-invisible-edits 'show-and-error
        org-pretty-entities t)

  ;; 日志: 完成任务时记录时间戳
  (setq org-log-done 'time
        org-log-into-drawer t)

  ;; TODO 关键词
  (setq org-todo-keywords
        '((sequence "TODO(t)" "IN-PROGRESS(i)" "WAITING(w@/!)"
                    "|" "DONE(d!)" "CANCELLED(c@)")))

  ;; Refile: 跨文件移动标题
  (setq org-refile-targets '((nil :maxlevel . 3)
                              (org-agenda-files :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

  ;; 标签不做列对齐 (配合 org-modern)
  (setq org-auto-align-tags nil
        org-tags-column 0))
```

### org-modern 视觉增强

**org-modern** (https://github.com/minad/org-modern) 是 2025 年的明确赢家, 在 GNU ELPA 上由 Daniel Mendler 维护. 它使用 text properties 技术 (比 org-superstar 的 character composition 更高效), 覆盖标题, 关键词, 表格, 代码块, 时间戳, 标签, 优先级的全方位美化. org-superstar 已进入维护模式, 不再添加新功能.

```elisp
(use-package org-modern
  :ensure t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :config
  (setq org-modern-star '("◉" "○" "◈" "◇" "⁕")
        org-modern-table nil))       ; 如使用 valign 则禁用表格样式
```

---

## 第七步: Org-roam PKM 核心引擎

### 基础配置与 SQLite

**⚠️ 头号 Windows 痛点已解决**: Emacs 29+ 内置 SQLite 支持. org-roam 自动检测 `(sqlite-available-p)` 返回 `t` 时使用内置 SQLite, 无需编译 emacsql-sqlite.exe, 无需 MSYS2 中的 gcc. 这是选择 Emacs 29+ 的最重要理由之一.

如果 `(sqlite-available-p)` 返回 `nil`, 说明你的 Emacs 二进制未包含 SQLite, 需要更换构建版本. 参考 nobiot 的 Zero-to-Emacs-and-Org-roam 指南 (https://github.com/nobiot/Zero-to-Emacs-and-Org-roam).

```elisp
(use-package org-roam
  :ensure t
  :custom
  (org-roam-directory (file-truename "~/org-roam/"))
  (org-roam-db-location
   (expand-file-name "org-roam.db" (file-truename "~/org-roam/")))
  (org-roam-completion-everywhere t)
  (org-roam-node-display-template
   (concat "${title:*} " (propertize "${tags:10}" 'face 'org-tag)))

  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n j" . org-roam-dailies-capture-today))

  :config
  (org-roam-db-autosync-mode)

  ;; 反向链接 buffer 显示在右侧
  (add-to-list 'display-buffer-alist
               '("\\*org-roam\\*"
                 (display-buffer-in-direction)
                 (direction . right)
                 (window-width . 0.33)
                 (window-height . fit-window-to-buffer))))
```

### 节点类型: 文件级 vs 标题级

org-roam v2 中, **任何带有 `:ID:` 属性的文件或标题都是节点**. 文件级节点在文件顶部有 `#+title:` 和 `:PROPERTIES:` 抽屉; 标题级节点是带 `:ID:` 的任意 `*` 标题, 适合不值得独立成文件的子主题.

```elisp
;; 控制哪些标题成为节点 (排除特定标签)
(setq org-roam-db-node-include-function
      (lambda ()
        (not (member "ATTACH" (org-get-tags)))))

;; ID 生成方法
(setq org-id-method 'ts
      org-id-ts-format "%Y%m%dT%H%M%S")
```

### Capture 模板设计

```elisp
(setq org-roam-capture-templates
      '(;; 默认笔记
        ("d" "默认" plain "%?"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: \n")
         :unnarrowed t)

        ;; 文献笔记 (学术研究用)
        ("l" "文献笔记" plain "%?"
         :target (file+head "lit/%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: :literature:\n\n* 核心观点\n\n* 方法论\n\n* 与我的研究的关联\n\n* 笔记\n")
         :unnarrowed t)

        ;; 概念笔记
        ("c" "概念" plain "%?"
         :target (file+head "concepts/%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: :concept:\n\n* 定义\n\n* 相关概念\n\n* 笔记\n")
         :unnarrowed t)

        ;; 闪念笔记 (快速捕获)
        ("f" "闪念" plain "%?"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: :fleeting:\n")
         :immediate-finish t :unnarrowed t)))
```

**模板语法要点**: `${title}` 展开为用户输入的标题, `${slug}` 是 URL 友好版本, `%?` 是光标位置, `%^{Prompt}` 创建交互提示. `:target` 是 org-roam 模板的必需项, 类型有 `file+head`, `file+olp`, `node`.

### Dailies 日记系统

```elisp
(setq org-roam-dailies-directory "daily/")

(setq org-roam-dailies-capture-templates
      '(("d" "默认" entry "* %<%H:%M> %?"
         :target (file+head "%<%Y-%m-%d>.org"
                            "#+title: %<%Y-%m-%d>\n#+filetags: :daily:\n"))
        ("t" "任务" entry "* TODO %?\nSCHEDULED: %t\n"
         :target (file+head+olp "%<%Y-%m-%d>.org"
                                "#+title: %<%Y-%m-%d>\n"
                                ("任务")))
        ("j" "日志" entry "* %<%H:%M> 日志\n%?\n"
         :target (file+head+olp "%<%Y-%m-%d>.org"
                                "#+title: %<%Y-%m-%d>\n"
                                ("日志")))))
```

### org-roam-ui 图谱可视化

org-roam-ui (https://github.com/org-roam/org-roam-ui) 是浏览器端的交互式图谱, 在本地启动 HTTP 服务器. **Windows 上无特殊问题**.

```elisp
(use-package org-roam-ui
  :ensure t
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t
        org-roam-ui-open-on-start t))
;; 用法: M-x org-roam-ui-mode → 自动打开浏览器访问 http://127.0.0.1:35901/
```

### 推荐目录结构

```
~/org-roam/
├── daily/                          # 日记 (org-roam-dailies)
├── lit/                            # 文献笔记
├── concepts/                       # 概念笔记
├── 20240115120000-some-topic.org   # 默认/闪念笔记 (扁平存放)
├── ...
└── org-roam.db                     # SQLite 数据库
```

**社区共识是偏向扁平结构**, 因为 org-roam 使用 ID 而非文件路径进行链接, 搜索界面显示标题而非路径, `#+filetags:` 比文件夹更灵活. 只为日记和文献笔记保留子目录即可.

---

## 第八步: PKM 扩展三件套

### org-transclusion -- 内容嵌入层

org-transclusion (https://github.com/nobiot/org-transclusion) 实现跨文件的 **实时内容嵌入**, 类似 Obsidian 的 `![[]]` 嵌入语法. 文件系统只存储 `#+transclude:` 关键字链接, 不复制内容. 安装源: **GNU ELPA** (稳定, FSF 版权), 当前版本 1.4.0. **Windows 无特殊问题** (纯 Elisp).

```elisp
(use-package org-transclusion
  :after org
  :bind (("C-c t a" . org-transclusion-add)
         ("C-c t t" . org-transclusion-mode)
         ("C-c t m" . org-transclusion-transient-menu))
  :config
  (add-to-list 'org-transclusion-extensions 'org-transclusion-indent-mode)
  (require 'org-transclusion-indent-mode)
  ;; ⚠️ 让 transclusion 链接注册为 org-roam 反向链接
  (with-eval-after-load 'org-roam
    (setq org-roam-db-extra-links-exclude-keys
          (remove "transclude" org-roam-db-extra-links-exclude-keys))))
```

嵌入 org-roam 节点的语法:

```org
#+transclude: [[id:20240115T120000][某个概念]] :only-contents
#+transclude: [[id:20240115T120000][某个概念]] :level 2 :exclude-elements (property-drawer)
#+transclude: [[file:~/org-roam/lit/some-paper.org::*方法论]]
```

**性能注意**: 单个 buffer 中有数十个 transclusion 时, `org-transclusion-add-all` 可能出现可感知的延迟. 对非关键嵌入使用 `:disable-auto` 标记, 需要时手动添加.

### org-ql -- 查询检索层

org-ql (https://github.com/alphapapa/org-ql) 提供类似 SQL 的查询语言, 用于跨文件搜索 org 条目. 安装源: **MELPA**, 约 **1600 stars**, 成熟度高但仍 pre-1.0.

```elisp
(use-package org-ql
  :ensure t
  :after org)
```

查询语法示例:

```elisp
;; 查找所有未完成的高优先级任务
(org-ql-search (org-agenda-files)
  '(and (todo "TODO") (priority "A")))

;; 在 org-roam 文件中查找包含特定标签的条目
(org-ql-search (directory-files-recursively org-roam-directory "\\.org$")
  '(and (tags "concept") (heading "neural")))

;; 查找过去 7 天修改的条目
(org-ql-search (org-agenda-files)
  '(ts :from -7 :to today))
```

**⚠️ 性能注意**: org-ql 需要打开并解析每个 org 文件, 当 org-roam 库有 **2000+ 文件**时初次查询会很慢. 替代方案: `org-roam-ql` (https://github.com/ahmed-shariff/org-roam-ql) 直接查询 org-roam 的 SQLite 数据库, 速度快得多. **Windows 已知问题**: Issue #426 报告了 dash 依赖版本导致的字节编译错误, 确保 `dash` 是最新版本即可.

### org-supertag -- 结构化标签层 (实验性)

org-supertag (https://github.com/yibie/org-supertag) 实现类似 Tana/Logseq 的行为驱动标签系统: 每个 "supertag" 可携带结构化字段, 自动为标题添加元数据模式.

**⚠️ 关键评估**: 这是一个 **实验性项目**, 从 2024 年 12 月的 v0.0.2 到 2025 年已迭代到 v5.3.0, 经历了多次架构重写. **不在 MELPA 上**, 只能从 GitHub 安装. API 频繁变更, 文档仍在完善中. 如果你的工作流对稳定性要求高, 建议暂时观望; 如果愿意尝鲜, 安装方式:

```elisp
;; 需要 straight.el 或 package-vc-install
(package-vc-install "https://github.com/yibie/org-supertag")

(use-package org-supertag
  :after org
  :config
  (org-supertag-setup))
```

与 org-roam 互补而非竞争: org-roam 管链接图谱, org-supertag 管结构化元数据.

---

## 第九步: 中英文混排字体与主题

### set-fontset-font + face-font-rescale-alist 组合方案

这两个机制应该 **同时使用**: `set-fontset-font` 指定 CJK 使用哪个字体, `face-font-rescale-alist` 调整该字体的缩放比例使中英文视觉高度一致.

```elisp
(defun my/setup-fonts ()
  "配置中英文混合字体."
  (when (display-graphic-p)
    ;; 英文字体
    (set-face-attribute 'default nil
                        :family "Cascadia Code"
                        :height 130)  ; 13pt

    ;; 中文字体: 为 han, kana, symbol, cjk-misc, bopomofo 指定字体
    (dolist (charset '(kana han symbol cjk-misc bopomofo))
      (set-fontset-font t charset
                        (font-spec :family "LXGW WenKai Mono")))

    ;; 缩放中文字体使其与英文对齐
    (setq face-font-rescale-alist
          '(("LXGW WenKai Mono" . 1.1)))))

;; 处理 daemon 模式
(if (daemonp)
    (add-hook 'after-make-frame-functions
              (lambda (frame)
                (with-selected-frame frame (my/setup-fonts))))
  (my/setup-fonts))
```

**推荐字体组合**:

- **最佳对齐**: Iosevka + Sarasa Mono SC (更纱黑体). Sarasa 专门设计为 1 个 CJK 字符 = 2 个拉丁字符, rescale 系数可设为 1.0.
- **最佳美观**: Cascadia Code + LXGW WenKai Mono (霞鹜文楷). 中文 Emacs 社区极其流行. Nerd Font 版本: https://github.com/Yikai-Liao/LxgwWenKaiNerdFont
- **Windows 自带**: Consolas + Microsoft YaHei (微软雅黑). 零安装成本的基线方案.

**精确像素对齐**: 如果需要 org 表格中的完美中英文对齐, 使用 cnfonts (https://github.com/tumashu/cnfonts, MELPA) 或 valign (https://github.com/casouri/valign, MELPA):

```elisp
;; valign: 用 overlay 实现可变宽度字体下的表格对齐
(use-package valign
  :ensure t
  :hook (org-mode . valign-mode))
```

**⚠️ Windows 字体提示**: 用 `M-: (cl-prettyprint (font-family-list))` 查看所有可用字体; 用 `C-u C-x =` (`describe-char`) 检查光标处字符实际使用的字体.

### doom-themes + doom-modeline

两个包均可独立于 Doom Emacs 使用, 安装源: **MELPA**.

```elisp
(use-package doom-themes
  :ensure t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t)           ; 67+ 主题可选
  (doom-themes-visual-bell-config)   ; 错误时闪烁 modeline
  (doom-themes-org-config))          ; 改进 org 字体渲染

(use-package nerd-icons
  :ensure t)
;; ⚠️ Windows: M-x nerd-icons-install-fonts 下载字体后需手动安装
;; (右键 .ttf → "安装" 或 "为所有用户安装")

(use-package doom-modeline
  :ensure t
  :init (doom-modeline-mode 1)
  :custom
  (doom-modeline-height 25)
  (doom-modeline-bar-width 4)
  (doom-modeline-icon t)
  (doom-modeline-buffer-file-name-style 'auto)
  (doom-modeline-project-detection 'project))
```

热门主题: `doom-one` (旗舰暗色), `doom-dracula`, `doom-gruvbox`, `doom-nord`, `doom-tokyo-night`.

---

## 第十步: 未来扩展点 (记录但暂不实现)

以下扩展按优先级排列, 在基础 PKM 系统稳定运行后逐步添加:

**org-agenda (任务管理)**: 内置于 org-mode. 设置 `org-agenda-files` 指向你的 org 文件目录, 配合 `org-agenda-custom-commands` 定义自定义视图. 与 org-roam 互补 -- 在 roam 笔记中使用 TODO 关键词, 它们会出现在 agenda 视图中. 推荐搭配 org-super-agenda (https://github.com/alphapapa/org-super-agenda) 做分组.

**citar + Zotero (学术引用)**: 现代方案是 citar (https://github.com/emacs-citar/citar) + Zotero 的 Better BibTeX 插件. BBT 自动导出 `.bib` 文件, citar 通过 org-cite (Org 9.5+ 内置) 读取. citar-org-roam 包打通引用与笔记. 工作链路: **Zotero → BBT → .bib → citar → org-cite → org-roam 文献笔记**.

```elisp
;; 未来添加
(use-package citar
  :custom
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)
  (citar-bibliography '("~/org/references.bib")))
```

**org-babel (代码执行)**: 在 org 文件中执行 Python/R/Julia 代码块, 支持会话和内联结果. 配置 `org-babel-load-languages` 加载对应语言. Python 开箱即用; R 需要 ESS 包; Julia 支持历史上较脆弱, 考虑用 emacs-jupyter + Julia kernel. **⚠️ Windows: 确保 python, R, julia 可执行文件在 PATH 中.**

**magit (Git)**: Emacs 中最优秀的 Git 界面 (https://magit.vc/). `M-x magit-status` 一键打开. evil-collection 已自动提供 Evil 键绑定. **⚠️ Windows: 大仓库可能偏慢, 可设置 `magit-git-executable` 为 git.exe 完整路径.**

**org-noter (PDF 标注)**: 推荐使用 Codeberg 维护分支 (https://codeberg.org/PeterMao/org-noter), 支持 org-roam 集成. 依赖 pdf-tools 做 PDF 渲染. **⚠️ Windows: pdf-tools 需要编译 epdfinfo, 可通过 MSYS2 或 Chocolatey 安装依赖.**

---

## 所有包速查表

| 包名 | 安装源 | 用途 | Windows 注意 |
|------|--------|------|-------------|
| evil | MELPA | Vim 模态编辑 | 无 |
| evil-collection | MELPA | 100+ 模式的 Evil 绑定 | 无 |
| evil-org | MELPA | Org + Evil 粘合 | 无 |
| general.el | MELPA | Leader key 框架 | 无 |
| which-key | GNU ELPA | 按键提示 | 无 |
| vertico | GNU ELPA | 垂直补全 UI | 无 |
| orderless | GNU ELPA | 模糊匹配 | 无 |
| consult | GNU ELPA | 增强搜索 | 需 rg, fd |
| marginalia | GNU ELPA | 补全注解 | 无 |
| embark | GNU ELPA | 上下文操作 | 无 |
| org-modern | GNU ELPA | Org 视觉美化 | 无 |
| org-roam | MELPA | Zettelkasten 笔记 | 需 SQLite (Emacs 29+) |
| org-roam-ui | MELPA | 图谱可视化 | 无 |
| org-transclusion | GNU ELPA | 内容嵌入 | 无 |
| org-ql | MELPA | 查询语言 | dash 版本 |
| org-supertag | GitHub | 结构化标签 | 无 (实验性) |
| doom-themes | MELPA | 主题包 | 无 |
| doom-modeline | MELPA | 底栏 | 需手动装字体 |
| nerd-icons | MELPA | 图标 | 需手动装字体 |
| cnfonts | MELPA | 中英字体对齐 | 无 |
| valign | MELPA | 表格像素对齐 | 无 |

---

## Windows 踩坑清单总览

1. **Native-comp**: GNU FTP 官方包不含. 使用 MSYS2 安装或社区构建, 并确保 libgccjit 在 PATH 中.
2. **SQLite**: Emacs 29+ 内置. 务必验证 `(sqlite-available-p)` 返回 `t`, 否则 org-roam 无法运行.
3. **HOME 目录**: 必须手动设置 HOME 环境变量, 否则 Emacs 可能将配置放在 `%APPDATA%` 或 `C:\`.
4. **进程性能**: 设置 `read-process-output-max` 为 1MB, `w32-pipe-read-delay` 为 0. LSP 和 magit 对此敏感.
5. **ripgrep/fd**: consult-ripgrep 和 consult-find 的必要外部依赖, 需单独安装并加入 PATH.
6. **find.exe 冲突**: Windows 自带的 `find.exe` 与 Unix find 不同, consult-find 应配置为使用 fd.
7. **Nerd Icons 字体**: `nerd-icons-install-fonts` 仅下载不自动安装, 需手动右键安装 .ttf 文件.
8. **路径分隔符**: elisp 中始终使用正斜杠 `/`. 对 org-roam-directory 使用 `file-truename` 处理符号链接.
9. **编码**: 统一设置 `(prefer-coding-system 'utf-8-unix)` 避免 CRLF 问题.
10. **Emacs server**: Windows 不支持 Unix domain socket, 如需 emacsclient (org-protocol 等) 需设置 `(setq server-use-tcp t)`.

---

## 从 Obsidian 迁移的思维转换

org-roam 与 Obsidian 的核心差异不在功能而在范式. Obsidian 用 `[[wikilink]]` 做文件名链接, org-roam 用 **UUID-based ID 链接** -- 重命名文件不会断链. org-roam 的节点可以是文件也可以是标题, 粒度更细. Obsidian 的 `![[embed]]` 对应 org-transclusion 的 `#+transclude:`. Obsidian 的标签是纯文本, org-supertag 尝试让标签携带结构化字段. 最关键的优势是 org-mode 的原生大纲编辑能力 -- 折叠/展开, 标题拖拽, refile, 内联代码执行 -- 这些是 Obsidian 的 Markdown 无法企及的.

**建议保留 Obsidian 作为只读参考**, 用 org-roam 建立新的笔记库, 逐步将重要笔记以手动方式迁移 (复制内容, 重建链接), 而非尝试自动化批量转换. 知识管理系统的价值在于使用过程中的思考, 而非数据本身的搬运.