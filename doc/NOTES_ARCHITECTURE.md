# orgseq 笔记库架构

## 文档目的

本文档定义 `~/NoteHQ/` 笔记库的物理结构、tag 体系思路、capture 模板、dashboard 设计与初始化规范，作为 orgseq 配置开发与数据初始化的依据。

这段设计文档基于一个核心承诺：**笔记系统应该跟随使用情况自然生长，而不是预先规划完整 schema**。本文档只提供最小起点 —— 2 个示例 tag、2 个示例 dashboard、几条占位符笔记 —— 用户在真实使用中按需扩展。任何看起来"详尽完备"的初始配置都应该被视为反模式。

---

## 一、设计原则

笔记库由两条原则支撑：

**碎片层与产出层物理分离**。原子笔记进入 `Roam/` 扁平目录，由 `org-roam` 负责索引和反向链接；正式产出物进入 类 PARA 层级目录，文件结构反映可交付物的内在组织。两层通过 `id:` 链接和 `org-transclusion` 通信，但不互相污染。这避免了"长文档拖慢笔记数据库"和"碎片想法淹没在项目目录里"两个常见问题。

**tag 承担分类职责，目录不承担分类职责**。除了 `daily/` 和 `dashboards/` 两个特殊子目录，以及AI生成的思考层（如 concept 等），`Roam/` 完全扁平。每条笔记落在 Roam 的 capture 子目录，文件名只是时间戳前缀的 slug。分类、检索、聚合全部由 supertag 完成。这解决了"每写一条新笔记都要决定放哪个文件夹"的认知摩擦。

---

## 二、日常工作流

整个架构服务于以下 4 阶段工作流。文档其余部分的所有具体决策都应该回到这个工作流验证。

### 阶段 1：启动 — GTD 主导今日工作

打开 Emacs 后，第一个动作是 `SPC a d` 进入 GTD Dashboard，确认今天要推进的项目和具体任务。GTD 系统决定**"今天做什么"**，笔记系统不参与这个决策。

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

```elisp
(setq org-roam-directory (expand-file-name "Roam/" "~/NoteHQ/"))
;; 严格只把 Roam/ 作为 org-roam 索引范围
;; PARA 三层不被 org-roam 数据库扫描

(setq org-agenda-files
      (list (expand-file-name "Roam/" "~/NoteHQ/")
            (expand-file-name "Outputs/" "~/NoteHQ/")
            (expand-file-name "Practice/" "~/NoteHQ/")))
;; agenda 跨 Roam 和 PARA,但不扫 Library 和 Archives
;; daily 笔记里的 TODO/PROJECT 通过这个设置进入 GTD 视图
```

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
;;; 编辑后用 SPC n m r 重载,无需重启 Emacs。

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
5. `SPC n m r` 重载

可能的扩展方向：临床工作的 client/session、教学的 course/lesson_prep/reflection、学生指导的 student/meeting、研究工作的 hypothesis/experiment/concept、健康追踪的 health_log。**但具体怎么定义字段、定义多少字段，请等到你真的写过 5 次再决定**。

---

## 五、Capture 模板

修改 `lisp/init-roam.el` 中的 `org-roam-capture-templates` 为下面的最小集合：

```elisp
(setq org-roam-capture-templates
      '(;; 默认:无 tag 的纯笔记。覆盖 80% 场景。
        ("d" "default" plain "%?"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n")
         :unnarrowed t)

        ;; 示例:带 tag 的笔记。其他 tag 类型按这个模式增加。
        ("r" "reading" plain
         "* TL;DR\n%?\n* Key points\n* My commentary\n"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                            "#+title: ${title}\n#+filetags: :reading:\n")
         :unnarrowed t)))
```

**起步只需要 default 模板就够**。当你决定为某类笔记建立独立的 supertag（例如 `lesson_prep`、`session`、`hypothesis`），同时在这里加一个对应的 capture 模板，模板正文用 org 标题骨架引导你思考关键问题。

模板正文的设计原则：标题骨架而非字段。字段交给 supertag 处理，模板只负责让你看到笔记应该展开的几个方向。

---

## 六、`lisp/init-supertag.el` 模块

```elisp
;;; init-supertag.el --- Tana-style structured tags via org-supertag -*- lexical-binding: t; -*-

;;; Commentary:
;; org-supertag 提供 Tana 式 tag + 字段 + dashboard 视图。
;; 与 init-roam.el 协作:capture 模板定义在 init-roam.el,
;; tag schema 定义在 ~/NoteHQ/Roam/supertag-schema.el。

;;; Code:

(use-package org-supertag
  :vc (:url "https://github.com/yibie/org-supertag" :rev :newest)
  :after org-roam
  :init
  (setq org-supertag-data-directory
        (expand-file-name "supertag-data/" user-emacs-directory))
  :config
  (let ((schema-file (expand-file-name "supertag-schema.el" "~/NoteHQ/Roam/")))
    (when (file-exists-p schema-file)
      (load schema-file :noerror :nomessage)))
  (org-supertag-setup))

;; ================================================================
;; 路径常量
;; ================================================================

(defconst orgseq/notehq-dir     (expand-file-name "~/NoteHQ/"))
(defconst orgseq/roam-dir       (expand-file-name "Roam/"     orgseq/notehq-dir))
(defconst orgseq/outputs-dir    (expand-file-name "Outputs/"  orgseq/notehq-dir))
(defconst orgseq/practice-dir   (expand-file-name "Practice/" orgseq/notehq-dir))
(defconst orgseq/library-dir    (expand-file-name "Library/"  orgseq/notehq-dir))
(defconst orgseq/archives-dir   (expand-file-name "Archives/" orgseq/notehq-dir))
(defconst orgseq/dashboards-dir (expand-file-name "dashboards/" orgseq/roam-dir))
(defconst orgseq/schema-file    (expand-file-name "supertag-schema.el" orgseq/roam-dir))

;; ================================================================
;; Schema 编辑与重载
;; ================================================================

(defun orgseq/edit-supertag-schema ()
  "Open the supertag schema definition file."
  (interactive)
  (find-file orgseq/schema-file))

(defun orgseq/reload-supertag-schema ()
  "Reload tag definitions without restarting Emacs."
  (interactive)
  (load orgseq/schema-file)
  (message "Supertag schema reloaded from %s" orgseq/schema-file))

;; ================================================================
;; Tag 与字段快速操作
;; ================================================================

(defun orgseq/supertag-quick-action ()
  "Context-aware popup for tag and field operations on the current node."
  (interactive)
  (require 'org-supertag)
  (let* ((node-id (org-id-get-create))
         (tags (ignore-errors (org-supertag-node-get-tags node-id))))
    (if (null tags)
        (call-interactively #'org-supertag-tag-add-tag)
      (let ((choice (completing-read
                     "Action: "
                     `("[+] Add another tag"
                       "[—] Remove a tag"
                       ,@(mapcar (lambda (tag) (format "[edit] %s fields" tag)) tags)
                       ,@(mapcar (lambda (tag) (format "[goto] linked from %s" tag)) tags)))))
        (cond
         ((string-prefix-p "[+]"   choice) (call-interactively #'org-supertag-tag-add-tag))
         ((string-prefix-p "[—]"   choice) (call-interactively #'org-supertag-tag-remove))
         ((string-prefix-p "[edit]" choice) (call-interactively #'org-supertag-node-edit-field))
         ((string-prefix-p "[goto]" choice) (call-interactively #'org-supertag-node-follow-ref)))))))

;; ================================================================
;; Dashboard 入口
;; ================================================================

(defun orgseq/open-dashboard (name)
  "Open dashboard NAME (without .org) and refresh all dynamic blocks."
  (find-file (expand-file-name (concat name ".org") orgseq/dashboards-dir))
  (when (fboundp 'org-update-all-dblocks)
    (ignore-errors (org-update-all-dblocks))))

(defun orgseq/dash-index   () (interactive) (orgseq/open-dashboard "index"))
(defun orgseq/dash-review  () (interactive) (orgseq/open-dashboard "weekly-review"))
(defun orgseq/dash-reading () (interactive) (orgseq/open-dashboard "reading"))

;; ================================================================
;; PARA 层导航
;; ================================================================

(defun orgseq/find-in-outputs ()
  (interactive)
  (let ((default-directory orgseq/outputs-dir))
    (call-interactively #'find-file)))

(defun orgseq/find-in-practice ()
  (interactive)
  (let ((default-directory orgseq/practice-dir))
    (call-interactively #'find-file)))

(defun orgseq/find-in-library ()
  (interactive)
  (let ((default-directory orgseq/library-dir))
    (call-interactively #'find-file)))

(defun orgseq/ripgrep-notehq ()
  "Ripgrep across the entire NoteHQ (Roam + PARA layers)."
  (interactive)
  (consult-ripgrep orgseq/notehq-dir))

;; ================================================================
;; Leader key 绑定 (与 init-roam.el 中 SPC n 不冲突)
;; init-roam.el 已占用: f c i b s g a r d t q
;; 本模块新增:        p (supertag) v (views) m (meta)
;; SPC P 顶层为 PARA 导航
;; ================================================================

(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual)
   :prefix "SPC"

   ;; --- 顶层 PARA 导航 (大写 P,与 SPC p project 区分) ---
   "P"   '(:ignore t :which-key "PARA")
   "P o" '(orgseq/find-in-outputs  :which-key "find in Outputs")
   "P p" '(orgseq/find-in-practice :which-key "find in Practice")
   "P l" '(orgseq/find-in-library  :which-key "find in Library")
   "P g" '(orgseq/ripgrep-notehq   :which-key "ripgrep all NoteHQ")

   ;; --- supertag 操作 ---
   "n p"   '(:ignore t :which-key "supertag")
   "n p p" '(orgseq/supertag-quick-action  :which-key "quick action")
   "n p a" '(org-supertag-tag-add-tag      :which-key "add tag")
   "n p e" '(org-supertag-node-edit-field  :which-key "edit field")
   "n p x" '(org-supertag-tag-remove       :which-key "remove tag")
   "n p l" '(org-supertag-node-list-fields :which-key "list fields")
   "n p j" '(org-supertag-node-follow-ref  :which-key "jump linked")

   ;; --- views / dashboards ---
   "n v"   '(:ignore t :which-key "views")
   "n v v" '(orgseq/dash-index    :which-key "dashboard index")
   "n v w" '(orgseq/dash-review   :which-key "weekly review")
   "n v r" '(orgseq/dash-reading  :which-key "reading queue")

   ;; --- meta / schema 维护 ---
   "n m"   '(:ignore t :which-key "meta/schema")
   "n m t" '(orgseq/edit-supertag-schema   :which-key "edit tag schema")
   "n m r" '(orgseq/reload-supertag-schema :which-key "reload schema")
   "n m d" '(orgseq/dash-index             :which-key "dashboard index")))

(provide 'init-supertag)
;;; init-supertag.el ends here
```

在 `init.el` 中追加：

```elisp
(require 'init-supertag)  ;; 紧跟 init-pkm.el 之后
```

新增 dashboard 文件后，记得在 `init-supertag.el` 中加对应的 `orgseq/dash-xxx` 函数和 `n v X` 绑定。

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
  - ~SPC n m r~ 重载 schema
  - ~SPC n c~  新建笔记 (按类型选模板)
  - ~SPC n p p~ 当前节点 tag/字段操作
  - ~SPC P o/p/l~ PARA 导航 (Outputs/Practice/Library)

* 增加新 dashboard 的步骤
  1. 在本目录新建 xxx.org 文件,写若干 #+BEGIN: supertag-query 块
  2. 在 lisp/init-supertag.el 加 orgseq/dash-xxx 函数和 leader 绑定
  3. 在本文件加链接
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

`scripts/bootstrap-notes.sh`（Linux/macOS）：

```bash
#!/usr/bin/env bash
# bootstrap-notes.sh — 初始化 ~/NoteHQ/ 笔记库结构
set -e

NOTEHQ="${HOME}/NoteHQ"

echo "==> Creating directory structure under ${NOTEHQ}/"
mkdir -p "${NOTEHQ}/Roam/daily"
mkdir -p "${NOTEHQ}/Roam/dashboards"
mkdir -p "${NOTEHQ}/Outputs/_template"
mkdir -p "${NOTEHQ}/Practice/_template"
mkdir -p "${NOTEHQ}/Library/bibliography"
mkdir -p "${NOTEHQ}/Library/datasets"
mkdir -p "${NOTEHQ}/Library/snippets"
mkdir -p "${NOTEHQ}/Library/references"
mkdir -p "${NOTEHQ}/Library/pdfs"
mkdir -p "${NOTEHQ}/Archives"

echo "==> Flattening existing Roam subdirectories (lit/, concepts/) if present"
cd "${NOTEHQ}/Roam"
shopt -s nullglob
if [ -d "lit" ]; then
  for f in lit/*.org; do mv "$f" .; done
  rmdir lit 2>/dev/null || echo "  (lit/ not empty, skipping rmdir)"
fi
if [ -d "concepts" ]; then
  for f in concepts/*.org; do mv "$f" .; done
  rmdir concepts 2>/dev/null || echo "  (concepts/ not empty, skipping rmdir)"
fi

echo "==> Done. Next:"
echo "  1. Drop supertag-schema.el into ~/NoteHQ/Roam/ (see docs §4)"
echo "  2. Drop dashboard files into ~/NoteHQ/Roam/dashboards/ (see docs §7)"
echo "  3. Drop seed example notes (see docs §8)"
echo "  4. Update lisp/init-roam.el capture templates (see docs §5)"
echo "  5. Add lisp/init-supertag.el (see docs §6)"
echo "  6. (cd ${NOTEHQ} && git init && git add . && git commit -m 'initial structure')"
```

`scripts/bootstrap-notes.ps1`（Windows）：

```powershell
$NoteHQ = Join-Path $HOME "NoteHQ"

$dirs = @(
  "Roam\daily",
  "Roam\dashboards",
  "Outputs\_template",
  "Practice\_template",
  "Library\bibliography",
  "Library\datasets",
  "Library\snippets",
  "Library\references",
  "Library\pdfs",
  "Archives"
)

foreach ($d in $dirs) {
  $full = Join-Path $NoteHQ $d
  New-Item -ItemType Directory -Force -Path $full | Out-Null
}

$litDir = Join-Path $NoteHQ "Roam\lit"
if (Test-Path $litDir) {
  Get-ChildItem $litDir -Filter *.org | Move-Item -Destination (Join-Path $NoteHQ "Roam")
  if ((Get-ChildItem $litDir).Count -eq 0) { Remove-Item $litDir }
}
$conceptsDir = Join-Path $NoteHQ "Roam\concepts"
if (Test-Path $conceptsDir) {
  Get-ChildItem $conceptsDir -Filter *.org | Move-Item -Destination (Join-Path $NoteHQ "Roam")
  if ((Get-ChildItem $conceptsDir).Count -eq 0) { Remove-Item $conceptsDir }
}

Write-Host "Done. See NOTES_ARCHITECTURE.md sections 4-8 for files to drop in."
```

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

笔记系统不应该被预先设计完整，应该跟随使用情况自然演化。以下原则指导扩展决策。

**Schema 字段的添加门槛**。任何新字段都该回答一个**你已经反复需要查询但当前 schema 答不出来**的问题。不要预先添加"可能用得上"的字段——预留字段会带来录入摩擦却很少被填写。

**Schema 字段的删除门槛**。任何字段如果**两周内没填过 3 次**，立刻删除。已有数据中的孤立值不影响（org-supertag 容忍 schema 与数据不完全一致）。

**新 tag 的添加门槛**。当某类事情你已经用 default 模板记过 5 次以上，且发现它们有共同的结构，就为它建一个新 tag。**先用，再结构化**，不要反过来。

**Dashboard 的迭代节奏**。第一版 dashboard 只放 1-2 个查询，跑一周后看哪些查询你真的每天看，删掉不看的，添加缺失的。Dashboard 应该反映你**当前**的关注焦点，而不是一个一劳永逸的定义。

**PARA 子目录的创建时机**。Outputs 子目录应该有具体的交付时刻；Practice 子目录应该对应一个真实的长期角色。**不要为"未来可能做的事"提前建目录**，那只会让 Outputs 目录里堆满空壳。

**碎片晋升的判断**。一条 daily 流水值不值得提升为独立 Roam 节点？**判定问题：这个想法以后可能会在另一个完全不同的上下文里被引用吗？** 是 → 提升；否 → 留在 daily。一条 Roam 碎片值不值得晋升为 Practice 沉淀？**判定问题：我会主动维护和审阅它吗？** 是 → 晋升；否 → 留在 Roam。

**Schema 文件的版本控制**。`supertag-schema.el` 在 `Roam/` 内，跟笔记一起 git。每次重大改动前打 tag，方便回滚。重大改动包括：删除字段、删除 tag、修改 `:type`、修改 `:options`。
