# Posting Feasibility For Neovim REST Client Workflow
**Tags:** `type:adr` `repo:nvim` `area:rest-client` `feature:posting-integration` `status:proposed` `owner:codex` `date-reviewed:2026-04-22` `adr:2026-04-22`
**Abstract:** Feasibility analysis of using `posting` as the terminal-side REST client for Neovim, driven by existing OpenAPI 3.x specs and layered request state. Conclusion: feasible for collection generation and interactive execution, but not strong enough by itself as a headless automation engine; the best fit is a hybrid workflow where Neovim generates and launches Posting collections while durable request state lives in project files.

- **Date:** 2026-04-22
- **References:** https://github.com/darrenburns/posting, https://posting.sh/guide/importing/, https://posting.sh/guide/environments/, https://posting.sh/guide/requests/, https://posting.sh/guide/scripting/, https://posting.sh/CHANGELOG/
- **Scope:** Evaluate whether Posting can back a Neovim REST-client feature using existing `openapi-v3.yaml` files, reusable payload mocks, and credential caching.

## Context

We want a Neovim-side REST client workflow with these requirements:

1. Start from an existing `openapi-v3.yaml`.
2. Generate actionable requests rather than hand-writing every endpoint.
3. Cache payload data for mockups or repeated request bodies.
4. Cache credentials or derived auth state without turning the repo into a secret dump.
5. Keep the result usable from Neovim with minimal friction.

`posting` is a terminal UI HTTP client with project-local collections stored as YAML files. Its documentation and changelog show three capabilities that matter here:

- it can import OpenAPI 3.x specs into collections
- it stores requests as readable `.posting.yaml` files
- it supports `.env` files plus Python request scripts for runtime mutation and token extraction

The important constraint is architectural: Posting is primarily a TUI application, not a headless request runner with a rich documented automation API.

## Decisions

### 1. Posting is feasible as the interactive request workbench

This is the strongest fit.

Posting collections are just directories, requests are simple YAML files, and a collection can be opened directly from a project path. That makes it compatible with a Neovim terminal workflow where the editor launches Posting in a dedicated terminal slot for the current project.

Recommendation:

- treat Posting as the interactive request browser/executor
- launch it from Neovim in a project-local collection directory
- keep the collection in version control where practical

### 2. OpenAPI-driven request generation is feasible, but import should be treated as a bootstrap/refresh step

Posting documents OpenAPI import via:

```text
posting import path/to/openapi.yaml
```

It also describes this feature as experimental. The upstream changelog is relevant here:

- OpenAPI import support already existed before 2026
- release `2.10.0` explicitly notes support for importing OpenAPI `3.0` specs, where earlier behavior was narrower

Implication:

- if we depend on existing `openapi-v3.yaml` files that are still on 3.0, require Posting `>= 2.10.0`
- use import as a generation step, not as the only source of truth for local customizations

Recommendation:

- generate collections from OpenAPI into a project-local generated directory
- keep custom environment files and helper scripts adjacent to, but logically separate from, imported request files
- assume re-import may need a controlled refresh command rather than ad hoc manual edits

### 3. Payload caching is feasible and clean

For non-secret request state, Posting is a good fit.

Three storage layers work well:

1. request body content inside `.posting.yaml`
2. project-local `.env` files for variables like base URLs, fixture IDs, and default headers
3. companion fixture files for larger JSON payloads or mock bodies edited outside the TUI

This aligns with Posting's documented model:

- requests are file-backed YAML
- variables come from `.env` files
- `posting.env` autoloads when no explicit `--env` is given

Recommendation:

- keep repeatable non-secret inputs in versioned files
- use separate env layers, for example:
  - `posting.env`
  - `env/shared.env`
  - `env/dev.env`
  - `env/mock.env`

### 4. Credential caching is feasible, but only with a split between durable secrets and session state

Posting gives us two distinct mechanisms:

1. `.env` files for durable variables
2. scripting APIs for session variables

This split matters.

From the scripting docs:

- `posting.set_variable(...)` stores session variables
- those variables live only for the Posting session

So Posting can extract and reuse tokens during a session, but does not by itself provide a documented durable credential cache beyond ordinary env files.

Recommendation:

- store durable secrets in gitignored env files
- use setup or post-response scripts to derive short-lived session values such as bearer tokens
- do not rely on Posting session variables for cross-session persistence

This is sufficient for:

- API keys
- base auth credentials
- token bootstrap flows

It is not sufficient by itself for:

- secure secret storage
- encrypted credential management
- durable cross-session token caches without additional scripting

### 5. Posting is only moderately feasible as an automation backend

This is the main limitation.

The documented CLI surfaces are strong for:

- opening collections
- importing OpenAPI
- locating config/collection paths

The docs reviewed here do not show a strong, stable, noninteractive "run request from the command line and emit the response" workflow comparable to a dedicated CLI runner. Posting is centered on the TUI.

That means:

- launching Posting from Neovim is straightforward
- driving Posting purely as a background automation engine is weaker

Recommendation:

- do not treat Posting as the sole automation backend for all editor actions
- treat it as the interactive UI layer
- keep higher-level automation in Neovim-side commands that generate collections, choose env files, and launch Posting with the right working set

## Files Touched / Created

No Neovim integration files were changed as part of this analysis.

Recommended future project layout:

```text
.posting/
  collection/
  scripts/
  env/
    posting.env
    shared.env
    dev.env
    mock.env
    secrets.local.env   # gitignored
  openapi/
    openapi-v3.yaml
```

Recommended launch shape from Neovim:

```text
posting --collection .posting/collection --env .posting/env/shared.env --env .posting/env/dev.env
```

## Alternatives Considered

### Native Neovim `.http` client plugins

Pros:

- more natural in-buffer editing and execution
- easier to target exact requests from the current buffer

Cons:

- weaker OpenAPI import story unless we build a generator ourselves
- more work to get a clean terminal-grade request browser

### Bespoke OpenAPI-to-request generator

Pros:

- maximal control over file layout and caching model
- easier to align exactly with our project conventions

Cons:

- reinvents request editing, auth handling, and interactive execution UX that Posting already provides

### Hybrid approach

Pros:

- best fit for the current requirement
- use OpenAPI to generate Posting collections
- use Neovim commands to refresh, launch, and manage env layers
- keep future option open for a native `.http` execution path if we outgrow Posting

Cons:

- two layers to manage: editor integration and Posting collection structure

## Open Flags For Future

1. Re-import behavior needs a real test.
   We still need to verify how safely `posting import` can refresh an existing generated collection without trampling local adjustments.

2. Headless execution needs a real test.
   The reviewed docs do not establish a strong noninteractive request-runner interface. If we need editor commands like "send current request without opening Posting", we may need either a second tool or a small wrapper layer.

3. Example/body fidelity from OpenAPI needs a real test.
   Posting can generate imported requests and has previously added JSON body defaults, but we still need to evaluate how well complex request bodies, auth schemes, and examples survive real specs in our codebase.

4. Secret strategy should remain layered.
   Durable secrets should stay in gitignored env files, with short-lived tokens generated into Posting session variables by scripts.

5. Version pinning is warranted.
   Since OpenAPI import is documented as experimental and 3.0 import support was explicitly fixed in `2.10.0`, this integration should pin a minimum Posting version instead of floating loosely.

## Bottom Line

Posting is a good candidate for:

- importing OpenAPI 3.x into project-local requests
- browsing and sending those requests interactively
- layering non-secret mock data and durable env configuration
- deriving auth tokens at runtime with scripts

Posting is a weaker candidate for:

- fully headless Neovim request execution
- durable credential caching beyond ordinary env files
- being the only automation primitive in the editor

Recommended direction:

- adopt Posting as the interactive request UI
- generate and refresh collections from `openapi-v3.yaml`
- store payload mocks and env layers in project files
- keep credentials in gitignored env files
- use Neovim commands to orchestrate import, launch, and environment selection
- defer any deeper "send request from current buffer without opening Posting" requirement until after a real prototype confirms whether Posting's TUI-first model is enough
