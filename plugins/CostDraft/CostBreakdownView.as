// CostBreakdownView.as - Cost breakdown tree for the Cost Draft workflow
//
// Docks into the left region and renders a Category > Family > Type tree of
// per-element costs sourced from the CostData temp table. CostDraftView
// calls RebuildFromCostData() after each recalculation.
//
// Also owns the Low / Mid / High color-threshold state — both numeric
// values and the per-stop colors. Defaults are pulled from CostDataSchema;
// users tweak the values in the footer; CostDraftView polls
// TakeThresholdsDirty() each frame and re-applies 3D colors on any edit.

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/CardUtils.as"
#include "../widgets/cards/ElementTreeCard.as"
#include "CostDataSchema.as"

class CostBreakdownView : Window
{
    private App@ _app;
    private AppScene@ _appScene;

    private CostBreakdownCard@ _tree;
    private bool _destroyed = false;

    // Threshold values and per-stop colors. Defaults come from
    // CostDataSchema; Load may overwrite via ApplySettings().
    private double _lowValue  = CostDataSchema::DEFAULT_LOW_VALUE;
    private double _midValue  = CostDataSchema::DEFAULT_MID_VALUE;
    private double _highValue = CostDataSchema::DEFAULT_HIGH_VALUE;
    private color  _lowColor  = CostDataSchema::DEFAULT_LOW_COLOR;
    private color  _midColor  = CostDataSchema::DEFAULT_MID_COLOR;
    private color  _highColor = CostDataSchema::DEFAULT_HIGH_COLOR;

    // Set whenever the user edits a threshold, changes a stop color, or
    // toggles the color overlay on/off. CostDraftView.Render polls
    // TakeThresholdsDirty() so the 3D overlay is re-applied (or cleared,
    // depending on the toggle) on change only.
    private bool _thresholdsDirty = false;

    // Owns the "paint 3D with the cost gradient" toggle. Default on.
    private bool _colorToggleOn = true;

    CostBreakdownView(App@ app)
    {
        super("Cost Breakdown", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionLeft);
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;

        if (_tree !is null)
        {
            _tree.Destroy();
            @_tree = null;
        }

        @_appScene = null;
        @_app = null;

        Window::Destroy();
    }

    bool Render(const IRenderContext& ctx) override
    {
        if (_tree is null)
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped(
                "Enter costs in the Cost Draft panel, then click Recalculate "
                "to see a Category / Family / Type breakdown here.");
            ImGui::PopStyleColor();
            return true;
        }

        _tree.Render();
        return true;
    }

    // Called by CostDraftView after CostData has been built.
    void RebuildFromCostData()
    {
        if (_destroyed || _appScene is null) return;

        if (_tree !is null)
        {
            _tree.Destroy();
            @_tree = null;
        }

        string tableName = "CostBreakdownTable";
        string tableQuery =
            "CREATE OR REPLACE TABLE " + tableName + " AS "
            "SELECT elementIndex, Category, Family, Type, Cost FROM CostData";

        array<string> filterColumns = { "Category", "Family", "Type" };
        array<string> hierarchyColumns = { "Category", "Family", "Type" };
        array<string> displayColumns = { "Cost" };
        array<TreeTableAggOp> aggOps = { TreeTableAggOp_Sum };

        @_tree = CostBreakdownCard(
            this,
            _appScene,
            tableName,
            tableQuery,
            filterColumns,
            hierarchyColumns,
            displayColumns,
            aggOps,
            {},     // aggKeyColumns
            {},     // hiddenColumns
            {},     // hiddenColumnAggOps
            true,   // respondToSelectionEvents
            true,   // sendSelectionEvents
            {}, {},
            "Cost Breakdown"
        );

        _tree.fillHeight = true;

        ApplyColorStopsToTree();
    }

    void ClearTree()
    {
        if (_destroyed) return;
        if (_tree !is null)
        {
            _tree.Destroy();
            @_tree = null;
        }
    }

    // --- Public API consumed by CostDraftView ---

    double GetLowValue()  const { return _lowValue;  }
    double GetMidValue()  const { return _midValue;  }
    double GetHighValue() const { return _highValue; }
    color  GetLowColor()  const { return _lowColor;  }
    color  GetMidColor()  const { return _midColor;  }
    color  GetHighColor() const { return _highColor; }
    bool   GetColorToggleOn() const { return _colorToggleOn; }

    // Pack the current state into a Settings record for Save.
    CostDataSchema::Settings GetSettings()
    {
        CostDataSchema::Settings s;
        s.lowValue  = _lowValue;
        s.midValue  = _midValue;
        s.highValue = _highValue;
        s.lowColor  = _lowColor;
        s.midColor  = _midColor;
        s.highColor = _highColor;
        return s;
    }

    // Replace the in-memory state with values from a loaded Settings record.
    // Marks dirty so 3D colors re-apply.
    void ApplySettings(CostDataSchema::Settings@ s)
    {
        _lowValue  = s.lowValue;
        _midValue  = s.midValue;
        _highValue = s.highValue;
        _lowColor  = s.lowColor;
        _midColor  = s.midColor;
        _highColor = s.highColor;
        _thresholdsDirty = true;
        ApplyColorStopsToTree();
    }

    // Used by the cost_draft_set_color_thresholds MCP tool. Updates the
    // numeric thresholds only; stop colors are left untouched.
    void SetColorStopValues(double low, double mid, double high)
    {
        _lowValue  = low;
        _midValue  = mid;
        _highValue = high;
        _thresholdsDirty = true;
        ApplyColorStopsToTree();
    }

    // Returns true once per change so the caller can re-apply downstream
    // colors without polling every frame.
    bool TakeThresholdsDirty()
    {
        bool d = _thresholdsDirty;
        _thresholdsDirty = false;
        return d;
    }

    // --- Rendering helpers used by CostBreakdownCard's footer ---

    void RenderColorThresholds()
    {
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_FrameBg, Style::GetColorBackground());
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_FrameBgHovered, Style::GetColorBackground());

        double newLow = _lowValue;
        double newMid = _midValue;
        double newHigh = _highValue;
        color newLowC = _lowColor;
        color newMidC = _midColor;
        color newHighC = _highColor;

        bool lowChanged  = RenderThresholdRow("Low",  "CBVLow",
            _lowColor,  _lowValue,
            CostDataSchema::DEFAULT_LOW_COLOR,  CostDataSchema::DEFAULT_LOW_VALUE,
            newLowC,  newLow);
        bool midChanged  = RenderThresholdRow("Mid",  "CBVMid",
            _midColor,  _midValue,
            CostDataSchema::DEFAULT_MID_COLOR,  CostDataSchema::DEFAULT_MID_VALUE,
            newMidC,  newMid);
        bool highChanged = RenderThresholdRow("High", "CBVHigh",
            _highColor, _highValue,
            CostDataSchema::DEFAULT_HIGH_COLOR, CostDataSchema::DEFAULT_HIGH_VALUE,
            newHighC, newHigh);

        ImGui::PopStyleColor(2);

        if (lowChanged || midChanged || highChanged)
        {
            _lowValue  = newLow;
            _midValue  = newMid;
            _highValue = newHigh;
            _lowColor  = newLowC;
            _midColor  = newMidC;
            _highColor = newHighC;
            _thresholdsDirty = true;
            ApplyColorStopsToTree();
        }
    }

    // Right-aligns the color-overlay toggle on the current line. Returns
    // true if the toggle changed, so the caller can also mark dirty.
    bool RenderColorToggleRightAligned()
    {
        string icon = Style::Icons::Color;
        float2 iconSize = Style::GetIconButtonSize(icon);
        float avail = ImGui::GetContentRegionAvail().x;
        if (avail > iconSize.x)
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() + avail - iconSize.x);

        string tooltip = _colorToggleOn ? "Clear 3D Colors" : "Apply 3D Colors";
        string iconId = icon + "##CBV_ColorToggle";
        bool clicked = VimFlex::IconButtonTransparentToggle(
            iconId, Style::GetColorText(), _colorToggleOn, true, float2(0, 0), tooltip);
        if (clicked)
        {
            _colorToggleOn = !_colorToggleOn;
            _thresholdsDirty = true;
        }
        return clicked;
    }

    // Renders one `[swatch] label [input] [eraser]` row. Writes any changes
    // into the out params; returns true if anything changed this frame.
    // Clicking the eraser resets both the color and the value to the
    // supplied defaults.
    private bool RenderThresholdRow(
        const string&in label, const string&in id,
        color currentColor, double currentValue,
        color defaultColor, double defaultValue,
        color&out newColor, double&out newValue)
    {
        const float labelColX = 34.0f;     // swatch ~24 + spacing
        const float inputColX = 80.0f;     // label ~40 + spacing

        // Default echoes so the caller doesn't see garbage.
        newColor = currentColor;
        newValue = currentValue;

        // 1) Color swatch — clickable, opens a picker popup.
        bool colorChanged = false;
        float4 curFloat = currentColor.toFloat4();
        string popupId = id + "_pick";

        if (ImGui::ColorButton(id + "_sw", curFloat, 0))
            ImGui::OpenPopup(popupId);

        if (ImGui::BeginPopup(popupId))
        {
            // RGB-only editing: pass alpha=1 in, force it back to 1 on the
            // way out so stored colors are always fully opaque.
            float4 pickIn = curFloat;
            pickIn.w = 1.0f;
            float4 pickOut = pickIn;
            if (ImGui::ColorPicker4("##" + id + "_pk", pickIn, pickOut,
                ImGuiColorEditFlags::ImGuiColorEditFlags_NoAlpha))
            {
                pickOut.w = 1.0f;
                newColor = color(pickOut);
                colorChanged = true;
            }
            ImGui::EndPopup();
        }

        // 2) Label in normal text color, offset past the swatch.
        ImGui::SameLine(labelColX);
        ImGui::AlignTextToFramePadding();
        ImGui::Text(label);

        // 3) Numeric input, leaving room for the eraser button on the right.
        float eraserW = Style::GetIconButtonSize(Style::Icons::Erase).x;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        ImGui::SameLine(inputColX);
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - eraserW - spacing);

        float valIn = float(currentValue);
        float valOut = valIn;
        bool valueChanged = ImGui::InputFloat("##" + id + "_v", valIn, valOut, 0.0f, 0.0f, "%.2f");
        if (valueChanged)
            newValue = double(valOut);

        // 4) Eraser — resets both the color and the value to defaults.
        // The label IS the ImGui ID, so we append a unique suffix per row
        // to keep all three erasers distinct.
        ImGui::SameLine();
        bool resetClicked = VimFlex::IconButtonTransparent(
            Style::Icons::Erase + "##" + id + "_erase",
            Style::GetColorText(), true, float2(0, 0),
            "Reset to default");
        if (resetClicked)
        {
            newColor = defaultColor;
            newValue = defaultValue;
        }

        return colorChanged || valueChanged || resetClicked;
    }

    // Tree color stops use the configured stop color but with a low fixed
    // alpha so the cell text stays legible over the band.
    private color TreeStopColor(color c)
    {
        return color(c.r, c.g, c.b, 60);
    }

    private void ApplyColorStopsToTree()
    {
        if (_tree is null) return;
        auto@ tt = _tree.GetTreeTable();
        if (tt is null) return;

        tt.SetDisplayColumnFormat(0, TreeTableFormat_Decimal);
        tt.SetDisplayColumnBold(0, true);
        tt.SetInitialSort(0, -1);

        tt.ClearDisplayColumnBgColor(0);
        tt.SetDisplayColumnBgColorMode(0, TreeTableColorMode_Interpolate);

        float lo = float(_lowValue);
        float mid = float(_midValue);
        float hi = float(_highValue);
        if (hi <= lo) hi = lo + 1.0f;
        if (mid <= lo || mid >= hi) mid = (lo + hi) * 0.5f;

        tt.SetDisplayColumnBgColorPoint(0, lo,  TreeStopColor(_lowColor));
        tt.SetDisplayColumnBgColorPoint(0, mid, TreeStopColor(_midColor));
        tt.SetDisplayColumnBgColorPoint(0, hi,  TreeStopColor(_highColor));
    }
}

// Subclass of ElementTreeCard that reserves a footer strip for the
// color-threshold inputs + the Select Costed / Select Uncosted buttons.
class CostBreakdownCard : ElementTreeCard
{
    private CostBreakdownView@ _view;
    private AppScene@ _appSceneRef;

    CostBreakdownCard(
        CostBreakdownView@ view,
        AppScene& scene,
        const string&in tableName,
        const string&in tableQuery,
        const array<string>&in filterColumns,
        const array<string>&in hierarchyColumns,
        const array<string>&in displayColumns,
        const array<TreeTableAggOp>&in aggOps,
        const array<string>&in aggKeyColumns,
        const array<string>&in hiddenColumns,
        const array<TreeTableAggOp>&in hiddenColumnAggOps,
        bool respondToSelectionEvents,
        bool sendSelectionEvents,
        const array<string>&in filterDefaultKeys,
        const array<array<string>>&in filterDefaultValues,
        const string&in cardTitle = "Elements",
        bool filterHideRoomElements = true,
        bool filterHideTypeElements = true
    )
    {
        super(scene, tableName, tableQuery, filterColumns, hierarchyColumns,
              displayColumns, aggOps, aggKeyColumns, hiddenColumns,
              hiddenColumnAggOps, respondToSelectionEvents, sendSelectionEvents,
              filterDefaultKeys, filterDefaultValues, cardTitle,
              filterHideRoomElements, filterHideTypeElements);
        @_view = view;
        @_appSceneRef = scene;
    }

    bool RenderBody(const float2&in availableDimensions) override
    {
        // Reserve: 3 threshold rows + small gap + 1 button row.
        float rowH = ImGui::GetFrameHeight() + ImGui::GetStyle().ItemSpacing.y;
        float footerH = 4.0f * rowH + Style::SpacingSmall;
        float2 treeDims(availableDimensions.x,
            availableDimensions.y > 0 ? availableDimensions.y - footerH : 0);

        // Capture the card body's left-padded cursor X so we can restore it
        // after the tree's BeginChild (which resets the window-relative line
        // origin to 0).
        float leftX = ImGui::GetCursorScreenPos().x;

        bool result = ElementTreeCard::RenderBody(treeDims);

        // Re-anchor the cursor to the card's padded column, then start a new
        // child so every line below (thresholds + buttons) flows from that
        // same left edge instead of snapping back to the parent window.
        float curY = ImGui::GetCursorScreenPos().y;
        ImGui::SetCursorScreenPos(float2(leftX, curY));

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_ChildBg, color(0, 0, 0, 0));
        ImGui::BeginChild("##CBFooter", float2(availableDimensions.x, footerH), 0, 0);
        ImGui::PopStyleColor();

        // Row 1: Select Costed / Select Uncosted, with the color-overlay
        // toggle right-aligned on the same line.
        if (VimFlex::ButtonSecondary("Select Costed", true))
            SelectByCost(true);
        ImGui::SameLine();
        if (VimFlex::ButtonSecondary("Select Uncosted", true))
            SelectByCost(false);
        ImGui::SameLine();
        if (_view !is null)
            _view.RenderColorToggleRightAligned();

        Style::VSpaceSmall();

        // Rows 2-4: Low / Mid / High threshold inputs.
        if (_view !is null)
            _view.RenderColorThresholds();

        ImGui::EndChild();

        return result;
    }

    private void SelectByCost(bool costed)
    {
        if (_appSceneRef is null) return;
        auto@ vimData = _appSceneRef.GetVimData();
        if (vimData is null) return;
        auto@ db = vimData.GetData();
        if (db is null) return;

        string op = costed ? "> 0" : "<= 0";
        auto@ res = db.DataQueryGeneric(
            "SELECT elementIndex FROM CostData WHERE Cost " + op);
        if (res is null)
        {
            VimFlex::Console::Warn("CostBreakdown: query failed for Select "
                + (costed ? "Costed" : "Uncosted"));
            return;
        }

        uint n = res.GetRowCount();
        if (n == 0)
        {
            _appSceneRef.GetSelectionService().Apply(Scene::SceneItemSet());
            return;
        }

        array<uint> ids;
        ids.reserve(n);
        for (uint r = 0; r < n; r++)
            ids.insertLast(res.GetItem(r, 0).GetUInt32());

        Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
        itemSet.Add(ids);
        _appSceneRef.GetSelectionService().Apply(itemSet);

        VimFlex::Console::Log("CostBreakdown: Selected " + n + " "
            + (costed ? "costed" : "uncosted") + " elements");
    }
}
