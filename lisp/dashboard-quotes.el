;;; dashboard-quotes.el --- Quote list for init-dashboard.el -*- lexical-binding: t; -*-

;; This is a PURE DATA file.  It defines one variable, `my/dashboard-quotes',
;; which is consumed by `init-dashboard.el' to populate the dashboard footer.
;;
;; Keeping the quotes out of `init-dashboard.el' has two benefits:
;;
;;   1. Editing the quotes no longer churns init-dashboard.el in git.
;;      (Adding or tweaking a quote is a pure data change, not a code change.)
;;
;;   2. The "Tip: SPC ..." entries reference live keybindings.  When a
;;      leader key changes elsewhere in the config, you only need to scan
;;      this one file to find stale references, not wade through the
;;      dashboard module.
;;
;; Categories (separated by commented headers below):
;;   - Emacs self-deprecation
;;   - Org / PKM / GTD humor
;;   - Programming / nerd wisdom
;;   - Dark / existential
;;   - Classic wisdom
;;   - Emacs tips (org-seq-specific, reference live keybindings)
;;
;; When a leader-key change invalidates a tip below, update the tip here
;; rather than letting it rot.  The dashboard displays one random quote
;; per session, so a wrong tip can mislead users for months before being
;; noticed if left uncorrected.

(defvar my/dashboard-quotes
  '(;; ── Emacs self-deprecation ──
    "The one true editor, Emacs!"
    "Who the hell uses VIM anyway? Go Evil!"
    "While any text editor can save your files, only Emacs can save your soul."
    "Vi Vi Vi, the editor of the beast."
    "Welcome to the church of Emacs."
    "I showed you my source code, pls respond."
    "Emacs is a great operating system, lacking only a decent editor."
    "M-x butterfly"
    "Emacs started as a text editor. Then it got ideas."
    "There is no place like ~"
    "~ sweet ~"
    "Your .emacs.d is a lifestyle choice."
    "The strstrstrstrstruggle is real. — Emacs Pinky"
    "Escape-Meta-Alt-Control-Shift. That's all."
    "M-x doctor — cheaper than therapy since 1985."
    "Real programmers use cat > program.c. The rest of us use Emacs."
    "(setq my-life nil) ;; it happens"
    "My software never has bugs. It just develops random features."
    "It compiles. Ship it."
    "Emacs outshines all other editors in approximately the same way that the noonday sun does the stars."
    "Free as free speech, free as free Beer."

    ;; ── Org / PKM / GTD humor ──
    "Org-mode is for keeping notes, maintaining TODO lists, and avoiding actual work. — Everyone"
    "Your mind is for having ideas, not holding them. That's what org-capture is for."
    "I don't have a system. I have 400 TODO items in 37 org files."
    "NEXT → IN-PROGRESS → WAITING → Who am I kidding → SOMEDAY"
    "I came here to write notes and chew bubblegum… and I'm all out of bubblegum."
    "The Zettelkasten doesn't think for you. It just judges you, silently."
    "Tags are just labels for things you'll never search for again."
    "If it's not in org-roam, it didn't happen."
    "One does not simply close the org-agenda."

    ;; ── Programming / nerd wisdom ──
    "Talk is cheap. Show me the code. — Linus Torvalds"
    "First, solve the problem. Then, write the code. — John Johnson"
    "Make it work, make it right, make it fast. — Kent Beck"
    "A complex system that works evolved from a simple system that worked. — John Gall"
    "The best code is no code at all."
    "Dad, what are clouds made of? Linux servers, mostly."
    "There are only two hard things in CS: cache invalidation, naming things, and off-by-one errors."
    "It works on my machine. ¯\\_(ツ)_/¯"
    "// TODO: fix this later   — commit from 2019"

    ;; ── Dark / existential ──
    "Perfection is achieved not when there is nothing more to add, but nothing left to take away."
    "Any sufficiently advanced .emacs.d is indistinguishable from an operating system."
    "The unexamined config is not worth loading."
    "You are what you (eval-buffer)."

    ;; ── Classic wisdom ──
    "The only way to do great work is to love what you do. — Steve Jobs"
    "Simplicity is the ultimate sophistication. — Leonardo da Vinci"
    "The mind is not a vessel to be filled, but a fire to be kindled. — Plutarch"
    "We are what we repeatedly do. Excellence is not an act, but a habit. — Aristotle"
    "In the middle of difficulty lies opportunity. — Albert Einstein"
    "The unexamined life is not worth living. — Socrates"
    "Knowing is not enough; we must apply. — Goethe"
    "Any sufficiently advanced technology is indistinguishable from magic. — Arthur C. Clarke"
    "The best time to plant a tree was 20 years ago. The second best time is now. — Chinese Proverb"
    "Programs must be written for people to read. — Harold Abelson"
    "The tools we use have a profound effect on our thinking habits. — Edsger Dijkstra"
    "Zettelkasten is not a method of storage, but a method of thinking. — Niklas Luhmann"
    "Your mind is for having ideas, not holding them. — David Allen"

    ;; ── Emacs tips (org-seq specific, reference live keybindings) ──
    ;; NOTE: these reference actual SPC leader keys defined in init-evil.el.
    ;; If you change a binding there, update the corresponding tip here.
    "Tip: SPC SPC opens M-x — run any command by name."
    "Tip: SPC / searches the whole project with ripgrep."
    "Tip: SPC n f to find any org-roam note instantly."
    "Tip: SPC a d opens the GTD Dashboard with live task counts."
    "Tip: , q in org buffers opens a single-keypress state picker."
    "Tip: SPC n d d captures a daily note for today."
    "Tip: SPC i i sends the current buffer to your LLM."
    "Tip: SPC TAB switches to the last buffer you were in."
    "Tip: SPC l l opens the full three-column workspace layout."
    "Tip: C-o in Dired/Agenda/Info opens a Casual menu with all actions."
    "Tip: SPC t t lets you switch themes on the fly."
    "Tip: SPC n p a adds a supertag to the current heading."
    "Tip: SPC w m maximizes the current window. SPC w = rebalances all."
    "Tip: SPC s s searches the current buffer with consult-line."
    "Tip: SPC f r opens recent files — your most-used shortcut."
    "Tip: SPC n t a adds a transclusion link for live content embedding."
    "Tip: SPC a w opens the weekly review — check stuck projects."
    "Tip: , k i clocks into a task. , k o clocks out. , k r shows report."
    "Tip: SPC g g opens Magit status — the best Git interface ever made."
    "Tip: SPC i m opens the gptel menu — switch models, adjust params."
    "Tip: In vertico, C-j/C-k moves up/down. RET confirms."
    "Tip: SPC h f describes any function. SPC h v describes any variable."
    "Tip: SPC b d kills the current buffer. SPC b l opens ibuffer."
    "Tip: winner-mode is on — C-c <left> undoes window layout changes."
    "Tip: SPC e e evals the last sexp. SPC e b evals the whole buffer."
    "Tip: SPC ' toggles a terminal popup at the bottom."
    "Tip: SPC a f starts a Vitamin-R-style focus slice at point."
    "Tip: SPC a F opens the focus dashboard with colored timeline bars."
    "Tip: SPC o f opens dirvish, the modern dired-based file manager.")
  "Rotating footer quotes for the startup dashboard.
Mix of Emacs humor, PKM/GTD sayings, programming aphorisms, classic
wisdom, and org-seq-specific tips that reference live leader keys.
`init-dashboard.el' picks one at random per session and wraps it to
window width.")

(provide 'dashboard-quotes)
;;; dashboard-quotes.el ends here
