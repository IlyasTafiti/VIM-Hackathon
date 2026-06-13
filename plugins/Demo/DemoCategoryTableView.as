// DemoCategoryTableView.as - Category table view for Demo Dashboard
//
// DemoCategoryTableCard (extends DemoTableCard):
//   Columns: Color dot, Category name, Elements (inline bar + count).
//
// DemoCategoryTableView (extends Window):
//   Dockable "Categories" tab in RegionRight. Populates card from all category stats.
//   Uses DemoMaterialService for color operations.

#include "../core/Window.as"
#include "../core/App.as"
#include "DemoTableCard.as"
#include "DemoDataService.as"
#include "DemoMaterialService.as"

class DemoCategoryTableCard : DemoTableCard
{
    private float _maxVal = 0;

    int GetColumnCount() override { return 3; }

    void SetupColumns() override
    {
        SetupColorDotColumn();
        ImGui::TableSetupColumn("Category", ImGuiTableColumnFlags_WidthStretch | ImGuiTableColumnFlags_DefaultSort);
        ImGui::TableSetupColumn("Elements", ImGuiTableColumnFlags_WidthFixed, 160);
    }

    void ApplyInitialSort() override
    {
        // Default: sort by element count descending
        SortByColumn(2, false);
    }

    void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl) override
    {
        RenderColorDot(idx, dl);
        RenderSelectableCell(idx, row);

        // Elements (inline bar + count)
        ImGui::TableNextColumn();
        {
            float val = items[idx].value;
            float lineH = ImGui::GetTextLineHeight();
            float2 cellPos = ImGui::GetCursorScreenPos();
            float cellW = ImGui::GetContentRegionAvail().x;
            float barMaxW = cellW * 0.65f;
            if (barMaxW < 10) barMaxW = 10;

            float barW = (_maxVal > 0) ? (val / _maxVal) * barMaxW : 0;
            if (barW < 2) barW = 2;

            float barY = cellPos.y + 2.0f;
            float barH = lineH - 4.0f;
            if (barH < 4) barH = 4;

            dl.AddRectFilled(
                float2(cellPos.x, barY),
                float2(cellPos.x + barW, barY + barH),
                items[idx].itemColor,
                3.0f, ImDrawFlags_RoundCornersAll);

            string countText = CardFormatInt(int(val));
            float countX = cellPos.x + barW + 4.0f;
            dl.AddText(float2(countX, cellPos.y), Style::GetColorText(), countText);

            ImGui::Dummy(float2(cellW, lineH));
        }
    }

    int CompareItems(uint a, uint b, int column, bool ascending) override
    {
        int result = 0;
        if (column == 1) // Category name
        {
            if (items[a].label < items[b].label) result = -1;
            else if (items[a].label > items[b].label) result = 1;
        }
        else if (column == 2) // Elements
        {
            if (items[a].value < items[b].value) result = -1;
            else if (items[a].value > items[b].value) result = 1;
        }

        return ascending ? result : -result;
    }

    void OnClearData() override
    {
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
funcdef void CategoryChartNotifyCallback();

class DemoCategoryTableView : Window
{
    private App@ _app;
    private AppScene@ _appScene;

    // The card
    DemoCategoryTableCard@ card;

    // Cross-chart coordination callbacks (set by plugin)
    CategoryChartNotifyCallback@ onClearOtherSelections = null;
    CategoryChartNotifyCallback@ onClearOtherColors = null;

    // Data
    private DemoDataService@ _dataService;
    private DemoMaterialService@ _matService;
    private bool _dataLoaded = false;

    // Color seed
    private uint _categorySeed = 0;

    // Events
    private Scene::EventToken@ _dataChangedToken = null;
    private bool _destroyed = false;
    private bool _needsFocus = false;

    DemoCategoryTableView(App@ app, DemoDataService@ dataService)
    {
        super("Categories", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_dataService = dataService;

        @card = DemoCategoryTableCard();
        card.title = "Categories";
        card.fillHeight = true;
        @card.onItemClicked = CardItemClickCallback(OnCategoryClicked);
        @card.onColorClicked = CardColorCallback(OnCategoryColorClicked);
        @card.onShuffleClicked = CardShuffleCallback(OnCategoryShuffleClicked);

        VimFlex::Console::Log("DemoCategoryTableView Created");
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

        array<CategoryStats>@ allCats = _dataService.GetAllCategoryStats();
        if (allCats is null) return;

        for (uint i = 0; i < allCats.length(); i++)
        {
            color col = GetDemoColor(i, _categorySeed);
            card.items.insertLast(CardItem(
                allCats[i].name,
                float(allCats[i].count),
                col));
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

    private void OnCategoryClicked(int index, const string&in label)
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
                    Scene::SceneItemSet@ catSet = _dataService.GetItemSetForCategory(card.items[idx].label);
                    if (catSet !is null)
                        merged.Add(catSet);
                }
            }
            if (merged.Count() > 0)
            {
                _appScene.GetSelectionService().Apply(merged);
                VimFlex::Console::Log("Selected " + merged.Count() + " elements from " + keys.length() + " categories");
            }
        }
        else
        {
            Scene::SceneItemSet@ itemSet = _dataService.GetItemSetForCategory(label);
            if (itemSet is null || itemSet.Count() == 0) return;

            _appScene.GetSelectionService().Apply(itemSet);
            VimFlex::Console::Log("Selected " + itemSet.Count() + " elements: " + label);
        }
    }

    private void OnCategoryColorClicked()
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

        array<CategoryStats>@ allStats = _dataService.GetAllCategoryStats();
        if (allStats is null) return;

        for (uint i = 0; i < allStats.length(); i++)
        {
            Scene::SceneItemSet@ itemSet = _dataService.GetItemSetForCategory(allStats[i].name);
            if (itemSet is null || itemSet.Count() == 0) continue;

            _matService.ApplyColor(itemSet, GetDemoColor(i, _categorySeed));
        }

        card.colorsApplied = true;
        VimFlex::Console::Log("Applied category colors to " + allStats.length() + " categories");
    }

    private void OnCategoryShuffleClicked()
    {
        _categorySeed = (_categorySeed + 3) % DEMO_PALETTE.length();
        for (uint i = 0; i < card.items.length(); i++)
            card.items[i].itemColor = GetDemoColor(i, _categorySeed);

        if (card.colorsApplied)
        {
            card.colorsApplied = false;
            OnCategoryColorClicked();
        }
    }
}
