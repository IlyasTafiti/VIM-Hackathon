// DemoMaterialTableView.as - Material table view for Demo Dashboard
//
// DemoMaterialTableCard (extends DemoTableCard):
//   Columns: Color dot (material color), Material name, Area, Volume, IsPaint.
//   Clear-colors button only (no toggle/shuffle -- elements show their own material colors).
//
// DemoMaterialTableView (extends Window):
//   Dockable "Materials" tab in RegionRight. Populates card from all material stats.

#include "../core/Window.as"
#include "../core/App.as"
#include "DemoTableCard.as"
#include "DemoDataService.as"
#include "DemoMaterialService.as"

class DemoMaterialTableCard : DemoTableCard
{
    // Material-specific parallel arrays
    array<float> itemAreas;
    array<float> itemVolumes;
    array<string> itemIsPaint;

    private float _maxArea = 0;
    private float _maxVolume = 0;

    int GetColumnCount() override { return 5; }

    void SetupColumns() override
    {
        SetupColorDotColumn();
        ImGui::TableSetupColumn("Material", ImGuiTableColumnFlags_WidthStretch);
        ImGui::TableSetupColumn("Area", ImGuiTableColumnFlags_WidthFixed, 100);
        ImGui::TableSetupColumn("Volume", ImGuiTableColumnFlags_WidthFixed | ImGuiTableColumnFlags_DefaultSort | ImGuiTableColumnFlags_PreferSortDescending, 100);
        ImGui::TableSetupColumn("Paint", ImGuiTableColumnFlags_WidthFixed, 50);
    }

    void ApplyInitialSort() override
    {
        SortByColumn(3, false); // Sort by Volume descending
    }

    void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl) override
    {
        RenderColorDot(idx, dl);
        RenderSelectableCell(idx, row);

        // Area column (inline bar + value)
        ImGui::TableNextColumn();
        if (idx < itemAreas.length())
        {
            RenderBarCell(idx, itemAreas[idx], _maxArea, dl);
        }

        // Volume column (inline bar + value)
        ImGui::TableNextColumn();
        if (idx < itemVolumes.length())
        {
            RenderBarCell(idx, itemVolumes[idx], _maxVolume, dl);
        }

        // IsPaint column
        ImGui::TableNextColumn();
        if (idx < itemIsPaint.length())
        {
            ImGui::Text(itemIsPaint[idx]);
        }
    }

    private void RenderBarCell(uint idx, float val, float maxVal, ImGui::ImDrawList@ dl)
    {
        float lineH = ImGui::GetTextLineHeight();
        float2 cellPos = ImGui::GetCursorScreenPos();
        float cellW = ImGui::GetContentRegionAvail().x;
        float barMaxW = cellW * 0.55f;
        if (barMaxW < 10) barMaxW = 10;

        float barW = (maxVal > 0) ? (val / maxVal) * barMaxW : 0;
        if (val > 0 && barW < 2) barW = 2;

        float barY = cellPos.y + 2.0f;
        float barH = lineH - 4.0f;
        if (barH < 4) barH = 4;

        if (barW > 0)
        {
            dl.AddRectFilled(
                float2(cellPos.x, barY),
                float2(cellPos.x + barW, barY + barH),
                items[idx].itemColor,
                3.0f, ImDrawFlags_RoundCornersAll);
        }

        float countX = cellPos.x + barW + 4.0f;
        float spaceLeft = (cellPos.x + cellW) - countX;
        string valText = FormatCompact(val, spaceLeft);
        dl.AddText(float2(countX, cellPos.y), Style::GetColorText(), valText);

        ImGui::Dummy(float2(cellW, lineH));
    }

    int CompareItems(uint a, uint b, int column, bool ascending) override
    {
        int result = 0;
        if (column == 1) // Material name
        {
            if (items[a].label < items[b].label) result = -1;
            else if (items[a].label > items[b].label) result = 1;
        }
        else if (column == 2) // Area
        {
            float va = (a < itemAreas.length()) ? itemAreas[a] : 0;
            float vb = (b < itemAreas.length()) ? itemAreas[b] : 0;
            if (va < vb) result = -1;
            else if (va > vb) result = 1;
        }
        else if (column == 3) // Volume
        {
            float va = (a < itemVolumes.length()) ? itemVolumes[a] : 0;
            float vb = (b < itemVolumes.length()) ? itemVolumes[b] : 0;
            if (va < vb) result = -1;
            else if (va > vb) result = 1;
        }
        else if (column == 4) // IsPaint
        {
            string sa = (a < itemIsPaint.length()) ? itemIsPaint[a] : "";
            string sb = (b < itemIsPaint.length()) ? itemIsPaint[b] : "";
            if (sa < sb) result = -1;
            else if (sa > sb) result = 1;
        }

        return ascending ? result : -result;
    }

    void OnClearData() override
    {
        itemAreas.resize(0);
        itemVolumes.resize(0);
        itemIsPaint.resize(0);
        _maxArea = 0;
        _maxVolume = 0;
    }

    void UpdateMaxValues()
    {
        _maxArea = 0;
        _maxVolume = 0;
        for (uint i = 0; i < itemAreas.length(); i++)
        {
            if (itemAreas[i] > _maxArea) _maxArea = itemAreas[i];
        }
        for (uint i = 0; i < itemVolumes.length(); i++)
        {
            if (itemVolumes[i] > _maxVolume) _maxVolume = itemVolumes[i];
        }
    }

    private string FormatCompact(float val, float maxPixelWidth)
    {
        // For large values, always use K/M suffixes to avoid
        // scientific notation issues with float-to-string conversion
        if (val >= 1000000.0f)
        {
            string mStr = CardFormatFloat(val / 1000000.0f, 1) + "M";
            if (ImGui::CalcTextSize(mStr).x <= maxPixelWidth)
                return mStr;
            return CardFormatInt(int(val / 1000000.0f)) + "M";
        }
        if (val >= 10000.0f)
        {
            string kStr = CardFormatFloat(val / 1000.0f, 1) + "K";
            if (ImGui::CalcTextSize(kStr).x <= maxPixelWidth)
                return kStr;
            return CardFormatInt(int(val / 1000.0f)) + "K";
        }

        // Small enough for direct formatting
        string full = CardFormatFloat(val, 1);
        if (ImGui::CalcTextSize(full).x <= maxPixelWidth)
            return full;

        return CardFormatInt(int(val));
    }

    // Override header controls to show a clear-colors button (non-toggle).
    // Materials show their own colors, so "apply" is not meaningful --
    // but the user may want to clear overrides left by other tabs.
    CardItemClickCallback@ onClearColorsClicked = null;

    void RenderHeaderControls() override
    {
        if (onClearColorsClicked is null) return;

        string iconColor = "\xEE\x9E\x90";
        float2 btnSize = Style::GetIconButtonSize(iconColor);
        float availX = ImGui::GetContentRegionAvail().x;
        float rightPad = headerPadX;

        if (availX > btnSize.x + rightPad)
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() + availX - btnSize.x - rightPad);

        color iconTextColor = Style::GetColorText();
        string clearId = iconColor + "##clearcolors_" + title;
        if (VimFlex::IconButtonTransparent(clearId, iconTextColor, true, float2(0, 0), "Clear Colors"))
        {
            onClearColorsClicked(0, "");
        }
    }
}

// Forward declaration callback for cross-chart coordination
funcdef void MaterialChartNotifyCallback();

class DemoMaterialTableView : Window
{
    private App@ _app;
    private AppScene@ _appScene;

    // The card
    DemoMaterialTableCard@ card;

    // Cross-chart coordination callbacks (set by plugin)
    MaterialChartNotifyCallback@ onClearOtherSelections = null;
    MaterialChartNotifyCallback@ onClearOtherColors = null;

    // Data
    private DemoDataService@ _dataService;
    private DemoMaterialService@ _matService;
    private bool _dataLoaded = false;

    // Events
    private Scene::EventToken@ _dataChangedToken = null;
    private bool _destroyed = false;
    private bool _needsFocus = false;

    DemoMaterialTableView(App@ app, DemoDataService@ dataService)
    {
        super("Materials", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_dataService = dataService;

        @card = DemoMaterialTableCard();
        card.title = "Materials";
        card.fillHeight = true;
        @card.onItemClicked = CardItemClickCallback(OnMaterialClicked);
        @card.onClearColorsClicked = CardItemClickCallback(OnClearColorsClicked);

        VimFlex::Console::Log("DemoMaterialTableView Created");
    }

    void SetMaterialService(DemoMaterialService@ matService)
    {
        @_matService = matService;
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;

        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }

        @onClearOtherSelections = null;
        @onClearOtherColors = null;

        if (card !is null)
        {
            @card.onItemClicked = null;
            @card.onClearColorsClicked = null;
            @card = null;
        }

        @_matService = null;
        @_dataService = null;
        @_appScene = null;
        @_app = null;

        Window::Destroy();
        VimFlex::Console::Log("DemoMaterialTableView Destroyed");
    }

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;
        _needsFocus = true;

        if (_dataChangedToken is null)
        {
            @_dataChangedToken = _appScene.GetVimDataService().OnVimDataChanged().Subscribe(
                Scene::Event::EventCallback(OnVimDataChanged));
        }

        OnVimDataChanged();
    }

    void Close() override
    {
        if (_destroyed)
        {
            Window::Close();
            return;
        }

        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }

        Window::Close();
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionRight);
    }

    private void OnVimDataChanged()
    {
        if (_dataService is null || !_dataService.IsDataLoaded())
        {
            card.ClearData();
            _dataLoaded = false;
            return;
        }

        UpdateCardItems();
    }

    void UpdateCardItems()
    {
        if (_dataService is null) return;

        card.ClearData();

        array<MaterialStats>@ allMats = _dataService.GetAllMaterialStats();
        if (allMats is null) return;

        for (uint i = 0; i < allMats.length(); i++)
        {
            // Material color from model
            uint8 mr = uint8(Math::Clamp(allMats[i].color_x * 255.0f, 0.0f, 255.0f));
            uint8 mg = uint8(Math::Clamp(allMats[i].color_y * 255.0f, 0.0f, 255.0f));
            uint8 mb = uint8(Math::Clamp(allMats[i].color_z * 255.0f, 0.0f, 255.0f));
            color matColor = color(mr, mg, mb, 255);

            // Use element count as the CardItem value (for consistency)
            card.items.insertLast(CardItem(
                allMats[i].name,
                float(allMats[i].elements),
                matColor));

            card.itemAreas.insertLast(allMats[i].totalArea);
            card.itemVolumes.insertLast(allMats[i].totalVolume);

            // IsPaint label
            string paintLabel;
            if (allMats[i].hasPaint > 0 && allMats[i].hasNonPaint > 0)
                paintLabel = "Mixed";
            else if (allMats[i].hasPaint > 0)
                paintLabel = "Yes";
            else
                paintLabel = "No";
            card.itemIsPaint.insertLast(paintLabel);
        }

        card.UpdateMaxValues();
        _dataLoaded = true;
    }

    bool Render(const IRenderContext& ctx) override
    {
        if (_needsFocus)
        {
            ImGui::SetWindowFocus();
            _needsFocus = false;
        }

        if (!_dataLoaded && _dataService !is null && _dataService.IsDataLoaded())
            UpdateCardItems();

        card.Render();

        return true;
    }

    // --- Callbacks ---

    private void OnMaterialClicked(int index, const string&in label)
    {
        if (!card.lastClickWasAdditive)
        {
            if (onClearOtherSelections !is null)
                onClearOtherSelections();
        }

        if (card.lastClickWasAdditive)
        {
            Scene::SceneItemSet merged;
            auto@ keys = card.selectedItems.getKeys();
            for (uint k = 0; k < keys.length(); k++)
            {
                uint idx = parseInt(keys[k]);
                if (idx < card.items.length())
                {
                    Scene::SceneItemSet@ matSet = _dataService.GetItemSetForMaterial(card.items[idx].label);
                    if (matSet !is null)
                        merged.Add(matSet);
                }
            }
            if (merged.Count() > 0)
            {
                _appScene.GetSelectionService().Apply(merged);
                VimFlex::Console::Log("Selected " + merged.Count() + " elements from " + keys.length() + " materials");
            }
        }
        else
        {
            Scene::SceneItemSet@ itemSet = _dataService.GetItemSetForMaterial(label);
            if (itemSet is null || itemSet.Count() == 0) return;

            _appScene.GetSelectionService().Apply(itemSet);
            VimFlex::Console::Log("Selected " + itemSet.Count() + " elements: " + label);
        }
    }

    private void OnClearColorsClicked(int index, const string&in label)
    {
        if (_matService !is null)
            _matService.ClearColors();

        if (onClearOtherColors !is null)
            onClearOtherColors();
    }
}
