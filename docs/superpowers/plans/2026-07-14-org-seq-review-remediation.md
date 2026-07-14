# org-seq Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Resolve every actionable issue from the 2026-07-14 repository review while preserving org-seq's private-config decisions and existing public workflows.

**Architecture:** Keep the current module graph and package manager. Add narrow safety boundaries around destructive operations, convert implicit error states into explicit failures, centralize the remaining shared paths, and keep the required org-supertag compatibility adaptation auditable, version-gated, backed up, and tested.

**Tech Stack:** Emacs 30.2, Emacs Lisp/ERT, PowerShell 7, POSIX shell, package.el/package-vc, Pandoc integration.

## Global Constraints

- Preserve the current `init.el` load order and guarded module loader.
- Do not add dependencies, change public keybindings, deploy, commit, or push.
- Keep intentional personal choices: automatic updates, unconfirmed Babel execution, and unpinned Git packages.
- Use temporary directories for every test that writes files.
- Run `pwsh -NoLogo -NoProfile -File scripts/check.ps1` and strict deployed validation before completion.

---

### Task 1: Deployment And Conversion Safety

**Files:**
- Modify: `deploy.ps1`
- Modify: `deploy.sh`
- Modify: `scripts/check.ps1`
- Create: `scripts/test-deploy-safety.ps1`
- Modify: `lisp/init-markdown.el`
- Create: `scripts/test-init-markdown.el`

**Interfaces:**
- Produces: `Resolve-SafeDeploymentTarget`, `Test-Deployment` failure propagation, and atomic `my/markdown-convert-to-org` output replacement.

- [x] **Step 1: Write failing deployment safety tests**

Test a normal nested target plus filesystem root, home, and repository-root rejection. Assert that a failed verification result is not accepted as completion. Add the PowerShell test runner to `scripts/check.ps1`.

```powershell
$safe = Resolve-SafeDeploymentTarget -Path (Join-Path $TestDrive '.emacs.d')
Assert-Equal ([IO.Path]::GetFullPath($safe)) ([IO.Path]::GetFullPath((Join-Path $TestDrive '.emacs.d')))
Assert-Throws { Resolve-SafeDeploymentTarget -Path ([IO.Path]::GetPathRoot($TestDrive)) }
Assert-Throws { Resolve-SafeDeploymentTarget -Path $HOME }
Assert-Throws { Resolve-SafeDeploymentTarget -Path $ScriptDir }
```

- [x] **Step 2: Run the PowerShell test and verify RED**

Run: `pwsh -NoLogo -NoProfile -File scripts/test-deploy-safety.ps1`

Expected: fail because `Resolve-SafeDeploymentTarget` and verification result enforcement do not exist.

- [x] **Step 3: Implement guarded deployment**

Add `[CmdletBinding(SupportsShouldProcess)]`, canonical target resolution, dangerous-target rejection, and a single main guard:

```powershell
$Target = Resolve-SafeDeploymentTarget -Path $Target
if ($PSCmdlet.ShouldProcess($Target, 'Deploy org-seq configuration')) {
    Backup-ExistingConfig
    Deploy-Config
    Install-StartMenuShortcuts
    Test-Deployment
    Write-PostInstall
}
```

Make compile/start failures throw before the completion summary. Mirror root/home/repo rejection and nonzero verification propagation in `deploy.sh`.

- [x] **Step 4: Write failing Markdown overwrite tests**

Cover declining an existing target and Pandoc failure preserving the original file.

```elisp
(should-error (my/markdown-convert-to-org) :type 'user-error)
(should (equal (my/test-file-contents org-file) "original\n"))
```

- [x] **Step 5: Run Markdown tests and verify RED**

Run: `emacs --batch -Q -L . -L lisp -l scripts/test-init-markdown.el -f ert-run-tests-batch-and-exit`

Expected: overwrite-preservation tests fail against the direct Pandoc `-o` implementation.

- [x] **Step 6: Implement atomic conversion**

Prompt before replacing an existing `.org` file, render into a same-directory temporary file, rename only after exit code zero, and remove the temporary file in `unwind-protect`.

- [x] **Step 7: Run deployment and Markdown tests GREEN**

Run both focused test commands. Expected: exit zero, original output preserved on decline/failure.

---

### Task 2: Runtime Correctness And Path Consistency

**Files:**
- Modify: `lisp/init-roam.el`
- Modify: `lisp/init-python.el`
- Modify: `lisp/init-update.el`
- Modify: `lisp/init-workspace.el`
- Modify: `scripts/test-provenance.el`
- Create: `scripts/test-init-python.el`
- Create: `scripts/test-init-update.el`
- Create: `scripts/test-init-workspace.el`

**Interfaces:**
- Consumes: central path variables from `init-org.el`.
- Produces: `my/python--environment-root`; failed package updates signal errors and do not save timestamps; startup preserves an explicitly opened Daily buffer.

- [x] **Step 1: Write failing path and Python tests**

Assert `init-roam.el` contains no reconstructed `10_Outputs/` or `20_Practice/` paths. Test Windows and POSIX environment roots:

```elisp
(let ((system-type 'windows-nt))
  (should (equal (my/python--environment-root "C:/Users/me/miniconda3/python.exe")
                 "C:/Users/me/miniconda3/")))
```

- [x] **Step 2: Verify path/Python RED**

Run the two focused ERT files. Expected: hard-coded path and Windows parent-directory assertions fail.

- [x] **Step 3: Centralize paths and fix Python root calculation**

Forward-declare `my/outputs-dir` and `my/practice-dir` in `init-roam.el` and pass those variables to `org-mem-watch-dirs`. Use the Python executable directory itself as a Windows environment root and the parent of `bin/` on POSIX.

- [x] **Step 4: Write failing update-state tests**

Stub archive refresh failure and assert `my/update--do-upgrade` signals. Stub `my/update--save-time` and assert it is not called after an incomplete update.

- [x] **Step 5: Verify update RED, then implement explicit failure**

After all update attempts, signal one contextual error when the collected error list is non-empty. Leave timestamp writes after the successful return only.

- [x] **Step 6: Write failing explicit-Daily startup test**

Stub the current startup target as a historical Daily buffer. Assert startup keeps that buffer, opens the Daily sidebar, and never calls `my/daily-workspace-open` for Today.

- [x] **Step 7: Verify Workspace RED, then preserve the selected Daily buffer**

Close Treemacs, retain the existing buffer in the editor window, and open/refresh the sidebar without changing dates or creating content.

- [x] **Step 8: Run all Task 2 tests GREEN**

Run the four focused ERT files. Expected: all pass with no user NoteHQ writes.

---

### Task 3: Third-Party, Focus, And AI Boundaries

**Files:**
- Modify: `lisp/init-pkm.el`
- Modify: `lisp/init-ai.el`
- Modify: `packages/org-focus-timer/org-focus-timer.el`
- Modify: `packages/org-focus-timer/README.md`
- Modify: `scripts/check.ps1`
- Create: `scripts/test-init-pkm.el`
- Create: `scripts/test-init-ai.el`
- Create: `packages/org-focus-timer/test-org-focus-timer.el`
- Create: `patches/org-supertag-5.8.1-emacs-30.patch`
- Modify: `THIRD_PARTY.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: version-gated and reversible org-supertag compatibility patching, `org-focus-dashboard-start`, and confirmation before full-buffer remote AI submission.

- [x] **Step 1: Write failing org-supertag compatibility tests**

Use a temporary fake 5.8.1 package. Assert exact replacements, an external backup, atomic preservation on unsupported source, and rollback restoration.

- [x] **Step 2: Verify compatibility RED**

Run: `emacs --batch -Q -L . -L lisp -l scripts/test-init-pkm.el -f ert-run-tests-batch-and-exit`

Expected: existing patcher writes in place without the required backup/version/rollback behavior.

- [x] **Step 3: Implement governed compatibility patching**

Keep the required 5.8.1 adaptation but gate it by package version and exact source text. Back up originals under an ignored org-seq compatibility-backup directory, write through temporary files, expose a confirmation-based rollback command, record the patch file and provenance, and warn instead of touching unknown upstream versions.

- [x] **Step 4: Write failing Focus tests**

Assert Dashboard `s` invokes a standalone `org-focus-dashboard-start` command that selects a writable source buffer, and assert package source/README contain no org-seq leader keys.

- [x] **Step 5: Verify Focus RED, then implement the standalone command**

Add a source-buffer chooser, switch to the selected writable buffer, then invoke `org-focus-start`. Remove all `SPC ...` references from the standalone package.

- [x] **Step 6: Write failing AI privacy tests**

Assert active regions are returned without a prompt, full-buffer submission asks for confirmation by default, and refusal raises `user-error` without calling the backend.

- [x] **Step 7: Verify AI RED, then add the confirmation boundary**

Add `my/ai-confirm-full-buffer-send` and keep region-based commands unchanged. Full-buffer commands proceed only after explicit confirmation unless the user customizes the guard off.

- [x] **Step 8: Run all Task 3 tests GREEN**

Run the PKM, AI, and standalone Focus ERT files. Expected: all pass and no installed package source is touched by tests.

---

### Task 4: Documentation And Completion Audit

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `doc/NOTES_ARCHITECTURE.md`
- Modify: `doc/CORE_ARCHITECTURE.md`
- Modify: `doc/WORKFLOW.md` if needed by final behavior
- Modify: `deploy.ps1`
- Modify: `deploy.sh`

**Interfaces:**
- Consumes: verified behavior from Tasks 1-3.
- Produces: one Daily-first architecture narrative and current post-deploy key reference.

- [x] **Step 1: Synchronize user and contributor documentation**

Replace the GTD-first startup narrative with Daily-first startup followed by a short GTD review. Remove the stale 3,500-line claim. Document deployment target protection, hard verification failure, reversible org-supertag adaptation, and the full-buffer AI confirmation.

- [x] **Step 2: Synchronize deployment summaries**

Use only current bindings: `SPC d`, `SPC t d`, `SPC n c`, `SPC n v v`, and `SPC P o/p/l`.

- [x] **Step 3: Run focused and complete validation**

```powershell
pwsh -NoLogo -NoProfile -File scripts/check.ps1
pwsh -NoLogo -NoProfile -File scripts/check.ps1 `
  -PackageUserDir 'C:\Users\exrld\.emacs.d\elpa' `
  -RequireAllModules -RequireDependencies
```

Expected: exit zero; strict mode may retain only explicitly optional tool warnings.

- [x] **Step 4: Audit completion evidence**

```powershell
git diff --check
git status --short --branch
rg --files -g '*.elc'
rg -n 'SPC a d|SPC a f|SPC n m|3,500 lines|启动 — GTD' README.md CONTRIBUTING.md doc deploy.ps1 deploy.sh packages
rg -n 'expand-file-name "10_Outputs/"|expand-file-name "20_Practice/"' lisp -g '*.el'
```

Expected: no whitespace errors or bytecode; no stale bindings/narrative; only `init-org.el` owns canonical PARA literals.

- [x] **Step 5: Review the complete diff**

Confirm changes are limited to the planned files, contain no secrets or user data, and do not alter the module order, public keybindings, or package-manager choice.

## Self-Review

- Spec coverage: every actionable review finding maps to Tasks 1-4.
- Intentional non-changes: dependency pinning, automatic package updates, Babel confirmation, and large-module decomposition remain unchanged by repository policy.
- No commits or pushes are included because the user did not request them.
