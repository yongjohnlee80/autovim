# rest.nvim OpenAPI Import
**Tags:** `repo:nvim` `area:rest-client` `feature:rest-nvim-integration` `type:todo-list` `owner:shared` `living-doc` `status:planned`
**Abstract:** Track the missing OpenAPI 3 import/generation layer for the Neovim `rest.nvim` workflow so specs under project docs can be converted into generated `.http` requests later.

- **Kickoff:** 2026-04-23
- **Owner(s):** shared
- **References:** [rest.nvim feasibility ADR](../design-decisions/2026-04-22-rest-nvim-feasibility.md), `/Users/yongsunglee/Source/Projects/LabelManager/lm/gold-search/cmd/gold-http/docs/route-search-openapi3.yaml`, `/Users/yongsunglee/Source/Projects/LabelManager/lm/gold-search/cmd/gold-http/docs/route-me-openapi3.yaml`

## Open

- Define the import contract: source spec paths, output layout under `.rest/http/generated/`, and overwrite vs refresh behavior.
- Decide whether the generator should live as a Neovim Lua command (`:RestImportOpenAPI`) or as an external script wrapped by Neovim.
- Generate baseline `.http` requests per OpenAPI operation with stable filenames and section headers.
- Map OpenAPI servers, params, auth, and example request bodies into `rest.nvim`-friendly `.http` blocks.
- Decide how environment placeholders like `{{BASE_URL}}` should be derived when specs contain concrete hosts.
- Define how multiple spec files in a single project should merge into one generated tree without collisions.
- Verify whether generated requests should be disposable-only or allow local overlays next to generated files.
- Add a refresh command that can safely regenerate without clobbering human-authored `.rest/http/local/` files.
- Test the first implementation against the gold HTTP specs under `cmd/gold-http/docs`.

## In progress

- None.

## Completed

- Scaffolded the `.rest/` project layout and env helpers for the Neovim `rest.nvim` workflow.
- Confirmed that the current integration has no native OpenAPI 3 import or sync command.
- Located candidate source specs in `lm/gold-search/cmd/gold-http/docs/` for the first real import test.

## Blocked / deferred

- Deferred until the `rest.nvim` workflow work is resumed; no generator implementation exists yet.

## Notes

- Current Neovim integration lives in `lua/plugins/rest-nvim.lua` and `lua/utils/rest.lua`.
- The existing ADR already recommends treating `.http` as the execution format and adding a generator layer instead of relying on `rest.nvim` itself for spec ingestion.
- Start with generation into `.rest/http/generated/`; avoid editing `rest.nvim` upstream unless the add-on layer proves too narrow.
