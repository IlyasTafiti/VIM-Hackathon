// PGBAuditMcpTools.as

#include "PGBAuditView.as"
#include "../core/App.as"

funcdef void PGBTwoStringsCallback(const string&in a, const string&in b);

namespace PGBAuditMcpTools
{
    PGBAuditView@ _view = null;

    void Register(PGBAuditView@ view)
    {
        @_view = view;
        auto@ mcp = VimFlex::GetMcpService();

        mcp.RegisterScriptTool(
            "pgb_run_audit",
            "Relance l'audit de conformite PGB sur le modele charge. "
            "Recalcule toutes les regles et met a jour le panneau PGB Audit.",
            {}, {}, {},
            McpToolVoidCallback(HandleRun)
        );

        mcp.RegisterScriptTool(
            "pgb_annotate_rule",
            "Ajoute un commentaire IA sous une regle PGB dans le panneau Audit. "
            "ruleId valides : 'no_level', 'warnings', 'rooms_no_area', 'generic_names', 'no_workset'.",
            {"string",  "string"},
            {"ruleId",  "annotation"},
            {"ID de la regle", "Texte du commentaire IA"},
            PGBTwoStringsCallback(HandleAnnotate)
        );

        VimFlex::Console::Log("PGBAuditMcpTools: pgb_run_audit + pgb_annotate_rule enregistres");
    }

    void HandleRun()
    {
        if (_view is null) return;
        _view.ReloadAudit();
    }

    void HandleAnnotate(const string&in ruleId, const string&in annotation)
    {
        if (_view is null) return;
        _view.SetRuleAnnotation(ruleId, annotation);
    }

    void ClearHandles() { @_view = null; }
}
