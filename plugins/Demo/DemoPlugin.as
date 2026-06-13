// DemoPlugin.as - Plugin registration for Demo Dashboard
//
// Registers the Demo Dashboard workflow with donut charts, level table,
// and room table showing Physical-Visible element distribution.
//
// HOW TO USE:
// 1. Load a VIM file
// 2. Switch to the "Demo Dashboard" workflow (under VIM Hackathon)
// 3. Click chart segments or table rows to select elements in the 3D viewport

#include "DemoView.as"
#include "DemoSummaryView.as"
#include "DemoLevelHistogramView.as"
#include "DemoRoomTableView.as"
#include "DemoCategoryTableView.as"
#include "DemoMaterialTableView.as"
#include "DemoMaterialService.as"
#include "DemoTagsView.as"
#include "../Main.as"
#include "../BuiltinPlugins.as"

namespace DemoPlugin
{
    DemoView@ demoView;
    DemoSummaryView@ summaryView;
    DemoLevelHistogramView@ levelTableView;
    DemoRoomTableView@ roomTableView;
    DemoCategoryTableView@ categoryTableView;
    DemoMaterialTableView@ materialTableView;
    DemoMaterialService@ matService;
    ElementTaggerView@ taggerView;

    Scene::EventToken@ gHandlePluginInit = VimFlex::OnPluginInit().Subscribe(
        Scene::Event::EventCallback(HandlePluginInit));

    Scene::EventToken@ gHandlePluginShutdown = VimFlex::OnPluginShutdown().Subscribe(
        Scene::Event::EventCallback(HandlePluginShutdown));

    void HandlePluginInit()
    {
        VimFlex::Console::Log("DemoPlugin: Initializing...");

        // Create shared material service (lifecycle bound to workflow)
        @matService = DemoMaterialService();
        matService.Init(g_app.GetAppScene());

        @demoView = DemoView(g_app);
        @summaryView = DemoSummaryView(g_app, demoView.dataService, demoView);
        @levelTableView = DemoLevelHistogramView(g_app, demoView.dataService);
        @roomTableView = DemoRoomTableView(g_app, demoView.dataService);
        @categoryTableView = DemoCategoryTableView(g_app, demoView.dataService);
        @materialTableView = DemoMaterialTableView(g_app, demoView.dataService);

        // Wire material service to data service and all views
        demoView.dataService.SetMaterialService(matService);
        demoView.SetMaterialService(matService);
        levelTableView.SetMaterialService(matService);
        roomTableView.SetMaterialService(matService);
        categoryTableView.SetMaterialService(matService);
        materialTableView.SetMaterialService(matService);

        // Wire cross-chart coordination
        demoView.SetLevelCard(levelTableView.card);
        demoView.SetRoomCard(roomTableView.card);
        demoView.SetCategoryCard(categoryTableView.card);
        demoView.SetMaterialCard(materialTableView.card);
        @levelTableView.onClearOtherSelections = LevelChartNotifyCallback(OnClearFromLevel);
        @levelTableView.onClearOtherColors = LevelChartNotifyCallback(OnClearColorsFromLevel);
        @roomTableView.onClearOtherSelections = RoomChartNotifyCallback(OnClearFromRoom);
        @roomTableView.onClearOtherColors = RoomChartNotifyCallback(OnClearColorsFromRoom);
        @categoryTableView.onClearOtherSelections = CategoryChartNotifyCallback(OnClearFromCategory);
        @categoryTableView.onClearOtherColors = CategoryChartNotifyCallback(OnClearColorsFromCategory);
        @materialTableView.onClearOtherSelections = MaterialChartNotifyCallback(OnClearFromMaterial);
        @materialTableView.onClearOtherColors = MaterialChartNotifyCallback(OnClearColorsFromMaterial);

        @taggerView = ElementTaggerView(g_app);

        g_app.views.AddDockableWindow(demoView);
        g_app.views.AddDockableWindow(summaryView);
        g_app.views.AddDockableWindow(levelTableView);
        g_app.views.AddDockableWindow(roomTableView);
        g_app.views.AddDockableWindow(categoryTableView);
        g_app.views.AddDockableWindow(materialTableView);
        g_app.views.AddDockableWindow(taggerView);

        auto@ builtInViews = BuiltinPlugins::GetBuiltInViews();

        g_app.AddWorkflow(
            "Demo Dashboard",
            false,
            builtInViews,
            {
                demoView,
                summaryView,
                BuiltinPlugins::elementTreeView,
                BuiltinPlugins::parameterView,
                categoryTableView,
                materialTableView,
                roomTableView,
                levelTableView,
                taggerView
            },
            false,
            "VIM Hackathon"
        );

        VimFlex::Console::Log("DemoPlugin: Ready");
    }

    void HandlePluginShutdown()
    {
        VimFlex::Console::Log("DemoPlugin: Shutting down...");

        if (gHandlePluginInit !is null)
        {
            gHandlePluginInit.Unsubscribe();
            @gHandlePluginInit = null;
        }

        if (gHandlePluginShutdown !is null)
        {
            gHandlePluginShutdown.Unsubscribe();
            @gHandlePluginShutdown = null;
        }

        if (demoView !is null)
        {
            demoView.Destroy();
            @demoView = null;
        }

        if (summaryView !is null)
        {
            summaryView.Destroy();
            @summaryView = null;
        }

        if (levelTableView !is null)
        {
            levelTableView.Destroy();
            @levelTableView = null;
        }

        if (roomTableView !is null)
        {
            roomTableView.Destroy();
            @roomTableView = null;
        }

        if (categoryTableView !is null)
        {
            categoryTableView.Destroy();
            @categoryTableView = null;
        }

        if (materialTableView !is null)
        {
            materialTableView.Destroy();
            @materialTableView = null;
        }

        if (taggerView !is null)
        {
            taggerView.Destroy();
            @taggerView = null;
        }

        if (matService !is null)
        {
            matService.Destroy();
            @matService = null;
        }

        VimFlex::Console::Log("DemoPlugin: Done");
    }

    // Helper to clear selection on a table card
    void ClearCardSelection(DemoTableCard@ card)
    {
        if (card is null) return;
        card.selectedIndex = -1;
        card.selectedItems.deleteAll();
    }

    void OnClearFromLevel()
    {
        if (demoView !is null)
            demoView.ClearChartSelections();
        if (roomTableView !is null) ClearCardSelection(roomTableView.card);
        if (categoryTableView !is null) ClearCardSelection(categoryTableView.card);
        if (materialTableView !is null) ClearCardSelection(materialTableView.card);
    }

    void OnClearColorsFromLevel()
    {
        if (demoView !is null)
            demoView.ClearChartColors();
        if (roomTableView !is null && roomTableView.card !is null)
            roomTableView.card.colorsApplied = false;
        if (categoryTableView !is null && categoryTableView.card !is null)
            categoryTableView.card.colorsApplied = false;
    }

    void OnClearFromRoom()
    {
        if (demoView !is null)
            demoView.ClearChartSelections();
        if (levelTableView !is null) ClearCardSelection(levelTableView.card);
        if (categoryTableView !is null) ClearCardSelection(categoryTableView.card);
        if (materialTableView !is null) ClearCardSelection(materialTableView.card);
    }

    void OnClearColorsFromRoom()
    {
        if (demoView !is null)
            demoView.ClearChartColors();
        if (levelTableView !is null && levelTableView.card !is null)
            levelTableView.card.colorsApplied = false;
        if (categoryTableView !is null && categoryTableView.card !is null)
            categoryTableView.card.colorsApplied = false;
    }

    void OnClearFromCategory()
    {
        if (demoView !is null)
            demoView.ClearChartSelections();
        if (levelTableView !is null) ClearCardSelection(levelTableView.card);
        if (roomTableView !is null) ClearCardSelection(roomTableView.card);
        if (materialTableView !is null) ClearCardSelection(materialTableView.card);
    }

    void OnClearColorsFromCategory()
    {
        if (demoView !is null)
            demoView.ClearChartColors();
        if (levelTableView !is null && levelTableView.card !is null)
            levelTableView.card.colorsApplied = false;
        if (roomTableView !is null && roomTableView.card !is null)
            roomTableView.card.colorsApplied = false;
    }

    void OnClearFromMaterial()
    {
        if (demoView !is null)
            demoView.ClearChartSelections();
        if (levelTableView !is null) ClearCardSelection(levelTableView.card);
        if (roomTableView !is null) ClearCardSelection(roomTableView.card);
        if (categoryTableView !is null) ClearCardSelection(categoryTableView.card);
    }

    void OnClearColorsFromMaterial()
    {
        if (demoView !is null)
            demoView.ClearChartColors();
        if (levelTableView !is null && levelTableView.card !is null)
            levelTableView.card.colorsApplied = false;
        if (roomTableView !is null && roomTableView.card !is null)
            roomTableView.card.colorsApplied = false;
        if (categoryTableView !is null && categoryTableView.card !is null)
            categoryTableView.card.colorsApplied = false;
    }
}
