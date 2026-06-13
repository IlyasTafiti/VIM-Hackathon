// DemoSummaryView.as - Summary statistics cards for Demo Dashboard
//
// Displays a 7x2 grid of summary stat cards showing model-wide counts.
// Docks to RegionTop alongside the BIM Documents donut chart.

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/CardUtils.as"
#include "DemoDataService.as"
#include "DemoView.as"

class DemoSummaryView : Window
{
    private App@ _app;
    private AppScene@ _appScene;
    private DemoDataService@ _dataService;
    private DemoView@ _demoView;

    private Scene::EventToken@ _dataChangedToken = null;
    private bool _destroyed = false;

    DemoSummaryView(App@ app, DemoDataService@ dataService, DemoView@ exView)
    {
        super("Summary", ImGuiWindowFlags(
            ImGuiWindowFlags::ImGuiWindowFlags_NoScrollbar
            | ImGuiWindowFlags::ImGuiWindowFlags_NoScrollWithMouse), false, true);
        @_app = app;
        @_appScene = app.GetAppScene();
        @_dataService = dataService;
        @_demoView = exView;

        VimFlex::Console::Log("DemoSummaryView Created");
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;

        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }

        @_demoView = null;
        @_dataService = null;
        @_appScene = null;
        @_app = null;

        Window::Destroy();
        VimFlex::Console::Log("DemoSummaryView Destroyed");
    }

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;

        if (_dataChangedToken is null)
        {
            @_dataChangedToken = _appScene.GetVimDataService().OnVimDataChanged().Subscribe(
                Scene::Event::EventCallback(OnVimDataChanged));
        }
    }

    void Close() override
    {
        if (_destroyed)
        {
            Window::Close();
            return;
        }

        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }

        Window::Close();
    }

    void RegisterDockingRegion() override
    {
        uint target = (_demoView !is null && _demoView.summaryDockId != 0)
            ? _demoView.summaryDockId : VimFlex::Docking::RegionTop;
        ImGui::DockBuilderDockWindow(_windowName, target);
    }

    private void OnVimDataChanged()
    {
        // Summary cards read directly from dataService each frame; nothing to cache
    }

    bool Render(const IRenderContext& ctx) override
    {
        float2 avail = ImGui::GetContentRegionAvail();
        RenderSummaryGrid(avail.x, avail.y);
        return true;
    }

    // --- Summary cards ---

    private void RenderSummaryGrid(float width, float height)
    {
        int cols = 7;
        int rows = 2;
        float gap = 6.0f;
        float pad = 2.0f;
        float cardW = (width - gap * (cols - 1) - pad) / cols;
        float cardH = (height - gap * (rows - 1) - pad) / rows;

        auto@ dl = ImGui::GetWindowDrawList();
        float2 origin = ImGui::GetCursorScreenPos();

        // Collect raw values for log-scale normalization
        array<float> rawVals = {
            float(_dataService.summaryPhysicalElements),
            float(_dataService.summaryTriangles),
            float(_dataService.summaryParameters),
            float(_dataService.summaryCategories),
            float(_dataService.summaryFamilies),
            float(_dataService.summaryFamilyTypes),
            float(_dataService.summaryMaterials),
            float(_dataService.summaryLevels),
            float(_dataService.summaryRooms),
            float(_dataService.summaryAreas),
            float(_dataService.summaryGrids),
            float(_dataService.summaryWorksets),
            float(_dataService.summaryViews),
            float(_dataService.summaryWarnings)
        };

        float maxLog = 0.0f;
        for (uint i = 0; i < rawVals.length(); i++)
        {
            float lv = Math::Log(rawVals[i] + 1.0f);
            if (lv > maxLog) maxLog = lv;
        }

        // Row 1
        RenderSummaryCard(dl, origin, 0, 0, "Physical Elements", FormatInt(_dataService.summaryPhysicalElements), cardW, cardH, gap, rawVals[0], maxLog);
        RenderSummaryCard(dl, origin, 1, 0, "Triangles", FormatFloat(_dataService.summaryTriangles), cardW, cardH, gap, rawVals[1], maxLog);
        RenderSummaryCard(dl, origin, 2, 0, "Parameters", FormatInt(_dataService.summaryParameters), cardW, cardH, gap, rawVals[2], maxLog);
        RenderSummaryCard(dl, origin, 3, 0, "Categories", FormatInt(_dataService.summaryCategories), cardW, cardH, gap, rawVals[3], maxLog);
        RenderSummaryCard(dl, origin, 4, 0, "Families", FormatInt(_dataService.summaryFamilies), cardW, cardH, gap, rawVals[4], maxLog);
        RenderSummaryCard(dl, origin, 5, 0, "Family Types", FormatInt(_dataService.summaryFamilyTypes), cardW, cardH, gap, rawVals[5], maxLog);
        RenderSummaryCard(dl, origin, 6, 0, "Materials", FormatInt(_dataService.summaryMaterials), cardW, cardH, gap, rawVals[6], maxLog);

        // Row 2
        RenderSummaryCard(dl, origin, 0, 1, "Level Names", FormatInt(_dataService.summaryLevels), cardW, cardH, gap, rawVals[7], maxLog);
        RenderSummaryCard(dl, origin, 1, 1, "Rooms", FormatInt(_dataService.summaryRooms), cardW, cardH, gap, rawVals[8], maxLog);
        RenderSummaryCard(dl, origin, 2, 1, "Areas", FormatInt(_dataService.summaryAreas), cardW, cardH, gap, rawVals[9], maxLog);
        RenderSummaryCard(dl, origin, 3, 1, "Grids", FormatInt(_dataService.summaryGrids), cardW, cardH, gap, rawVals[10], maxLog);
        RenderSummaryCard(dl, origin, 4, 1, "Worksets", FormatInt(_dataService.summaryWorksets), cardW, cardH, gap, rawVals[11], maxLog);
        RenderSummaryCard(dl, origin, 5, 1, "Views", FormatInt(_dataService.summaryViews), cardW, cardH, gap, rawVals[12], maxLog);
        RenderSummaryCard(dl, origin, 6, 1, "Warnings", FormatInt(_dataService.summaryWarnings), cardW, cardH, gap, rawVals[13], maxLog);

        ImGui::Dummy(float2(width, height));
    }

    private void RenderSummaryCard(ImGui::ImDrawList@ dl, const float2&in origin,
        int col, int row, const string&in label, const string&in value,
        float w, float h, float gap, float rawValue, float maxLog)
    {
        float x = origin.x + col * (w + gap);
        float y = origin.y + row * (h + gap);
        float rounding = 8.0f;

        // Log-scaled intensity based on value magnitude
        float intensity = 0.0f;
        if (maxLog > 0.0f)
            intensity = Math::Log(rawValue + 1.0f) / maxLog;

        float tr, tg, tb, maxAlpha;
        if (Style::IsLightColorTheme())
        {
            // Light mode: larger values = stronger blue tint
            tr = 70.0f;  tg = 140.0f; tb = 210.0f;
            maxAlpha = 32.0f;
        }
        else
        {
            // Dark mode: reversed -- smaller values = stronger blue tint
            intensity = 1.0f - intensity;
            tr = 50.0f;  tg = 110.0f; tb = 185.0f;
            maxAlpha = 50.0f;
        }

        float alpha = maxAlpha * intensity;
        color tint = color(uint8(tr), uint8(tg), uint8(tb), uint8(alpha));

        float2 cardMin = float2(x, y);
        float2 cardMax = float2(x + w, y + h);

        dl.AddRectFilled(cardMin, cardMax,
            Style::GetColorFrame(), rounding, ImDrawFlags_RoundCornersAll);
        dl.PushClipRect(float2(x + 1, y + 1), float2(x + w - 1, y + h - 1), true);
        dl.AddRectFilled(cardMin, cardMax, tint, 0.0f);
        dl.PopClipRect();

        color bc = color(42, 74, 127, 128);
        dl.AddRect(cardMin, cardMax, bc, rounding, ImDrawFlags_RoundCornersAll, 1.0f);

        // Measure text sizes for true centering
        ImGui::PushFont(Style::GetFontBold2ExtraLarge());
        float2 valSize = ImGui::CalcTextSize(value);
        ImGui::PopFont();
        float2 lblSize = ImGui::CalcTextSize(label);

        float contentH = valSize.y + 4.0f + lblSize.y;
        float startY = y + (h - contentH) * 0.5f;

        // Value (bold 2XL, centered)
        float valX = x + (w - valSize.x) * 0.5f;
        ImGui::PushFont(Style::GetFontBold2ExtraLarge());
        ImGui::SetCursorScreenPos(float2(valX, startY));
        ImGui::PushStyleColor(ImGuiCol_Text, Style::GetColorAction());
        ImGui::Text(value);
        ImGui::PopStyleColor();
        ImGui::PopFont();

        // Label (regular, centered below value)
        float lblX = x + (w - lblSize.x) * 0.5f;
        float lblY = startY + valSize.y + 4.0f;
        ImGui::SetCursorScreenPos(float2(lblX, lblY));
        ImGui::PushStyleColor(ImGuiCol_Text, CardTextSecondary());
        ImGui::Text(label);
        ImGui::PopStyleColor();
    }

    private string FormatInt(int val)
    {
        if (val >= 1000000)
            return CardFormatFloat(float(val) / 1000000.0f, 1) + "M";
        if (val >= 10000)
            return CardFormatFloat(float(val) / 1000.0f, 1) + "K";
        return CardFormatInt(val);
    }

    private string FormatFloat(float val)
    {
        if (val >= 1000000.0f)
            return CardFormatFloat(val / 1000000.0f, 1) + "M";
        if (val >= 10000.0f)
            return CardFormatFloat(val / 1000.0f, 1) + "K";
        return CardFormatFloat(val, 0);
    }
}
