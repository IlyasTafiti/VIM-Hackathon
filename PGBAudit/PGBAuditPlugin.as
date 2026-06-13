// PGBAuditPlugin.as — Workflow "PGB Audit" avec outils MCP
//
// Outils MCP exposés :
//   pgb_run_audit      — relance l'audit complet
//   pgb_annotate_rule  — injecte un commentaire IA sur une règle

#include "PGBAuditMcpTools.as"
#include "../Main.as"
#include "../BuiltinPlugins.as"

namespace PGBAuditPlugin
{
    PGBAuditView@ g_view;

    Scene::EventToken@ gInitToken = VimFlex::OnPluginInit()
        .Subscribe(Scene::Event::EventCallback(HandlePluginInit));

    Scene::EventToken@ gShutdownToken = VimFlex::OnPluginShutdown()
        .Subscribe(Scene::Event::EventCallback(HandlePluginShutdown));

    void HandlePluginInit()
    {
        @g_view = PGBAuditView(g_app);
        g_app.views.AddDockableWindow(g_view);

        PGBAuditMcpTools::Register(g_view);

        g_app.AddWorkflow(
            "PGB Audit",
            false,
            BuiltinPlugins::GetBuiltInViews(),
            {
                g_view,
                BuiltinPlugins::parameterView
            },
            false
        );

        VimFlex::Console::Log("PGBAudit: Plugin initialise — pgb_run_audit + pgb_annotate_rule actifs");
    }

    void HandlePluginShutdown()
    {
        PGBAuditMcpTools::ClearHandles();

        if (gInitToken !is null)     { gInitToken.Unsubscribe();     @gInitToken     = null; }
        if (gShutdownToken !is null) { gShutdownToken.Unsubscribe(); @gShutdownToken = null; }
        if (g_view !is null)         { g_view.Destroy();             @g_view         = null; }

        VimFlex::Console::Log("PGBAudit: Plugin arrete");
    }
}
