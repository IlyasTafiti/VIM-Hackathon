# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this folder.

## What This Is

AngelScript user plugins for **VIM Flex**, a native Windows 3D BIM viewer. Plugins add workflows, dockable UI panels (ImGui), and analytics over BIM data stored in DuckDB. This folder maps to the live `UserPlugins` directory (`%LOCALAPPDATA%\VIM\VIM Flex\UserPlugins\`) via the `vim-flex` MCP server — VIM Flex loads plugins from here on startup. See the root `CLAUDE.md` for shared BIM concepts.

Plugins are enabled in `vimflex.plugins.json`. Current plugins: `Demo/` (analytics dashboard with donut charts, level/room tables, material overrides) and `CostDraft/` (per-element cost estimation with 3D coloring and DuckDB save files). Each has a detailed README — read it before editing that plugin.

## Build / Test / Debug

There is no offline compiler. The dev loop runs through the `vim-flex` MCP server, which requires VIM Flex running in **Developer Mode** (Settings > Developer Settings):

1. Edit `.as` files (directly, or via `vim_write_script_file` / `vim_patch_script_file`)
2. `vim_compile` (MCP) — compiles all scripts in-process, no restart needed; errors come back as `[ERR] path/file.as:LINE message`
3. Test queries with `vim_query` (MCP) against the loaded model

- A compile error in ANY file under UserPlugins breaks loading — check all files, not just the one you edited.
- After a plugin recompile registers a new MCP script tool, clients don't refresh their tool list — and `/mcp reconnect vim-flex` has not proven to fix it. Tell the user to exit Claude Code and restart it to completely clear the MCP cache.
- VS Code debugging: attach via `angel-lsp-dap` on port 27979 (`.vscode/launch.json`).

## API Reference (don't guess at APIs)

- `as.predefined` (in this folder, and authoritative copy in `%ProgramFiles%\VIM\VIM Flex\`) — every available function signature: ImGui, `VimFlex::`, `Scene::`, widgets. Check it before writing helpers.
- `README.md` (this folder) — plugin file templates, lifecycle, TreeTable usage, SQL schema tables, query patterns.
- `%ProgramFiles%\VIM\VIM Flex\Scripts\` — built-in scripts (`core/Window.as`, `widgets/TreeTable.as`, `Main.as`, `BuiltinPlugins.as`) that plugins `#include` with relative paths like `../core/Window.as`.
- `%ProgramFiles%\VIM\VIM Flex\SamplePlugins\Example\` — reference plugin showing all the major patterns.
- `.claude/skills/` and `.claude/agents/` — project skills (angelscript-vim, bim-query, debug-autonomy, ui-ux-standard, ...) and specialized agents (`INDEX.md` is the selection guide).

## Architecture

A plugin is a folder of 3–4 files following one pattern (see `README.md` for full templates):

- `*Plugin.as` — namespace with global `EventToken`s subscribing to `VimFlex::OnPluginInit()` / `OnPluginShutdown()`. Init creates views, calls `g_app.views.AddDockableWindow()` and `g_app.AddWorkflow()`. Shutdown unsubscribes every token and destroys views.
- `*View.as` — `Window` subclass. `Render()` is called every frame (the base class handles Begin/End — don't call them). Subscribes to `OnVimDataChanged()` in `Open()`, unsubscribes in both `Close()` and `Destroy()`.
- `*DataService.as` — SQL via `array.DeserializeFromQuery(vimData, query)` into proxy classes, plus pre-built `Scene::SceneItemSet`s for instant 3D selection/coloring.
- `*Constants.as` — colors, thresholds, helpers.

Data is queried with DuckDB SQL over BIM tables (`Elements`, `Categories`, `Levels`, `Rooms`, `Warnings`, ...). Hierarchical UI uses the `TreeTable` widget: first `CREATE OR REPLACE TABLE` a flat denormalized table via `DataQueryGeneric()`, then configure (`SetFilterColumns`, aggregation — **before** `Init()`), then `Init(vimData, tableName, hierarchyCols, displayCols, scene, "elementIndex")`. 3D interaction goes through `GetSelectionService().Apply(itemSet)` and `GetInteractionService()` (isolate/frame/show-all).

## Critical Gotchas (silent failures and crashes)

- **`string`, not `hstring`** in SQL proxy classes — `hstring` compiles but returns empty strings at runtime. Proxy field names must exactly match SQL column aliases; use value arrays (`array<MyRow>`), not handle arrays.
- **`Util::FormatDecimal`/`FormatInt` add thousands separators** — UI display only. For CSV, SQL VALUES, or any machine-readable output use `FormatCSVNumber()` from `shared/StringUtils.as` or `formatFloat(val, "", 0, 6)`.
- **No trailing commas in array literals** — adds a null entry.
- `DeserializeFromQuery` wants `Scene::VimData@` (i.e. `wrapper.GetData()`), not the `VimData` wrapper.
- Never `GROUP_CONCAT` element IDs — models have millions of elements; aggregate counts, query IDs on-demand per click.
- `Core::EscapeSql()` when interpolating strings into SQL.
- Always unsubscribe event tokens in both `Destroy()` and `Close()`; always call `TreeTable.Destroy()` on cleanup.
- AngelScript `string` has no `replace`; `ImGui::TextUnformatted` is not bound (use `ImGui::Text`); every `PushStyleColor` needs a matching `PopStyleColor`.
- Tables made via `DataQueryGeneric` `CREATE TABLE` are regular (non-TEMP) DuckDB tables — they persist across calls on the main connection.
- Debug output: `VimFlex::Console::Log()`.
