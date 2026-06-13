// QCDataService.as — Stocke les resultats du controle qualite postes par Claude
// et materialise les violations en tables DuckDB pour la selection 3D.
//
// Claude (via les outils MCP) ne fait que poster des resultats par module
// (georef / params / structure / loin) et, optionnellement, un ruleId qui
// pointe vers une requete de violations connue. Le DataService cree alors une
// table "QCViolations_<ruleId>" reutilisable par QCResultsView (TreeTable) et
// par la selection 3D.

// ── Proxy classes pour DeserializeFromQuery ──

class QCCountRow { int n; }
class QCIdxRow   { uint32 elementIndex; }

// ── Un resultat de module poste par Claude ──

class QCResult
{
    string moduleId;     // "georef" | "params" | "structure" | "loin"
    string moduleLabel;  // libelle affiche
    string status;       // "pass" | "warn" | "fail"
    string detail;       // texte libre poste par Claude
    string ruleId;       // optionnel — lie a une requete de violations 3D
    int    count;        // nb de violations (rempli depuis la table si ruleId connu)

    QCResult(const string&in id, const string&in label)
    {
        moduleId    = id;
        moduleLabel = label;
        status      = "pending";
        detail      = "";
        ruleId      = "";
        count       = 0;
    }

    bool IsAudited() { return status != "pending"; }
}

// ── Service principal ──

class QCDataService
{
    array<QCResult@> results;     // un par module, ordre fixe

    private Scene::VimData@ _vimData;

    QCDataService()
    {
        _BuildModules();
    }

    private void _BuildModules()
    {
        results.insertLast(QCResult("georef",    "Georeference"));
        results.insertLast(QCResult("params",    "Parametres"));
        results.insertLast(QCResult("structure", "Structure IFC"));
        results.insertLast(QCResult("loin",      "LOI / LOIN"));
    }

    void SetVimData(Scene::VimData@ vimData)
    {
        @_vimData = vimData;
    }

    bool HasModel() { return _vimData !is null; }

    // ── Ecriture des resultats (appelee depuis les outils MCP) ──

    // Poste / met a jour le resultat d'un module. Si ruleId est connu, la table
    // de violations est creee et le compte rempli automatiquement.
    void SetResult(const string&in moduleId, const string&in status,
                   const string&in detail, const string&in ruleId)
    {
        QCResult@ r = _Find(moduleId);
        if (r is null) return;

        r.status = status;
        r.detail = detail;
        r.ruleId = ruleId;
        r.count  = 0;

        if (ruleId != "" && _vimData !is null)
            r.count = BuildViolationTable(ruleId);
    }

    void ClearResults()
    {
        for (uint i = 0; i < results.length(); i++)
        {
            results[i].status = "pending";
            results[i].detail = "";
            results[i].ruleId = "";
            results[i].count  = 0;
        }
    }

    int AuditedCount()
    {
        int n = 0;
        for (uint i = 0; i < results.length(); i++)
            if (results[i].IsAudited()) n++;
        return n;
    }

    int PassingCount()
    {
        int n = 0;
        for (uint i = 0; i < results.length(); i++)
            if (results[i].status == "pass") n++;
        return n;
    }

    private QCResult@ _Find(const string&in moduleId)
    {
        for (uint i = 0; i < results.length(); i++)
            if (results[i].moduleId == moduleId) return results[i];
        return null;
    }

    // ── Violations : tables DuckDB + selection 3D ──

    // Cree "QCViolations_<ruleId>" et renvoie le nombre de violations.
    int BuildViolationTable(const string&in ruleId)
    {
        if (_vimData is null) return 0;
        string q = _GetRuleQuery(ruleId);
        if (q == "") return 0;

        string tbl = "QCViolations_" + ruleId;
        _vimData.DataQueryGeneric("CREATE OR REPLACE TABLE " + tbl + " AS " + q);

        array<QCCountRow> cnt;
        cnt.DeserializeFromQuery(_vimData, "SELECT COUNT(*) as n FROM " + tbl);
        return (cnt.length() > 0) ? cnt[0].n : 0;
    }

    // Selectionne et isole en 3D les elements en violation d'une regle.
    int SelectViolations(const string&in ruleId, AppScene@ appScene)
    {
        if (_vimData is null || appScene is null) return 0;

        // Garantit que la table existe (au cas ou la regle n'a pas ete postee).
        if (_GetRuleQuery(ruleId) == "") return 0;
        BuildViolationTable(ruleId);

        string tbl = "QCViolations_" + ruleId;
        array<QCIdxRow> rows;
        rows.DeserializeFromQuery(_vimData,
            "SELECT elementIndex FROM " + tbl + " LIMIT 50000");

        if (rows.length() == 0) return 0;

        Scene::SceneItemSet@ s = Scene::SceneItemSet();
        for (uint i = 0; i < rows.length(); i++) s.Add(rows[i].elementIndex);

        appScene.GetSelectionService().Apply(s);
        appScene.GetInteractionService().IsolateSelection();
        appScene.GetInteractionService().FrameSelection();
        return int(rows.length());
    }

    bool IsKnownRule(const string&in ruleId) { return _GetRuleQuery(ruleId) != ""; }

    // Toutes les requetes renvoient : elementIndex, Category, Family, Count
    // (compatibles directement avec le TreeTable {"Category","Family"},{"Count"}).
    private string _GetRuleQuery(const string&in id)
    {
        if (id == "structure_no_level")
            return
                "SELECT e.index as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM Elements e "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE e.domain = 'Physical-Visible' AND e.levelIndex IS NULL";

        if (id == "structure_no_workset")
            return
                "SELECT e.index as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM Elements e "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE e.domain = 'Physical-Visible' AND e.worksetIndex IS NULL";

        if (id == "params_generic_type")
            return
                "SELECT e.index as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyTypeName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM Elements e "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE e.domain = 'Physical-Visible' "
                "AND (e.familyTypeName LIKE '%Default%' "
                "  OR e.familyTypeName LIKE '%Generic%' "
                "  OR e.familyName    LIKE '%Default%' "
                "  OR e.familyName    LIKE '%Generic%')";

        if (id == "loin_unnamed_type")
            return
                "SELECT e.index as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM Elements e "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE e.domain = 'Physical-Visible' "
                "AND (e.familyTypeName IS NULL OR e.familyTypeName = '')";

        if (id == "loin_rooms_no_area")
            return
                "SELECT r.elementIndex as elementIndex, "
                "'Piece' as Category, "
                "COALESCE(r.name, '<sans nom>') as Family, "
                "1 as Count "
                "FROM Rooms r "
                "WHERE r.area IS NULL OR r.area <= 0";

        return "";
    }
}
