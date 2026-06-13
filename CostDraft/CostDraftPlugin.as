// CostDraftPlugin.as - Plugin registration for Cost Draft
//
// Registers a "Cost Draft" workflow with the Cost Breakdown tree (left, replaces
// the built-in element tree) and the editable Costs panel (right).

#include "CostDraftView.as"
#include "CostBreakdownView.as"
#include "CostDraftMcpTools.as"
#include "../Main.as"
#include "../BuiltinPlugins.as"

namespace CostDraftPlugin
{
    CostDraftView@ costDraftView;
    CostBreakdownView@ costBreakdownView;

    Scene::EventToken@ gHandlePluginInit = VimFlex::OnPluginInit().Subscribe(
        Scene::Event::EventCallback(HandlePluginInit));

    Scene::EventToken@ gHandlePluginShutdown = VimFlex::OnPluginShutdown().Subscribe(
        Scene::Event::EventCallback(HandlePluginShutdown));

    void HandlePluginInit()
    {
        VimFlex::Console::Log("CostDraftPlugin: Initializing...");

        @costBreakdownView = CostBreakdownView(g_app);
        g_app.views.AddDockableWindow(costBreakdownView);

        @costDraftView = CostDraftView(g_app);
        costDraftView.SetBreakdownView(costBreakdownView);
        g_app.views.AddDockableWindow(costDraftView);

        auto@ builtInViews = BuiltinPlugins::GetBuiltInViews();
        g_app.AddWorkflow(
            "Cost Draft",
            false,
            builtInViews,
            {
                BuiltinPlugins::parameterView,
                costBreakdownView,
                costDraftView
            },
            false,
            "VIM Hackathon"
        );

        CostDraftMcpTools::Register(costDraftView, costBreakdownView);

        VimFlex::Console::Log("CostDraftPlugin: Initialization complete");
    }

    void HandlePluginShutdown()
    {
        VimFlex::Console::Log("CostDraftPlugin: Shutting down...");

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

        CostDraftMcpTools::ClearViewHandles();

        if (costDraftView !is null)
        {
            costDraftView.Destroy();
            @costDraftView = null;
        }

        if (costBreakdownView !is null)
        {
            costBreakdownView.Destroy();
            @costBreakdownView = null;
        }

        VimFlex::Console::Log("CostDraftPlugin: Shutdown complete");
    }
}
