# Rsync Detection Modes for `utils.remote_sync`

**Tags:** `type:adr` `repo:autovim` `area:remote-sync` `area:plugin-architecture` `status:planned` `adr:2026-04-26`

**Abstract:** `utils.remote_sync`'s default rsync invocations rely on size+mtime detection, which produces false-positive drift on active service mirrors (containers writing into bind-mounted dirs constantly bump dir mtimes) and risks `<leader>rp` silently overwriting unpushed local edits. Solution: a `detection` field in `.autovim-remote.json` accepting named modes (`lazy` / `safe` / `paranoid`), each mapping to vetted per-operation flag bundles. Default `safe` — push uses fast stat-based detection, pull and drift use `--checksum` for accuracy.

- **Date:** 2026-04-26
- **References:**
  - Sibling ADR: `docs/design-decisions/2026-04-25-remote-dev-local-first-git-backed-sync.md` — the workflow this ADR refines
  - Upstream todo: `~/Source/Remote/docs/todo-lists/autovim-remote-sync-improvements.md` — discovered during live deploy of forgejo / vaultwarden / nginx mirrors
  - Prior commit: `1be281e` (`--no-owner --no-group` defaults; sets the precedent of "stop preserving stat info we don't need")
- **Scope:** rsync invocation flags for `M.pull` / `M.push` / `M.drift`. Out of scope: per-file granular operations (deferred to a future follow-up); the workflow's overall shape.

## Context

The sibling ADR (2026-04-25) introduced the local-first rsync + git-backed-mirror workflow. v1 used the same flag set for every rsync invocation:

```lua
{ "rsync", "-az", "--info=stats1", ...excludes... }
```

`-a` (`-rlptgoD`) preserves owner / group / permissions / mtimes / device nodes / symlinks recursively. After commit `1be281e` we stripped owner/group preservation (the `--no-owner --no-group` fix for cross-user pushes). What remained was the default rsync change-detection algorithm: **transfer a file if its size or mtime differs**.

That default detection turned out to be the wrong choice for two of our three operations. The symptom that surfaced it during live deployment:

```
# remote-sync log — /home/johno/Source/Remote/Contabo1.VPS/etc-nginx
kind: drift   exit: 0   ts: 2026-04-26T11:45:10Z

## stdout (last 200 lines)

.d..t...... ./
```

The Vaultwarden / nginx / Forgejo containers write tmp files / lock files / log lines into bind-mounted dirs constantly. Each write bumps the **parent directory's** mtime on the host, even when the file being written is excluded from rsync via the project's `exclude` list. The dir mtime is therefore *almost always* drifted between local and remote, and our excludes can't suppress it because rsync is reporting on the dir itself, not on the excluded files inside.

Three concrete problems compound from there:

1. **`<leader>rs` push refuses to run** — `M.push` runs `M.drift` first and aborts on any drift output. Phantom dir-mtime drift therefore blocks every push of a freshly-edited config until the user either runs `<leader>rp` first to flatten the timestamp or escapes via `:lua require('utils.remote_sync').push({force=true})`. Both are friction the workflow shouldn't impose.
2. **`<leader>rp` pull risks silent overwrite of local edits** — pull runs `rsync -az ... remote → local`. Because rsync's default detection treats "different size or mtime" as "transfer needed", a remote container that bumped a file's mtime (without changing content) AND a local edit (newer mtime) interact badly: rsync's stat-based view is "files differ" → source wins → local edits silently clobbered.
3. **Trains pull-before-push muscle memory**, which makes #2 more likely to bite. The user learns "drift is normal, just pull first" — exactly the wrong instinct when local has unpushed edits.

A tighter rsync invocation can address all three, but the right invocation differs by operation: push is intentional and rare-to-need-byte-comparison; pull is destructive on conflict; drift is the read-only accuracy check that informs the gate.

## Decisions

### 1. Make detection configurable via a `detection` field in `.autovim-remote.json`

Per-project config gains an optional field:

```json
{
  "host": "...",
  "remote_path": "...",
  "exclude": [...],
  "detection": "safe"
}
```

Three accepted values, each mapping to a vetted per-operation flag bundle. Missing → `"safe"` (the default).

**Why per-project rather than global:** different mirrors have different cost profiles. A small `etc-nginx` config tree is fast to checksum-compare; a hypothetical 10GB asset mirror would not be. The maintainer should be able to tune per service. Per-project also matches the existing schema's design (excludes, delete, commands all per-project).

**Why named modes rather than raw flag lists:** an earlier draft explored exposing the rsync flags directly (`drift_detection: ["checksum", "omit-dir-mtime", ...]`). Rejected because:

- Users without rsync fluency can construct subtly wrong combinations (e.g., `--size-only` + `--checksum` is contradictory; `--update` on push is meaningless).
- The same flag set is wrong for different operations (push vs pull vs drift have orthogonal needs — see Decision 3).
- Named modes communicate intent (`safe` vs `lazy` vs `paranoid`); a flag list communicates implementation.

The named-mode design has a clean future extension to a `rsync_extra_flags` escape hatch (Decision 5) for the rare power-user case.

### 2. The three modes — `lazy` / `safe` / `paranoid`

| Mode | Push | Pull | Drift | Mental model |
|---|---|---|---|---|
| **`lazy`** | stat | stat | stat | "Fastest, trust mtime+size, eat the false positives." For mirrors with no active services touching the tree |
| **`safe`** *(default)* | stat | **checksum** | **checksum** | Push is fast (intentional act, retry-cheap). Pull is content-only, never silently clobbers. Drift is accurate, no phantom-mtime false positives |
| **`paranoid`** | **checksum** | **checksum** | **checksum** | Content-compare everywhere. Slowest. Use when size+mtime equality has been observed to lie about content (rare; e.g., generators rewriting files in place with identical metadata) |

`safe` is the default because it solves the actual problem the user hit (phantom dir-mtime blocking push, pull risk on conflict) without paying the byte-read cost on push (where it's least useful — the user has just edited the file and *wants* to send it).

`lazy` is preserved as the strict v1-equivalent for users who specifically opt out of the safety guard for performance. `paranoid` exists for the safety-critical edge case where even content-changes might be missed by stat detection.

### 3. Per-operation rationale — why three operations need three different defaults

Each operation has a distinct goal and risk profile:

| Operation | Goal | Failure mode if wrong | Right detection |
|---|---|---|---|
| **`<leader>rs` push** | Send the local state I just edited | Either no-op (false negative) or sends unintended files (false positive). Both are recoverable — push is intentional and re-runnable | stat is fine; user has just edited so the mtime bump is *intentional* and signals "send this" |
| **`<leader>rp` pull** | Pick up legitimate remote changes; do not destroy local work | Silent overwrite of unpushed local edits (data loss) | checksum — only transfer files whose **content** actually differs |
| **`<leader>rd` drift** | Tell the user whether real divergence exists, with no false positives | False positive blocks push (user friction); false negative misses real drift (worse — user pushes assuming clean state) | checksum — false-negative-free, false-positive-rare |

This per-operation breakdown is why a single global "compare via checksum" or "compare via stat" toggle is the wrong abstraction. Each mode resolves these three operations differently, and the mode names communicate the trade-off the maintainer is making.

### 4. Universal flags — `-O` and `--no-owner --no-group` apply in all modes

Two flag bundles are correct in *every* mode and are not exposed as configuration:

- **`-O` (`--omit-dir-times`)** — kills phantom dir-mtime drift at the rsync layer. Cleaner than parsing `--itemize-changes` output to filter `.d..t......` lines after the fact. Directory mtimes are a side effect of file writes (often excluded files), not an intentionally-set value; we have no operational use for them.
- **`--no-owner --no-group`** — already in place from commit `1be281e`. Cross-user pushes can't preserve UID/GID anyway; preserving them only produces noise + exit-23 warnings.

Putting these outside the mode system avoids an explosion of permutations (3 modes × 2 dir-mtime states × 2 owner-preserve states = 12) where 9 are wrong by construction.

### 5. Defer the escape hatch (`rsync_extra_flags`)

A later iteration could expose:

```json
{
  "detection": "safe",
  "rsync_extra_flags": {
    "push": ["--bwlimit=10M"],
    "pull": ["--partial"],
    "drift": []
  }
}
```

…appended to the mode's base flags after the universal flags. Not in v1. Adding it later is non-breaking. Keeping v1 simple gives us a stable feedback signal on whether the modes alone are sufficient.

### 6. Migration — `safe` is the default for configs without `detection`

Existing per-project `.autovim-remote.json` files (docker-test, docker-forgejo, docker-vaultwarden, etc-nginx) don't have a `detection` field. They get `safe` automatically — a behavior change, but in the direction of *more* safety: pulls become slightly slower (checksum on small trees = milliseconds) but never silently overwrite, and drift never reports phantom mtime divergence.

Configs that explicitly want the v1 behavior set `"detection": "lazy"`.

No tooling-side migration needed; no backwards-compat shims; no per-project file edits required.

## Files touched / created

| File | Action | Purpose |
|---|---|---|
| `lua/utils/remote_sync.lua` | edit | Read `cfg.detection` (default `"safe"`); per-operation flag selection |
| `README.md` | edit | Add `detection` row to the schema table; document each mode + the per-op rationale |
| `docs/design-decisions/2026-04-26-rsync-detection-modes.md` | created | This ADR |

No test fixtures (the module has no test suite; smoke-tested via `nvim --headless` against a real mirror). No external dependencies added.

## Alternatives considered

**Filter `.d..t......` lines in the drift parser** — earlier draft. Implements the dir-mtime fix in our Lua parser rather than in rsync. Rejected because (a) `-O` does the same thing at the rsync layer with zero parser code; (b) the parser approach doesn't help pull at all (where `--checksum` is the actual fix); (c) hides info from the log float that the user might want to see.

**Drop `-t` entirely (no mtime preservation)** — would eliminate all mtime-based detection issues but at cost of useful per-file last-edited info. Not worth the trade-off; `-O` (dir mtimes only) gets us 99% of the value without sacrificing file-level metadata.

**`--update` on pull** — initially considered for the "don't overwrite local edits" half. Rejected: silent footgun where remote has a real new version but local mtime happens to be newer (e.g. user `touch`'d the file) → real update silently skipped. `--checksum` is strictly safer.

**Raw flag-list config (`drift_detection: ["checksum", "omit-dir-mtime", ...]`)** — covered in Decision 1's rationale. Power without guidance is a UX trap.

**Single global mode (no per-op variance)** — every operation runs the same flag set. Simpler. Loses the per-operation optimization where push is fast (cheap to retry) and pull is safe (cheap byte-read insurance). The whole point of the design is that the three operations have different goals.

**Dir-mtime suppression via a per-project `exclude_dir_mtime: true`** — a single boolean for the dir-mtime fix only, leaving everything else alone. Doesn't help pull's overwrite risk. Half a fix.

## Open flags for future

1. **Measure `--checksum` cost on real mirrors** before declaring `safe` is universally fine. Most current mirrors are small (etc-nginx ~6KB, docker-forgejo config dir ~10KB). A future heavyweight mirror (Nextcloud config tree, mailcow's full conf hierarchy) could make `safe`'s pull/drift feel sluggish. If it does, two options: (a) lower the default to a hybrid mode that's `--size-only` baseline + `--checksum` on suspicious mtime drift; (b) document `lazy` as a per-project override.
2. **`rsync_extra_flags`** (Decision 5) — implement when someone hits a real need. `--bwlimit` and `--partial` for resumable transfers are the most commonly-asked-for.
3. **Per-operation detection override** — `detection: { push: "lazy", pull: "safe", drift: "paranoid" }`. More expressive than the named modes; harder to reason about. Defer until a real use case appears.
4. **macOS rsync 2.x compatibility** — `--checksum` and `-O` both predate 3.0, should work fine on macOS's stock rsync. Verify on the mac-os branch before declaring parity.
5. **Drift report richer parsing** (a separate todo item) — once we have `safe` mode, the drift output is genuinely "real differences only", which makes a structured render of the changes (added/deleted/modified) more useful. Tracked in `~/Source/Remote/docs/todo-lists/autovim-remote-sync-improvements.md` as P8.

## See also

- `docs/design-decisions/2026-04-25-remote-dev-local-first-git-backed-sync.md` — the workflow this ADR refines.
- `~/Source/Remote/docs/todo-lists/autovim-remote-sync-improvements.md` — the live punch list this issue (P1) was extracted from. Other items there will become their own ADRs as they get picked up.
