# Teleport for Codex — design note

> **Status: NOT IMPLEMENTED. Blocked on validation.** This is a plan, not working
> code. Do not ship an implementation built only from the notes below — the Codex
> session format and resume semantics must be confirmed against a **real session**
> first. (We just learned this the hard way: Claude Code's project-dir encoding
> wasn't what anyone would have guessed, and a 33-check suite that assumed the rule
> stayed green while real resume broke.)

## Goal

`dotai tp` already moves a live **Claude Code** conversation between machines. Do the
same for **Codex** (OpenAI's CLI): package the current Codex session + repo state,
ship it, and resume it on the target.

The engine is mostly harness-agnostic already — `teleport.sh send` takes
`--harness`, and today it prints a friendly "Codex isn't supported yet". The repo
handling (URL match → clone or worktree, uncommitted patch, untracked, local-commit
bundle) is reusable as-is. What's Codex-specific is **finding, packaging, placing,
and resuming the session transcript**.

## Why this is blocked right now

To build and validate this we need, at minimum:
1. A machine with `codex` installed to **generate a real session** (inspect the
   actual on-disk format), and
2. A reachable Codex environment on the **target** to confirm resume works.

At the time of writing: `codex` is **not installed on the mini**, and the MacBook
(where Codex is used) was **powered off**. So there is neither a real session to
package nor an environment to resume on. Inferring the format and shipping code
would be guessing — exactly the failure mode we just fixed for Claude.

## What to confirm first (the grounding step)

On a machine with Codex:

```bash
command -v codex && codex --version
# run one throwaway session, then inspect what it wrote:
find ~/.codex/sessions -name '*.jsonl' | tail -1 | xargs -I{} sh -c 'echo {}; head -5 {}'
```

Answer these against the **real file**, do not assume:
- **Where** sessions live (expected `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, to confirm).
- The **line/event schema**, and **where the cwd / working dir lives** (the field name).
- How a session is **identified** (a UUID? the filename?) and how it's **resumed**
  (`codex resume <id>` / `--last` / a flag — confirm the exact command).
- Whether the target needs any **index/registry** updated (like Claude's
  `~/.claude/projects/<encoded-cwd>/` dir name) for `codex resume` to find a
  dropped-in transcript — this is precisely what bit us on the Claude side.

## Implementation sketch (once grounded)

1. **send:** with `--harness codex`, find the latest (or `--session`) rollout file
   for the current cwd, stage it alongside the repo payload (reuse existing repo
   bundling untouched), ship via the existing rsync path.
2. **receive:** land the repo (existing clone/worktree logic, no change), then place
   the rollout file where Codex expects it on the target — rewriting any cwd field
   the way `cmd_receive` already rewrites Claude's, and creating whatever
   index/dir Codex needs. Print the real `codex resume …` command.
3. **skill:** the `teleport` skill currently asserts Claude Code via
   `$CLAUDE_CODE_SESSION_ID`. Add a Codex detection path.
4. **tests:** add a Codex scenario to the Docker suite using a **captured real
   rollout fixture** — and assert placement against where `codex resume` actually
   looks, not against our own placement function (the non-circular lesson).

## Out of scope for this note

No code is included on purpose. The next session should start from the grounding
step above on a Codex-capable machine, then implement + validate end-to-end (a real
laptop→mini Codex teleport that actually resumes), the same bar Claude teleport met.
