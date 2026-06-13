// ChatQCPlugin.as — Enregistrement du workflow "ChatQC".
//
// Monte le chatbox (ChatQCView, a gauche) et le panneau de resultats
// (QCResultsView, a droite), puis enregistre les 4 outils MCP qui forment le
// contrat d'integration avec Claude (qc-orchestrator).

#include "QCMcpTools.as"
#include "QCChecklistView.as"
#include "../Main.as"
#include "../BuiltinPlugins.as"

namespace ChatQCPlugin
{
    ChatQCView@      g_chat;
    QCResultsView@   g_results;
    QCChecklistView@ g_checklist;

    Scene::EventToken@ gInitToken = VimFlex::OnPluginInit()
        .Subscribe(Scene::Event::EventCallback(HandlePluginInit));

    Scene::EventToken@ gShutdownToken = VimFlex::OnPluginShutdown()
        .Subscribe(Scene::Event::EventCallback(HandlePluginShutdown));

    void HandlePluginInit()
    {
        @g_chat      = ChatQCView(g_app);
        @g_results   = QCResultsView(g_app);
        @g_checklist = QCChecklistView(g_app);

        g_app.views.AddDockableWindow(g_chat);
        g_app.views.AddDockableWindow(g_results);
        g_app.views.AddDockableWindow(g_checklist);

        QCMcpTools::Register(g_chat, g_results);

        g_app.AddWorkflow(
            "ChatQC",
            false,
            BuiltinPlugins::GetBuiltInViews(),
            {
                g_chat,
                g_results,
                g_checklist,
                BuiltinPlugins::parameterView
            },
            false
        );

        VimFlex::Console::Log("ChatQC: Plugin initialise — chatbox + QC Checklist + 4 outils MCP actifs");
    }

    void HandlePluginShutdown()
    {
        QCMcpTools::ClearHandles();

        if (gInitToken !is null)     { gInitToken.Unsubscribe();     @gInitToken     = null; }
        if (gShutdownToken !is null) { gShutdownToken.Unsubscribe(); @gShutdownToken = null; }
        if (g_chat !is null)         { g_chat.Destroy();             @g_chat         = null; }
        if (g_results !is null)      { g_results.Destroy();          @g_results      = null; }
        if (g_checklist !is null)    { g_checklist.Destroy();        @g_checklist    = null; }

        VimFlex::Console::Log("ChatQC: Plugin arrete");
    }
}
