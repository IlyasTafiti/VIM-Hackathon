// PGBAuditDataService.as - Évalue 5 règles de conformité PGB contre le modèle chargé
//
// Chaque règle génère une table DuckDB "PGBAudit_<id>" via DataQueryGeneric.
// La view peut ensuite utiliser ces tables directement pour le TreeTable de détail
// et pour la sélection 3D.

// ── Proxy classes pour DeserializeFromQuery ──

class PGBCountRow { int n; }

class PGBElementRow
{
    uint32 elementIndex;
    string Category;
    string Family;
    int    Count;
}

// ── Définition d'une règle PGB ──

class PGBRule
{
    string id;
    string label;
    string ruleCategory;
    int    violationCount;
    bool   loaded;

    PGBRule(const string&in _id, const string&in _label, const string&in _cat)
    {
        id            = _id;
        label         = _label;
        ruleCategory  = _cat;
        violationCount = 0;
        loaded        = false;
    }

    bool IsPassing() { return loaded && violationCount == 0; }
}

// ── Service principal ──

class PGBAuditDataService
{
    array<PGBRule@> rules;
    int    totalPhysicalElements;
    bool   loaded;

    private Scene::VimData@ _vimData;

    PGBAuditDataService()
    {
        _BuildRules();
        totalPhysicalElements = 0;
        loaded = false;
    }

    private void _BuildRules()
    {
        rules.insertLast(PGBRule("no_level",      "Elements sans niveau assigne",       "Spatialite"));
        rules.insertLast(PGBRule("warnings",      "Elements avec avertissements actifs", "Coordination"));
        rules.insertLast(PGBRule("rooms_no_area", "Pieces sans surface calculee",        "Spatialite"));
        rules.insertLast(PGBRule("generic_names", "Types generiques non renommes",       "Conventions"));
        rules.insertLast(PGBRule("no_workset",    "Elements sans workset",               "Coordination"));
    }

    void SetVimData(Scene::VimData@ vimData)
    {
        @_vimData = vimData;
        loaded = false;
    }

    bool IsLoaded() { return loaded; }

    void Load()
    {
        if (_vimData is null) return;

        array<PGBCountRow> totals;
        totals.DeserializeFromQuery(_vimData,
            "SELECT COUNT(*) as n FROM Elements WHERE domain = 'Physical-Visible'");
        totalPhysicalElements = (totals.length() > 0) ? totals[0].n : 0;

        for (uint i = 0; i < rules.length(); i++)
            _LoadRule(rules[i]);

        loaded = true;
    }

    private void _LoadRule(PGBRule@ rule)
    {
        string q = _GetViolationQuery(rule.id);
        if (q == "") { rule.violationCount = 0; rule.loaded = true; return; }

        string tbl = "PGBAudit_" + rule.id;
        _vimData.DataQueryGeneric("CREATE OR REPLACE TABLE " + tbl + " AS " + q);

        array<PGBCountRow> cnt;
        cnt.DeserializeFromQuery(_vimData, "SELECT COUNT(*) as n FROM " + tbl);
        rule.violationCount = (cnt.length() > 0) ? cnt[0].n : 0;
        rule.loaded = true;
    }

    private string _GetViolationQuery(const string&in id)
    {
        if (id == "no_level")
            return
                "SELECT e.index as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM Elements e "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE e.domain = 'Physical-Visible' AND e.levelIndex IS NULL";

        if (id == "warnings")
            return
                "SELECT DISTINCT ew.elementIndex as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM ElementWarnings ew "
                "JOIN Elements e ON ew.elementIndex = e.index "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE ew.elementKindIsLeaf = true AND e.domain = 'Physical-Visible'";

        if (id == "rooms_no_area")
            return
                "SELECT r.elementIndex as elementIndex, "
                "'Piece' as Category, "
                "COALESCE(r.name, '<sans nom>') as Family, "
                "1 as Count "
                "FROM Rooms r "
                "WHERE r.area IS NULL OR r.area <= 0";

        if (id == "generic_names")
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

        if (id == "no_workset")
            return
                "SELECT e.index as elementIndex, "
                "COALESCE(c.name, '<inconnu>') as Category, "
                "COALESCE(e.familyName, '<inconnu>') as Family, "
                "1 as Count "
                "FROM Elements e "
                "LEFT JOIN Categories c ON e.categoryIndex = c.index "
                "WHERE e.domain = 'Physical-Visible' AND e.worksetIndex IS NULL";

        return "";
    }

    // ── Utilitaires publics ──

    int GetPassingCount()
    {
        int n = 0;
        for (uint i = 0; i < rules.length(); i++)
            if (rules[i].IsPassing()) n++;
        return n;
    }

    // Sélectionne et cadre les éléments en violation d'une règle dans la vue 3D
    void SelectAndFrameRule(const string&in ruleId, AppScene@ appScene)
    {
        if (_vimData is null) return;

        string tbl = "PGBAudit_" + ruleId;
        array<PGBElementRow> rows;
        rows.DeserializeFromQuery(_vimData,
            "SELECT elementIndex, Category, Family, Count FROM " + tbl + " LIMIT 50000");

        Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
        for (uint i = 0; i < rows.length(); i++)
            itemSet.Add(rows[i].elementIndex);

        appScene.GetSelectionService().Apply(itemSet);
        if (rows.length() > 0)
            appScene.GetInteractionService().FrameSelection();
    }
}
