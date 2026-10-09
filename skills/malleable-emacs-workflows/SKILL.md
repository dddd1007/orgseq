---
name: org-seq Malleable Workflows
description: Design and review small org-seq and Emacs workflow tools by turning repeated user friction into bounded behavior composed from Emacs APIs, existing packages, and structured external CLI calls. Use when proposing or implementing a personal workflow automation, integrating a CLI as an Emacs service, deciding between a live prototype, an init module, and a reusable package, or evaluating whether an idea belongs in org-seq.
---

# Malleable Emacs Workflows

Turn a repeated task into the smallest safe workflow that satisfies the actual
user. Preserve org-seq's existing architecture instead of creating a parallel
framework.

Read [references/article-and-org-seq.md](references/article-and-org-seq.md)
when evaluating an org-seq runtime change or explaining the source rationale.

## 1. Frame the Friction

Inspect the repository instructions, Git state, relevant documentation, and
existing implementation before designing anything. Record this compact brief:

```text
Repeated task:
Desired outcome:
Inputs and outputs:
Source of truth:
Read boundaries:
Outbound destination and minimum data:
Sensitive data and confirmation:
Mutation boundaries:
Failure and partial-state behavior:
Idempotency:
Rollback or compensation:
Recovery verification:
Audience and environments:
Timebox:
Success checks:
Non-goals:
```

Define what must not be built. Prefer one-way import, export, or launch behavior
over bidirectional synchronization unless synchronization is the explicit need.

## 2. Inventory Building Blocks

Search in this order:

1. Existing org-seq commands and module-owned interfaces.
2. Built-in Emacs and Org APIs.
3. Already-installed packages with stable public APIs.
4. External programs that expose structured, scriptable output.
5. New Elisp code for only the missing behavior.

Treat an authenticated CLI as a narrow service boundary when it already owns
authentication and remote API details. Reuse ideas freely, but record provenance
in `THIRD_PARTY.md` before copying or closely adapting source code.

## 3. Compose Through Small Seams

Separate the workflow into the smallest useful layers:

```text
request -> transport -> normalize -> domain transform -> present -> mutate
```

- Represent intermediate data with plain Elisp structures such as plists,
  alists, vectors, or hash tables.
- Keep normalization and domain transforms pure where practical.
- Keep UI commands thin; let them call inspectable functions.
- Keep remote state, Org state, and display state distinct.
- Define one owner for each path, popup, keybinding, package, and mutation.
- Add a shared abstraction only after multiple real workflows need the same
  behavior.

## 4. Prototype Live, Then Graduate Deliberately

Use a scratch buffer, an Org source block, IELM, or a temporary Elisp file to
test the smallest end-to-end slice in a running Emacs session. Keep prototype
mutations in temporary data or behind explicit confirmation.

Choose the durable home only after the behavior is useful:

- Keep a disposable experiment outside committed runtime code.
- Put org-seq-specific integration in the owning `lisp/init-*.el` module.
- Put reusable, independently publishable behavior under `packages/<name>/`
  and keep the `lisp/` integration thin.
- Add no code when an existing command or binding already solves the task.

Use the article's build-for-1 versus build-for-N distinction only for the
number of users or audiences. Separately, treat committed org-seq code as having
a broad support surface: Windows, Linux, macOS, GUI, daemon, and batch startup
all add compatibility and validation obligations even with one operator.

## 5. Invoke External Programs Safely

- Check availability with `executable-find` and expose optional dependencies
  through the existing doctor when the workflow becomes user-visible.
- Default to passing the executable and every argument separately through
  `process-file`, `call-process`, `make-process`, or the owning process API.
- When a Windows `.ps1` or `.cmd` shim requires a PowerShell wrapper, reuse
  org-seq's existing quoted wrapper pattern and pass the resulting script as one
  PowerShell argument. Do not add ad hoc or unescaped interpolation.
- Request JSON or another stable machine format; parse it with native APIs.
- Capture exit status, stdout, and stderr separately enough to diagnose failure.
- Validate response shape before using it.
- Delegate authentication to the external tool without reading or logging its
  tokens, credentials, or credential-bearing environment variables.
- Classify every outbound field and send only the minimum needed. Confirm before
  sending a full buffer, private note or file, or sensitive local path to any
  remote service, including a nominally read-only authenticated CLI.
- Keep sensitive request data and remote responses out of logs and diagnostics;
  redact stderr before presenting or persisting it when needed.
- Confirm remote writes or destructive local actions, then verify the resulting
  state.
- Make repeated requests idempotent where the remote interface permits it.
  Otherwise define duplicate detection, compensation, or manual reconciliation.
- Define how to detect and recover from partial local/remote success before
  enabling a multi-step mutation.
- Use an asynchronous process when latency would block normal interaction.

## 6. Fit the Existing org-seq Contracts

- Centralize shared NoteHQ and PARA paths in `lisp/init-org.el`.
- Reuse `init-popup` for placement and the owning module for lifecycle.
- Register Git-hosted packages in `init-packages`; keep feature configuration in
  its owner module.
- Put global leader bindings in `init-evil` and audit critical bindings.
- Declare module dependencies in both `init.el` and `;; Requires:` headers.
- Preserve `custom.el` overrides, the AI send boundary, and read-only rendering
  boundaries.
- Keep optional tools optional unless the documented core workflow requires
  them.

## 7. Harden in Proportion to Scope

Always exercise:

- the smallest successful end-to-end case;
- pure transformations and the narrowest useful integration boundary;
- byte compilation for every changed Elisp file;
- focused ERT for the changed behavior.

When the workflow invokes an external program, also exercise:

- a missing executable or package;
- a nonzero process exit;
- malformed, empty, or partial structured output;
- relevant Windows paths, spaces, apostrophes, Unicode, and shim quoting.

When the workflow mutates local or remote state, also exercise:

- user cancellation before mutation;
- failure after each independently successful step;
- repeat invocation and duplicate detection;
- rollback, compensation, or documented manual recovery;
- final-state verification after success and recovery.

For a multi-file refactor or pre-commit readiness check, run the default
canonical `scripts/check.ps1`. For deployed or release readiness, also run
the strict gate with an explicit deployed package directory plus
`-RequireAllModules -RequireDependencies`. The default check may report missing
runtime dependencies as warnings and is not proof of deployed readiness.

Verify final state rather than treating a zero-noise command as proof. Mark
inapplicable and unrun checks explicitly. Stop when the stated success checks
pass and the non-goals remain out of scope.

## 8. Report the Design

Summarize the result in a compact, reviewable contract:

```text
Observed friction and chosen scope:
Selected building blocks:
Layer contracts and data shape:
Owning module or package:
Read and mutation boundaries:
Failure, idempotency, and recovery behavior:
Validation matrix:
Explicit non-goals:
```

When implementation was requested, compare the final diff and verification
results against this contract. When only analysis was requested, stop at the
contract and do not mutate runtime code.

## Guardrails

- Do not copy the article's GitHub issue tool merely to demonstrate the idea.
- Do not turn malleability into a general plugin, layer, or service framework.
- Do not confuse live evaluation with permission to bypass module ownership,
  tests, privacy, or rollback boundaries.
- Do not treat the article's BIBO and percentage analogies as engineering proof.
- Do not use "works for me" to excuse fragile behavior once code is committed
  to this deployable, cross-platform repository.
