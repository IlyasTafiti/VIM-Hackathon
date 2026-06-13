// QCResultsView.as — Affiche les resultats du controle qualite par module.
//
// 4 modules : Georeference, Parametres, Structure IFC, LOI/LOIN.
// Chaque module montre un statut (pass / warn / fail) et le commentaire poste
// par Claude. Si un ruleId est attache, le module est cliquable : selection +
// isolation 3D des violations et TreeTable de detail.
//
// Cette vue possede le QCDataService ; les outils MCP appellent ses methodes
// publiques (AddResult / ClearResults / SelectViolations).

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/TreeTable.as"
#include "../widgets/cards/CardUtils.as"
#include "QCDataService.as"

const color QC_GREEN  = color(70,  200, 100, 255);
const color QC_RED    = color(225, 70,  60,  255);
const color QC_YELLOW = color(230, 175, 50,  255);
const color QC_GREY   = color(120, 130, 145, 255);
const color QC_TRACK  = color(50,  50,  50,  200);

class QCResultsView : Window
{
    private App@               _app;
    private AppScene@          _appScene;
    private QCDataService@     _ds;
    private TreeTable@         _tree;
    private Scene::EventToken@ _token;
    private bool               _destroyed;
    private string             _selRule;
    private bool               _rebuildTree;

    QCResultsView(App@ app)
    {
        super("QC Results", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app        = app;
        @_appScene   = app.GetAppScene();
        @_ds         = QCDataService();
        _destroyed   = false;
        _selRule     = "";
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
        _selRule = "";
        _rebuildTree = false;
        if (_tree !is null) { _tree.Destroy(); @_tree = null; }
    }

    // ── API appelee par les outils MCP ──

    void AddResult(const string&in moduleId, const string&in status,
                   const string&in detail, const string&in ruleId)
    {
        _ds.SetResult(moduleId, status, detail, ruleId);
    }

    void ClearResults()
    {
        _ds.ClearResults();
        _selRule = "";
        _rebuildTree = false;
        if (_tree !is null) { _tree.Destroy(); @_tree = null; }
    }

    int SelectViolations(const string&in ruleId)
    {
        return _ds.SelectViolations(ruleId, _appScene);
    }

    // ── Rendu ──

    bool Render(const IRenderContext& ctx) override
    {
        if (!_ds.HasModel())
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped("Chargez un modele VIM pour afficher les resultats QC.");
            ImGui::PopStyleColor();
            return true;
        }

        _RenderScore();
        Style::VSpace();
        ImGui::Separator();
        Style::VSpace();
        _RenderModules();

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
        int audited = _ds.AuditedCount();
        int total   = int(_ds.results.length());
        int pass    = _ds.PassingCount();

        if (audited == 0)
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped("Aucun module audite. Posez une question dans ChatQC "
                "(ex : \"audit complet\") pour lancer le controle.");
            ImGui::PopStyleColor();
            return;
        }

        float pct = audited > 0 ? float(pass) / float(audited) : 0.0f;
        color c   = (pass == audited) ? QC_GREEN : (pct >= 0.5f ? QC_YELLOW : QC_RED);

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, c);
        ImGui::Text("Conformite  " + pass + " / " + audited + "  modules conformes");
        ImGui::PopStyleColor();
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text("" + audited + " / " + total + " modules audites");
        ImGui::PopStyleColor();

        Style::VSpace();

        auto@  dl  = ImGui::GetWindowDrawList();
        float2 pos = ImGui::GetCursorScreenPos();
        float  w   = ImGui::GetContentRegionAvail().x;
        float  h   = 8.0f;
        dl.AddRectFilled(pos, float2(pos.x + w, pos.y + h), QC_TRACK, 4.0f, ImDrawFlags_RoundCornersAll);
        if (pct > 0.01f)
        {
            float fw = w * pct;
            if (fw < 8.0f) fw = 8.0f;
            dl.AddRectFilled(pos, float2(pos.x + fw, pos.y + h), c, 4.0f, ImDrawFlags_RoundCornersAll);
        }
        ImGui::Dummy(float2(w, h + 4.0f));
    }

    private void _RenderModules()
    {
        for (uint i = 0; i < _ds.results.length(); i++)
        {
            QCResult@ r = _ds.results[i];

            color  lc; string prefix;
            if      (r.status == "pass") { lc = QC_GREEN;  prefix = "[OK] "; }
            else if (r.status == "warn") { lc = QC_YELLOW; prefix = "[~] ";  }
            else if (r.status == "fail") { lc = QC_RED;    prefix = "[!!] "; }
            else                         { lc = QC_GREY;   prefix = "[..] "; }

            bool   selectable = r.ruleId != "" && _ds.IsKnownRule(r.ruleId);
            string countStr   = selectable ? ("   " + r.count + " violations") : "";
            string label      = prefix + r.moduleLabel + countStr + "##" + r.moduleId;
            bool   sel         = _selRule == r.ruleId && _selRule != "";

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, lc);
            if (selectable)
            {
                if (ImGui::Selectable(label, sel))
                {
                    _selRule     = r.ruleId;
                    _rebuildTree = true;
                    SelectViolations(r.ruleId);
                }
            }
            else
            {
                ImGui::Text(prefix + r.moduleLabel);
            }
            ImGui::PopStyleColor();

            if (r.detail != "")
            {
                ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, color(180, 200, 225, 220));
                ImGui::TextWrapped("   " + r.detail);
                ImGui::PopStyleColor();
            }

            Style::VSpaceSmall();
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

        // S'assure que la table de violations existe.
        _ds.BuildViolationTable(_selRule);
        string tbl = "QCViolations_" + _selRule;

        @_tree = TreeTable();
        _tree.tableId                  = "##qc_detail";
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
