# rest.nvim Feasibility For Neovim REST Client Workflow
**Tags:** `type:adr` `repo:nvim` `area:rest-client` `feature:rest-nvim-integration` `status:proposed` `owner:codex` `date-reviewed:2026-04-22` `adr:2026-04-22`
**Abstract:** Feasibility analysis of using `rest.nvim` as the Neovim-native REST client. Conclusion: strong fit for in-editor automation and acceptable response UI, but no native OpenAPI 3 ingestion path was identified. The best path is to treat `.http` files as the operational format and add a generator layer, not rely on rest.nvim itself to import specs.

- **Date:** 2026-04-22
- **References:** https://github.com/rest-nvim/rest.nvim, https://github.com/rest-nvim/rest.nvim/issues/414, https://github.com/mistweaverco/kulala-cmp-graphql.nvim
- **Scope:** Evaluate whether `rest.nvim` is a better Neovim REST-client foundation than a terminal-first tool when we need OpenAPI 3-driven request generation, cached request state, and editor automation.

## Context

We want a Neovim REST-client feature with these requirements:

1. use an existing `openapi-v3.yaml` as the source
2. generate actionable requests from the spec
3. cache payloads for mocks and repeated request bodies
4. cache credentials or auth-related state safely enough for day-to-day development
5. keep the workflow pleasant inside Neovim

`rest.nvim` is a Neovim plugin built around `.http` files, a tree-sitter parser for HTTP syntax, and an internal curl client. Its documented features include:

- running requests directly from `.http` buffers
- organized response panes
- request and response hooks
- dynamic and environment variables
- Lua scripting inside `.http` files
- cookie persistence
- env-file selection and registration

The most important architectural difference versus Posting is that `rest.nvim` is editor-native. It does not need a second terminal-side TUI to be useful.

## Decisions

### 1. `.http` is a good operational format

This is the strongest part of `rest.nvim`.

The plugin explicitly follows the IntelliJ HTTP client spec for `.http` file syntax. That means requests are plain text, live naturally in the repo, are diffable, and can be grouped near the code they exercise.

That makes `.http` a strong fit for:

- version-controlled example requests
- reproducible manual test flows
- lightweight automation from editor commands
- generating files from OpenAPI as a first step, then editing them locally

For this use case, `.http` is not a weakness. It is one of the main reasons `rest.nvim` is attractive.

### 2. rest.nvim is stronger than Posting for editor automation

This is the main reason to prefer it if Neovim is the center of the workflow.

Documented command surfaces include:

- `:Rest run`
- `:Rest run {name}`
- `:Rest last`
- `:Rest env show`
- `:Rest env select`
- `:Rest env set {path}`

That is a better foundation for Neovim automation than a TUI-first tool because:

- requests are already buffer-local
- the active request is cursor-addressable
- env switching is built into editor commands
- response panes are managed in Neovim windows rather than an external terminal

Recommendation:

- if we want editor commands like "run current request", `rest.nvim` is a better primitive than Posting

### 3. rest.nvim is acceptable for UI, but it is not a full visual API workspace

Its UI is good enough for editor-native work, not for a richer API-browser experience.

What the README supports:

- dedicated result panes
- request statistics
- cookies/log inspection
- winbar integration
- Telescope env picker
- Lualine env indicator

That gives it a usable response UI and some nice integration polish.

What it does not appear to provide:

- an OpenAPI operation browser
- a collection tree generated from the spec
- form-driven parameter editors
- visual auth/profile management beyond env files and scripts

So the answer to "is this good for UI visual?" is:

- yes for request/response editing inside Neovim
- no if the expectation is a Postman-like exploratory visual workspace

### 4. OpenAPI ingestion is the missing feature

This is the biggest feasibility gap.

From the reviewed upstream docs, no native OpenAPI import or sync workflow is documented. The plugin is centered on `.http` parsing and execution, not spec ingestion.

That means your stated requirement:

- "use existing openapi-v3.yaml file to generate actionable requests"

is not solved by `rest.nvim` out of the box.

Implication:

- configuration alone is unlikely to be enough
- we need either:
  - a Lua-side generator layer that converts OpenAPI operations into `.http` files
  - an external generator followed by rest.nvim as the execution layer
  - a fork/plugin extension if we want import behavior to feel native

Recommendation:

- do not fork first
- build an add-on generator layer first
- only fork if upstream extension points prove too narrow

### 5. A generator add-on is more sensible than an immediate fork

At this stage, an add-on layer is lower risk than a fork.

Why:

- `.http` is plain text, so generation is straightforward
- Neovim can create and refresh `.http` files without modifying the plugin
- env and scripting features already exist in the plugin
- a fork increases maintenance cost immediately, especially since upstream configuration already changed in a breaking way across versions

The migration issue in upstream is relevant here:

- earlier `setup()`-style configuration broke during a v3 migration
- current configuration is documented through `vim.g.rest_nvim`

Implication:

- the plugin is usable, but we should assume some config churn
- minimizing fork surface is a safer starting point

### 6. Payload caching is feasible and cleaner than with a TUI-first tool

This is another strong point for `rest.nvim`.

Payloads can live directly in `.http` files, which is excellent for:

- request examples
- mock bodies
- checked-in smoke-test flows

For larger or sensitive values, the documented env support helps:

- env file discovery
- env file selection
- env file registration per `.http` file

Recommendation:

- keep stable example payloads in `.http`
- keep mutable non-secret values in project env files
- keep secrets in gitignored env files

### 7. Credential caching is feasible, but should stay env-file based

`rest.nvim` supports env files and response-driven variable reuse, and it also persists cookies.

That is enough for common dev flows:

- bearer tokens copied from env
- login requests that set cookies
- dynamic values captured and reused in later requests

But it is still not a secret manager.

Recommendation:

- use gitignored `.env` files for durable credentials
- use response hooks / scripts for derived values
- treat cookie persistence as convenience state, not as the canonical credential store

### 8. rest.nvim is a better long-term base if we want OpenAPI-driven `.http` generation

This is the key architectural conclusion.

If we accept that OpenAPI import needs an extra layer, then `rest.nvim` is a strong destination format because:

- generated `.http` files remain fully usable by humans
- requests stay inside Neovim
- automation can target buffers and requests directly
- UI feedback stays inside the editor

By contrast, Posting solves import more directly but keeps the execution UX outside the editor.

## Files Touched / Created

No plugin code was changed as part of this analysis.

Recommended future project layout if we choose `rest.nvim`:

```text
http/
  generated/
    api.http
  local/
    scratch.http
  env/
    shared.env
    dev.env
    mock.env
    secrets.local.env   # gitignored
openapi/
  openapi-v3.yaml
lua/
  utils/
    openapi_http.lua
```

Recommended automation boundary:

- OpenAPI parser / generator writes `.http` files
- `rest.nvim` executes them
- Neovim commands handle refresh, env selection, and request targeting

## Alternatives Considered

### rest.nvim plus generator add-on

Pros:

- best editor integration
- good for automation
- plain-text request format
- no initial fork required

Cons:

- we must build the OpenAPI ingestion ourselves

### rest.nvim fork with native OpenAPI import

Pros:

- tighter user experience if fully implemented

Cons:

- much higher maintenance cost
- couples our feature set to upstream internal changes
- likely premature before proving the simpler generator approach

### Posting

Pros:

- stronger collection-style import story
- good for interactive terminal browsing

Cons:

- weaker editor-native automation model
- less natural for cursor-based execution in Neovim

## Open Flags For Future

1. We need to inspect the actual `.http` spec examples used by rest.nvim before writing a generator.
   The README confirms IntelliJ-style `.http`, but the exact conventions for named requests, variable syntax, and scripting layout should be validated against upstream examples.

2. We need a real generator strategy.
   The likely paths are:
   - Lua parser + emitter in this config
   - external generator that emits `.http`
   - hybrid: external OpenAPI parsing, local Lua post-processing

3. We need to decide whether generated `.http` files are disposable or semi-managed.
   If they are regenerated often, local customizations need a separate file or overlay model.

4. We should pin a plugin version.
   The upstream migration issue shows config surface churn, so this integration should not float blindly on the newest release.

5. We should test how good the response UI feels for large JSON bodies.
   The feature list is solid, but real ergonomics need a local prototype.

## Bottom Line

`rest.nvim` is a good candidate if the goal is:

- Neovim-native request editing
- in-editor request execution
- automation against the current buffer or named requests
- version-controlled request definitions in `.http`

`rest.nvim` is not a complete answer if the goal is:

- native OpenAPI 3 ingestion without extra tooling
- rich collection browsing from a spec
- a more visual Postman-style workspace

Recommended direction:

- choose `rest.nvim` if editor-native automation is the priority
- treat `.http` as the target request format
- build an add-on generator from `openapi-v3.yaml` into `.http`
- keep payload mocks in `.http` or adjacent env files
- keep credentials in gitignored env files
- defer any fork until the add-on approach proves that upstream extension points are insufficient
