// BIMCopilotPlugin.as — Enregistrement du workflow "BIM Copilot"
//
// Workflow dédié avec le panneau Copilot à gauche + vues standard.
// Les outils MCP (copilot_set_response, copilot_set_status,
// copilot_select_rule, copilot_show_all) sont enregistrés à l'init.

#include "BIMCopilotMcpTools.as"
#include "../Main.as"
#include "../BuiltinPlugins.as"

namespace BIMCopilotPlugin
{
    BIMCopilotView@ g_view;

    Scene::EventToken@ gInitToken = VimFlex::OnPluginInit()
        .Subscribe(Scene::Event::EventCallback(HandlePluginInit));

    Scene::EventToken@ gShutdownToken = VimFlex::OnPluginShutdown()
        .Subscribe(Scene::Event::EventCallback(HandlePluginShutdown));

    void HandlePluginInit()
    {
        @g_view = BIMCopilotView(g_app);
        g_app.views.AddDockableWindow(g_view);

        BIMCopilotMcpTools::Register(g_view, g_app.GetAppScene());

        g_app.AddWorkflow(
            "BIM Copilot",
            false,
            BuiltinPlugins::GetBuiltInViews(),
            {
                g_view,
                BuiltinPlugins::elementTreeView,
                BuiltinPlugins::parameterView
            },
            false
        );

        VimFlex::Console::Log("BIMCopilot: Plugin initialise — 4 outils MCP actifs");
    }

    void HandlePluginShutdown()
    {
        BIMCopilotMcpTools::ClearHandles();

        if (gInitToken !is null)     { gInitToken.Unsubscribe();     @gInitToken     = null; }
        if (gShutdownToken !is null) { gShutdownToken.Unsubscribe(); @gShutdownToken = null; }
        if (g_view !is null)         { g_view.Destroy();             @g_view         = null; }

        VimFlex::Console::Log("BIMCopilot: Plugin arrete");
    }
}
