// DemoView.as - BIM Documents donut chart view for Demo Dashboard
//
// Displays an interactive donut chart for BIM Document element distribution.
// Clicking a chart segment selects those elements in the 3D viewport.
// Also owns the shared DemoDataService and loading modal.

#include "../core/Window.as"
#include "../core/App.as"
#include "DemoConstants.as"
#include "DemoDataService.as"
#include "DemoDonutChart.as"
#include "DemoLevelHistogramView.as"
#include "DemoMaterialTableView.as"
#include "DemoMaterialService.as"

class DemoView : Window
{
    private App@ _app;
    private AppScene@ _appScene;
    private DemoMaterialService@ _matService;

    // Data (public so plugin can share with level histogram)
    DemoDataService@ dataService;

    // Table cards (set by plugin after construction)
    DemoLevelHistogramCard@ levelCard;
    DemoRoomTableCard@ roomCard;
    DemoCategoryTableCard@ categoryCard;
    DemoMaterialTableCard@ materialCard;

    // Charts
    private DemoDonutChart@ _bimDocumentDonut;

    // Events
    private Scene::EventToken@ _dataChangedToken = null;
    private bool _destroyed = false;

    // Deferred loading state -- ensures loading modal renders before heavy work
    private bool _needsLoad = false;
    private int _loadFrameCount = 0;

    DemoView(App@ app)
    {
        super("BIM Documents", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();

        @dataService = DemoDataService();

        // BIM Document donut
        @_bimDocumentDonut = DemoDonutChart();
        _bimDocumentDonut.title = "BIM Documents";
        @_bimDocumentDonut.onItemClicked = CardItemClickCallback(OnBimDocumentClicked);
        @_bimDocumentDonut.onColorClicked = CardColorCallback(OnBimDocumentColorClicked);
        @_bimDocumentDonut.onShuffleClicked = CardShuffleCallback(OnBimDocumentShuffleClicked);

        VimFlex::Console::Log("DemoView Created");
    }

    void SetLevelCard(DemoLevelHistogramCard@ card)
    {
        @levelCard = card;
    }

    void SetRoomCard(DemoRoomTableCard@ card)
    {
        @roomCard = card;
    }

    void SetCategoryCard(DemoCategoryTableCard@ card)
    {
        @categoryCard = card;
    }

    void SetMaterialCard(DemoMaterialTableCard@ card)
    {
        @materialCard = card;
    }

    void SetMaterialService(DemoMaterialService@ matService)
    {
        @_matService = matService;
    }

    void ClearChartSelections()
    {
        _bimDocumentDonut.selectedIndex = -1;
        if (categoryCard !is null)
        {
            categoryCard.selectedIndex = -1;
            categoryCard.selectedItems.deleteAll();
        }
        if (materialCard !is null)
        {
            materialCard.selectedIndex = -1;
            materialCard.selectedItems.deleteAll();
        }
    }

    void ClearChartColors()
    {
        _bimDocumentDonut.colorsApplied = false;
        if (categoryCard !is null)
            categoryCard.colorsApplied = false;
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

        @levelCard = null;
        @roomCard = null;
        @categoryCard = null;
        @materialCard = null;
        @_matService = null;

        // Break circular references: chart delegates -> this view
        if (_bimDocumentDonut !is null)
        {
            @_bimDocumentDonut.onItemClicked = null;
            @_bimDocumentDonut.onColorClicked = null;
            @_bimDocumentDonut.onShuffleClicked = null;
            @_bimDocumentDonut = null;
        }

        // Release cached SceneItemSets
        if (dataService !is null)
        {
            dataService.ClearData();
            @dataService = null;
        }

        @_appScene = null;
        @_app = null;

        Window::Destroy();
    }

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;

        VimFlex::RequestUpdateDockingRegions(-1, -1, 0.22, -1);

        if (_dataChangedToken is null)
        {
            @_dataChangedToken = _appScene.GetVimDataService().OnVimDataChanged().Subscribe(
                Scene::Event::EventCallback(OnVimDataChanged));
        }

        OnVimDataChanged();
        _app.GetAppScene().enableRender = true;
    }

    void Close() override
    {
        if (_destroyed)
        {
            Window::Close();
            return;
        }

        // Reset element colors when leaving the Demo Dashboard
        if (_appScene !is null)
        {
            _appScene.GetMaterialService().ClearMaterialOverrides();
        }

        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }

        Window::Close();
    }

    private void OnVimDataChanged()
    {
        auto@ vimData = _appScene.GetVimData();
        if (vimData is null || vimData.GetData() is null)
        {
            // VIM file unloaded: clear colors and donut state
            if (_bimDocumentDonut.colorsApplied && _matService !is null)
                _matService.ClearColors();

            _bimDocumentDonut.colorsApplied = false;
            _bimDocumentDonut.selectedIndex = -1;
            _bimDocumentDonut.items.resize(0);

            dataService.ClearData();
            return;
        }

        dataService.SetVimData(vimData.GetData());
        // Defer loading so the "Loading..." modal renders first
        _needsLoad = true;
        _loadFrameCount = 0;
    }

    // Color seed offsets per chart for visual variety
    private uint _bimDocumentSeed = 10;

    private void UpdateCharts()
    {
        // BIM Document donut
        uint docCount = dataService.bimDocumentStats.length();
        _bimDocumentDonut.items.resize(docCount);
        _bimDocumentDonut.selectedIndex = -1;
        for (uint i = 0; i < docCount; i++)
        {
            _bimDocumentDonut.items[i] = CardItem(
                dataService.bimDocumentStats[i].title,
                float(dataService.bimDocumentStats[i].count),
                GetDemoColor(i, _bimDocumentSeed));
        }

        // Level histogram updates itself via OnVimDataChanged

        // Clear selection state
    }

    private void ClearLevelHistogramSelection()
    {
        if (levelCard !is null)
        {
            levelCard.selectedIndex = -1;
            levelCard.selectedItems.deleteAll();
        }
        if (roomCard !is null)
        {
            roomCard.selectedIndex = -1;
            roomCard.selectedItems.deleteAll();
        }
        if (categoryCard !is null)
        {
            categoryCard.selectedIndex = -1;
            categoryCard.selectedItems.deleteAll();
        }
        if (materialCard !is null)
        {
            materialCard.selectedIndex = -1;
            materialCard.selectedItems.deleteAll();
        }
    }

    private void OnBimDocumentClicked(int index, const string&in label)
    {
        ClearLevelHistogramSelection();

        Scene::SceneItemSet@ itemSet = dataService.GetItemSetForBimDocument(label);
        ApplySelection(label, itemSet);
    }

    private void ApplySelection(const string&in label, Scene::SceneItemSet@ itemSet)
    {
        if (itemSet is null || itemSet.Count() == 0) return;

        _appScene.GetSelectionService().Apply(itemSet);

        VimFlex::Console::Log("Selected " + itemSet.Count() + " elements: " + label);
    }

    private void ClearLevelHistogramColors()
    {
        if (levelCard !is null)
            levelCard.colorsApplied = false;
        if (roomCard !is null)
            roomCard.colorsApplied = false;
        if (categoryCard !is null)
            categoryCard.colorsApplied = false;
    }

    private void OnBimDocumentColorClicked()
    {
        if (_bimDocumentDonut.colorsApplied)
        {
            _matService.ClearColors();
            ClearChartColors();
            ClearLevelHistogramColors();
            return;
        }

        _matService.ClearColors();
        ClearChartColors();
        ClearLevelHistogramColors();

        dictionary donutColorIndex;
        for (uint i = 0; i < _bimDocumentDonut.items.length(); i++)
            donutColorIndex[_bimDocumentDonut.items[i].label] = int(i);

        array<BimDocumentStats>@ allStats = dataService.GetAllBimDocumentStats();
        if (allStats is null) return;

        for (uint i = 0; i < allStats.length(); i++)
        {
            Scene::SceneItemSet@ itemSet = dataService.GetItemSetForBimDocument(allStats[i].title);
            if (itemSet is null || itemSet.Count() == 0) continue;

            color col;
            int donutIdx = -1;
            if (donutColorIndex.exists(allStats[i].title))
                donutColorIndex.get(allStats[i].title, donutIdx);

            if (donutIdx >= 0)
                col = _bimDocumentDonut.items[donutIdx].itemColor;
            else
                col = GetDemoColor(i, _bimDocumentSeed);

            _matService.ApplyColor(itemSet, col);
        }

        _bimDocumentDonut.colorsApplied = true;
        VimFlex::Console::Log("Applied BIM document colors to " + allStats.length() + " groups");
    }

    // --- Shuffle callbacks ---

    private void ApplyShuffledColors(DemoDonutChart@ donut, uint seed)
    {
        for (uint i = 0; i < donut.items.length(); i++)
            donut.items[i].itemColor = GetDemoColor(i, seed);
    }

    private void OnBimDocumentShuffleClicked()
    {
        _bimDocumentSeed = (_bimDocumentSeed + 3) % DEMO_PALETTE.length();
        ApplyShuffledColors(_bimDocumentDonut, _bimDocumentSeed);
        if (_bimDocumentDonut.colorsApplied)
        {
            _bimDocumentDonut.colorsApplied = false;
            OnBimDocumentColorClicked();
        }
    }

    // Stores the right split node ID for the Summary view to dock into
    uint summaryDockId = 0;

    void RegisterDockingRegion() override
    {
        // Target 600px out of 1920px default app width = 0.3125
        float leftFraction = 600.0f / 1920.0f;

        uint leftId = 0;
        uint rightId = 0;
        ImGui::DockBuilderSplitNode(VimFlex::Docking::RegionTop,
            ImGuiDir_Left, leftFraction, leftId, rightId);

        ImGui::DockBuilderDockWindow(_windowName, leftId);
        summaryDockId = rightId;
    }

    bool Render(const IRenderContext& ctx) override
    {
        // Deferred loading: render modal overlay while cards show "No data"
        if (_needsLoad)
        {
            _loadFrameCount++;
            string modalId = "Loading##BIMDashboard";
            ImGui::OpenPopup(modalId);

            Style::PushModalStyle();
            Style::SetNextWindowCentered(float2(280, 0));
            if (ImGui::BeginPopupModal(modalId,
                ImGuiWindowFlags::ImGuiWindowFlags_NoTitleBar
                | ImGuiWindowFlags::ImGuiWindowFlags_AlwaysAutoResize))
            {
                Style::PushModalBodyStyle();

                Style::TitleText("Demo Dashboard");
                ImGui::Dummy(float2(0, Style::SpacingLarge));
                ImGui::Text("Loading Data...");
                ImGui::Dummy(float2(0, Style::SpacingLarge));

                if (_loadFrameCount >= 3)
                {
                    if (!dataService.IsLoading())
                    {
                        dataService.StartLoadAllAsync();
                    }
                    else if (dataService.IsLoadingComplete())
                    {
                        dataService.FinishLoadAllAsync();
                        UpdateCharts();
                        _needsLoad = false;
                        ImGui::CloseCurrentPopup();
                    }
                }

                Style::PopModalBodyStyle();
                ImGui::EndPopup();
            }
            Style::PopModalStyle();
        }

        _bimDocumentDonut.fillHeight = true;
        _bimDocumentDonut.Render();

        return true;
    }

}
