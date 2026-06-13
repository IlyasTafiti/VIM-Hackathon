// DemoTableCard.as - Reusable base class for sortable table cards
//
// Provides: header controls (shuffle/color buttons), sortable ImGui table with
// ListClipper virtualization, multi-selection (click/Ctrl+click/Shift+click).
//
// Subclasses override:
//   GetColumnCount()     - total column count
//   SetupColumns()       - ImGui::TableSetupColumn() calls
//   RenderRowCells()     - per-row cell rendering (use RenderSelectableCell + RenderColorDot helpers)
//   CompareItems()       - sort comparison (-1/0/+1, already direction-aware)
//   ApplyInitialSort()   - optional initial sort on first data load
//   OnClearData()        - optional cleanup of subclass-specific arrays
//
// See Demo/README.md for a minimal subclass example.

#include "../widgets/cards/Card.as"
#include "../widgets/cards/CardUtils.as"
#include "DemoConstants.as"
#include "DemoCardTypes.as"

class DemoTableCard : Card
{
    // Shared data
    array<CardItem> items;

    // Callbacks
    CardItemClickCallback@ onItemClicked = null;
    CardColorCallback@ onColorClicked = null;
    CardShuffleCallback@ onShuffleClicked = null;

    // Selection state
    int selectedIndex = -1;
    bool colorsApplied = false;
    bool lastClickWasAdditive = false;
    dictionary selectedItems;
    int _anchorRow = -1;

    // Sorted index mapping (display row -> items[] index)
    protected array<uint> _sortedIndices;
    private bool _needsSort = true;

    DemoTableCard()
    {
        super();
        paddingX = 16.0f;
        paddingY = 12.0f;
        rounding = 10.0f;
    }

    // --- Overridable by subclasses ---

    // Return the number of table columns.
    int GetColumnCount() { return 1; }

    // Set up ALL table columns via ImGui::TableSetupColumn().
    void SetupColumns() {}

    // Render all cells for a row. Call RenderSelectableCell() in the column
    // that should handle click/selection, and TableNextColumn() + draw for the rest.
    void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl) {}

    // Compare two items for sorting. Return -1, 0, or +1.
    // The return value should already account for direction: negate for descending.
    // Column indices match the order from SetupColumns() (0-based).
    int CompareItems(uint a, uint b, int column, bool ascending)
    {
        return 0;
    }

    // Called when sorted indices are first built. Override to apply an initial sort.
    void ApplyInitialSort()
    {
        // Default: no initial sort (items appear in data order)
    }

    // --- Shared infrastructure ---

    void RenderHeaderControls() override
    {
        if (onColorClicked is null) return;

        string iconShuffle = "\xEE\xA2\xB1";
        string iconColor   = "\xEE\x9E\x90";

        string colorHover = colorsApplied ? "Clear Colors" : "Apply Colors";

        float2 shuffleSize = Style::GetIconButtonSize(iconShuffle);
        float2 colorSize = Style::GetIconButtonSize(iconColor);
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float totalW = shuffleSize.x + spacing + colorSize.x;

        float availX = ImGui::GetContentRegionAvail().x;
        float rightPad = headerPadX;
        if (availX > totalW + rightPad)
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() + availX - totalW - rightPad);

        color iconTextColor = Style::GetColorText();
        string shuffleId = iconShuffle + "##shuffle_" + title;
        if (VimFlex::IconButtonTransparent(shuffleId, iconTextColor, true, float2(0, 0), "Shuffle Colors"))
        {
            if (onShuffleClicked !is null)
                onShuffleClicked();
        }

        ImGui::SameLine();

        string colorId = iconColor + "##color_" + title;
        if (VimFlex::IconButtonTransparentToggle(colorId, iconTextColor, colorsApplied, true, float2(0, 0), colorHover))
        {
            onColorClicked();
        }
    }

    bool RenderBody(const float2&in dims) override
    {
        if (items.length() == 0)
        {
            ImGui::TextDisabled("No data");
            return false;
        }

        // Initialize sorted indices if needed
        if (_needsSort || _sortedIndices.length() != items.length())
        {
            _sortedIndices.resize(items.length());
            for (uint i = 0; i < items.length(); i++)
                _sortedIndices[i] = i;
            ApplyInitialSort();
            _needsSort = false;
        }

        int tableFlags = ImGuiTableFlags_Sortable
            | ImGuiTableFlags_ScrollY
            | ImGuiTableFlags_RowBg
            | ImGuiTableFlags_BordersOuterH
            | ImGuiTableFlags_BordersV
            | ImGuiTableFlags_NoBordersInBody
            | ImGuiTableFlags_Resizable
            | ImGuiTableFlags_SizingStretchProp;

        float2 tableSize = float2(dims.x, dims.y > 0 ? dims.y : 0);

        if (!ImGui::BeginTable("##Table_" + title, GetColumnCount(), tableFlags, tableSize))
            return false;

        SetupColumns();

        ImGui::TableSetupScrollFreeze(0, 1);
        ImGui::TableHeadersRow();

        // Handle sorting
        auto@ sortSpecs = ImGui::TableGetSortSpecs();
        if (sortSpecs.SpecsDirty && sortSpecs.SpecsCount > 0)
        {
            auto@ spec = sortSpecs.GetSpec(0);
            bool asc = (spec.SortDirection == ImGuiSortDirection_Ascending);
            int col = spec.ColumnIndex;

            int selOrigIdx = (selectedIndex >= 0 && selectedIndex < int(_sortedIndices.length()))
                ? int(_sortedIndices[selectedIndex]) : -1;

            SortIndices(col, asc);

            if (selOrigIdx >= 0)
            {
                selectedIndex = -1;
                for (uint k = 0; k < _sortedIndices.length(); k++)
                {
                    if (int(_sortedIndices[k]) == selOrigIdx)
                    {
                        selectedIndex = int(k);
                        break;
                    }
                }
            }

            sortSpecs.SpecsDirty = false;
        }

        // Render rows with clipper
        ImGui::ListClipper clipper;
        clipper.Begin(int(_sortedIndices.length()));

        while (clipper.Step())
        {
            for (int row = clipper.DisplayStart; row < clipper.DisplayEnd; row++)
            {
                uint idx = _sortedIndices[row];

                ImGui::TableNextRow();
                auto@ dl = ImGui::GetWindowDrawList();
                RenderRowCells(idx, row, dl);
            }
        }

        ImGui::EndTable();
        return false;
    }

    void ClearData()
    {
        items.resize(0);
        selectedIndex = -1;
        _anchorRow = -1;
        selectedItems.deleteAll();
        InvalidateSort();
        OnClearData();
    }

    // Override to clear subclass-specific arrays
    void OnClearData() {}

    bool HasSelection()
    {
        return selectedItems.getKeys().length() > 0;
    }

    void InvalidateSort()
    {
        _needsSort = true;
    }

    // --- Helpers for subclasses ---

    // Render a selectable cell that handles click/Ctrl/Shift selection.
    // Call from RenderRowCells() in the column that should be the click target.
    // Calls TableNextColumn() internally.
    void RenderSelectableCell(uint idx, int row)
    {
        ImGui::TableNextColumn();
        bool isSelected = selectedItems.exists("" + idx);
        if (ImGui::Selectable(items[idx].label + "##row" + row, isSelected,
            ImGuiSelectableFlags_SpanAllColumns))
        {
            HandleRowClick(row, idx);
        }
    }

    // Render a color dot column cell. Call from RenderRowCells().
    // Calls TableNextColumn() internally.
    void RenderColorDot(uint idx, ImGui::ImDrawList@ dl)
    {
        ImGui::TableNextColumn();
        float2 cellMin = ImGui::GetCursorScreenPos();
        float lineH = ImGui::GetTextLineHeight();
        float cx = cellMin.x + 12.0f;
        float cy = cellMin.y + lineH * 0.5f;
        dl.AddCircleFilled(float2(cx, cy), 5.0f, items[idx].itemColor, 12);
    }

    // Set up a non-sortable, fixed-width color dot column. Call from SetupColumns().
    void SetupColorDotColumn()
    {
        ImGui::TableSetupColumn("", ImGuiTableColumnFlags_WidthFixed
            | ImGuiTableColumnFlags_NoSort | ImGuiTableColumnFlags_NoResize, 24);
    }

    // --- Private helpers ---

    private void HandleRowClick(int row, uint idx)
    {
        bool ctrlHeld = ImGui::IsKeyDown(ImGuiMod_Ctrl);
        bool shiftHeld = ImGui::IsKeyDown(ImGuiMod_Shift);
        lastClickWasAdditive = ctrlHeld || shiftHeld;

        if (shiftHeld && _anchorRow >= 0)
        {
            int lo = (_anchorRow < row) ? _anchorRow : row;
            int hi = (_anchorRow > row) ? _anchorRow : row;
            if (!ctrlHeld)
                selectedItems.deleteAll();
            for (int r = lo; r <= hi; r++)
            {
                if (r >= 0 && r < int(_sortedIndices.length()))
                    selectedItems["" + _sortedIndices[r]] = true;
            }
        }
        else if (ctrlHeld)
        {
            string key = "" + idx;
            if (selectedItems.exists(key))
                selectedItems.delete(key);
            else
                selectedItems[key] = true;
            _anchorRow = row;
        }
        else
        {
            selectedItems.deleteAll();
            selectedItems["" + idx] = true;
            _anchorRow = row;
        }

        selectedIndex = row;
        if (onItemClicked !is null)
            onItemClicked(int(idx), items[idx].label);
    }

    void SortByColumn(int column, bool ascending)
    {
        SortIndices(column, ascending);
    }

    private void SortIndices(int column, bool ascending)
    {
        for (uint i = 1; i < _sortedIndices.length(); i++)
        {
            uint key = _sortedIndices[i];
            int j = int(i) - 1;
            while (j >= 0 && CompareItems(_sortedIndices[j], key, column, ascending) > 0)
            {
                _sortedIndices[j + 1] = _sortedIndices[j];
                j--;
            }
            _sortedIndices[j + 1] = key;
        }
    }
}
