// DemoRoomTableView.as - Room table view for Demo Dashboard
//
// DemoRoomTableCard (extends DemoTableCard):
//   Columns: Color dot, Name, Number, Level, Area, Volume, Elements.
//
// DemoRoomTableView (extends Window):
//   Dockable "Rooms" tab in RegionRight. Populates card from DemoDataService.roomStats.
//   Uses DemoMaterialService for color operations (preserves glass invariant).
//   IMPORTANT: Color application uses GetPhysicalItemSetForRoom() (not GetItemSetForRoom())
//   to avoid overwriting the glass material on room geometry with an opaque color.

#include "../core/Window.as"
#include "../core/App.as"
#include "DemoTableCard.as"
#include "DemoDataService.as"
#include "DemoMaterialService.as"

class DemoRoomTableCard : DemoTableCard
{
    // Room-specific data
    array<string> itemNumbers;
    array<string> itemLevelNames;
    array<float> itemAreas;
    array<float> itemVolumes;

    int GetColumnCount() override { return 7; }

    void SetupColumns() override
    {
        SetupColorDotColumn();
        ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch | ImGuiTableColumnFlags_DefaultSort);
        ImGui::TableSetupColumn("Number", ImGuiTableColumnFlags_WidthFixed, 60);
        ImGui::TableSetupColumn("Level", ImGuiTableColumnFlags_WidthFixed, 100);
        ImGui::TableSetupColumn("Area", ImGuiTableColumnFlags_WidthFixed, 60);
        ImGui::TableSetupColumn("Volume", ImGuiTableColumnFlags_WidthFixed, 70);
        ImGui::TableSetupColumn("Elements", ImGuiTableColumnFlags_WidthFixed, 60);
    }

    void RenderRowCells(uint idx, int row, ImGui::ImDrawList@ dl) override
    {
        RenderColorDot(idx, dl);
        RenderSelectableCell(idx, row);

        // Number
        ImGui::TableNextColumn();
        if (idx < itemNumbers.length() && !itemNumbers[idx].isEmpty())
            ImGui::Text(itemNumbers[idx]);
        else
            ImGui::TextDisabled("-");

        // Level
        ImGui::TableNextColumn();
        if (idx < itemLevelNames.length() && !itemLevelNames[idx].isEmpty())
            ImGui::Text(itemLevelNames[idx]);
        else
            ImGui::TextDisabled("-");

        // Area
        ImGui::TableNextColumn();
        if (idx < itemAreas.length() && itemAreas[idx] > 0)
            ImGui::Text(CardFormatInt(int(itemAreas[idx])));
        else
            ImGui::TextDisabled("-");

        // Volume
        ImGui::TableNextColumn();
        if (idx < itemVolumes.length() && itemVolumes[idx] > 0)
            ImGui::Text(CardFormatInt(int(itemVolumes[idx])));
        else
            ImGui::TextDisabled("-");

        // Elements
        ImGui::TableNextColumn();
        ImGui::Text(CardFormatInt(int(items[idx].value)));
    }

    int CompareItems(uint a, uint b, int column, bool ascending) override
    {
        int result = 0;
        if (column == 1) // Name
        {
            if (items[a].label < items[b].label) result = -1;
            else if (items[a].label > items[b].label) result = 1;
        }
        else if (column == 2) // Number
        {
            string na = (a < itemNumbers.length()) ? itemNumbers[a] : "";
            string nb = (b < itemNumbers.length()) ? itemNumbers[b] : "";
            if (na < nb) result = -1;
            else if (na > nb) result = 1;
        }
        else if (column == 3) // Level
        {
            string la = (a < itemLevelNames.length()) ? itemLevelNames[a] : "";
            string lb = (b < itemLevelNames.length()) ? itemLevelNames[b] : "";
            if (la < lb) result = -1;
            else if (la > lb) result = 1;
        }
        else if (column == 4) // Area
        {
            float va = (a < itemAreas.length()) ? itemAreas[a] : 0;
            float vb = (b < itemAreas.length()) ? itemAreas[b] : 0;
            if (va < vb) result = -1;
            else if (va > vb) result = 1;
        }
        else if (column == 5) // Volume
        {
            float va = (a < itemVolumes.length()) ? itemVolumes[a] : 0;
            float vb = (b < itemVolumes.length()) ? itemVolumes[b] : 0;
            if (va < vb) result = -1;
            else if (va > vb) result = 1;
        }
        else if (column == 6) // Elements
        {
            if (items[a].value < items[b].value) result = -1;
            else if (items[a].value > items[b].value) result = 1;
        }

        return ascending ? result : -result;
    }

    void OnClearData() override
    {
        itemNumbers.resize(0);
        itemLevelNames.resize(0);
        itemAreas.resize(0);
        itemVolumes.resize(0);
    }
}

funcdef void RoomChartNotifyCallback();

class DemoRoomTableView : Window
{
    private App@ _app;
    private AppScene@ _appScene;

    DemoRoomTableCard@ card;

    RoomChartNotifyCallback@ onClearOtherSelections = null;
    RoomChartNotifyCallback@ onClearOtherColors = null;

    private DemoDataService@ _dataService;
    private DemoMaterialService@ _matService;
    private bool _dataLoaded = false;

    private uint _roomSeed = 3;

    private Scene::EventToken@ _dataChangedToken = null;
    private bool _destroyed = false;

    DemoRoomTableView(App@ app, DemoDataService@ dataService)
    {
        super("Rooms", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_dataService = dataService;

        @card = DemoRoomTableCard();
        card.title = "Rooms";
        card.fillHeight = true;
        @card.onItemClicked = CardItemClickCallback(OnRoomClicked);
        @card.onColorClicked = CardColorCallback(OnRoomColorClicked);
        @card.onShuffleClicked = CardShuffleCallback(OnRoomShuffleClicked);

        VimFlex::Console::Log("DemoRoomTableView Created");
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

        for (uint i = 0; i < _dataService.roomStats.length(); i++)
        {
            color col = GetDemoColorForLabel(_dataService.roomStats[i].name, i, _roomSeed);
            card.items.insertLast(CardItem(
                _dataService.roomStats[i].name,
                float(_dataService.roomStats[i].count),
                col));
            card.itemNumbers.insertLast(_dataService.roomStats[i].number);
            card.itemLevelNames.insertLast(_dataService.roomStats[i].levelName);
            card.itemAreas.insertLast(_dataService.roomStats[i].area);
            card.itemVolumes.insertLast(_dataService.roomStats[i].volume);
        }

        _dataLoaded = true;
    }

    bool Render(const IRenderContext& ctx) override
    {
        if (!_dataLoaded && _dataService !is null && _dataService.IsDataLoaded())
            UpdateCardItems();

        card.Render();
        return true;
    }

    // --- Callbacks ---

    private void OnRoomClicked(int index, const string&in label)
    {
        if (!card.lastClickWasAdditive)
        {
            if (onClearOtherSelections !is null)
                onClearOtherSelections();
        }

        if (card.lastClickWasAdditive)
        {
            // Build a merged set from all selected items (including room geometry for visibility)
            Scene::SceneItemSet merged;
            auto@ keys = card.selectedItems.getKeys();
            for (uint k = 0; k < keys.length(); k++)
            {
                uint idx = parseInt(keys[k]);
                if (idx < card.items.length())
                {
                    Scene::SceneItemSet@ roomSet = _dataService.GetItemSetForRoom(card.items[idx].label);
                    if (roomSet !is null)
                        merged.Add(roomSet);
                }
            }
            if (merged.Count() > 0)
            {
                _appScene.GetSelectionService().Apply(merged);
                VimFlex::Console::Log("Selected " + merged.Count() + " elements from " + keys.length() + " rooms");
            }
        }
        else
        {
            Scene::SceneItemSet@ itemSet = _dataService.GetItemSetForRoom(label);
            if (itemSet is null || itemSet.Count() == 0) return;

            _appScene.GetSelectionService().Apply(itemSet);
            VimFlex::Console::Log("Selected " + itemSet.Count() + " elements: " + label);
        }

    }

    private void OnRoomColorClicked()
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

        array<RoomStats>@ allStats = _dataService.GetAllRoomStats();
        if (allStats is null) return;

        for (uint i = 0; i < allStats.length(); i++)
        {
            Scene::SceneItemSet@ physItems = _dataService.GetPhysicalItemSetForRoom(allStats[i].name);
            if (physItems !is null && physItems.Count() > 0)
                _matService.ApplyColor(physItems, GetDemoColorForLabel(allStats[i].name, i, _roomSeed));
        }

        card.colorsApplied = true;
        VimFlex::Console::Log("Applied room colors to " + allStats.length() + " rooms");
    }

    private void OnRoomShuffleClicked()
    {
        _roomSeed = (_roomSeed + 3) % DEMO_PALETTE.length();
        for (uint i = 0; i < card.items.length(); i++)
            card.items[i].itemColor = GetDemoColorForLabel(card.items[i].label, i, _roomSeed);

        if (card.colorsApplied)
        {
            card.colorsApplied = false;
            OnRoomColorClicked();
        }
    }
}
