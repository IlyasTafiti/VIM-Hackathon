# VIM Flex User Scripts

This folder contains user plugins that extend VIM Flex with custom BIM analytics, visualizations, and workflows. Plugins are written in AngelScript and loaded automatically on startup.

---

## Getting Started: The Example Plugin

The best way to learn plugin development is to read the **Example** plugin (`SamplePlugins/Example/`). It is a fully-featured BIM analytics dashboard demonstrating the most important patterns.

**To run it:**
1. Load a VIM file
2. Select the **BIM Analytics** workflow from the workflow menu
3. Browse element statistics by Category, Level, Family, Workset, and more
4. Click chart bars to select elements in the 3D viewport

**What it demonstrates:**
- Plugin lifecycle (`OnPluginInit`, `OnPluginShutdown`)
- SQL queries against BIM data (`DeserializeFromQuery`)
- Event subscription (data changes, selection changes)
- Scene selection service integration
- Visibility and isolation of elements
- Custom workflows with docked views
- ImGui UI rendering
- 3D visualizations with a custom viewport

---

## Plugin Structure

A plugin typically has 3-4 files in its own folder:

```
UserPlugins/
+-- MyPlugin/
    +-- MyPluginConstants.as    # Constants, enums, color helpers
    +-- MyPluginDataService.as  # SQL queries and data management
    +-- MyPluginView.as         # UI view (Window subclass)
    +-- MyPluginPlugin.as       # Plugin registration and lifecycle
```

---

## Plugin Lifecycle

```
OnPluginInit()
  +-- Create views
  +-- Register workflows
  +-- Subscribe to OnVimDataChanged()

OnVimDataChanged()
  +-- Run SQL queries via DeserializeFromQuery()
  +-- Update UI state

View.Render()  [called each frame]
  +-- Draw ImGui widgets

OnPluginShutdown()
  +-- Unsubscribe all event tokens
  +-- Destroy views
```

---

## File Templates

### Constants (`MyPluginConstants.as`)

```angelscript
const color COLOR_GOOD = color(115, 174, 73, 255);
const color COLOR_BAD  = color(222, 64, 56, 255);
const float THRESHOLD_WARNING = 5.0f;

color GetQualityColor(float value)
{
    return value < THRESHOLD_WARNING ? COLOR_GOOD : COLOR_BAD;
}
```

### Data Service (`MyPluginDataService.as`)

Proxy class field names must match SQL column aliases exactly.

```angelscript
#include "MyPluginConstants.as"

class CategoryStats
{
    string name;        // matches "c.name as name" - must be string, not hstring
    int count;          // matches "COUNT(*) as count"
}

class ElementWithIndex
{
    uint32 elementIndex;  // matches "e.index as elementIndex"
}

class MyDataService
{
    array<CategoryStats> categoryStats;
    int totalElements = 0;

    private Scene::VimData@ _vimData;
    private bool _loaded = false;

    void SetVimData(Scene::VimData@ vimData)
    {
        @_vimData = vimData;
        _loaded = false;
    }

    bool IsLoaded() { return _loaded; }

    void Load()
    {
        if (_vimData is null) return;

        categoryStats.DeserializeFromQuery(_vimData,
            "SELECT c.name as name, COUNT(*) as count " +
            "FROM Elements e " +
            "LEFT JOIN Categories c ON e.categoryIndex = c.index " +
            "WHERE c.name IS NOT NULL " +
            "GROUP BY c.name " +
            "ORDER BY count DESC " +
            "LIMIT 15");

        totalElements = 0;
        for (uint i = 0; i < categoryStats.length(); i++)
            totalElements += categoryStats[i].count;

        _loaded = true;
    }

    array<uint32>@ GetElementsForCategory(const string&in catName)
    {
        array<ElementWithIndex> rows;
        rows.DeserializeFromQuery(_vimData,
            "SELECT e.index as elementIndex " +
            "FROM Elements e " +
            "LEFT JOIN Categories c ON e.categoryIndex = c.index " +
            "WHERE c.name = '" + Core::EscapeSql(catName) + "'");

        array<uint32>@ result = array<uint32>();
        for (uint i = 0; i < rows.length(); i++)
            result.insertLast(rows[i].elementIndex);
        return result;
    }
}
```

### View (`MyPluginView.as`)

```angelscript
#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/TreeTable.as"
#include "MyPluginConstants.as"
#include "MyPluginDataService.as"

class MyPluginView : Window
{
    private App@ _app;
    private AppScene@ _appScene;
    private MyDataService@ _dataService;
    private TreeTable@ _tree;
    private Scene::EventToken@ _dataChangedToken = null;

    MyPluginView(App@ app)
    {
        super("My Plugin", ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_dataService = MyDataService();
    }

    void Destroy() override
    {
        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }
        if (_tree !is null)
        {
            _tree.Destroy();
            @_tree = null;
        }
    }

    void Open() override
    {
        Window::Open();
        if (_dataChangedToken is null)
        {
            @_dataChangedToken = _appScene.GetVimDataService().OnVimDataChanged()
                .Subscribe(Scene::Event::EventCallback(OnVimDataChanged));
        }
        OnVimDataChanged();
    }

    void Close() override
    {
        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }
        Window::Close();
    }

    private void OnVimDataChanged()
    {
        auto@ vimDataWrapper = _appScene.GetVimData();
        if (vimDataWrapper is null) return;
        auto@ vimData = vimDataWrapper.GetData();
        if (vimData is null) return;

        _dataService.SetVimData(vimData);
        _dataService.Load();

        if (_tree !is null) _tree.Destroy();

        // Step 1: create the flat denormalized temp table
        string tableName = "MyPluginTable";
        vimData.DataQueryGeneric(
            "CREATE OR REPLACE TABLE " + tableName + " AS SELECT "
            "    e.index AS elementIndex, "
            "    COALESCE(cat.name, '<unknown>') AS Category, "
            "    COALESCE(e.familyName, '<unknown>') AS Family, "
            "    COALESCE(level.name, '<unknown>') AS Level, "
            "    COALESCE(e.domain, '<unknown>') AS Domain, "
            "    1 AS Count "
            "FROM Elements e "
            "LEFT JOIN Categories cat ON e.categoryIndex = cat.index "
            "LEFT JOIN Levels level ON e.levelIndex = level.index "
            "WHERE e.domain = 'Physical-Visible'"
        );

        // Step 2: init TreeTable - SetFilterColumns and aggregation must come BEFORE Init()
        @_tree = TreeTable();
        _tree.tableId = "##MyTree";
        _tree.sendSelectionEvents = true;
        _tree.respondToSelectionEvents = true;
        _tree.showFooter = true;
        _tree.footerLabel = "TOTAL";

        _tree.SetFilterColumns(vimDataWrapper, {"Category", "Level"});
        _tree.SetDisplayColumnAggregation(0, TreeTableAggOp_Sum);
        _tree.SetDisplayColumnFormat(0, TreeTableFormat_Integer);

        _tree.Init(vimData, tableName,
            {"Category", "Family"},
            {"Count"},
            _appScene.GetScene(), "elementIndex");
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionLeft);
    }

    bool Render(const IRenderContext& ctx) override
    {
        if (!_dataService.IsLoaded())
        {
            ImGui::TextDisabled("Load a VIM file to begin");
            return true;
        }

        ImGui::Text("Total Elements: " + _dataService.totalElements);
        Style::VSpace();

        if (_tree !is null)
        {
            _tree.maxHeight = ImGui::GetContentRegionAvail().y;
            _tree.Render();
        }

        return true;
    }
}
```

### Plugin Registration (`MyPluginPlugin.as`)

```angelscript
#include "MyPluginView.as"
#include "../Main.as"
#include "../BuiltinPlugins.as"

namespace MyPlugin
{
    MyPluginView@ myView;

    Scene::EventToken@ gInitToken = VimFlex::OnPluginInit()
        .Subscribe(Scene::Event::EventCallback(HandlePluginInit));

    Scene::EventToken@ gShutdownToken = VimFlex::OnPluginShutdown()
        .Subscribe(Scene::Event::EventCallback(HandlePluginShutdown));

    void HandlePluginInit()
    {
        @myView = MyPluginView(g_app);
        g_app.views.AddDockableWindow(myView);

        g_app.AddWorkflow(
            "My Plugin",
            false,
            BuiltinPlugins::GetBuiltInViews(),
            {
                myView,
                BuiltinPlugins::parameterView
            },
            false
        );
    }

    void HandlePluginShutdown()
    {
        if (gInitToken !is null) { gInitToken.Unsubscribe(); @gInitToken = null; }
        if (gShutdownToken !is null) { gShutdownToken.Unsubscribe(); @gShutdownToken = null; }
        if (myView !is null) { myView.Destroy(); @myView = null; }
    }
}
```

---

## TreeTable

`TreeTable` is the primary widget for displaying hierarchical BIM data. It is backed by DuckDB and integrates with the scene selection service.

### Setup

TreeTable requires a flat denormalized temp table created via SQL first. `Init()` takes the temp table name - not a SQL string and not `"Vim_Element"`. Always: create the table, set filter/aggregation, then call Init.

```angelscript
#include "../widgets/TreeTable.as"

// Step 1: create flat denormalized temp table
string tableName = "MyTree";
vimData.DataQueryGeneric(
    "CREATE OR REPLACE TABLE " + tableName + " AS SELECT "
    "    e.index AS elementIndex, "
    "    COALESCE(cat.name, '<unknown>') AS Category, "
    "    COALESCE(e.familyName, '<unknown>') AS Family, "
    "    COALESCE(e.familyTypeName, '<unknown>') AS Type, "
    "    COALESCE(level.name, '<unknown>') AS Level, "
    "    1 AS Count "
    "FROM Elements e "
    "LEFT JOIN Categories cat ON e.categoryIndex = cat.index "
    "LEFT JOIN Levels level ON e.levelIndex = level.index "
    "WHERE e.domain = 'Physical-Visible'"
);

// Step 2: configure then Init (SetFilterColumns and aggregation MUST come before Init)
TreeTable@ tree = TreeTable();
tree.tableId = "##MyTree";
tree.sendSelectionEvents = true;
tree.respondToSelectionEvents = true;

tree.SetFilterColumns(vimDataWrapper, {"Category", "Level", "Workset"});
tree.SetDisplayColumnAggregation(0, TreeTableAggOp_Sum);
tree.SetDisplayColumnFormat(0, TreeTableFormat_Integer);
tree.SetDisplayColumnHideZero(0, true);

tree.Init(vimData, tableName,
    {"Category", "Family", "Type"},  // hierarchy levels (must be columns in temp table)
    {"Count"},                        // display columns (must be columns in temp table)
    scene, "elementIndex");           // elementIndex column used for 3D selection sync

tree.SetDisplayColumnBgColorMode(0, TreeTableColorMode_Interpolate);
tree.SetDisplayColumnBgColorPoint(0, 0.0f, color(50, 200, 50, 60));
tree.SetDisplayColumnBgColorPoint(0, 1000.0f, color(200, 50, 50, 60));

tree.showFooter = true;
tree.footerLabel = "TOTAL";

// Each frame:
tree.Render();

// On destroy:
tree.Destroy();
```

### Aggregation Options

| Constant | Meaning |
|----------|---------|
| `TreeTableAggOp_Sum` | Sum of leaf values |
| `TreeTableAggOp_Average` | Average of leaf values |
| `TreeTableAggOp_Max` | Maximum leaf value |
| `TreeTableAggOp_Min` | Minimum leaf value |
| `TreeTableAggOp_Count` | Count of leaves |
| `TreeTableAggOp_First` | First leaf value |
| `TreeTableAggOp_CountDistinctFromKey` | Count of distinct values of a designated key column, rolled up through group nodes. Used when leaf rows can repeat (e.g. one element appearing in multiple warnings). Requires `SetDisplayColumnAggregationKey()` to be called before `Init()`. The key column only needs to exist as a column in the temp table - it does not need to be a display or hidden column. |

```angelscript
// Example: count distinct warnings per group node, where each leaf row is one element x warning
tree.SetDisplayColumnAggregation(1, TreeTableAggOp_CountDistinctFromKey);
tree.SetDisplayColumnAggregationKey(1, "warningIndex");  // call before Init()
// warningIndex just needs to be a column in the temp table - no hidden column needed
```

### Format Options

| Constant | Example Output |
|----------|---------------|
| `TreeTableFormat_Integer` | `1,234` |
| `TreeTableFormat_Decimal` | `1.5K`, `2.3M` |
| `TreeTableFormat_Delta` | `+1,234` / `-567` |
| `TreeTableFormat_DeltaDecimal` | `+1.5K` / `-0.3` |

### Color Modes

```angelscript
// Gradient (numeric interpolation)
tree.SetDisplayColumnBgColorMode(0, TreeTableColorMode_Interpolate);
tree.SetDisplayColumnBgColorPoint(0, 0.0f,    color(50, 200, 50, 60));
tree.SetDisplayColumnBgColorPoint(0, 1000.0f, color(200, 50, 50, 60));

// Categorical (string mapping)
tree.SetDisplayColumnBgColorMode(1, TreeTableColorMode_Map);
tree.SetDisplayColumnBgColorPair(1, "Level 1", color(100, 150, 255, 80));
tree.SetDisplayColumnBgColorPair(1, "Level 2", color(255, 150, 100, 80));
```

### Filter Widget Integration

`SetFilterColumns()` **must** be called before `Init()`.

```angelscript
// Must be called BEFORE Init():
_tree.SetFilterColumns(vimDataWrapper, {"Category", "Level", "Workset"});
_tree.AddFilterDefault("Domain", {"Physical-Visible"});
```

---

## SQL Reference

### Proxy Class Deserialization

Field names in the proxy class must exactly match the SQL column aliases.

```angelscript
class MyRow
{
    string categoryName;   // matches "c.name as categoryName" - must be string, not hstring
    int count;              // matches "COUNT(*) as count"
    float elevation;        // matches "l.elevation as elevation"
}

array<MyRow> rows;
rows.DeserializeFromQuery(vimData,
    "SELECT c.name as categoryName, COUNT(*) as count, l.elevation as elevation " +
    "FROM Elements e " +
    "LEFT JOIN Categories c ON e.categoryIndex = c.index " +
    "LEFT JOIN Levels l ON e.levelIndex = l.index " +
    "WHERE c.name IS NOT NULL " +
    "GROUP BY c.name, l.elevation " +
    "ORDER BY count DESC");
```

Use `string` for all text columns in deserialized proxy classes. `hstring` will compile but silently returns empty strings at runtime. Use `hstring` only for non-SQL code where you need fast hash comparisons.

### Common Tables

| Table | Useful Columns |
|-------|----------------|
| `Elements` | `index`, `name`, `familyName`, `familyTypeName`, `faceCount`, `categoryIndex`, `levelIndex`, `worksetIndex`, `bimDocumentIndex`, `id`, `domain`, `kind`, `owner` |
| `Categories` | `index`, `name`, `domain` |
| `Levels` | `index`, `name`, `elevation` |
| `Families` | `index`, `name`, `isSystemFamily` |
| `FamilyTypes` | `index`, `name`, `familyIndex` |
| `Rooms` | `index`, `name`, `area`, `elementIndex` |
| `Worksets` | `index`, `name` |
| `Warnings` | `index`, `vimWarningCategory`, `description`, `severity` |
| `ElementsInWarnings` | `elementIndex`, `warningIndex` |
| `ElementWarnings` | `warningIndex`, `elementIndex`, `elementKind`, `elementKindIsLeaf`, `elementParentOrSelf` |
| `BimDocuments` | `index`, `title`, `isLinked` |
| `MaterialsInElement` | `area`, `volume`, `isPaint`, `materialIndex`, `elementIndex` |
| `Groups` | `position_xyz`, `groupType`, `elementIndex` |
| `AssemblyInstances` | `position_xyz`, `assemblyTypeName`, `elementIndex` |
| `Phases` | `elementIndex` |
| `DesignOptions` | `isPrimary`, `elementIndex` |
| `Systems` | `systemType`, `familyTypeIndex`, `elementIndex` |
| `ElementsInSystem` | `roles`, `systemIndex`, `elementIndex` |

### Useful Query Patterns

**Count by category:**
```sql
SELECT c.name as name, COUNT(*) as count
FROM Elements e
LEFT JOIN Categories c ON e.categoryIndex = c.index
WHERE c.name IS NOT NULL
GROUP BY c.name
ORDER BY count DESC
```

**Elements in a specific category:**
```sql
SELECT e.index as elementIndex
FROM Elements e
LEFT JOIN Categories c ON e.categoryIndex = c.index
WHERE c.name = 'Walls'
```

**Elements with warnings (prefer `ElementWarnings` over `ElementsInWarnings`):**
```sql
SELECT ew.elementIndex as elementIndex, w.vimWarningCategory as category
FROM ElementWarnings ew
LEFT JOIN Warnings w ON ew.warningIndex = w.index
WHERE w.vimWarningCategory IS NOT NULL
  AND ew.elementKindIsLeaf = true
```

**Room areas:**
```sql
SELECT name, area
FROM Rooms
WHERE area > 0 AND name IS NOT NULL
ORDER BY area DESC
```

---

## Common Patterns

### Selecting Elements in the Viewport

```angelscript
Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
for (uint i = 0; i < indices.length(); i++)
    itemSet.Add(indices[i]);
_appScene.GetSelectionService().Apply(itemSet);
```

### Isolating Elements

Use `GetInteractionService()` for isolation and framing. It correctly handles ghost mode, auto-sections, room elements, and state management.

```angelscript
// Select and isolate
Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
itemSet.Add(indices);
_appScene.GetSelectionService().Apply(itemSet);
_appScene.GetInteractionService().IsolateSelection();
_appScene.GetInteractionService().FrameSelection();

// Show all (undo isolation)
_appScene.GetInteractionService().ShowAll();
```

### Event Subscription

```angelscript
Scene::EventToken@ token = someEvent.Subscribe(
    Scene::Event::EventCallback(MyHandler));

// Unsubscribe when done (always do this in Destroy/Close):
token.Unsubscribe();
```

---

## Tips

1. Always unsubscribe from events in both `Destroy()` and `Close()`
2. Use `string` for all SQL deserialization fields - `hstring` silently returns empty strings at runtime
3. Proxy class field names must exactly match SQL column aliases
4. Call `TreeTable.Destroy()` on cleanup - it owns tree nodes and scene subscriptions
5. Call `SetFilterColumns()` before `Init()` on TreeTable
6. Use `VimFlex::Console::Log()` for debug output
7. Check `Scripts/as.predefined` for the full available API before writing helpers
8. Use `Core::EscapeSql()` when interpolating user strings into SQL queries
9. For `TreeTableAggOp_CountDistinctFromKey`: the key column only needs to exist as a column in the temp table - it does not need to be a display or hidden column. Call `SetDisplayColumnAggregationKey()` before `Init()`.
10. Prefer `ElementWarnings` over `ElementsInWarnings` for warning audit queries - it expands family/type warnings to instance elements and classifies element kinds.

*Last updated: 27 March 2026*
