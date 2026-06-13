// CostDraftView.as - Editable cost table keyed by {Category, Family, FamilyType}
//
// Auto-populates rows from the model's unique Category/Family/FamilyType combos.
// Each row has a CostPerUnit, a CostUnit (Count | InstanceParameter | TypeParameter),
// and an optional CostUnitParameterName used when CostUnit references a parameter.
//
// Features:
//   - Case-insensitive search over Category/Family/Type.
//   - Row selection (checkbox column) + Select-All-Shown / Clear Selection buttons.
//   - Bulk-edit strip with per-field Apply.
//   - Color toggle icon (palette icon from Example) that automatically re-applies
//     on recalculate while enabled. Elements whose Cost == 0 use UNKNOWN_COLOR.
//   - Cost Breakdown tree lives in CostBreakdownView (left region).

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/Card.as"
#include "../widgets/cards/CardUtils.as"
#include "CostBreakdownView.as"

// ── Constants ──

const color COST_UNKNOWN_COLOR = color(229, 229, 229, 255);

// ── CostUnit enum (matches serialized string literals) ──

enum CostUnitKind
{
    CostUnit_Count = 0,
    CostUnit_InstanceParameter = 1,
    CostUnit_TypeParameter = 2
}

namespace CostDraftConst
{
    const array<string> UNIT_NAMES = { "Count", "InstanceParameter", "TypeParameter" };

    string UnitToString(int kind)
    {
        if (kind >= 0 && uint(kind) < UNIT_NAMES.length())
            return UNIT_NAMES[kind];
        return "Count";
    }

    int UnitFromString(const string&in name)
    {
        for (uint i = 0; i < UNIT_NAMES.length(); i++)
        {
            if (UNIT_NAMES[i] == name) return int(i);
        }
        return CostUnit_Count;
    }

    // Compatibility shim for VimFlex::Combo, which does not exist in this
    // engine version. Same signature: returns true when the selection changed.
    bool Combo(const string&in label, const array<string>&in items, int current, int&out selected)
    {
        selected = current;
        bool changed = false;
        string preview = (current >= 0 && uint(current) < items.length())
            ? items[current] : "";
        if (ImGui::BeginCombo(label, preview))
        {
            for (uint i = 0; i < items.length(); i++)
            {
                bool isSelected = (int(i) == current);
                if (ImGui::Selectable(items[i], isSelected))
                {
                    selected = int(i);
                    changed = true;
                }
                if (isSelected)
                    ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        return changed;
    }

    // Compatibility shim for VimData::SerializeElementIndicesToTable, which
    // does not exist in this engine version. Writes the set's element indices
    // into a single-column table named by tableName. The column is always
    // "idx" (the field name of CostDraftIdxRow).
    void SerializeElementIndicesToTable(Scene::VimData@ db, const Scene::SceneItemSet@ items, const string&in tableName)
    {
        array<CostDraftIdxRow> rows;
        auto@ elements = items.GetElements();
        rows.reserve(elements.length());
        for (uint i = 0; i < elements.length(); i++)
        {
            CostDraftIdxRow row;
            row.idx = elements[i];
            rows.insertLast(row);
        }
        rows.SerializeToTable(db, tableName);
    }
}

// ── Plain data classes ──

class CostDraftIdxRow
{
    uint idx;
}

class CostInfo
{
    string Category;
    string Family;
    string FamilyType;
    double CostPerUnit = 0.0;
    int CostUnit = CostUnit_Count;
    string CostUnitParameterName;

    bool Selected = false;
}

class ComboRow
{
    string Category;
    string Family;
    string FamilyType;
}

class CostSummaryRow
{
    double totalCost;
    uint32 elementCount;
    double avgCost;
    double minCost;
    double maxCost;
    uint32 missingParamCount;
}

class SelectionCostRow
{
    double totalCost;
    uint32 elementCount;
}

class CostElementRow
{
    uint32 elementIndex;
    double cost;
}

// DB-shaped twin of CostInfo for DeserializeFromQuery reads. CostUnit is
// the serialized VARCHAR form ("Count" | "InstanceParameter" | "TypeParameter").
class CostInfoRow
{
    string Category;
    string Family;
    string FamilyType;
    double CostPerUnit;
    string CostUnit;
    string CostUnitParameterName;
}

// ── View ──

class CostDraftView : Window
{
    private App@ _app;
    private AppScene@ _appScene;
    private VimData@ _vimData;

    private CostBreakdownView@ _breakdown;

    // Editable rows
    private array<CostInfo> _rows;

    // Summary stats over CostData
    private double _totalCost = 0.0;
    private uint _elementCount = 0;
    private double _avgCost = 0.0;
    private double _minCost = 0.0;
    private double _maxCost = 0.0;
    private uint _missingParamCount = 0;

    // Cost of currently-selected scene elements. Recomputed on selection
    // change and after each Recalculate.
    private double _selectionCost = 0.0;
    private uint _selectionCostCount = 0;

    // Search
    private string _searchText;

    // Bulk-edit draft values. All three fields are optional — an empty
    // string (or unit index 0) means "leave unchanged" when Apply is pressed.
    private string _bulkCostPerUnitText;    // parsed as double when non-empty
    private int _bulkUnitChoice = 0;        // 0 = no change; 1..3 = CostUnitKind + 1
    private string _bulkParameterName;

    // Sync-with-selection state (enabled by default; no-op until something is selected)
    private bool _syncSelection = true;
    private dictionary _selectedCombos;   // RowKey → bool, combos represented in current selection

    // Per-element cost cache (used when coloring)
    private array<uint> _elementIndices;
    private array<double> _elementCosts;

    // Events
    private Scene::EventToken@ _dataChangedToken = null;
    private Scene::EventToken@ _selectionChangedToken = null;
    private bool _destroyed = false;

    private bool _needsFocus = true;
    private bool _costDirty = true;

    // Guard flags to prevent reentrancy during heavy SQL.
    private bool _recalculating = false;

    // Cached filter result. Rebuilt only when search text, sync toggle,
    // the selected combo set, or _rows itself changes.
    private array<uint> _filteredIndices;
    private bool _filterDirty = true;
    private string _lastFilterSearch;
    private bool _lastFilterSync = false;
    private uint _lastFilterSelCount = 0;
    private uint _lastFilterRowCount = 0;

    // Visual container
    private CostDraftCard@ _card;

    // Deferred recalc / load state — holds a "Calculating Costs..." modal on
    // screen for a few frames so ImGui can paint before we block the main
    // thread with the actual SQL work.
    private bool _pendingWork = false;
    private uint _pendingFrames = 0;
    private string _pendingAction;        // "recalc" | "load" | "save" | "clear"
    private string _pendingFilePath;      // set for "load" and "save" actions

    CostDraftView(App@ app)
    {
        super("Costs", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_vimData = _appScene.GetVimData();

        @_card = CostDraftCard(this);
    }

    void SetBreakdownView(CostBreakdownView@ breakdown)
    {
        @_breakdown = breakdown;
    }

    // ── Lifecycle ──

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;

        @_vimData = _appScene.GetVimData();

        // Subscribe to the VIM-file-change event (fires only when a new VIM
        // is loaded/reloaded), NOT GetDataUpdatedCallbacks(), which also fires
        // on our own DataQueryGeneric writes and would wipe loaded costs by
        // re-running PopulateFromModel after every Recalculate.
        if (_dataChangedToken is null && _appScene !is null)
        {
            @_dataChangedToken = _appScene.GetVimDataService()
                .OnVimDataChanged()
                .Subscribe(Scene::Event::EventCallback(HandleDataUpdated));
        }

        if (_selectionChangedToken is null && _appScene !is null)
        {
            @_selectionChangedToken = _appScene.GetSelectionService()
                .OnSelectionChanged()
                .Subscribe(Scene::Event::EventCallback(HandleSelectionChanged));
        }

        // Give the editor half the screen for data entry.
        VimFlex::RequestUpdateDockingRegions(-1, 0.50, -1, -1);

        PopulateFromModel();
        MaybeRecalculate();
        _needsFocus = true;
    }

    void Close() override
    {
        ClearColors();
        UnsubscribeFromEvents();
        Window::Close();
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;

        ClearColors();
        UnsubscribeFromEvents();

        if (_card !is null)
        {
            _card.ClearView();
            _card.Destroy();
            @_card = null;
        }

        @_breakdown = null;
        @_appScene = null;
        @_vimData = null;
        @_app = null;

        Window::Destroy();
        VimFlex::Console::Log("CostDraftView: Destroyed");
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionRight);
    }

    private void UnsubscribeFromEvents()
    {
        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }
        if (_selectionChangedToken !is null)
        {
            _selectionChangedToken.Unsubscribe();
            @_selectionChangedToken = null;
        }
    }

    private void HandleSelectionChanged()
    {
        if (_syncSelection)
        {
            RefreshSelectedCombos();
            InvalidateFilter();
        }
        // Reset row checkboxes on any scene-selection change so the user can't
        // accidentally bulk-edit rows hidden by the new filter.
        ClearRowSelection();
        RecomputeSelectionCost();
    }

    // Sums CostData.Cost over the currently-selected scene elements, so
    // the summary strip can show "Selection Cost: $X".
    private void RecomputeSelectionCost()
    {
        _selectionCost = 0.0;
        _selectionCostCount = 0;

        if (_appScene is null || _vimData is null) return;
        auto@ db = _vimData.GetData();
        if (db is null) return;

        const Scene::SceneItemSet@ selSet = _appScene.GetSelectionService().GetSelectionSet();
        if (selSet is null || selSet.Count() == 0) return;

        string selTable = "_CostDraftSelCost";
        CostDraftConst::SerializeElementIndicesToTable(db, selSet, selTable);

        array<SelectionCostRow> rows;
        rows.DeserializeFromQuery(db,
            "SELECT COALESCE(SUM(cd.Cost), 0) AS totalCost, "
            "       CAST(COUNT(*) AS UINTEGER) AS elementCount "
            "FROM CostData cd JOIN " + selTable + " s ON cd.elementIndex = s.idx");
        db.DataQueryGeneric("DROP TABLE IF EXISTS " + selTable);

        if (rows.length() > 0)
        {
            _selectionCost = rows[0].totalCost;
            _selectionCostCount = rows[0].elementCount;
        }
    }

    private void ClearRowSelection()
    {
        bool anyChanged = false;
        for (uint i = 0; i < _rows.length(); i++)
        {
            if (_rows[i].Selected)
            {
                _rows[i].Selected = false;
                anyChanged = true;
            }
        }
        if (anyChanged)
            InvalidateFilter();
    }

    // Populates _selectedCombos with the Cat/Fam/Type keys represented in the
    // current 3D selection. Called on selection change (when sync is on) and
    // when sync is toggled on.
    private void RefreshSelectedCombos()
    {
        _selectedCombos.deleteAll();

        if (_appScene is null || _vimData is null) return;
        auto@ db = _vimData.GetData();
        if (db is null) return;

        const Scene::SceneItemSet@ selSet = _appScene.GetSelectionService().GetSelectionSet();
        if (selSet is null || selSet.Count() == 0) return;

        string selTable = "_CostDraftSelIdx";
        CostDraftConst::SerializeElementIndicesToTable(db, selSet, selTable);

        array<ComboRow> combos;
        combos.DeserializeFromQuery(db,
            "SELECT DISTINCT "
            "COALESCE(c.name, '<unknown>') AS Category, "
            "COALESCE(e.familyName, '<unknown>') AS Family, "
            "COALESCE(e.familyTypeName, '<unknown>') AS FamilyType "
            "FROM Elements e "
            "LEFT JOIN Categories c ON e.categoryIndex = c.\"index\" "
            "JOIN " + selTable + " s ON s.idx = e.\"index\" "
            "WHERE e.domain = 'Physical-Visible'");

        db.DataQueryGeneric("DROP TABLE IF EXISTS " + selTable);

        for (uint i = 0; i < combos.length(); i++)
        {
            string key = RowKey(combos[i].Category, combos[i].Family, combos[i].FamilyType);
            _selectedCombos.set(key, true);
        }
    }

    private void HandleDataUpdated()
    {
        if (_recalculating) return;

        ClearColors();
        PopulateFromModel();
        _costDirty = true;
        MaybeRecalculate();
    }

    // ── Populate From Model ──

    private void PopulateFromModel()
    {
        if (_vimData is null || _vimData.GetData() is null) return;

        array<ComboRow> combos;
        combos.DeserializeFromQuery(_vimData.GetData(),
            "SELECT DISTINCT "
            "COALESCE(c.name, '<unknown>') AS Category, "
            "COALESCE(e.familyName, '<unknown>') AS Family, "
            "COALESCE(e.familyTypeName, '<unknown>') AS FamilyType "
            "FROM Elements e "
            "LEFT JOIN Categories c ON e.categoryIndex = c.index "
            "WHERE e.domain = 'Physical-Visible' "
            "ORDER BY Category, Family, FamilyType");

        // Preserve existing edits (cost, unit, parameter, Selected) for
        // rows whose key still matches; new combos get class-default values.
        dictionary existing;
        for (uint i = 0; i < _rows.length(); i++)
        {
            CostInfo@ r = _rows[i];
            existing.set(RowKey(r.Category, r.Family, r.FamilyType), @r);
        }

        array<CostInfo> newRows;
        newRows.reserve(combos.length());
        for (uint i = 0; i < combos.length(); i++)
        {
            string key = RowKey(combos[i].Category, combos[i].Family, combos[i].FamilyType);

            CostInfo@ preserved = null;
            if (existing.exists(key))
                existing.get(key, @preserved);

            CostInfo row;
            if (preserved !is null)
            {
                row.Category = preserved.Category;
                row.Family = preserved.Family;
                row.FamilyType = preserved.FamilyType;
                row.CostPerUnit = preserved.CostPerUnit;
                row.CostUnit = preserved.CostUnit;
                row.CostUnitParameterName = preserved.CostUnitParameterName;
                row.Selected = preserved.Selected;
            }
            else
            {
                row.Category = combos[i].Category;
                row.Family = combos[i].Family;
                row.FamilyType = combos[i].FamilyType;
            }
            newRows.insertLast(row);
        }
        _rows = newRows;
        InvalidateFilter();
    }

    private string RowKey(const string&in cat, const string&in fam, const string&in type)
    {
        return cat + "\x1F" + fam + "\x1F" + type;
    }

    // ── Build CostInfoRows temp table from _rows ──

    private bool BuildCostInfoRowsTable()
    {
        if (_vimData is null || _vimData.GetData() is null) return false;

        auto@ db = _vimData.GetData();

        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE CostInfoRows ("
            "Category VARCHAR, Family VARCHAR, FamilyType VARCHAR, "
            "CostPerUnit DOUBLE, CostUnit VARCHAR, CostUnitParameterName VARCHAR)");

        if (_rows.length() == 0) return true;

        const uint CHUNK = 200;
        uint failedChunks = 0;
        for (uint start = 0; start < _rows.length(); start += CHUNK)
        {
            uint end = start + CHUNK;
            if (end > _rows.length()) end = _rows.length();

            string sql = "INSERT INTO CostInfoRows VALUES ";
            for (uint i = start; i < end; i++)
            {
                CostInfo@ r = _rows[i];
                if (i > start) sql += ", ";
                sql += "('" + Core::EscapeSql(r.Category) + "', "
                     + "'" + Core::EscapeSql(r.Family) + "', "
                     + "'" + Core::EscapeSql(r.FamilyType) + "', "
                     + formatFloat(r.CostPerUnit, "", 0, 6) + ", "
                     + "'" + CostDraftConst::UnitToString(r.CostUnit) + "', "
                     + "'" + Core::EscapeSql(r.CostUnitParameterName) + "')";
            }
            auto@ res = db.DataQueryGeneric(sql);
            if (res is null)
            {
                failedChunks++;
                VimFlex::Console::Warn("CostDraft: chunk INSERT failed for rows "
                    + start + "-" + (end - 1) + " (first key: "
                    + _rows[start].Category + "/" + _rows[start].Family
                    + "/" + _rows[start].FamilyType + ")");
            }
        }
        if (failedChunks > 0)
            VimFlex::Console::Warn("CostDraft: " + failedChunks
                + " chunk INSERT(s) failed in BuildCostInfoRowsTable");
        return true;
    }

    // ── Build CostData table with per-element costs ──

    private bool BuildCostDataTable()
    {
        if (_vimData is null || _vimData.GetData() is null) return false;
        auto@ db = _vimData.GetData();

        // Narrow the element set to the Cat/Fam/Type combos referenced by CostInfoRows
        // so the parameter scan is cheap.
        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE CostMatchedElements AS "
            "SELECT e.\"index\" AS elementIndex, "
            "       COALESCE(c.name, '<unknown>') AS Category, "
            "       COALESCE(e.familyName, '<unknown>') AS Family, "
            "       COALESCE(e.familyTypeName, '<unknown>') AS Type "
            "FROM Elements e "
            "JOIN Categories c ON e.categoryIndex = c.\"index\" "
            "JOIN CostInfoRows ci "
            "    ON COALESCE(c.name, '<unknown>') = ci.Category "
            "    AND COALESCE(e.familyName, '<unknown>') = ci.Family "
            "    AND COALESCE(e.familyTypeName, '<unknown>') = ci.FamilyType "
            "WHERE e.domain = 'Physical-Visible'");

        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE CostData AS "
            "WITH TypeIdx AS ( "
            "    SELECT ft.elementIndex AS typeElementIndex, "
            "           f.name AS familyName, ft.name AS typeName "
            "    FROM FamilyTypes ft "
            "    JOIN Families f ON ft.familyIndex = f.\"index\" "
            "    WHERE EXISTS (SELECT 1 FROM CostInfoRows ci "
            "                  WHERE ci.CostUnit = 'TypeParameter' "
            "                    AND ci.Family = f.name "
            "                    AND ci.FamilyType = ft.name) "
            "), "
            "InstParamVals AS ( "
            "    SELECT p.elementIndex, pd.name AS paramName, "
            "           COALESCE(TRY_CAST(SPLIT_PART(p.value, '|', 1) AS DOUBLE), 0) AS rawValue, "
            "           ROW_NUMBER() OVER (PARTITION BY p.elementIndex, pd.name ORDER BY p.\"index\") AS rn "
            "    FROM Parameters p "
            "    JOIN ParameterDescriptors pd ON p.parameterDescriptorIndex = pd.\"index\" "
            "    WHERE pd.name IN (SELECT DISTINCT CostUnitParameterName FROM CostInfoRows "
            "                      WHERE CostUnit = 'InstanceParameter' AND CostUnitParameterName <> '') "
            "    AND p.elementIndex IN (SELECT elementIndex FROM CostMatchedElements) "
            "), "
            "TypeParamVals AS ( "
            "    SELECT ti.familyName, ti.typeName, pd.name AS paramName, "
            "           COALESCE(TRY_CAST(SPLIT_PART(p.value, '|', 1) AS DOUBLE), 0) AS rawValue, "
            "           ROW_NUMBER() OVER (PARTITION BY ti.typeElementIndex, pd.name ORDER BY p.\"index\") AS rn "
            "    FROM Parameters p "
            "    JOIN ParameterDescriptors pd ON p.parameterDescriptorIndex = pd.\"index\" "
            "    JOIN TypeIdx ti ON ti.typeElementIndex = p.elementIndex "
            "    WHERE pd.name IN (SELECT DISTINCT CostUnitParameterName FROM CostInfoRows "
            "                      WHERE CostUnit = 'TypeParameter' AND CostUnitParameterName <> '') "
            ") "
            "SELECT "
            "    me.elementIndex, "
            "    me.Category, "
            "    me.Family, "
            "    me.Type, "
            "    CASE ci.CostUnit "
            "        WHEN 'Count' THEN ci.CostPerUnit "
            "        WHEN 'InstanceParameter' THEN COALESCE(ip.rawValue, 0) * ci.CostPerUnit "
            "        WHEN 'TypeParameter' THEN COALESCE(tp.rawValue, 0) * ci.CostPerUnit "
            "        ELSE 0 "
            "    END AS Cost, "
            "    CASE "
            "        WHEN ci.CostUnit = 'InstanceParameter' AND ip.rawValue IS NULL THEN 1 "
            "        WHEN ci.CostUnit = 'TypeParameter' AND tp.rawValue IS NULL THEN 1 "
            "        ELSE 0 "
            "    END AS MissingParam "
            "FROM CostMatchedElements me "
            "JOIN CostInfoRows ci "
            "    ON me.Category = ci.Category "
            "    AND me.Family = ci.Family "
            "    AND me.Type = ci.FamilyType "
            "LEFT JOIN InstParamVals ip "
            "    ON ip.elementIndex = me.elementIndex "
            "    AND ip.paramName = ci.CostUnitParameterName "
            "    AND ip.rn = 1 "
            "    AND ci.CostUnit = 'InstanceParameter' "
            "LEFT JOIN TypeParamVals tp "
            "    ON tp.familyName = me.Family "
            "    AND tp.typeName = me.Type "
            "    AND tp.paramName = ci.CostUnitParameterName "
            "    AND tp.rn = 1 "
            "    AND ci.CostUnit = 'TypeParameter'");

        return true;
    }

    // Always rebuilds CostData and the breakdown tree so every Cat/Fam/Type is
    // visible (with $0 when no costs are entered). The SQL is cheap because the
    // parameter CTEs filter to names actually referenced in CostInfoRows, so a
    // fresh model with all-zero-Count rows touches no parameter data.
    private void MaybeRecalculate()
    {
        if (_rows.length() == 0)
        {
            ResetSummary();
            _elementIndices.resize(0);
            _elementCosts.resize(0);
            if (_breakdown !is null) _breakdown.ClearTree();
            ClearColors();
            _costDirty = false;
            return;
        }

        Recalculate();
        _costDirty = false;
    }

    private void ResetSummary()
    {
        _totalCost = 0.0;
        _elementCount = 0;
        _avgCost = 0.0;
        _minCost = 0.0;
        _maxCost = 0.0;
        _missingParamCount = 0;
    }

    private void Recalculate()
    {
        if (_vimData is null || _vimData.GetData() is null) return;

        _recalculating = true;

        if (!BuildCostInfoRowsTable()) { _recalculating = false; return; }
        if (!BuildCostDataTable())     { _recalculating = false; return; }

        LoadSummary();
        LoadElementCosts();

        if (_breakdown !is null)
            _breakdown.RebuildFromCostData();

        _recalculating = false;

        if (_breakdown !is null && _breakdown.GetColorToggleOn())
            ApplyColors();

        RecomputeSelectionCost();

        VimFlex::Console::Log("CostDraft: Recalculated — $"
            + Util::FormatDecimal(_totalCost, 2) + " across "
            + _elementCount + " elements"
            + (_missingParamCount > 0
                ? (" (" + _missingParamCount + " missing param values)")
                : ""));
    }

    private void LoadSummary()
    {
        ResetSummary();

        if (_vimData is null || _vimData.GetData() is null) return;

        array<CostSummaryRow> rows;
        rows.DeserializeFromQuery(_vimData.GetData(),
            "SELECT "
            "    COALESCE(SUM(Cost), 0) AS totalCost, "
            "    CAST(COUNT(*) AS UINTEGER) AS elementCount, "
            "    COALESCE(AVG(Cost), 0) AS avgCost, "
            "    COALESCE(MIN(CASE WHEN Cost > 0 THEN Cost END), 0) AS minCost, "
            "    COALESCE(MAX(Cost), 0) AS maxCost, "
            "    CAST(SUM(CASE WHEN MissingParam = 1 THEN 1 ELSE 0 END) AS UINTEGER) AS missingParamCount "
            "FROM CostData");

        if (rows.length() > 0)
        {
            _totalCost = rows[0].totalCost;
            _elementCount = rows[0].elementCount;
            _avgCost = rows[0].avgCost;
            _minCost = rows[0].minCost;
            _maxCost = rows[0].maxCost;
            _missingParamCount = rows[0].missingParamCount;
        }
    }

    private void LoadElementCosts()
    {
        _elementIndices.resize(0);
        _elementCosts.resize(0);

        if (_vimData is null || _vimData.GetData() is null) return;

        array<CostElementRow> rows;
        rows.DeserializeFromQuery(_vimData.GetData(),
            "SELECT elementIndex, Cost AS cost FROM CostData");

        _elementIndices.resize(rows.length());
        _elementCosts.resize(rows.length());
        for (uint i = 0; i < rows.length(); i++)
        {
            _elementIndices[i] = rows[i].elementIndex;
            _elementCosts[i] = rows[i].cost;
        }
    }

    // ── 3D coloring ──

    private void ApplyColors()
    {
        if (_appScene is null) return;
        auto@ matService = _appScene.GetMaterialService();

        matService.ClearMaterialOverrides();

        if (_elementIndices.length() == 0) return;

        // Thresholds and stop colors come from the breakdown view so the 3D
        // gradient matches the TreeTable gradient the user sees.
        double low, mid, high;
        color lowC, midC, highC;
        if (_breakdown !is null)
        {
            low  = _breakdown.GetLowValue();
            mid  = _breakdown.GetMidValue();
            high = _breakdown.GetHighValue();
            lowC  = _breakdown.GetLowColor();
            midC  = _breakdown.GetMidColor();
            highC = _breakdown.GetHighColor();
        }
        else
        {
            low  = CostDataSchema::DEFAULT_LOW_VALUE;
            mid  = CostDataSchema::DEFAULT_MID_VALUE;
            high = CostDataSchema::DEFAULT_HIGH_VALUE;
            lowC  = CostDataSchema::DEFAULT_LOW_COLOR;
            midC  = CostDataSchema::DEFAULT_MID_COLOR;
            highC = CostDataSchema::DEFAULT_HIGH_COLOR;
        }

        // Group element indices by packed-uint32 color key. For a linear
        // gradient bounded by three stops the total unique-color count is
        // O(2 * 256), so the dictionary stays small.
        dictionary colorKeyToGroup;  // string key → uint index into `groups`
        array<color> groupColors;
        array<array<uint>> groups;

        for (uint i = 0; i < _elementIndices.length(); i++)
        {
            color c = _elementCosts[i] <= 0.0
                ? COST_UNKNOWN_COLOR
                : InterpolateCostColor(_elementCosts[i],
                    low, mid, high, lowC, midC, highC);

            string key = "" + int(c.r) + "," + int(c.g) + "," + int(c.b) + "," + int(c.a);
            uint groupIdx;
            if (colorKeyToGroup.get(key, groupIdx))
            {
                groups[groupIdx].insertLast(_elementIndices[i]);
            }
            else
            {
                groupIdx = groups.length();
                colorKeyToGroup.set(key, groupIdx);
                groupColors.insertLast(c);
                groups.insertLast(array<uint>());
                groups[groupIdx].insertLast(_elementIndices[i]);
            }
        }

        // Apply one SetColor per unique color.
        uint appliedElements = 0;
        for (uint g = 0; g < groupColors.length(); g++)
        {
            Scene::SceneItemSet@ groupSet = Scene::SceneItemSet();
            groupSet.Add(groups[g]);
            matService.SetColor(groupSet, groupColors[g]);
            appliedElements += groups[g].length();
        }

        VimFlex::Console::Log("CostDraft: Colors applied to " + appliedElements
            + " elements across " + groupColors.length() + " color groups");
    }

    // Piecewise interpolation: lowC→midC from `low` to `mid`, midC→highC
    // from `mid` to `high`. Costs outside [low, high] clamp to the edge
    // colors.
    private color InterpolateCostColor(double cost, double low, double mid, double high,
                                       color lowC, color midC, color highC)
    {
        if (cost <= low) return lowC;
        if (cost >= high) return highC;

        if (cost <= mid)
        {
            double r = mid - low;
            if (r <= 0.0) return midC;
            float t = Math::Clamp(float((cost - low) / r), 0.0f, 1.0f);
            return lowC.Lerp(midC, t);
        }
        double r = high - mid;
        if (r <= 0.0) return midC;
        float t = Math::Clamp(float((cost - mid) / r), 0.0f, 1.0f);
        return midC.Lerp(highC, t);
    }

    private void ClearColors()
    {
        if (_appScene !is null)
            _appScene.GetMaterialService().ClearMaterialOverrides();
    }

    // ── MCP entry point ──
    //
    // External flow: an AI agent mutates the CostInfoRows table via
    // vim_query (UPDATE, INSERT, DELETE, COPY FROM, ...), then calls the
    // cost_draft_recalculate MCP tool. That tool defers here. We read
    // CostInfoRows back into `_rows` (preserving any in-flight row
    // selection the user had), then run the standard recalc. Subsequent
    // Recalculate rebuilds CostInfoRows from `_rows`, which now mirrors
    // whatever the agent wrote, so the write round-trips cleanly.
    void AbsorbCostInfoRowsAndRecalculate()
    {
        if (_vimData is null || _vimData.GetData() is null) return;
        auto@ db = _vimData.GetData();

        // Nothing to absorb if the plugin hasn't recalculated yet and the
        // table doesn't exist — just kick a recalc so initial state is
        // consistent.
        auto@ probe = db.DataQueryGeneric("SELECT 1 FROM CostInfoRows LIMIT 0");
        if (probe is null)
        {
            VimFlex::Console::Warn("CostDraft MCP: CostInfoRows does not "
                "exist yet; running a plain recalc from existing _rows");
            _costDirty = true;
            MaybeRecalculate();
            return;
        }

        array<CostInfoRow> dbRows;
        dbRows.DeserializeFromQuery(db,
            "SELECT Category, Family, FamilyType, CostPerUnit, CostUnit, "
            "       CostUnitParameterName FROM CostInfoRows");

        // Preserve the user's current checkbox selection so the agent's
        // edits don't clear their in-progress bulk-edit state.
        dictionary oldSelection;
        for (uint i = 0; i < _rows.length(); i++)
        {
            CostInfo@ r = _rows[i];
            if (r.Selected)
                oldSelection.set(RowKey(r.Category, r.Family, r.FamilyType), true);
        }

        array<CostInfo> newRows;
        newRows.reserve(dbRows.length());
        for (uint i = 0; i < dbRows.length(); i++)
        {
            CostInfoRow@ src = dbRows[i];
            CostInfo r;
            r.Category = src.Category;
            r.Family = src.Family;
            r.FamilyType = src.FamilyType;
            r.CostPerUnit = src.CostPerUnit;
            r.CostUnit = CostDraftConst::UnitFromString(src.CostUnit);
            r.CostUnitParameterName = src.CostUnitParameterName;
            r.Selected = oldSelection.exists(RowKey(r.Category, r.Family, r.FamilyType));
            newRows.insertLast(r);
        }
        _rows = newRows;

        VimFlex::Console::Log("CostDraft MCP: absorbed " + dbRows.length()
            + " rows from CostInfoRows");

        _costDirty = true;
        InvalidateFilter();
        MaybeRecalculate();
    }

    // ── Save/Load ──
    //
    // Single-file format: a DuckDB database file (.duckdb) holding two
    // tables — CostInfoRows (the cost rows) and CostSettings (the user's
    // Low/Mid/High color thresholds).

    private bool HasDuckDbExtension(const string&in path)
    {
        int idx = path.findLast(".duckdb");
        return idx >= 0 && idx == int(path.length()) - 7;
    }

    // Synchronous save worker. RequestSaveCostFile() opens the file dialog
    // and defers the call here so any pending input edits commit before we
    // pack them into Settings.
    private void SaveCostFile(const string&in path)
    {
        if (path.isEmpty()) return;
        if (_vimData is null || _vimData.GetData() is null) return;
        auto@ db = _vimData.GetData();

        // Sync current edits from _rows into the CostInfoRows staging table.
        if (!BuildCostInfoRowsTable()) return;

        string escapedPath = Core::EscapeSql(path);

        // Detach any stale alias from a previous CostDraftSave in this session.
        db.DataQueryGeneric("DETACH IF EXISTS CostDraftSave");
        db.DataQueryGeneric("ATTACH '" + escapedPath + "' AS CostDraftSave");

        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE CostDraftSave.CostInfoRows AS "
            "SELECT Category, Family, FamilyType, CostPerUnit, "
            "       CostUnit, CostUnitParameterName "
            "FROM CostInfoRows");

        // Stamp the schema version and persist the current threshold state
        // (defaults if the breakdown view hasn't been built yet).
        CostDataSchema::WriteSchemaMeta(db, "CostDraftSave");
        CostDataSchema::Settings settings;
        if (_breakdown !is null)
            settings = _breakdown.GetSettings();
        CostDataSchema::WriteSettings(db, "CostDraftSave", settings);

        db.DataQueryGeneric("DETACH CostDraftSave");

        VimFlex::Console::Log("CostDraft: Saved " + _rows.length() + " rows to " + path);
    }

    // Synchronous load worker. RequestLoadCostFile() opens the file dialog
    // and defers the call here so the "Calculating Costs..." modal can paint
    // first.
    private void LoadCostFile(const string&in path)
    {
        if (path.isEmpty()) return;
        if (_vimData is null || _vimData.GetData() is null) return;
        auto@ db = _vimData.GetData();

        string escapedPath = Core::EscapeSql(path);

        // 1) Attach the cost file, check schema version, and stage
        //    CostInfoImport + read settings.
        db.DataQueryGeneric("DETACH IF EXISTS CostDraftLoad");
        db.DataQueryGeneric("ATTACH '" + escapedPath + "' AS CostDraftLoad (READ_ONLY)");

        int version = CostDataSchema::ReadSchemaVersion(db, "CostDraftLoad");
        if (version > CostDataSchema::CURRENT_SCHEMA_VERSION)
        {
            VimFlex::Console::Warn("CostDraft: file was saved by a newer plugin (v"
                + version + " > v" + CostDataSchema::CURRENT_SCHEMA_VERSION
                + "); refusing to load");
            db.DataQueryGeneric("DETACH CostDraftLoad");
            return;
        }

        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE CostInfoImport AS "
            "SELECT "
            "    CAST(Category AS VARCHAR) AS Category, "
            "    CAST(Family AS VARCHAR) AS Family, "
            "    CAST(FamilyType AS VARCHAR) AS FamilyType, "
            "    CAST(CostPerUnit AS DOUBLE) AS CostPerUnit, "
            "    CAST(CostUnit AS VARCHAR) AS CostUnit, "
            "    CAST(COALESCE(CostUnitParameterName, '') AS VARCHAR) AS CostUnitParameterName "
            "FROM CostDraftLoad.CostInfoRows");

        // Read thresholds (the schema module fills in defaults for any
        // columns the file's version doesn't carry).
        if (_breakdown !is null)
        {
            CostDataSchema::Settings settings = CostDataSchema::ReadSettings(
                db, "CostDraftLoad", version);
            _breakdown.ApplySettings(settings);
        }

        db.DataQueryGeneric("DETACH CostDraftLoad");

        // 2) Do the merge entirely in SQL:
        //    - every model combo (LEFT JOIN src) gets its cost applied when present
        //    - loaded rows whose key is not in the model are appended after
        //    This avoids any AngelScript dictionary round-trip where script
        //    reference-type classes can silently lose fields.
        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE _CostLoadMerged AS "
            "WITH combos AS ( "
            "    SELECT DISTINCT "
            "        COALESCE(c.name, '<unknown>') AS Category, "
            "        COALESCE(e.familyName, '<unknown>') AS Family, "
            "        COALESCE(e.familyTypeName, '<unknown>') AS FamilyType "
            "    FROM Elements e "
            "    LEFT JOIN Categories c ON e.categoryIndex = c.\"index\" "
            "    WHERE e.domain = 'Physical-Visible' "
            ") "
            "SELECT combos.Category, combos.Family, combos.FamilyType, "
            "       COALESCE(src.CostPerUnit, 0.0) AS CostPerUnit, "
            "       COALESCE(src.CostUnit, 'Count') AS CostUnit, "
            "       COALESCE(src.CostUnitParameterName, '') AS CostUnitParameterName "
            "FROM combos "
            "LEFT JOIN CostInfoImport src "
            "    ON combos.Category = src.Category "
            "    AND combos.Family = src.Family "
            "    AND combos.FamilyType = src.FamilyType "
            "UNION ALL "
            "SELECT src.Category, src.Family, src.FamilyType, "
            "       src.CostPerUnit, src.CostUnit, src.CostUnitParameterName "
            "FROM CostInfoImport src "
            "WHERE NOT EXISTS ( "
            "    SELECT 1 FROM combos m "
            "    WHERE m.Category = src.Category "
            "      AND m.Family = src.Family "
            "      AND m.FamilyType = src.FamilyType) "
            "ORDER BY Category, Family, FamilyType");

        // 3) Preserve current checkbox selection by key so Load doesn't
        //    clear the user's in-progress row selection.
        dictionary oldSelection;
        for (uint i = 0; i < _rows.length(); i++)
        {
            CostInfo@ r = _rows[i];
            if (r.Selected)
            {
                string key = RowKey(r.Category, r.Family, r.FamilyType);
                oldSelection.set(key, true);
            }
        }

        // 4) Deserialize into a DB-shaped struct, then translate the
        //    VARCHAR CostUnit to its int enum when copying into _rows.
        array<CostInfoRow> dbRows;
        dbRows.DeserializeFromQuery(db,
            "SELECT Category, Family, FamilyType, CostPerUnit, CostUnit, "
            "       CostUnitParameterName FROM _CostLoadMerged");

        array<CostInfo> newRows;
        newRows.reserve(dbRows.length());
        for (uint i = 0; i < dbRows.length(); i++)
        {
            CostInfoRow@ src = dbRows[i];
            CostInfo r;
            r.Category = src.Category;
            r.Family = src.Family;
            r.FamilyType = src.FamilyType;
            r.CostPerUnit = src.CostPerUnit;
            r.CostUnit = CostDraftConst::UnitFromString(src.CostUnit);
            r.CostUnitParameterName = src.CostUnitParameterName;
            r.Selected = oldSelection.exists(RowKey(r.Category, r.Family, r.FamilyType));
            newRows.insertLast(r);
        }
        _rows = newRows;

        VimFlex::Console::Log("CostDraft: Loaded " + dbRows.length() + " rows from " + path);
        _costDirty = true;
        InvalidateFilter();
        MaybeRecalculate();
    }

    // ── Selection helpers ──

    private bool RowMatchesSearch(CostInfo@ row, const string&in searchUpper)
    {
        if (searchUpper.isEmpty()) return true;
        if (row.Category.ToUpperCase().findFirst(searchUpper) >= 0) return true;
        if (row.Family.ToUpperCase().findFirst(searchUpper) >= 0) return true;
        if (row.FamilyType.ToUpperCase().findFirst(searchUpper) >= 0) return true;
        return false;
    }

    // Combines search text with the optional sync-with-selection filter.
    // When sync is on AND there is a 3D selection, only rows whose
    // {Category, Family, Type} is represented in the selection pass.
    // When sync is on but nothing is selected, the filter is a no-op
    // (show everything) so the default-on toggle doesn't empty the table.
    private bool RowMatchesFilter(CostInfo@ row, const string&in searchUpper)
    {
        if (!RowMatchesSearch(row, searchUpper)) return false;
        if (_syncSelection && _selectedCombos.getKeys().length() > 0)
        {
            string key = RowKey(row.Category, row.Family, row.FamilyType);
            if (!_selectedCombos.exists(key)) return false;
        }
        return true;
    }

    // Rebuilds _filteredIndices when any filter input changes. Avoids the
    // per-frame O(N) scan + string allocations when 1952+ rows are loaded.
    private void EnsureFilteredIndices()
    {
        uint selCount = _selectedCombos.getKeys().length();
        bool dirty = _filterDirty
            || _lastFilterSearch != _searchText
            || _lastFilterSync != _syncSelection
            || _lastFilterSelCount != selCount
            || _lastFilterRowCount != _rows.length();
        if (!dirty) return;

        string searchUpper = _searchText.ToUpperCase();
        bool syncActive = _syncSelection && selCount > 0;

        _filteredIndices.resize(0);
        _filteredIndices.reserve(_rows.length());
        for (uint i = 0; i < _rows.length(); i++)
        {
            CostInfo@ r = _rows[i];
            if (!RowMatchesSearch(r, searchUpper)) continue;
            if (syncActive)
            {
                string key = RowKey(r.Category, r.Family, r.FamilyType);
                if (!_selectedCombos.exists(key)) continue;
            }
            _filteredIndices.insertLast(i);
        }

        _filterDirty = false;
        _lastFilterSearch = _searchText;
        _lastFilterSync = _syncSelection;
        _lastFilterSelCount = selCount;
        _lastFilterRowCount = _rows.length();
    }

    private void InvalidateFilter()
    {
        _filterDirty = true;
    }

    private uint CountSelected()
    {
        uint n = 0;
        for (uint i = 0; i < _rows.length(); i++)
            if (_rows[i].Selected) n++;
        return n;
    }

    private void SelectAllShown(const string&in searchUpper)
    {
        for (uint i = 0; i < _rows.length(); i++)
        {
            if (RowMatchesFilter(_rows[i], searchUpper))
                _rows[i].Selected = true;
        }
    }

    private void ClearSelection()
    {
        for (uint i = 0; i < _rows.length(); i++)
            _rows[i].Selected = false;
    }

    // Apply every non-empty bulk field to the selected rows in one pass.
    // Empty CostPerUnit text → skip; unit choice 0 → skip; empty parameter → skip.
    private void ApplyBulkNonEmpty()
    {
        bool applyCpu = !_bulkCostPerUnitText.isEmpty();
        double cpuValue = 0.0;
        if (applyCpu)
        {
            cpuValue = parseFloat(_bulkCostPerUnitText);
        }

        bool applyUnit = _bulkUnitChoice > 0;
        int unitValue = _bulkUnitChoice - 1;   // 1→Count, 2→InstanceParameter, 3→TypeParameter

        bool applyParam = !_bulkParameterName.isEmpty();

        if (!applyCpu && !applyUnit && !applyParam) return;

        uint applied = 0;
        for (uint i = 0; i < _rows.length(); i++)
        {
            if (!_rows[i].Selected) continue;
            if (applyCpu)   _rows[i].CostPerUnit = cpuValue;
            if (applyUnit)  _rows[i].CostUnit = unitValue;
            if (applyParam) _rows[i].CostUnitParameterName = _bulkParameterName;
            applied++;
        }

        if (applied > 0)
            _costDirty = true;
    }

    // ── Rendering ──

    bool Render(const IRenderContext& ctx) override
    {
        if (_needsFocus)
        {
            ImGui::SetWindowFocus(_windowName);
            _needsFocus = false;
        }

        // Any breakdown change (threshold value, stop color, or the 3D
        // overlay toggle itself) sets the dirty flag; we respond by either
        // applying the updated gradient or clearing the overrides.
        if (_breakdown !is null && _breakdown.TakeThresholdsDirty())
        {
            if (_breakdown.GetColorToggleOn())
                ApplyColors();
            else
                ClearColors();
        }

        if (_card !is null)
            _card.Render();

        RenderPendingModal();
        return true;
    }

    // Holds a small modal on screen for a few frames before running the
    // queued action. The delay lets ImGui (a) paint the modal before we
    // block the main thread with SQL, and (b) commit any in-flight input
    // edits — InputFloat doesn't write its buffer back to the bound value
    // until its next render after focus loss, so a synchronous Save click
    // would otherwise read a stale threshold.
    private void RenderPendingModal()
    {
        if (!_pendingWork) return;

        _pendingFrames++;
        string modalId = "CalculatingCosts##CostDraft";
        ImGui::OpenPopup(modalId);

        Style::PushModalStyle();
        Style::SetNextWindowCentered(float2(320, 0));
        if (ImGui::BeginPopupModal(modalId,
            ImGuiWindowFlags::ImGuiWindowFlags_NoTitleBar
            | ImGuiWindowFlags::ImGuiWindowFlags_AlwaysAutoResize))
        {
            string label = "Calculating Costs...";
            if      (_pendingAction == "load")  label = "Loading...";
            else if (_pendingAction == "save")  label = "Saving...";
            else if (_pendingAction == "clear") label = "Clearing...";

            Style::PushModalBodyStyle();
            Style::TitleText("Cost Draft");
            ImGui::Dummy(float2(0, Style::SpacingLarge));
            ImGui::Text(label);
            ImGui::Dummy(float2(0, Style::SpacingLarge));

            if (_pendingFrames >= 3)
            {
                string action = _pendingAction;
                string path = _pendingFilePath;

                _pendingWork = false;
                _pendingAction = "";
                _pendingFilePath = "";

                if (action == "recalc")
                {
                    Recalculate();
                    _costDirty = false;
                }
                else if (action == "load")
                {
                    LoadCostFile(path);
                }
                else if (action == "save")
                {
                    SaveCostFile(path);
                }
                else if (action == "clear")
                {
                    ClearAllCosts();
                }

                ImGui::CloseCurrentPopup();
            }
            Style::PopModalBodyStyle();
            ImGui::EndPopup();
        }
        Style::PopModalStyle();
    }

    // Called by CostDraftCard inside the card body.
    // Wrapped in a BeginChild so ImGui::GetContentRegionAvail() and -1
    // widths stay within the card's padded body (left/right margins work).
    void RenderCardBody(const float2&in dims)
    {
        bool inChild = dims.y > 0;
        if (inChild)
        {
            ImGui::PushStyleColor(ImGuiCol_ChildBg, color(0, 0, 0, 0));
            ImGui::BeginChild("##CostDraftCardBody", float2(dims.x, dims.y), 0, 0);
            ImGui::PopStyleColor();
        }

        // Style input backgrounds so they stand out against the card.
        ImGui::PushStyleColor(ImGuiCol_FrameBg, Style::GetColorBackground());
        ImGui::PushStyleColor(ImGuiCol_FrameBgHovered, Style::GetColorBackground());

        RenderDescription();
        Style::VSpace();
        RenderToolbar();
        Style::VSpace();
        RenderSummary();
        Style::VSpace();
        RenderSearchAndSelection();
        Style::VSpaceSmall();

        // Reserve a fixed height for the bulk-edit strip at the bottom so
        // the table doesn't shift when a selection is made.
        float reservedH = ComputeBulkStripReservedHeight();
        float availY = ImGui::GetContentRegionAvail().y;
        float tableH = availY - reservedH;
        if (tableH < 60.0f) tableH = 60.0f;

        RenderRowsTable(tableH);
        Style::VSpaceSmall();
        RenderBulkEditStrip();

        ImGui::PopStyleColor(2);

        if (inChild)
            ImGui::EndChild();
    }

    private float ComputeBulkStripReservedHeight()
    {
        // Accounts for: spacing + label line + input row + vertical padding.
        return Style::SpacingSmall
             + ImGui::GetTextLineHeightWithSpacing()
             + ImGui::GetFrameHeight()
             + ImGui::GetStyle().ItemSpacing.y * 2.0f;
    }


    private void RenderDescription()
    {
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextSecondary());
        ImGui::TextWrapped(
            "Enter a cost per unit for each Category / Family / Type. "
            "Use Count for flat per-element cost, or bind to an instance/type "
            "parameter to multiply by a numeric value (raw values in ft / ft^2 / ft^3).");
        ImGui::PopStyleColor();
    }

    private void RenderToolbar()
    {
        bool busy = _pendingWork;

        if (VimFlex::ButtonPrimary("Save", !busy))
            RequestSaveCostFile();

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        if (VimFlex::ButtonSecondary("Load", !busy))
            RequestLoadCostFile();

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        string recalcLabel = _costDirty ? "Recalculate *" : "Recalculate";
        if (VimFlex::ButtonSecondary(recalcLabel, !busy))
            RequestRecalculate();

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        // Clear wipes cost data on every row. Enabled only when any row has
        // non-default cost info so it's not a stray destructive click target.
        bool anyCostSet = HasAnyCostData();
        if (VimFlex::ButtonDestructive("Clear", anyCostSet && !busy))
            RequestClear();
    }

    private void RequestRecalculate()
    {
        _pendingWork = true;
        _pendingFrames = 0;
        _pendingAction = "recalc";
    }

    private void RequestClear()
    {
        _pendingWork = true;
        _pendingFrames = 0;
        _pendingAction = "clear";
    }

    private void RequestLoadCostFile()
    {
        string path = VimFlex::OpenFileDialog("Load Cost Draft",
            "Cost Draft files (*.duckdb)\0*.duckdb\0");
        if (path.isEmpty()) return;
        _pendingFilePath = path;
        _pendingWork = true;
        _pendingFrames = 0;
        _pendingAction = "load";
    }

    private void RequestSaveCostFile()
    {
        string path = VimFlex::SaveFileDialog("Save Cost Draft",
            "Cost Draft files (*.duckdb)\0*.duckdb\0");
        if (path.isEmpty()) return;
        if (!HasDuckDbExtension(path))
            path += ".duckdb";
        _pendingFilePath = path;
        _pendingWork = true;
        _pendingFrames = 0;
        _pendingAction = "save";
    }

    private bool HasAnyCostData()
    {
        for (uint i = 0; i < _rows.length(); i++)
        {
            CostInfo@ r = _rows[i];
            if (r.CostPerUnit != 0.0) return true;
            if (r.CostUnit != CostUnit_Count) return true;
            if (!r.CostUnitParameterName.isEmpty()) return true;
        }
        return false;
    }

    private void ClearAllCosts()
    {
        for (uint i = 0; i < _rows.length(); i++)
        {
            CostInfo@ r = _rows[i];
            r.CostPerUnit = 0.0;
            r.CostUnit = CostUnit_Count;
            r.CostUnitParameterName = "";
        }
        _costDirty = true;
        InvalidateFilter();
        MaybeRecalculate();
        VimFlex::Console::Log("CostDraft: Cleared cost data on " + _rows.length() + " rows");
    }

    private void RenderSummary()
    {
        // Total in a larger font, with thousands separators.
        // Dark theme → white; light theme → accent for contrast.
        color totalColor = Style::IsLightColorTheme()
            ? Style::GetColorAction()
            : color(255, 255, 255, 255);
        ImGui::PushFont(Style::GetFontBoldExtraLarge());
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, totalColor);
        ImGui::Text("Total: " + FormatMoney(_totalCost));
        ImGui::PopStyleColor();
        ImGui::PopFont();

        // Selection Cost on its own line under Total, same style as the
        // secondary summary line below.
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextSecondary());
        string selCostLabel = "Selection Cost: " + FormatMoney(_selectionCost);
        if (_selectionCostCount > 0)
            selCostLabel += "  (" + CardFormatInt(int(_selectionCostCount)) + " selected)";
        ImGui::Text(selCostLabel);
        ImGui::PopStyleColor();

        // Element count + Avg on a third line.
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextSecondary());
        ImGui::Text(CardFormatInt(int(_elementCount)) + " elements");
        ImGui::PopStyleColor();

        ImGui::SameLine(); Style::HSpace(); ImGui::SameLine();
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text("|");
        ImGui::PopStyleColor();

        ImGui::SameLine(); Style::HSpace(); ImGui::SameLine();
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextSecondary());
        ImGui::Text("Avg: " + FormatMoney(_avgCost));
        ImGui::PopStyleColor();

        if (_missingParamCount > 0)
        {
            ImGui::SameLine(); Style::HSpace(); ImGui::SameLine();
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CARD_AMBER);
            ImGui::Text("! " + CardFormatInt(int(_missingParamCount)) + " missing param values");
            ImGui::PopStyleColor();
        }
    }

    // Formats a dollar amount with thousands separators and 2 decimal places,
    // e.g. 1234567.8 → "$1,234,567.80".
    private string FormatMoney(double val)
    {
        if (val < 0.0)
            return "-$" + Util::FormatDecimal(-val, 2);
        return "$" + Util::FormatDecimal(val, 2);
    }

    private void RenderSearchAndSelection()
    {
        // Sync-with-selection toggle: when on, the table is filtered to rows
        // whose {Category, Family, Type} is represented in the 3D selection.
        if (VimFlex::ToggleButton("Sync", _syncSelection, true, float2(0, 0),
            0, "Filter the table to rows whose Category/Family/Type is in the 3D selection"))
        {
            _syncSelection = !_syncSelection;
            if (_syncSelection)
                RefreshSelectedCombos();
            else
                _selectedCombos.deleteAll();
            InvalidateFilter();
        }

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        // Search box
        float searchWidth = Math::Min(ImGui::GetContentRegionAvail().x * 0.50f, 420.0f);
        if (searchWidth < 140.0f) searchWidth = 140.0f;
        ImGui::SetNextItemWidth(searchWidth);

        string sIn = _searchText;
        string sOut = sIn;
        if (ImGui::InputText("##CostDraftSearch", sIn, sOut))
            _searchText = sOut;

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        string searchUpper = _searchText.ToUpperCase();

        if (VimFlex::ButtonSecondary("Select All Shown", true))
            SelectAllShown(searchUpper);

        ImGui::SameLine();
        Style::HSpaceSmall();
        ImGui::SameLine();

        uint selCount = CountSelected();
        if (VimFlex::ButtonSecondary("Clear Selection", selCount > 0))
            ClearSelection();

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text("" + selCount + " selected");
        ImGui::PopStyleColor();
    }

    // Bulk-edit strip, always rendered so the table bottom doesn't jump.
    // When no rows are selected, shows a hint. Otherwise shows three optional
    // fields (empty = no change) plus a single "Apply" button.
    private void RenderBulkEditStrip()
    {
        uint selCount = CountSelected();

        if (selCount == 0)
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::Text("Select rows to bulk-edit their cost, unit, or parameter.");
            ImGui::PopStyleColor();
            return;
        }

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextSecondary());
        ImGui::Text("Bulk edit (" + selCount + " selected) — leave blank to skip:");
        ImGui::PopStyleColor();

        // $/Unit
        ImGui::AlignTextToFramePadding();
        ImGui::Text("$/Unit:");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(100);
        string cpuIn = _bulkCostPerUnitText;
        string cpuOut = cpuIn;
        if (ImGui::InputText("##bulkCpu", cpuIn, cpuOut))
            _bulkCostPerUnitText = cpuOut;

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        // Unit (with "(no change)" as the first option)
        ImGui::AlignTextToFramePadding();
        ImGui::Text("Unit:");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(160);
        array<string> unitOptions = { "(no change)", "Count", "InstanceParameter", "TypeParameter" };
        int newUnitIdx = _bulkUnitChoice;
        if (CostDraftConst::Combo("##bulkUnit", unitOptions, _bulkUnitChoice, newUnitIdx))
            _bulkUnitChoice = newUnitIdx;

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        // Parameter
        ImGui::AlignTextToFramePadding();
        ImGui::Text("Parameter:");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(180);
        string pIn = _bulkParameterName;
        string pOut = pIn;
        if (ImGui::InputText("##bulkParam", pIn, pOut))
            _bulkParameterName = pOut;

        ImGui::SameLine();
        Style::HSpace();
        ImGui::SameLine();

        if (VimFlex::ButtonPrimary("Apply", true))
            ApplyBulkNonEmpty();
    }

    private void RenderRowsTable(float height)
    {
        if (_rows.length() == 0)
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped("No Category / Family / Type combinations found. Load a VIM file to populate.");
            ImGui::PopStyleColor();
            return;
        }

        int flags = ImGuiTableFlags_BordersInnerV
                  | ImGuiTableFlags_BordersOuter
                  | ImGuiTableFlags_RowBg
                  | ImGuiTableFlags_Resizable
                  | ImGuiTableFlags_ScrollY
                  | ImGuiTableFlags_ScrollX
                  | ImGuiTableFlags_SizingStretchProp;

        if (!ImGui::BeginTable("##CostInfoTable", 7, ImGuiTableFlags(flags), float2(-1, height)))
            return;

        ImGui::TableSetupColumn("",          ImGuiTableColumnFlags_WidthFixed, 28.0f);
        ImGui::TableSetupColumn("Category",  ImGuiTableColumnFlags_WidthStretch, 1.4f);
        ImGui::TableSetupColumn("Family",    ImGuiTableColumnFlags_WidthStretch, 1.4f);
        ImGui::TableSetupColumn("Type",      ImGuiTableColumnFlags_WidthStretch, 1.4f);
        ImGui::TableSetupColumn("$ / Unit",  ImGuiTableColumnFlags_WidthStretch, 1.6f);
        ImGui::TableSetupColumn("Unit",      ImGuiTableColumnFlags_WidthStretch, 1.6f);
        ImGui::TableSetupColumn("Parameter", ImGuiTableColumnFlags_WidthStretch, 2.0f);
        ImGui::TableSetupScrollFreeze(0, 1);
        ImGui::TableHeadersRow();

        // Build/reuse the filtered index list. EnsureFilteredIndices only
        // rescans the rows when an input changed — the loop is a no-op on
        // frames where nothing is dirty, so 2000-row models don't tank FPS.
        EnsureFilteredIndices();

        // Row height = frame height + item spacing. Passing it to Begin lets
        // the clipper skip its measurement pass (and avoids double-render
        // oscillation when the visible range is small).
        float rowHeight = ImGui::GetFrameHeight() + ImGui::GetStyle().ItemSpacing.y;

        ImGui::ListClipper clipper;
        clipper.Begin(int(_filteredIndices.length()), rowHeight);

        while (clipper.Step())
        {
        for (int r = clipper.DisplayStart; r < clipper.DisplayEnd; r++)
        {
            uint i = _filteredIndices[r];
            CostInfo@ row = _rows[i];

            ImGui::TableNextRow();
            ImGui::PushID(int(i));

            // Checkbox
            ImGui::TableNextColumn();
            bool selIn = row.Selected;
            bool selOut = selIn;
            if (ImGui::Checkbox("##sel", selIn, selOut))
                row.Selected = selOut;

            // Category / Family / Type
            ImGui::TableNextColumn();
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextPrimary());
            ImGui::Text(row.Category);
            ImGui::PopStyleColor();

            ImGui::TableNextColumn();
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextPrimary());
            ImGui::Text(row.Family);
            ImGui::PopStyleColor();

            ImGui::TableNextColumn();
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextPrimary());
            ImGui::Text(row.FamilyType);
            ImGui::PopStyleColor();

            // Cost per unit
            ImGui::TableNextColumn();
            ImGui::SetNextItemWidth(-1);
            float cpuIn = float(row.CostPerUnit);
            float cpuOut = cpuIn;
            if (ImGui::InputFloat("##cpu", cpuIn, cpuOut, 1.0f, 10.0f, "%.2f"))
            {
                row.CostPerUnit = double(cpuOut);
                _costDirty = true;
            }

            // Cost unit combo
            ImGui::TableNextColumn();
            ImGui::SetNextItemWidth(-1);
            int newUnit = row.CostUnit;
            if (CostDraftConst::Combo("##unit", CostDraftConst::UNIT_NAMES, row.CostUnit, newUnit))
            {
                row.CostUnit = newUnit;
                _costDirty = true;
            }

            // Parameter name
            ImGui::TableNextColumn();
            if (row.CostUnit == CostUnit_Count)
            {
                ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
                ImGui::Text("-");
                ImGui::PopStyleColor();
            }
            else
            {
                ImGui::SetNextItemWidth(-1);
                string pIn = row.CostUnitParameterName;
                string pOut = pIn;
                if (ImGui::InputText("##pname", pIn, pOut))
                {
                    row.CostUnitParameterName = pOut;
                    _costDirty = true;
                }
            }

            ImGui::PopID();
        }
        }
        clipper.End();

        ImGui::EndTable();
    }
}

// ── Card wrapper for CostDraftView ──
//
// Renders a titled, rounded card container around the view's contents.
// The color toggle lives in the card header (right-aligned), and the card
// body delegates back to the view for rendering.

class CostDraftCard : Card
{
    private CostDraftView@ _view;

    CostDraftCard(CostDraftView@ view)
    {
        super();
        @_view = view;
        title = "Costs";
        fillHeight = true;
        paddingX = 16.0f;
        paddingY = 12.0f;
        rounding = 10.0f;
    }

    // Called by CostDraftView.Destroy() before destroying the card so we
    // don't keep a dangling handle back to a being-destroyed view.
    void ClearView()
    {
        @_view = null;
    }

    bool RenderBody(const float2&in dims) override
    {
        if (_view !is null)
            _view.RenderCardBody(dims);
        return false;
    }
}
