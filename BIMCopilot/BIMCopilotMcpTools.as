// BIMCopilotMcpTools.as

#include "BIMCopilotView.as"
#include "../core/App.as"

funcdef void CopilotStringCallback(const string&in s);

class CopilotCheckRow { int n; }
class CopilotIdxRow   { uint32 elementIndex; }

namespace BIMCopilotMcpTools
{
    BIMCopilotView@ _view     = null;
    AppScene@       _appScene = null;

    void Register(BIMCopilotView@ view, AppScene@ appScene)
    {
        @_view     = view;
        @_appScene = appScene;

        auto@ mcp = VimFlex::GetMcpService();

        mcp.RegisterScriptTool(
            "copilot_set_response",
            "Affiche une reponse IA dans le panneau BIM Copilot de VIM Flex. "
            "Appelez apres avoir analyse le modele pour presenter vos conclusions. "
            "Utilisez des sauts de ligne \\n pour structurer le texte.",
            {"string"}, {"response"}, {"Texte de la reponse IA"},
            CopilotStringCallback(HandleResponse)
        );

        mcp.RegisterScriptTool(
            "copilot_set_status",
            "Met a jour la ligne de statut du panneau BIM Copilot.",
            {"string"}, {"status"}, {"Courte ligne de statut"},
            CopilotStringCallback(HandleStatus)
        );

        mcp.RegisterScriptTool(
            "copilot_select_rule",
            "Selectionne et cadre en 3D les elements en violation d'une regle PGB. "
            "ruleId valides : 'no_level', 'warnings', 'rooms_no_area', 'generic_names', 'no_workset'. "
            "Requiert que l'audit PGB ait ete lance au prealable (workflow PGB Audit).",
            {"string"}, {"ruleId"}, {"ID de la regle PGB"},
            CopilotStringCallback(HandleSelectRule)
        );

        mcp.RegisterScriptTool(
            "copilot_show_all",
            "Annule l'isolation 3D et affiche tous les elements du modele.",
            {}, {}, {},
            McpToolVoidCallback(HandleShowAll)
        );

        VimFlex::Console::Log("BIMCopilotMcpTools: 4 outils enregistres");
    }

    void HandleResponse(const string&in text)
    {
        if (_view is null) return;
        _view.SetResponse(text);
    }

    void HandleStatus(const string&in text)
    {
        if (_view is null) return;
        _view.SetStatus(text);
    }

    void HandleSelectRule(const string&in ruleId)
    {
        if (_appScene is null) return;
        auto@ w = _appScene.GetVimData();
        if (w is null) return;
        auto@ d = w.GetData();
        if (d is null) return;

        string tbl = "PGBAudit_" + ruleId;
        array<CopilotIdxRow> rows;
        rows.DeserializeFromQuery(d, "SELECT elementIndex FROM " + tbl + " LIMIT 50000");

        if (rows.length() == 0)
        {
            if (_view !is null) _view.SetStatus("Aucune violation pour : " + ruleId);
            return;
        }

        Scene::SceneItemSet@ s = Scene::SceneItemSet();
        for (uint i = 0; i < rows.length(); i++) s.Add(rows[i].elementIndex);
        _appScene.GetSelectionService().Apply(s);
        _appScene.GetInteractionService().IsolateSelection();
        _appScene.GetInteractionService().FrameSelection();

        if (_view !is null) _view.SetStatus("" + rows.length() + " elements selectionnes");
    }

    void HandleShowAll()
    {
        if (_appScene is null) return;
        _appScene.GetInteractionService().ShowAll();
        if (_view !is null) _view.SetStatus("Vue complete restauree");
    }

    void ClearHandles() { @_view = null; @_appScene = null; }
}
