// PGBAuditView.as

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/TreeTable.as"
#include "../widgets/cards/CardUtils.as"
#include "PGBAuditDataService.as"

const color PGB_GREEN  = color(70,  200, 100, 255);
const color PGB_RED    = color(225, 70,  60,  255);
const color PGB_YELLOW = color(230, 175, 50,  255);
const color PGB_TRACK  = color(50,  50,  50,  200);

class PGBAuditView : Window
{
    private App@                  _app;
    private AppScene@             _appScene;
    private PGBAuditDataService@  _ds;
    private TreeTable@            _tree;
    private Scene::EventToken@    _token;
    private bool                  _destroyed;
    private string                _selRule;
    private bool                  _rebuildTree;

    // Annotations injectées via MCP (deux tableaux parallèles)
    private array<string> _aKeys;
    private array<string> _aVals;

    PGBAuditView(App@ app)
    {
        super("PGB Audit", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app      = app;
        @_appScene = app.GetAppScene();
        @_ds       = PGBAuditDataService();
        _destroyed = false;
        _selRule   = "";
        _rebuildTree = false;
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionRight);
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;
        _Unsub();
        if (_tree !is null) { _tree.Destroy(); @_tree = null; }
        @_ds = null; @_appScene = null; @_app = null;
        Window::Destroy();
    }

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;
        if (_token is null)
            @_token = _appScene.GetVimDataService().OnVimDataChanged()
                .Subscribe(Scene::Event::EventCallback(OnData));
        OnData();
    }

    void Close() override { _Unsub(); Window::Close(); }

    private void _Unsub()
    {
        if (_token !is null) { _token.Unsubscribe(); @_token = null; }
    }

    private void OnData()
    {
        if (_destroyed) return;
        auto@ w = _appScene.GetVimData();
        if (w is null) return;
        auto@ d = w.GetData();
        if (d is null) return;
        _ds.SetVimData(d);
        _ds.Load();
        _selRule = "";
        _rebuildTree = false;
        _aKeys.resize(0);
        _aVals.resize(0);
        if (_tree !is null) { _tree.Destroy(); @_tree = null; }
    }

    // ── API MCP ──

    void ReloadAudit() { OnData(); }

    void SetRuleAnnotation(const string&in ruleId, const string&in text)
    {
        for (uint i = 0; i < _aKeys.length(); i++)
            if (_aKeys[i] == ruleId) { _aVals[i] = text; return; }
        _aKeys.insertLast(ruleId);
        _aVals.insertLast(text);
    }

    private string _Annot(const string&in ruleId)
    {
        for (uint i = 0; i < _aKeys.length(); i++)
            if (_aKeys[i] == ruleId) return _aVals[i];
        return "";
    }

    // ── Rendu ──

    bool Render(const IRenderContext& ctx) override
    {
        if (!_ds.IsLoaded())
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped("Chargez un modele VIM pour lancer l'audit PGB.");
            ImGui::PopStyleColor();
            return true;
        }

        _RenderScore();
        Style::VSpace();
        ImGui::Separator();
        Style::VSpace();
        _RenderRules();

        if (_selRule != "")
        {
            Style::VSpace();
            ImGui::Separator();
            Style::VSpace();
            _RenderTree();
        }

        return true;
    }

    private void _RenderScore()
    {
        int   pass  = _ds.GetPassingCount();
        int   total = int(_ds.rules.length());
        float pct   = total > 0 ? float(pass) / float(total) : 0.0f;

        color c = pass == total ? PGB_GREEN : (pct >= 0.5f ? PGB_YELLOW : PGB_RED);

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, c);
        ImGui::Text("Conformite PGB  " + pass + " / " + total + "  (" + int(pct * 100.0f + 0.5f) + "%)");
        ImGui::PopStyleColor();
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text("" + _ds.totalPhysicalElements + " elements physiques audites");
        ImGui::PopStyleColor();

        Style::VSpace();

        // Barre de progression
        auto@  dl  = ImGui::GetWindowDrawList();
        float2 pos = ImGui::GetCursorScreenPos();
        float  w   = ImGui::GetContentRegionAvail().x;
        float  h   = 8.0f;
        dl.AddRectFilled(pos, float2(pos.x + w, pos.y + h), PGB_TRACK, 4.0f, ImDrawFlags_RoundCornersAll);
        if (pct > 0.01f)
        {
            float fw = w * pct;
            if (fw < 8.0f) fw = 8.0f;
            dl.AddRectFilled(pos, float2(pos.x + fw, pos.y + h), c, 4.0f, ImDrawFlags_RoundCornersAll);
        }
        ImGui::Dummy(float2(w, h + 4.0f));
    }

    private void _RenderRules()
    {
        for (uint i = 0; i < _ds.rules.length(); i++)
        {
            PGBRule@ r      = _ds.rules[i];
            bool     pass   = r.IsPassing();
            bool     sel    = _selRule == r.id;
            string   annot  = _Annot(r.id);

            color    lc     = pass ? PGB_GREEN : PGB_RED;
            string   prefix = pass ? "[OK] " : "[!!] ";
            string   count  = pass ? "OK" : ("" + r.violationCount + " violations");
            string   label  = prefix + r.label + "   " + count + "##" + r.id;

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, lc);
            if (ImGui::Selectable(label, sel))
            {
                _selRule     = r.id;
                _rebuildTree = true;
                if (!pass) _ds.SelectAndFrameRule(r.id, _appScene);
            }
            ImGui::PopStyleColor();

            // Annotation IA si présente
            if (annot != "")
            {
                ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, color(180, 210, 255, 210));
                ImGui::TextWrapped("   " + annot);
                ImGui::PopStyleColor();
            }

            Style::VSpace();
        }
    }

    private void _RenderTree()
    {
        if (_rebuildTree) { _BuildTree(); _rebuildTree = false; }
        if (_tree is null) return;
        _tree.maxHeight = ImGui::GetContentRegionAvail().y;
        _tree.Render();
    }

    private void _BuildTree()
    {
        if (_tree !is null) { _tree.Destroy(); @_tree = null; }
        auto@ w = _appScene.GetVimData();
        if (w is null) return;
        auto@ d = w.GetData();
        if (d is null) return;

        string tbl = "PGBAudit_" + _selRule;

        @_tree = TreeTable();
        _tree.tableId                  = "##pgb_d";
        _tree.sendSelectionEvents      = true;
        _tree.respondToSelectionEvents = true;
        _tree.showFooter               = true;
        _tree.footerLabel              = "TOTAL";

        _tree.SetDisplayColumnAggregation(0, TreeTableAggOp_Sum);
        _tree.SetDisplayColumnFormat(0, TreeTableFormat_Integer);
        _tree.SetDisplayColumnBgColorMode(0, TreeTableColorMode_Interpolate);
        _tree.SetDisplayColumnBgColorPoint(0,  0.0f, color(225, 70, 60, 20));
        _tree.SetDisplayColumnBgColorPoint(0, 50.0f, color(225, 70, 60, 70));

        _tree.Init(d, tbl, {"Category", "Family"}, {"Count"},
            _appScene.GetScene(), "elementIndex");
    }
}
