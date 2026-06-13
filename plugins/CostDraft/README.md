# Cost Draft

Workflow for drafting per-element cost estimates keyed by
`{Category, Family, FamilyType}` and visualizing the results in 3D.

Replaces the earlier `CostVisualization` plugin (which keyed costs by Revit
element ID).

## Files

| File | Purpose |
|------|---------|
| `CostDraftPlugin.as` | Plugin registration and workflow wiring |
| `CostDraftView.as` | Editable cost table, search/selection/bulk edit, recalc, 3D coloring, Save/Load |
| `CostBreakdownView.as` | Left-side Window hosting the `ElementTreeCard` plus a footer with the Low/Mid/High threshold inputs (value + color swatch + reset), `Select Costed` / `Select Uncosted` buttons, and the 3D color-overlay toggle |
| `CostDataSchema.as` | Persistence schema, version stamp, and lazy in-memory migration |
| `CostDraftMcpTools.as` | Registers the `cost_draft_recalculate` and `cost_draft_set_color_thresholds` script MCP tools |
| `snowdon_cost_sheet.duckdb` | Sample saved cost sheet (a Save-format `.duckdb` file, loadable via the `Load` button) |

## Workflow layout

Workflow name: **Cost Draft**

| Region | Contents | Notes |
|--------|----------|-------|
| Left   | `parameterView` (built-in, tab), `CostBreakdownView` | Replaces the built-in `elementTreeView` for this workflow |
| Right  | `CostDraftView` (titled "Costs") | Given ~50% of screen width on open via `VimFlex::RequestUpdateDockingRegions(-1, 0.50, -1, -1)` |

## Data model

```angelscript
enum CostUnitKind { CostUnit_Count, CostUnit_InstanceParameter, CostUnit_TypeParameter }

class CostInfo
{
    string Category;
    string Family;
    string FamilyType;
    double CostPerUnit;
    int    CostUnit;                  // CostUnitKind
    string CostUnitParameterName;     // ignored when CostUnit == Count
    bool   Selected;                  // runtime-only (not persisted)
}
```

Rows live in `array<CostInfo> _rows` in `CostDraftView`. The
`{Category, Family, FamilyType}` triple is the unique key; `PopulateFromModel()`
keeps edits for keys that still exist and appends new combos.

## Populate From Model

On `Open()` and on `GetVimDataService().OnVimDataChanged()` (fires only when a
VIM is loaded/reloaded — deliberately **not** `GetDataUpdatedCallbacks()`, which
would also fire on the plugin's own `DataQueryGeneric` writes and wipe loaded
costs after every recalc), the view runs:

```sql
SELECT DISTINCT
    COALESCE(c.name,        '<unknown>') AS Category,
    COALESCE(e.familyName,  '<unknown>') AS Family,
    COALESCE(e.familyTypeName, '<unknown>') AS FamilyType
FROM Elements e
LEFT JOIN Categories c ON e.categoryIndex = c.index
WHERE e.domain = 'Physical-Visible'
ORDER BY Category, Family, FamilyType
```

Each combo becomes a row with defaults `CostPerUnit=0, CostUnit=Count`.

## Cost calculation

`Recalculate()` rebuilds three DuckDB tables on the main connection:

1. **`CostInfoRows`** — serialized from `_rows` via chunked `INSERT VALUES`
   (200 rows per query). Strings are escaped with `Core::EscapeSql`; numeric
   values use AngelScript's built-in `formatFloat(val, "", 0, 6)` — using
   `Util::FormatDecimal` here would inject thousands-separator commas that
   break the comma-delimited VALUES tuple (see CODE_STYLE §8).

2. **`CostMatchedElements`** — physical-visible elements joined to
   `CostInfoRows` on `Category / Family / FamilyType`, so the parameter scan
   below only touches matched elements.

3. **`CostData`** — one row per physical element that matches a `CostInfoRows`
   key, with `Cost`, `MissingParam`, and `elementIndex` columns. Built from
   `CostMatchedElements` via a CTE chain:
   - `TypeIdx`: `FamilyTypes.elementIndex` mapped to `(familyName, typeName)`,
     filtered via `EXISTS` to only types referenced by `TypeParameter` rows.
   - `InstParamVals`: `Parameters × ParameterDescriptors` filtered to
     parameter names referenced by `InstanceParameter` rows, and to elements
     in `CostMatchedElements`. Uses `ROW_NUMBER()` to pick a single value per
     (element, name) if a name appears multiple times.
   - `TypeParamVals`: same pattern, joined to the type element via `TypeIdx`.
   - Final `SELECT` applies the per-row cost formula:

| CostUnit | Formula |
|----------|---------|
| `Count` | `CostPerUnit` |
| `InstanceParameter` | `TRY_CAST(SPLIT_PART(p.value, '|', 1) AS DOUBLE) * CostPerUnit`; parameter looked up on the element |
| `TypeParameter` | same, but parameter looked up on the element's FamilyType element |

The raw native value (left of the `\|` in the Revit `raw\|display` string) is
used. Non-numeric values yield 0 (`TRY_CAST` + `COALESCE`); `MissingParam = 1`
is set when the element has no row for the named parameter at all. Revit units
are raw (ft / ft² / ft³).

Optimization: the parameter CTEs filter by descriptor name and element set, so
when no rows reference parameters the CTE scans nothing. This keeps the
initial recalc cheap on a zero-cost model.

## UI features (CostDraftView)

- **Header** + description (secondary text).
- **Toolbar**: `Save`, `Load`, `Recalculate` (label becomes `Recalculate *`
  when the state is dirty), and a destructive `Clear` button (resets every
  row's cost data; enabled only when some row has non-default cost info).
  Long actions defer behind a short "Calculating Costs..." modal so ImGui
  can paint (and commit in-flight input edits) before the SQL blocks the
  main thread. The 3D color toggle lives in `CostBreakdownView`'s footer,
  not here.
- **Summary**: `Total` (large bold), a `Selection Cost` line (sum of
  `CostData.Cost` over the current 3D selection, with selected-element
  count), element count, `Avg`, and a `CARD_AMBER` warning showing the
  count of elements with missing parameter values.
- **Sync toggle** (default on): filters the table to rows whose
  Category/Family/Type is represented in the current 3D selection; a no-op
  when nothing is selected.
- **Search** (`ImGui::InputText`): substring, case-insensitive, matches
  any of Category / Family / Type.
- **Selection**: checkbox column, `Select All Shown` (respects current filter),
  `Clear Selection`, live count of selected rows.
- **Bulk-edit strip** (always rendered; shows a hint until ≥1 row is
  selected): fields for `CostPerUnit`, `CostUnit` (with a "(no change)"
  option), and `CostUnitParameterName`, plus a single `Apply` button —
  blank/unset fields are skipped, so the user can push one field at a time.
- **Row table**: checkbox (28px fixed) + Category / Family / Type
  (1.4 stretch each, `CardTextPrimary()`), `$ / Unit` (1.6 — matches Unit
  so the +/- spinner fits), `Unit` (1.6), `Parameter` (2.0). Parameter input
  is disabled (`-`) when `CostUnit == Count`. Switching unit preserves the
  parameter name.

## 3D coloring

- Color-overlay toggle (icon button, right-aligned in `CostBreakdownView`'s
  footer, default **on**):
  - On → `ApplyColors()` maps element costs through a piecewise gradient
    between the Low / Mid / High threshold values and their per-stop colors
    (defaults green → amber → red; both editable in the breakdown footer).
    Costs outside `[low, high]` clamp to the edge colors. Elements with
    `Cost <= 0` (no cost, or missing parameter) receive
    `COST_UNKNOWN_COLOR = color(229, 229, 229, 255)` — the same unknown color
    constant used by the Example plugin.
  - Off → `ClearMaterialOverrides()`.
- While the toggle is on, `Recalculate()` re-applies colors automatically, and
  any threshold/stop-color edit in the breakdown footer (polled via
  `TakeThresholdsDirty()`) re-applies them on the next frame.

## Save / Load

Single-file format: a DuckDB database file (`*.duckdb`). Schema layout and
version-aware reads live in `CostDataSchema.as`; `CostDraftView` only knows
how to wire the model's `CostInfoRows` to disk and delegates everything
else to the schema module.

Tables in a current-version file:

| Table | Purpose |
|------|--------|
| `_CostDraftMeta` | Single row holding `schema_version INTEGER`. Absent ⇒ implicit v1. |
| `CostInfoRows` | `Category, Family, FamilyType, CostPerUnit, CostUnit, CostUnitParameterName` (`CostUnit` written as the enum name, e.g. `Count`). |
| `CostSettings` | `lowValue, midValue, highValue` `DOUBLE`s + per-stop RGBA columns (`lowR/G/B/A`, `midR/G/B/A`, `highR/G/B/A` as `UTINYINT`). |

`Save` calls `BuildCostInfoRowsTable()` to sync `_rows` into the active
DuckDB schema, then `ATTACH '<path>' AS CostDraftSave`, copies
`CostInfoRows`, calls `CostDataSchema::WriteSchemaMeta(...)` and
`WriteSettings(...)`, and `DETACH CostDraftSave`. The `INSERT` into
`CostSettings` uses `formatFloat(val, "", 0, 6)` to avoid the
thousands-separator issue in `Util::FormatDecimal` (see CODE_STYLE §8).

`Load` runs `ATTACH '<path>' AS CostDraftLoad (READ_ONLY)`, calls
`CostDataSchema::ReadSchemaVersion(...)`, refuses to load files written by
a newer plugin (with a warning), then `CostDataSchema::ReadSettings(...)`
and `_breakdown.ApplySettings(...)`. The merge against the model combos →
`DeserializeFromQuery` into `array<CostInfoRow>` → translate `CostUnit` to
its int enum → `MaybeRecalculate()` is unchanged.

### Schema versioning and lazy migration

`CostDataSchema::CURRENT_SCHEMA_VERSION` is the version Save stamps. Load
reads the file's `schema_version` and dispatches `ReadSettings` to the
matching read paths; absent columns leave the in-memory `Settings` fields
at their defaults. Migration is **lazy**: the on-disk file is never
modified by Load — the user's next Save rewrites it in the current format.

To bump the schema:

1. Add new columns to the relevant `WriteX(...)` call (current-version
   writer always emits the full set).
2. Append a new `if (version >= N)` block in the corresponding `ReadX(...)`
   that pulls the new columns when present.
3. Bump `CURRENT_SCHEMA_VERSION`.
4. Document the new version in the file header's "Version history" comment.

Backwards-compat ground rules to keep migrations small:

- New columns are nullable or have a sensible default; old columns never
  disappear or change semantics.
- New tables are optional; readers probe via `information_schema`.

Version history (mirrored in `CostDataSchema.as`):

| Version | Change |
|---------|--------|
| v1 | `CostInfoRows` + `CostSettings(lowValue, midValue, highValue)`. Files written before `_CostDraftMeta` existed are treated as v1. |
| v2 | `CostSettings` adds per-stop RGBA color columns so the user-chosen gradient (e.g. blue→purple instead of green→red) round-trips through Save/Load. |

## Agent workflow (MCP)

`CostDraftMcpTools.as` registers two script tools via
`VimFlex::GetMcpService().RegisterScriptTool(...)`:

| Tool | Args | Behavior |
|------|------|----------|
| `cost_draft_recalculate` | none | Reads the current `CostInfoRows` DuckDB table back into `_rows`, preserves the user's row-checkbox selection by key, then runs the standard recalc path (`MaybeRecalculate` → `BuildCostInfoRowsTable` → `BuildCostDataTable` → `LoadSummary` → `LoadElementCosts` → `CostBreakdownView.RebuildFromCostData` → `ApplyColors`). |
| `cost_draft_set_color_thresholds` | `lowValue`, `midValue`, `highValue` (doubles, same currency units as `CostData.Cost`) | Pushes the three values into `CostBreakdownView` via `SetColorStopValues`, updates the TreeTable gradient stops, and marks the overlay dirty so `CostDraftView.Render` re-applies 3D colors on the next frame. Per-stop colors are preserved — edit them via the in-app color pickers (or a future extension to this tool). |

Typical agent session:

```
-- 1. Inspect schema & current state
vim_query: SELECT * FROM CostInfoRows LIMIT 5
-- 2. Mutate values in place
vim_query: UPDATE CostInfoRows
           SET CostPerUnit = 50.0, CostUnit = 'InstanceParameter',
               CostUnitParameterName = 'Area'
           WHERE Category = 'Walls' AND Family = 'Basic Wall'
-- 3. Absorb & recalc; the tree and 3D coloring update in place
cost_draft_recalculate
-- 4. Use the Cost distribution to pick useful thresholds
vim_query: SELECT approx_quantile(Cost, 0.50) AS p50,
                  approx_quantile(Cost, 0.90) AS p90,
                  approx_quantile(Cost, 0.99) AS p99
           FROM CostData WHERE Cost > 0
-- 5. Retarget the gradient at the meaningful per-element cost range
cost_draft_set_color_thresholds lowValue=100 midValue=2500 highValue=25000
```

Callbacks run on the main render thread (via
`ProcessPendingScriptToolCalls`), so they're safe to touch plugin state
directly. Registration happens in `HandlePluginInit`; the view handles are
nulled in `HandlePluginShutdown` so a stale registration after a plugin
recompile becomes a warn-and-noop instead of a crash. The actual
unregistration is handled by `App.Destroy`'s
`UnregisterAllScriptTools()`.

**Client-side gotcha**: MCP clients cache the tool list for the life of
the transport connection. When a plugin recompile registers a new tool
mid-session (e.g. after adding a third tool here), the VIM Flex server
broadcasts `notifications/tools/list_changed`, but most clients don't
re-query `tools/list` — and `/mcp reconnect vim-flex` has not proven to
force a refresh either. Exit Claude Code and restart it to completely
clear the MCP cache. The UserPlugins-level `CLAUDE.md` (one folder up)
carries the same reminder.

## Known gotchas / things to mind when editing

- `DeserializeFromQuery` wants `Scene::VimData@` (i.e. `_vimData.GetData()`),
  not the `VimData` wrapper.
- `ImGui::TextUnformatted` is not bound — use `ImGui::Text`.
- AngelScript `string` has no `replace` method — use `join(s.split(...), ...)`.
- `ImGui::InputFloat` uses the in/out pattern (`value`, `&valueOut`).
- Every `PushStyleColor` needs a matching `PopStyleColor`.
- No trailing commas in array literals (adds a null entry).
- The `CostInfoRows`, `CostMatchedElements`, `CostData`, and `CostBreakdownTable`
  names are regular (non-TEMP) DuckDB tables — they survive across
  `DataQueryGeneric` calls on the main connection.
