// DemoLevelHistogramView.as - Level table view for Demo Dashboard
//
// DemoLevelHistogramCard (extends DemoTableCard):
//   Columns: Color dot, Level name, Elevation, Elements (inline bar + count).
//   Pins <unknown> to top via CompareItems override.
//
// DemoLevelHistogramView (extends Window):
//   Dockable "Levels" tab in RegionRight. Populates card from DemoDataService.levelStats.
//   Uses DemoMaterialService for color operations (preserves glass invariant).

#include "../core/Window.as"
#include "../core/App.as"
#include "DemoTableCard.as"
#include "DemoDataService.as"
#include "DemoMaterialService.as"

class DemoLevelHistogramCard : DemoTableCard
{
    // Level-specific data
    array<float> itemElevations;
    private float _maxVal = 0;

    int GetColumnCount() override { return 4; }

    void SetupColumns() override
    {
        SetupColorDotColumn();
        ImGui::TableSetupColumn("Level", ImGuiTableColumnFlags_WidthStretch | ImGuiTableColumnFlags_DefaultSort);
        ImGui::TableSetupColumn("Elev.", ImGuiTableColumnFlags_WidthFixed, 40);
        ImGui::TableSetupColumn("Elements", ImGuiTableColumnFlags_WidthFixed, 160);
    }

    void ApplyInitialSort() override
    {
        // Pin <unknown> to top, keep elevation ascending
        SortByColumn(2, true);
    }

    void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl) override
    {
        RenderColorDot(idx, dl);
        RenderSelectableCell(idx, row);

        // Elevation
        ImGui::TableNextColumn();
        if (idx < itemElevations.length())
        {
            float elev = itemElevations[idx];
            if (elev < 999999.0f)
                ImGui::Text(CardFormatFloat(elev, 1));
            else
                ImGui::TextDisabled("-");
        }
        else
        {
            ImGui::TextDisabled("-");
        }

        // Elements (inline bar + count)
        ImGui::TableNextColumn();
        {
            float lineH = ImGui::GetTextLineHeight();
            float2 cellPos = ImGui::GetCursorScreenPos();
            float cellW = ImGui::GetContentRegionAvail().x;
            float barMaxW = cellW * 0.65f;
            if (barMaxW < 10) barMaxW = 10;

            float barW = (_maxVal > 0) ? (items[idx].value / _maxVal) * barMaxW : 0;
            if (barW < 2) barW = 2;

            float barY = cellPos.y + 2.0f;
            float barH = lineH - 4.0f;
            if (barH < 4) barH = 4;

            dl.AddRectFilled(
                float2(cellPos.x, barY),
                float2(cellPos.x + barW, barY + barH),
                items[idx].itemColor,
                3.0f, ImDrawFlags_RoundCornersAll);

            string countText = CardFormatInt(int(items[idx].value));
            float countX = cellPos.x + barW + 4.0f;
            dl.AddText(float2(countX, cellPos.y), Style::GetColorText(), countText);

            ImGui::Dummy(float2(cellW, lineH));
        }
    }

    int CompareItems(uint a, uint b, int column, bool ascending) override
    {
        // <unknown> always sorts to top
        bool aUnknown = (items[a].label == UNKNOWN_LABEL);
        bool bUnknown = (items[b].label == UNKNOWN_LABEL);
        if (aUnknown && !bUnknown) return -1;
        if (!aUnknown && bUnknown) return 1;

        int result = 0;
        if (column == 1) // Level name
        {
            if (items[a].label < items[b].label) result = -1;
            else if (items[a].label > items[b].label) result = 1;
        }
        else if (column == 2) // Elevation
        {
            float va = (a < itemElevations.length()) ? itemElevations[a] : 0;
            float vb = (b < itemElevations.length()) ? itemElevations[b] : 0;
            if (va < vb) result = -1;
            else if (va > vb) result = 1;
        }
        else if (column == 3) // Elements
        {
            if (items[a].value < items[b].value) result = -1;
            else if (items[a].value > items[b].value) result = 1;
        }

        return ascending ? result : -result;
    }

    void OnClearData() override
    {
        itemElevations.resize(0);
        _maxVal = 0;
    }

    void UpdateMaxValue()
    {
        _maxVal = 0;
        for (uint i = 0; i < items.length(); i++)
        {
            if (items[i].value > _maxVal) _maxVal = items[i].value;
        }
    }
}

// Forward declaration callback for cross-chart coordination
funcdef void LevelChartNotifyCallback();

class DemoLevelHistogramView : Window
{
    private App@ _app;
    private AppScene@ _appScene;

    // The card
    DemoLevelHistogramCard@ card;

    // Cross-chart coordination callbacks (set by plugin)
    LevelChartNotifyCallback@ onClearOtherSelections = null;
    LevelChartNotifyCallback@ onClearOtherColors = null;

    // Data
    private DemoDataService@ _dataService;
    private DemoMaterialService@ _matService;
    private bool _dataLoaded = false;

    // Color seed
    private uint _levelSeed = 7;

    // Events
    private Scene::EventToken@ _dataChangedToken = null;
    private bool _destroyed = false;
    private bool _needsFocus = false;

    DemoLevelHistogramView(App@ app, DemoDataService@ dataService)
    {
        super("Levels", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_dataService = dataService;

        @card = DemoLevelHistogramCard();
        card.title = "Levels";
        card.fillHeight = true;
        @card.onItemClicked = CardItemClickCallback(OnLevelClicked);
        @card.onColorClicked = CardColorCallback(OnLevelColorClicked);
        @card.onShuffleClicked = CardShuffleCallback(OnLevelShuffleClicked);

        VimFlex::Console::Log("DemoLevelHistogramView Created");
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
            @card.onColorClicked = null;
            @card.onShuffleClicked = null;
            @card = null;
        }

        @_matService = null;
        @_dataService = null;
        @_appScene = null;
        @_app = null;

        Window::Destroy();
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
            if (card.colorsApplied && _matService !is null)
            {
                _matService.ClearColors();
                card.colorsApplied = false;
            }
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

        for (uint i = 0; i < _dataService.levelStats.length(); i++)
        {
            color col = GetDemoColorForLabel(_dataService.levelStats[i].name, i, _levelSeed);
            card.items.insertLast(CardItem(
                _dataService.levelStats[i].name,
                float(_dataService.levelStats[i].count),
                col));
            card.itemElevations.insertLast(_dataService.levelStats[i].elevation);
        }

        card.UpdateMaxValue();
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

    private void OnLevelClicked(int index, const string&in label)
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
                    Scene::SceneItemSet@ lvlSet = _dataService.GetItemSetForLevel(card.items[idx].label);
                    if (lvlSet !is null)
                        merged.Add(lvlSet);
                }
            }
            if (merged.Count() > 0)
            {
                _appScene.GetSelectionService().Apply(merged);
                VimFlex::Console::Log("Selected " + merged.Count() + " elements from " + keys.length() + " levels");
            }
        }
        else
        {
            Scene::SceneItemSet@ itemSet = _dataService.GetItemSetForLevel(label);
            if (itemSet is null || itemSet.Count() == 0) return;

            _appScene.GetSelectionService().Apply(itemSet);
            VimFlex::Console::Log("Selected " + itemSet.Count() + " elements: " + label);
        }
    }

    private void OnLevelColorClicked()
    {
        if (card.colorsApplied)
        {
            _matService.ClearColors();
            card.colorsApplied = false;
            if (onClearOtherColors !is null)
                onClearOtherColors();
            return;
        }

        _matService.ClearColors();
        if (onClearOtherColors !is null)
            onClearOtherColors();

        array<LevelStats>@ allStats = _dataService.GetAllLevelStats();
        if (allStats is null) return;

        for (uint i = 0; i < allStats.length(); i++)
        {
            Scene::SceneItemSet@ itemSet = _dataService.GetItemSetForLevel(allStats[i].name);
            if (itemSet is null || itemSet.Count() == 0) continue;

            _matService.ApplyColor(itemSet, GetDemoColorForLabel(allStats[i].name, i, _levelSeed));
        }

        card.colorsApplied = true;
        VimFlex::Console::Log("Applied level colors to " + allStats.length() + " levels");
    }

    private void OnLevelShuffleClicked()
    {
        _levelSeed = (_levelSeed + 3) % DEMO_PALETTE.length();
        for (uint i = 0; i < card.items.length(); i++)
            card.items[i].itemColor = GetDemoColorForLabel(card.items[i].label, i, _levelSeed);

        if (card.colorsApplied)
        {
            card.colorsApplied = false;
            OnLevelColorClicked();
        }
    }
}
