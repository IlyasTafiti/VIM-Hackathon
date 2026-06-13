// QCMcpTools.as — Contrat d'integration entre le plugin ChatQC (VIM) et Claude.
//
// Outils MCP exposes :
//   qc_set_chat_response(text)                 — affiche une reponse dans le chatbox
//   qc_add_result(module, status, detail, rule)— poste le resultat d'un module QC
//   qc_select_violations(ruleId)               — selectionne/isole les violations en 3D
//   qc_clear_results()                         — vide les resultats QC

#include "ChatQCView.as"
#include "QCResultsView.as"
#include "../core/App.as"

funcdef void QCStringCallback(const string&in s);
funcdef void QCAddResultCallback(const string&in module, const string&in status,
                                 const string&in detail, const string&in ruleId);

namespace QCMcpTools
{
    ChatQCView@    _chat    = null;
    QCResultsView@ _results = null;

    void Register(ChatQCView@ chat, QCResultsView@ results)
    {
        @_chat    = chat;
        @_results = results;

        auto@ mcp = VimFlex::GetMcpService();

        mcp.RegisterScriptTool(
            "qc_set_chat_response",
            "Affiche une reponse dans le chatbox ChatQC de VIM Flex. "
            "Appelez apres avoir analyse le modele pour repondre a la question de "
            "l'utilisateur. Utilisez des sauts de ligne \\n pour structurer le texte.",
            {"string"}, {"text"}, {"Texte de la reponse a afficher"},
            QCStringCallback(HandleChatResponse)
        );

        mcp.RegisterScriptTool(
            "qc_add_result",
            "Poste le resultat d'un module de controle qualite dans le panneau QC Results. "
            "module : 'georef' | 'params' | 'structure' | 'loin'. "
            "status : 'pass' | 'warn' | 'fail'. "
            "detail : commentaire court explique a l'utilisateur. "
            "ruleId : optionnel ('' si aucun) — lie le module a une requete de "
            "violations pour la selection 3D. ruleId connus : 'structure_no_level', "
            "'structure_no_workset', 'params_generic_type', 'loin_unnamed_type', "
            "'loin_rooms_no_area'.",
            {"string",  "string",  "string",  "string"},
            {"module",  "status",  "detail",  "ruleId"},
            {"Module QC", "Statut", "Commentaire", "ID de regle (ou vide)"},
            QCAddResultCallback(HandleAddResult)
        );

        mcp.RegisterScriptTool(
            "qc_select_violations",
            "Selectionne et isole en 3D les elements en violation d'une regle. "
            "ruleId connus : 'structure_no_level', 'structure_no_workset', "
            "'params_generic_type', 'loin_unnamed_type', 'loin_rooms_no_area'.",
            {"string"}, {"ruleId"}, {"ID de la regle de violation"},
            QCStringCallback(HandleSelectViolations)
        );

        mcp.RegisterScriptTool(
            "qc_clear_results",
            "Vide tous les resultats QC du panneau QC Results (remet les modules a 'non audite').",
            {}, {}, {},
            McpToolVoidCallback(HandleClear)
        );

        VimFlex::Console::Log("QCMcpTools: 4 outils enregistres");
    }

    void HandleChatResponse(const string&in text)
    {
        if (_chat is null) return;
        _chat.AppendAssistant(text);
    }

    void HandleAddResult(const string&in module, const string&in status,
                         const string&in detail, const string&in ruleId)
    {
        if (_results is null) return;
        _results.AddResult(module, status, detail, ruleId);
        if (_chat !is null)
            _chat.SetStatus("Module '" + module + "' : " + status);
    }

    void HandleSelectViolations(const string&in ruleId)
    {
        if (_results is null) return;
        int n = _results.SelectViolations(ruleId);
        if (_chat !is null)
        {
            if (n > 0) _chat.SetStatus("" + n + " elements en violation selectionnes (" + ruleId + ")");
            else       _chat.SetStatus("Aucune violation pour : " + ruleId);
        }
    }

    void HandleClear()
    {
        if (_results !is null) _results.ClearResults();
        if (_chat !is null) _chat.SetStatus("Resultats QC effaces.");
    }

    void ClearHandles() { @_chat = null; @_results = null; }
}
