// QCChecklistView.as — Catalogue statique des verifications QC du projet Snowdon.
//
// Onglet "QC Checklist" : reprend la grille de verification definie par les
// documents d'exigences du dossier (Cahier des charges BIM + Plan d'execution
// BIM) sous la forme des codes de test T1..T8 + TR. Chaque test liste les
// criteres concrets et leur source (section CdC / PEB), et indique le module
// live (georef / params / structure / loin) et le ruleId 3D quand il existe.
//
// Vue de reference : contenu statique, ne depend pas du modele charge. Sert de
// "quoi verifier" en regard du panneau "QC Results" qui montre le "resultat".

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/CardUtils.as"

const color CHK_BLUE   = color(99,  150, 245, 255);  // georef
const color CHK_ORANGE = color(235, 160, 70,  255);  // structure
const color CHK_PURPLE = color(190, 130, 245, 255);  // params
const color CHK_GREEN  = color(90,  200, 120, 255);  // loin
const color CHK_GREY   = color(150, 160, 175, 255);  // sans module
const color CHK_TITLE  = color(99,  102, 241, 255);  // indigo accent

class QCCheckItem
{
    string text;
    string src;
    QCCheckItem(const string&in t, const string&in s) { text = t; src = s; }
}

class QCCheck
{
    string code;      // "T1".."T8", "TR"
    string title;     // libelle court
    string moduleId;  // "georef" | "params" | "structure" | "loin" | ""
    string ruleId;    // ruleId 3D associe, ou ""
    array<QCCheckItem@> items;

    QCCheck(const string&in c, const string&in t, const string&in m, const string&in r)
    {
        code = c; title = t; moduleId = m; ruleId = r;
    }

    void Add(const string&in text, const string&in src)
    {
        items.insertLast(QCCheckItem(text, src));
    }
}

class QCChecklistView : Window
{
    private App@            _app;
    private array<QCCheck@> _checks;
    private bool            _destroyed;

    QCChecklistView(App@ app)
    {
        super("QC Checklist", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app      = app;
        _destroyed = false;
        _BuildChecks();
    }

    void RegisterDockingRegion() override
    {
        // Meme region que QC Results -> s'affiche comme un onglet voisin.
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionRight);
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;
        _checks.resize(0);
        @_app = null;
        Window::Destroy();
    }

    // ── Catalogue des verifications (issu de exigences/ : CdC + PEB) ──

    private void _BuildChecks()
    {
        QCCheck@ t1 = QCCheck("T1", "Remise documentaire", "", "");
        t1.Add("7 maquettes IFC4 'tel que construit' presentes : ARC, STR, CVC, PLO, ELE, FAC, SIT.", "CdC 6.3");
        t1.Add("Nommage SNW_A_[DISCIPLINE] respecte ; pas de date, underscore seul autorise.", "CdC 5.2.5 / 3.4.5");
        t1.Add("Livrables complementaires : .rvt natifs, 2D PDF+DWG, nomenclatures XLSX, base GMAO XLSX, rapport coordination PDF+BCF, PEB a jour, index de remise.", "CdC 6.3 / PEB 8");
        _checks.insertLast(t1);

        QCCheck@ t2 = QCCheck("T2", "Structure IFC", "structure", "structure_no_level");
        t2.Add("Version IFC4 uniquement (ISO 16739) ; IFC2x3 et anterieurs refuses.", "CdC 3.2");
        t2.Add("Arborescence spatiale : IfcProject > IfcSite > IfcBuilding > IfcBuildingStorey > (IfcZone) > IfcSpace > equipement.", "CdC 3.2");
        t2.Add("Tous les niveaux presents : Parking, L1, M1, L2..L5, R1..R3, Parapet.", "PEB 7.1.4");
        t2.Add("Aucun element sans niveau assigne (hors-niveau).", "ruleId structure_no_level");
        t2.Add("Elements rattaches a un sous-projet (ZG_/ZL_/ZT_/ZV_).", "ruleId structure_no_workset / PEB 7.1.8");
        _checks.insertLast(t2);

        QCCheck@ t3 = QCCheck("T3", "Georeferencement", "georef", "");
        t3.Add("SCR EPSG:2272 (NAD83 / Pennsylvania South State Plane), unite US Survey Feet.", "CdC 5.2.1");
        t3.Add("Survey Point : E 1 370 149.563 ft / N 258 246.564 ft / Elev -12.000 ft.", "CdC 5.2.1");
        t3.Add("Project Base Point a X=0 Y=0 Z=0, niveau L1, altitude 780.5 ft (NAVD88).", "CdC 5.2.1 / PEB 7.1.3");
        t3.Add("Nord projet = nord vrai, rotation 0 degre.", "CdC 5.2.1");
        t3.Add("Georeferencement exporte dans IfcMapConversion + IfcProjectedCRS ; origine interne commune a toutes les disciplines.", "CdC 5.2.1 / PEB 7.1.3");
        _checks.insertLast(t3);

        QCCheck@ t4 = QCCheck("T4", "Classes & modelisation", "params", "params_generic_type");
        t4.Add("Classes IFC correctes par ouvrage (IfcWall, IfcSlab, IfcRoof, IfcWindow, IfcDoor, IfcColumn, IfcBeam, IfcSpace, IfcFlowTerminal...).", "CdC 5.3.1");
        t4.Add("Objets non classes ramenes a IfcBuildingElementProxy : a minimiser.", "CdC 5.3.1");
        t4.Add("Uniformat II (2015) niveau 3 minimum sur tous les objets.", "CdC 5.3.2 / PEB 7.2.1");
        t4.Add("Unites imperiales : longueur ft, surface ft2, volume ft3 ; poids <= 200 Mo / fichier.", "CdC 3.4.4 / 3.4.3");
        t4.Add("Pas de types generiques / Generic Models hors temporaires ZT_.", "ruleId params_generic_type / PEB 7.1.9");
        _checks.insertLast(t4);

        QCCheck@ t5 = QCCheck("T5", "Proprietes LOIN", "loin", "loin_unnamed_type");
        t5.Add("Psets standards IFC presents (Pset_WallCommon, Pset_SlabCommon, ...).", "PEB 7.2.3");
        t5.Add("SNW_CODE_GMAO = GBQ_<Uniformat niv.3> sur equipements et terminaux (Mechanical/Plumbing/Electrical Equipment, Lighting, Air Terminals, Sprinklers).", "PEB 7.2.2");
        t5.Add("Psets personnalises : Pset_GBQ_Exploitation, Pset_GBQ_Securite (resistance feu), Pset_GBQ_Finitions, Pset_GBQ_Produit.", "PEB 7.2.3");
        t5.Add("Types nommes / non generiques (LOD 350 a la reception).", "ruleId loin_unnamed_type");
        t5.Add("Pieces (IfcSpace) avec attributs programmatiques.", "PEB 7.1.5");
        _checks.insertLast(t5);

        QCCheck@ t6 = QCCheck("T6", "Quantites", "loin", "loin_rooms_no_area");
        t6.Add("Export BaseQuantities active.", "CdC 6.2.1 / PEB 7.3.1");
        t6.Add("Space Boundaries niveau 1.", "PEB 7.3.1");
        t6.Add("Surfaces des pieces renseignees (area > 0).", "ruleId loin_rooms_no_area");
        t6.Add("Compositions multicouches : somme des epaisseurs = epaisseur globale.", "CdC 3.4.1 / PEB 7.2.4");
        _checks.insertLast(t6);

        QCCheck@ t7 = QCCheck("T7", "Clash / coordination", "", "");
        t7.Add("Hard clash tolerance 0 mm ; clearance MEP 25 mm, structure 50 mm.", "PEB 7.6.4");
        t7.Add("Paires testees : ARC x STR/CVC/PLO/ELE, CVC x STR/PLO/ELE, PLO x STR, ELE x STR.", "PEB 7.6.4");
        t7.Add("Exclusions : Insulation, Generic Models, intersections < 5 mm2 ; rapport BCF joint.", "PEB 7.6.4 / 7.6");
        t7.Add("Necessite le modele federe (Dalux) : hors perimetre d'un audit mono-modele VIM.", "n.a.");
        _checks.insertLast(t7);

        QCCheck@ t8 = QCCheck("T8", "Visuel & integrite", "structure", "");
        t8.Add("Pas d'elements indefinis, incorrects ou dupliques.", "CdC 4.2");
        t8.Add("Pas de composants involontaires ; intentions de conception respectees.", "CdC 4.2");
        t8.Add("Tout objet heberge par un niveau et associe a une phase (Situation existante / SNW_Construction).", "PEB 7.1.9");
        t8.Add("Elements verticaux divises par niveau ; purge des vues/familles non utilisees avant depot.", "PEB 7.1.9");
        _checks.insertLast(t8);

        QCCheck@ tr = QCCheck("TR", "Rapport de verification", "", "");
        tr.Add("Verdict global + constats par test, chacun avec sa severite.", "Cahier participant");
        tr.Add("Severite : Mineur (corriger au prochain depot) / Significatif (correction avec delai) / Bloquant (refus, correction immediate).", "Cahier participant");
        tr.Add("Recommandations au donneur d'ouvrage.", "Cahier participant");
        _checks.insertLast(tr);
    }

    private color _ModuleColor(const string&in m)
    {
        if      (m == "georef")    return CHK_BLUE;
        else if (m == "structure") return CHK_ORANGE;
        else if (m == "params")    return CHK_PURPLE;
        else if (m == "loin")      return CHK_GREEN;
        return CHK_GREY;
    }

    private string _ModuleLabel(const string&in m)
    {
        if (m == "") return "documentaire / externe";
        return m;
    }

    // ── Rendu ──

    bool Render(const IRenderContext& ctx) override
    {
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CHK_TITLE);
        ImGui::PushFont(Style::GetFontBold());
        ImGui::Text("QC Checklist  --  Exigences Snowdon (CdC + PEB)");
        ImGui::PopFont();
        ImGui::PopStyleColor();

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::TextWrapped("Grille de verification a la Reception / DOE. Chaque test indique son module "
            "d'audit live et le ruleId 3D quand il existe. Posez la question correspondante dans ChatQC "
            "pour obtenir le resultat sur le modele charge.");
        ImGui::PopStyleColor();

        Style::VSpaceSmall();
        _RenderLegend();
        Style::VSpaceSmall();
        ImGui::Separator();
        Style::VSpaceSmall();

        ImGui::PushStyleColor(ImGuiCol_ChildBg, color(0, 0, 0, 0));
        ImGui::BeginChild("##qc_checklist", float2(ImGui::GetContentRegionAvail().x,
            ImGui::GetContentRegionAvail().y), 0, 0);

        for (uint i = 0; i < _checks.length(); i++)
            _RenderCheck(_checks[i]);

        ImGui::EndChild();
        ImGui::PopStyleColor();

        return true;
    }

    private void _RenderLegend()
    {
        ImGui::TextColored(CHK_BLUE,   "georef");   ImGui::SameLine();
        ImGui::TextColored(CHK_ORANGE, "structure"); ImGui::SameLine();
        ImGui::TextColored(CHK_PURPLE, "params");   ImGui::SameLine();
        ImGui::TextColored(CHK_GREEN,  "loin");     ImGui::SameLine();
        ImGui::TextColored(CHK_GREY,   "documentaire / externe");
    }

    private void _RenderCheck(QCCheck@ c)
    {
        color mc = _ModuleColor(c.moduleId);
        string header = c.code + "  -  " + c.title + "##chk_" + c.code;

        ImGui::SetNextItemOpen(true, ImGuiCond_Once);
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, mc);
        bool open = ImGui::CollapsingHeader(header);
        ImGui::PopStyleColor();

        if (!open) { Style::VSpaceTiny(); return; }

        ImGui::Indent();

        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, mc);
        ImGui::Text("Module : " + _ModuleLabel(c.moduleId)
            + (c.ruleId != "" ? ("   |   ruleId : " + c.ruleId) : ""));
        ImGui::PopStyleColor();
        Style::VSpaceTiny();

        for (uint i = 0; i < c.items.length(); i++)
        {
            QCCheckItem@ it = c.items[i];

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, color(205, 220, 240, 230));
            ImGui::TextWrapped("- " + it.text);
            ImGui::PopStyleColor();

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped("      source : " + it.src);
            ImGui::PopStyleColor();

            Style::VSpaceTiny();
        }

        ImGui::Unindent();
        Style::VSpaceSmall();
    }
}
