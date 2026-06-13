# Demo Dashboard Plugin

Interactive BIM analytics dashboard with summary stat cards, a BIM Documents donut chart, sortable level/room/category/material tables, element tagging, transparent room geometry, and cross-chart coordination.

---

## File Map

| File | Purpose |
|------|---------|
| `DemoPlugin.as` | Plugin entry point. Creates services and views, registers the workflow, wires cross-chart callbacks. |
| `DemoView.as` | "BIM Documents" view (top panel, left). Hosts the BIM Documents donut chart, owns the shared DemoDataService and the deferred loading modal. |
| `DemoSummaryView.as` | Summary view (top panel, docked right of the donut). 7x2 grid of model-wide stat cards (elements, triangles, parameters, categories, ...). |
| `DemoLevelHistogramView.as` | Levels tab (right panel). Sortable table with elevation and inline element bars. |
| `DemoRoomTableView.as` | Rooms tab (right panel). Sortable table with room number, level, area, volume, elements. |
| `DemoCategoryTableView.as` | Categories tab (right panel). Sortable table with inline element bars, default-sorted by count descending. |
| `DemoMaterialTableView.as` | Materials tab (right panel). Sortable table with model material colors, area/volume bars, paint flag. Clear-colors button only (no apply/shuffle). |
| `DemoTagsView.as` | Tags tab (right panel). `ElementTaggerView`: assigns custom tags to selected elements, stored in a DuckDB table (`_ExTagUserTags`) keyed by UniqueId, with CSV save/load. |
| `DemoDataService.as` | Shared data layer. SQL queries, stats deserialization, SceneItemSet pre-building, parallel async loading. Owns no UI. |
| `DemoMaterialService.as` | Centralized material override service. Maintains the glass material invariant on room geometry. |
| `DemoTableCard.as` | Reusable base class for sortable table cards. Provides sort, selection (click/Ctrl/Shift), clipper, header controls. |
| `DemoDonutChart.as` | Donut chart card (extends Card). Used by DemoView for the BIM Documents chart. |
| `DemoCardTypes.as` | Shared types: `CardItem` class and callback funcdefs (`CardItemClickCallback`, `CardColorCallback`, `CardShuffleCallback`). |
| `DemoConstants.as` | Color palette (`DEMO_PALETTE`), unknown label/color constants (`UNKNOWN_LABEL`, `UNKNOWN_COLOR`), color helper functions. |
| `vxp.json` | Plugin manifest (name, version, author, description, license). |

---

## Architecture

```
DemoPlugin (orchestrator)
    |
    +-- DemoMaterialService (material overrides + glass invariant)
    |       ^
    |       | SetRoomGeometry() / ClearRoomGeometry()
    |       |
    +-- DemoDataService (SQL queries, SceneItemSets)
    |       ^
    |       | reads stats from
    |       |
    +-- DemoView (BIM Documents donut, owns DemoDataService + loading modal)
    |       |
    +-- DemoSummaryView (7x2 summary stat grid, reads dataService directly)
    |       |
    +-- DemoLevelHistogramView --> DemoLevelHistogramCard : DemoTableCard
    |       |
    +-- DemoRoomTableView ------> DemoRoomTableCard : DemoTableCard
    |       |
    +-- DemoCategoryTableView --> DemoCategoryTableCard : DemoTableCard
    |       |
    +-- DemoMaterialTableView --> DemoMaterialTableCard : DemoTableCard
    |
    +-- ElementTaggerView (Tags tab; standalone, DuckDB tag table + CSV import/export)
```

### Data Flow

1. **VIM file loaded** -- `OnVimDataChanged` fires in each view
2. DemoView defers loading a few frames (so the loading modal renders), then calls `dataService.StartLoadAllAsync()` -- 7 parallel jobs (summary, category, family type, BIM document, level, room, material)
3. Each job runs SQL, populates stats arrays, builds SceneItemSets
4. When all jobs complete, `FinishLoadAllAsync()` calls `ApplyRoomGeometry()` -> `matService.SetRoomGeometry()` with merged room geometry
5. Views populate their card items from dataService stats (polling `IsDataLoaded()` in Render)
6. User interacts with charts/tables -> selection/color callbacks fire

### Material Override Flow

All color operations go through `DemoMaterialService`:
- `ClearColors()` -- calls engine `ClearMaterialOverrides()`, then re-applies glass
- `ApplyColor(set, color)` -- creates a cached `StandardOpaque` material instance per color and calls `SetMaterialOverride()`. This avoids the bug where `SetColor()` turns elements with transparent submeshes fully transparent.

Material instances are cached for reuse across clear/apply cycles and destroyed on data unload or plugin shutdown.

This ensures room geometry always stays transparent regardless of which card applies/clears colors.

**Gotcha**: Room table's "Apply Colors" must use `GetPhysicalItemSetForRoom()` (not `GetItemSetForRoom()`) to avoid overwriting glass on room geometry with an opaque color.

### Cross-Chart Coordination

When any card applies colors or selection, it notifies others via callbacks wired in DemoPlugin:
- `onClearOtherSelections` -- fired on click, clears selections in other cards
- `onClearOtherColors` -- fired on color toggle, clears colorsApplied flags in other cards

All four table views (Levels, Rooms, Categories, Materials) expose these callbacks. The plugin's callback functions (`OnClearFromLevel`, `OnClearFromRoom`, `OnClearFromCategory`, `OnClearFromMaterial`, and the `OnClearColorsFrom*` variants) call `demoView.ClearChartSelections()` / `ClearChartColors()` and reset the other table cards' selection / `colorsApplied` state. The Materials card has no apply/shuffle controls; its clear-colors button calls `_matService.ClearColors()` and fires `onClearOtherColors`.

---

## DemoTableCard -- How to Subclass

DemoTableCard provides the full table infrastructure. Subclasses only define columns and cell rendering.

### Required Overrides

| Method | Purpose |
|--------|---------|
| `int GetColumnCount()` | Total number of columns (including color dot if used) |
| `void SetupColumns()` | Call `ImGui::TableSetupColumn()` for each column. Use `SetupColorDotColumn()` helper for the dot. |
| `void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl)` | Render all cells for one row. Call `RenderSelectableCell(idx, row)` for the click-target column. Call `RenderColorDot(idx, dl)` for the color dot. Call `ImGui::TableNextColumn()` + draw for others. |
| `int CompareItems(uint a, uint b, int column, bool ascending)` | Return -1/0/+1 for sorting. Return value is already direction-aware (negate for descending). |

### Optional Overrides

| Method | Purpose |
|--------|---------|
| `void ApplyInitialSort()` | Called once when sorted indices are first built. Use `SortByColumn(col, asc)`. |
| `void OnClearData()` | Called by `ClearData()` to clear subclass-specific arrays. |

### Helper Methods (call from overrides)

| Method | Purpose |
|--------|---------|
| `RenderSelectableCell(idx, row)` | Renders the name label with Selectable + SpanAllColumns. Handles click/Ctrl/Shift. Calls `TableNextColumn()` internally. |
| `RenderColorDot(idx, dl)` | Renders a filled circle with `items[idx].itemColor`. Calls `TableNextColumn()` internally. |
| `SetupColorDotColumn()` | Adds a fixed 24px non-sortable column for the color dot. |
| `SortByColumn(col, asc)` | Programmatically sort by a column index. |

### Example: Minimal Table Card

```angelscript
class MyCard : DemoTableCard
{
    int GetColumnCount() override { return 2; }

    void SetupColumns() override
    {
        ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch);
        ImGui::TableSetupColumn("Count", ImGuiTableColumnFlags_WidthFixed, 60);
    }

    void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl) override
    {
        RenderSelectableCell(idx, row);

        ImGui::TableNextColumn();
        ImGui::Text(CardFormatInt(int(items[idx].value)));
    }

    int CompareItems(uint a, uint b, int column, bool ascending) override
    {
        int result = 0;
        if (column == 0)
        {
            if (items[a].label < items[b].label) result = -1;
            else if (items[a].label > items[b].label) result = 1;
        }
        else if (column == 1)
        {
            if (items[a].value < items[b].value) result = -1;
            else if (items[a].value > items[b].value) result = 1;
        }
        return ascending ? result : -result;
    }
}
```

---

## DemoDataService -- SceneItemSet Dictionaries

The data service pre-builds SceneItemSets at load time for instant selection and coloring. There is one dictionary per grouping: `_categoryToSet`, `_familyTypeToSet`, `_bimDocumentToSet`, `_levelToSet`, and `_materialToSet`. For rooms, there are three separate dictionaries:

| Dictionary | Domain Filter | Purpose |
|------------|--------------|---------|
| `_roomToSet` | Physical-Visible + Topography + Rooms | Selection (includes room geometry for visibility) |
| `_roomPhysicalToSet` | Physical-Visible + Topography only | Color application (avoids overwriting glass on room geometry) |
| `_roomGeometryToSet` | Rooms only | Glass material override target |

**Gotcha**: When applying room colors, use `GetPhysicalItemSetForRoom()`. When selecting rooms (click), use `GetItemSetForRoom()` so room geometry stays visible in the viewport. The glass material on room geometry is managed by DemoMaterialService, not by the views.

---

## Common Gotchas

| Issue | Solution |
|-------|----------|
| Room geometry turns opaque after color toggle | Room color clicked handler must use `GetPhysicalItemSetForRoom()`, not `GetItemSetForRoom()` |
| Colors from other cards clear glass | All cards must call `_matService.ClearColors()` instead of engine `ClearMaterialOverrides()` directly |
| `<unknown>` not at top of level table | `CompareItems()` must pin `UNKNOWN_LABEL` to top: return -1 for unknown-a, +1 for unknown-b |
| Duplicate level names | DataService groups by `COALESCE(l.name)` which merges levels with identical names at different elevations |
| Selection highlights override glass | Glass invariant is maintained by DemoMaterialService -- every `ClearColors()` call re-applies the glass override to room geometry |
| New card doesn't clear other cards | Wire `onClearOtherSelections` / `onClearOtherColors` in DemoPlugin and add clear logic in the callback |
| Color palette colors too similar for neighbors | Palette is pre-ordered for maximum perceptual contrast between consecutive entries |
| AngelScript trailing comma | Never use trailing commas in array literals -- adds a null entry |
| `colorsApplied` flag stale after cross-chart clear | Plugin callbacks must reset the flag on affected cards |

---

## Lifecycle Summary

```
HandlePluginInit()
    Create DemoMaterialService, init with AppScene
    Create DemoView (which creates DemoDataService)
    Create SummaryView, LevelTableView, RoomTableView, CategoryTableView, MaterialTableView, TaggerView
    Wire material service to data service and the chart/table views
    Wire cross-chart callbacks
    Register dockable windows and the "Demo Dashboard" workflow (VIM Hackathon)

VIM File Loaded -> OnVimDataChanged()
    DemoView defers loading a few frames so the loading modal renders first
    DataService.StartLoadAllAsync() runs 7 parallel load jobs (SQL + SceneItemSets)
    DataService.FinishLoadAllAsync() calls ApplyRoomGeometry() -> matService.SetRoomGeometry()
    Each view populates card items from dataService stats once IsDataLoaded()

VIM File Unloaded -> OnVimDataChanged()
    Each view clears card data, resets selection/color state
    DataService.ClearData() cancels pending load jobs and calls matService.ClearRoomGeometry()

HandlePluginShutdown()
    Destroy views (unsubscribe events, null callbacks)
    Destroy material service (destroys glass + cached color material instances)
```
