# HEAD-Based Drift Detection (Path C) for `utils.remote_sync`

**Tags:** `type:adr` `repo:autovim` `area:remote-sync` `area:plugin-architecture` `status:shipped` `adr:2026-04-26` `commit:256b03a`

**Abstract:** The original drift gate compared the remote against the local working tree, so any unpushed local edit was flagged as drift and made `<leader>rs` refuse on every iteration of edit-then-push. Switched to comparing remote against the local git mirror's `HEAD`, which represents "last synced state in either direction." `M.push` now commits a pre-push snapshot before rsync, then runs a quiet auto-pull post-push, so HEAD stays in sync with remote across editing sessions. `<leader>rS` added as a confirm-prompted force-push escape hatch.

- **Date:** 2026-04-26
- **References:**
  - Sibling ADR: `2026-04-25-remote-dev-local-first-git-backed-sync.md` — the original workflow (which already named git as the snapshot baseline; this ADR realizes that intent)
  - Sibling ADR: `2026-04-26-rsync-detection-modes.md` — `lazy`/`safe`/`paranoid` modes (orthogonal axis: *what to compare*; this ADR is *what to compare against*)
  - Implementation commit: `256b03a` on omarchy
- **Scope:** `M.drift` / `M.push` / `M.pull` semantics + `<leader>rS` keymap. Out of scope: backwards-compat shim for older `.autovim-remote.json` configs (none exist outside this single user); statusline integration; concurrent-writer locking.

## Context

The sibling ADR (2026-04-25) introduced rsync + git-backed-mirror workflow with three operations:

- `<leader>rp` → rsync remote → local; auto-`git commit` the result as a snapshot
- `<leader>rd` → drift report (read-only)
- `<leader>rs` → push local → remote; refuses on drift

The intent was that *git would serve as the snapshot baseline*. The pull's auto-snap commit captured "what the remote looked like last time we pulled," and any future drift would be detected against that baseline.

**The actual implementation didn't use git for drift comparison**. It just ran `rsync -azni --checksum --dry-run` from remote to local working tree. This was simpler to write but lost the 3-way reference git was supposed to provide.

The failure mode surfaced during live deployment of forgejo / vaultwarden / nginx mirrors:

> "we have to address this immediately... I can't push the changes as these were detected as drifts for some reason. let's push the changes to the remote by force"
>
> — user, after every editing-then-pushing cycle

The user was hitting this loop:

1. `<leader>rp` to pull remote state (HEAD = remote at that moment)
2. Edit some file locally
3. `<leader>rs` → drift check sees "remote file ≠ local working tree file" (because local has new content) → flags as drift → push refused
4. User has two bad options:
   - **Pull-then-push**: would silently overwrite their unpushed edits because rsync's safe-mode `--checksum` confirms content differs and brings the remote (older) version down on top of local
   - **Force-push**: bypasses the gate that's supposed to be the safety mechanism, training "force is normal" muscle memory

Either path defeats the workflow's purpose.

### Why pure rsync drift can't disambiguate the three cases

A 2-way diff (remote vs local) collapses three distinct states into one signal:

| Scenario | rsync `--dry-run` output | What we *want* drift to report |
|---|---|---|
| Local has unpushed edits; remote unchanged | files differ | **NOT drift** — push freely |
| Remote has changes since our last pull; local unchanged | files differ | **DRIFT** — pull-merge before push |
| Both edited concurrently | files differ | **DRIFT** — real conflict, manual resolve |

All three are indistinguishable to `rsync --checksum --dry-run`. The disambiguation requires a third reference: **what did we last sync?** Compare:

- `last-sync == remote` → no remote drift; local edits are safe to push
- `last-sync != remote` → remote has changed; pull-merge required

The local mirror's git history is exactly that reference — pull's auto-snap commit *is* "what we last synced." The original implementation just didn't connect that dot.

## Decisions

### 1. Drift compares remote against `git HEAD`, not against the working tree

`M.drift` now extracts `HEAD` to a temp dir via `git archive HEAD | tar -x`, then runs `rsync -azni --dry-run` from remote against that temp dir. Any output is real drift (remote changed since our last sync); empty output is no drift.

**Why:** restores the 3-way reference the original ADR intended. HEAD = "last synced state in either direction"; working tree = "current local with unpushed edits"; remote = "what's on the VPS now." Drift is now specifically "remote ≠ HEAD."

**Cost / tradeoff:** an extra `git archive | tar -x` per drift check (cheap on small config trees; ~10–50ms). Falls back to working-tree comparison when state == "none" pre-bootstrap (no HEAD to use).

### 2. Drift adds `--no-times --no-perms` to its rsync flags

`git archive | tar -x` stamps every extracted file with the current time + tar's default perms. Without these flags, every drift comparison would surface `.f..t......` (mtime differs) and `.d...p.....` (dir perms differ) for every entry — drowning out actual content drift.

**Why:** drift answers "did the content drift?" — mtime / perms differences from the temp extraction don't represent that.

**Cost / tradeoff:** none for our use case. Push and pull paths still preserve mtimes / perms via the default `-a` flag set; only drift's comparison loop ignores them. If a future use case actually cares about perm drift in detection, it'd be a separate flag (`detection_includes_perms`) on the project config.

### 3. `M.push` commits a `pre-push` snap before rsync

After the drift check passes (remote == HEAD), push calls `maybe_commit_snap(root, "pre-push")` to capture the working tree as a new commit before the rsync runs. This advances HEAD to match what's about to be sent.

**Why:** keeps HEAD-based drift detection coherent across editing sessions. Without the pre-push commit, HEAD would lag behind remote (remote = what we just pushed; HEAD = state before our edits) and the next drift check would falsely report "remote has changes" — exactly the bug we just fixed, in a new form.

**Cost / tradeoff:** an extra commit per push (with meaningful content); zero commits when working tree matches HEAD already (the empty-commit guard in `maybe_commit_snap` handles this). The git history now has two commit-flavors (`snap pull <iso>` from pulls, `snap pre-push <iso>` from pushes), which is informative rather than noisy.

### 4. `M.push` triggers a quiet auto-pull post-push

After successful rsync push, push calls `M.pull({ quiet = true })`. Mostly a no-op (pre-push commit already left HEAD == remote == working tree), but catches the edge case where a concurrent writer modified remote between our drift check and our push.

**Why:** removes a remaining race window. Drift check at T0 says clean; rsync push at T1 sends our state; if another admin pushed at T0.5 between those, we'd silently overwrite. Auto-pull at T2 surfaces that as a new snap commit, so the user sees the merge happened.

**Cost / tradeoff:** one extra rsync round-trip per push (typically <100ms). Harmless when no concurrent writer exists.

### 5. `maybe_commit_snap(root, label, on_done)` helper

Factored out of pull's existing snap-commit logic. Single source of truth for "commit working tree as snap if there are changes; init git first if needed; refuse to commit if state is ancestor."

**Why:** push and pull both need the same logic. Without the helper, the push refactor would duplicate ~30 lines of git plumbing. The label parameter (`"pull"` / `"pre-push"`) propagates to the commit message so git history records *why* each snap exists.

**Cost / tradeoff:** small helper, no behavioral change for pull. Empty-commit guard via `git status --porcelain` — no commit when working tree matches HEAD, in either pull or push paths.

### 6. `<leader>rS` — force-push with confirm prompt

New keymap. Calls `M.push({ force = true })` after a `vim.ui.select` confirmation:

```
Force push? Drift gate will be skipped — you may overwrite remote changes.
[ no, cancel ]
[ yes, force push ]
```

**Why:** the drift gate exists for a reason; bypassing it should be a deliberate "I know what I'm doing" rather than a habitual reflex. The confirm prompt slows the user down enough to think. The keymap `<leader>rS` (capital S) mirrors the lowercase pattern used elsewhere in this config (lower = frequent action, upper = explicit/heavier variant).

**Cost / tradeoff:** one extra keypress when force-push is genuinely needed. Acceptable friction for a destructive operation.

## Files touched / created

| File | Action | Purpose |
|---|---|---|
| `lua/utils/remote_sync.lua` | edit (~250 lines changed) | New `maybe_commit_snap` helper; `M.drift` uses git archive HEAD; `M.push` commits-before + pulls-after; `M.pull` gains `opts.quiet` and `opts.on_done` |
| `lua/plugins/remote-sync.lua` | edit | `<leader>rS` keymap with `vim.ui.select` confirm; updated `<leader>rs` desc to reflect new flow |
| `README.md` | edit | Schema row for `<leader>rS`; `<leader>rd` description notes "compares remote against git HEAD"; `<leader>rs` description notes the auto-snap-before + auto-pull-after; "What's Inside" bullet refresh |
| `docs/design-decisions/2026-04-26-head-based-drift-detection.md` | created | This ADR |

No tests added (no test suite exists for this module; smoke-tested via `nvim --headless` against the live `docker-forgejo` mirror). No external dependencies added.

## Alternatives considered

**Pure rsync 2-way diff (the original).** Documented in *Context*. Conflates three distinct states; produces false-positive "drift" on every local edit. Rejected.

**`--update` flag on pull.** Would skip files where local mtime is newer than remote. Avoids overwriting local edits but introduces a footgun: if remote has a real new version *and* local mtime happens to be newer (e.g., user `touch`'d the file), pull silently skips the real update. Strictly worse than the HEAD-based approach. Rejected.

**Shadow-tree maintenance.** Maintain a sibling directory (`.autovim-remote-shadow/`) that gets refreshed on every pull/push to capture "last synced state." Drift compares remote vs shadow. Works conceptually but: (a) doubles disk usage on the local side, (b) adds a separate bookkeeping mechanism orthogonal to git (which is already serving the same purpose), (c) breaks any "git diff HEAD" intuition the user develops about the snapshot history. Rejected — git's already there, use it.

**Filter `--itemize-changes` parser instead of `--no-times --no-perms`.** Parse rsync's output and discard lines where the only change indicator is `t` or `p`. Works for the time/perm filtering, but: (a) parsing rsync's internal flag format is brittle (the format has subtle edge cases per rsync version), (b) the rsync flag approach is one line of code, (c) filtering at the source (rsync) is cleaner than filtering at the consumer (parser). Rejected — the flag approach is strictly simpler.

**Per-operation `detection` modes drive what gets compared.** Already exists (sibling ADR `2026-04-26-rsync-detection-modes.md`) — `lazy` vs `safe` vs `paranoid` controls **what to compare** (size+mtime vs content). This ADR is orthogonal: it controls **what to compare against** (working tree vs HEAD). Both axes coexist; this ADR doesn't replace mode selection, it changes the reference point all modes use.

**Skip force-push entirely; require manual rsync.** Considered for the "discourage habitual force" angle. Rejected because there are legitimate force-push scenarios (e.g., known one-time wholesale reset of remote), and forcing the user out of the keymap layer for those would teach the wrong workflow ("when in doubt, drop to shell"). The confirm prompt is the right midpoint.

## Open flags for future

1. **HEAD might be empty** in a freshly-init'd repo with no commits. Currently the drift implementation falls back to working-tree comparison in this case (with a notify). Better long-term: reject drift checks until at least one commit exists, OR auto-create an empty initial commit during git init. Not urgent — the path is hit only on the very first pull.
2. **Concurrent writer race window** — drift check at T0, push at T1, no detection of writer at T0.5. The post-push quiet pull catches it *after* the fact (surfaces as a new snap commit) but doesn't *prevent* the overwrite. Real prevention requires either remote-side advisory locking or a "fetch before push" round-trip with a hash check. Out of scope; tracked for later.
3. **`--no-perms` on drift might mask a real perms issue** — e.g., a service config that needs to be `0600` got rsync'd as `0644` and we'd never know. Acceptable for our use case (we don't manage perms via this workflow), but a more rigorous shop might want a separate `<leader>rd!` strict-mode that re-enables perm comparison.
4. **Pre-push commit message doesn't include push details** — currently just `snap pre-push <iso>`. Could include the destination host or a pushed-files summary. Not load-bearing, just nice-to-have for `git log` legibility.
5. **Force-push prompt might fatigue** — once the user has confirmed force-push N times in a session and "knows what they're doing," the prompt becomes friction without value. Could add a session-scoped opt-out (`:RemoteSyncTrustForcePush` for the rest of nvim's lifetime), but that defeats the purpose. Punt unless it becomes annoying.
6. **The drift fallback when state == "none" still uses working tree** — same false-positive behavior as before in that case. Pre-bootstrap mirrors are rare (only the very first session before the first pull); not worth fixing unless we see it bite.

## See also

- `docs/design-decisions/2026-04-25-remote-dev-local-first-git-backed-sync.md` — the original workflow this ADR refines.
- `docs/design-decisions/2026-04-26-rsync-detection-modes.md` — orthogonal axis: what to compare (size+mtime vs content) per operation.
- `~/Source/Remote/docs/todo-lists/autovim-remote-sync-improvements.md` — P1 of that punch list (the "phantom drift on every push" symptom) is now resolved by this ADR; P3 (force-push UX) is also delivered via the `<leader>rS` keymap.
