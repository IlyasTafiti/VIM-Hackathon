// CostDraftMcpTools.as - MCP tool surface for agent-driven cost editing.
//
// Exposes two tools:
//
//   cost_draft_recalculate
//     No args. Reads the live CostInfoRows DuckDB table back into the
//     plugin's in-memory _rows array and re-runs the standard recalc, so
//     agent edits made via vim_query (INSERT/UPDATE/DELETE against
//     CostInfoRows) show up in the Cost Breakdown tree and 3D viewport
//     without any file round-trip.
//
//   cost_draft_set_color_thresholds
//     Three doubles — lowValue / midValue / highValue. Pushes them into
//     the Cost Breakdown view's threshold state (the three inputs with the
//     colored swatches), updates the TreeTable gradient stops, and marks
//     the 3D overlay dirty so the next frame re-applies. Per-stop colors
//     are left unchanged (edit them via the in-app color pickers or a
//     future extension to this tool).
//
// Registered at plugin init; removed wholesale by App.Destroy via
// VimFlex::GetMcpService().UnregisterAllScriptTools().

#include "CostDraftView.as"
#include "CostBreakdownView.as"
#include "../core/App.as"

// Funcdef for tool callbacks with three double arguments. Matches the
// McpTool*Callback funcdefs declared in App.as; the C++ dispatcher calls
// SetArgDouble for each arg and then Execute() on the AS context.
funcdef void McpToolThreeDoubleCallback(double a, double b, double c);

namespace CostDraftMcpTools
{
    // Held across the plugin lifetime so the registered callbacks can
    // reach the live views. Nulled on plugin shutdown; the callbacks
    // become a warn-and-noop.
    CostDraftView@ _view = null;
    CostBreakdownView@ _breakdown = null;

    void Register(CostDraftView@ view, CostBreakdownView@ breakdown)
    {
        @_view = view;
        @_breakdown = breakdown;

        auto@ mcp = VimFlex::GetMcpService();

        mcp.RegisterScriptTool(
            "cost_draft_recalculate",
            "Absorb changes made via SQL to the CostInfoRows table into the "
                "Cost Draft plugin's in-memory cost rows and re-run the cost "
                "calculation. Call this after modifying CostInfoRows (via "
                "vim_query UPDATE/INSERT/DELETE) so the changes are reflected "
                "in the Cost Breakdown tree and the 3D viewport coloring. "
                "CostInfoRows schema: Category VARCHAR, Family VARCHAR, "
                "FamilyType VARCHAR, CostPerUnit DOUBLE, CostUnit VARCHAR "
                "('Count' | 'InstanceParameter' | 'TypeParameter'), "
                "CostUnitParameterName VARCHAR.",
            {}, {}, {},
            McpToolVoidCallback(HandleRecalculate)
        );

        mcp.RegisterScriptTool(
            "cost_draft_set_color_thresholds",
            "Set the Low / Mid / High cost thresholds used for the Cost "
                "Breakdown tree background gradient and the 3D element "
                "coloring. Values are in the same currency units as "
                "CostData.Cost (typically dollars). Per-stop colors are "
                "preserved. The TreeTable gradient updates immediately; "
                "the 3D overlay re-applies on the next render frame.",
            {"double",                     "double",                     "double"},
            {"lowValue",                   "midValue",                   "highValue"},
            {"Low cost threshold (green)", "Mid cost threshold (amber)", "High cost threshold (red)"},
            McpToolThreeDoubleCallback(HandleSetColorThresholds)
        );

        VimFlex::Console::Log(
            "CostDraftMcpTools: registered cost_draft_recalculate + "
            "cost_draft_set_color_thresholds");
    }

    // Tool invocations run on the main update loop (ProcessPendingScriptToolCalls
    // is pumped from App.Render), so it's safe to touch plugin state directly.

    void HandleRecalculate()
    {
        if (_view is null)
        {
            VimFlex::Console::Warn(
                "cost_draft_recalculate: CostDraft view is unavailable");
            return;
        }
        _view.AbsorbCostInfoRowsAndRecalculate();
    }

    void HandleSetColorThresholds(double low, double mid, double high)
    {
        if (_breakdown is null)
        {
            VimFlex::Console::Warn(
                "cost_draft_set_color_thresholds: Cost Breakdown view "
                "is unavailable");
            return;
        }
        _breakdown.SetColorStopValues(low, mid, high);
        VimFlex::Console::Log(
            "CostDraftMcp: thresholds set low=" + low
            + " mid=" + mid + " high=" + high);
    }

    // Called from plugin shutdown so the callbacks stop dispatching if
    // the MCP service hangs on to a stale registration between
    // recompiles.
    void ClearViewHandles()
    {
        @_view = null;
        @_breakdown = null;
    }
}
