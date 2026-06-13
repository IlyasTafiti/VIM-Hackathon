// CostDataSchema.as - Persistence schema, versioning, and migration for
// CostDraft .duckdb files.
//
// Save always writes the current version. Load reads the schema_version
// from a `_CostDraftMeta` table, then ReadSettings() pulls in only the
// columns that exist in that version, leaving other fields at their
// in-memory defaults. The on-disk file is never modified by Load —
// migration is lazy: the user's next Save rewrites the file in the
// current format.
//
// Backwards-compat rules to keep migrations small:
// - New columns are nullable or have a sensible default; old columns
//   never disappear or change semantics.
// - New tables are optional; readers probe via information_schema.
// - Bump CURRENT_SCHEMA_VERSION whenever any read path needs a branch.
//
// Version history:
//   v1: CostInfoRows + CostSettings(lowValue, midValue, highValue).
//       (Files written before _CostDraftMeta existed are treated as v1.)
//   v2: CostSettings adds per-stop RGBA color columns
//       (lowR/G/B/A, midR/G/B/A, highR/G/B/A).

#include "../core/Window.as"

namespace CostDataSchema
{
    const int CURRENT_SCHEMA_VERSION = 2;
    const string META_TABLE = "_CostDraftMeta";

    // Default threshold values: shown the first time the breakdown panel
    // opens and used as the fallback when a loaded file omits them.
    const double DEFAULT_LOW_VALUE  = 0.0;
    const double DEFAULT_MID_VALUE  = 5000.0;
    const double DEFAULT_HIGH_VALUE = 10000.0;

    // Default gradient stop colors (green → amber → red). Fully opaque —
    // the TreeTable uses a reduced alpha derived at render time so cell
    // text stays readable; stored colors are always opaque.
    const color DEFAULT_LOW_COLOR  = color( 50, 200,  50, 255);
    const color DEFAULT_MID_COLOR  = color(250, 160,  50, 255);
    const color DEFAULT_HIGH_COLOR = color(200,  30,  50, 255);

    // In-memory representation of the CostSettings table. Older files only
    // populate the fields they carry; unset fields stay at their defaults.
    class Settings
    {
        double lowValue  = DEFAULT_LOW_VALUE;
        double midValue  = DEFAULT_MID_VALUE;
        double highValue = DEFAULT_HIGH_VALUE;

        color lowColor  = DEFAULT_LOW_COLOR;
        color midColor  = DEFAULT_MID_COLOR;
        color highColor = DEFAULT_HIGH_COLOR;
    }

    // Returns true when `name` is a table in the attached `alias` database.
    //
    // DuckDB's information_schema.tables only sees the *current* database,
    // not attached ones, so we can't filter on table_schema/table_catalog
    // there. Probing with SELECT...LIMIT 0 is reliable cross-database — and
    // thanks to the DataQueryGeneric null-on-failure fix, a missing table
    // shows up as a null result we can detect.
    bool TableExists(Scene::VimData@ db, const string&in alias, const string&in name)
    {
        auto@ r = db.DataQueryGeneric(
            "SELECT 1 FROM " + alias + "." + name + " LIMIT 0");
        return r !is null;
    }

    // Reads the schema_version stamp. Returns 1 (the implicit version of
    // files written before _CostDraftMeta existed) when the meta table is
    // absent.
    int ReadSchemaVersion(Scene::VimData@ db, const string&in alias)
    {
        if (!TableExists(db, alias, META_TABLE))
            return 1;

        auto@ row = db.DataQueryGeneric(
            "SELECT schema_version FROM " + alias + "." + META_TABLE + " LIMIT 1");
        if (row is null || row.GetRowCount() == 0)
            return 1;
        return row.GetItem(0, 0).GetInt32();
    }

    // Reads CostSettings in a version-aware way. Each `if (version >= N)`
    // block pulls the columns introduced at version N; absent columns leave
    // the corresponding Settings fields at their defaults. To add a new
    // version, append a new block here, bump CURRENT_SCHEMA_VERSION, and
    // teach WriteSettings to emit the new columns.
    Settings ReadSettings(Scene::VimData@ db, const string&in alias, int version)
    {
        Settings s;

        if (!TableExists(db, alias, "CostSettings"))
            return s;

        // v1: numeric thresholds
        if (version >= 1)
        {
            auto@ r = db.DataQueryGeneric(
                "SELECT lowValue, midValue, highValue "
                "FROM " + alias + ".CostSettings LIMIT 1");
            if (r !is null && r.GetRowCount() > 0)
            {
                s.lowValue  = r.GetItem(0, 0).GetDouble();
                s.midValue  = r.GetItem(0, 1).GetDouble();
                s.highValue = r.GetItem(0, 2).GetDouble();
            }
        }

        // v2: per-stop RGBA color columns. CAST UTINYINT to INTEGER so the
        // AngelScript GetInt32() accessor matches the column type (there's
        // no GetUInt8() binding, and GetUInt32() on a UTINYINT doesn't
        // auto-widen — it returns 0).
        if (version >= 2)
        {
            auto@ r = db.DataQueryGeneric(
                "SELECT CAST(lowR  AS INTEGER), CAST(lowG  AS INTEGER), "
                "       CAST(lowB  AS INTEGER), CAST(lowA  AS INTEGER), "
                "       CAST(midR  AS INTEGER), CAST(midG  AS INTEGER), "
                "       CAST(midB  AS INTEGER), CAST(midA  AS INTEGER), "
                "       CAST(highR AS INTEGER), CAST(highG AS INTEGER), "
                "       CAST(highB AS INTEGER), CAST(highA AS INTEGER) "
                "FROM " + alias + ".CostSettings LIMIT 1");
            if (r !is null && r.GetRowCount() > 0)
            {
                s.lowColor = color(
                    uint8(r.GetItem(0,  0).GetInt32()),
                    uint8(r.GetItem(0,  1).GetInt32()),
                    uint8(r.GetItem(0,  2).GetInt32()),
                    uint8(r.GetItem(0,  3).GetInt32()));
                s.midColor = color(
                    uint8(r.GetItem(0,  4).GetInt32()),
                    uint8(r.GetItem(0,  5).GetInt32()),
                    uint8(r.GetItem(0,  6).GetInt32()),
                    uint8(r.GetItem(0,  7).GetInt32()));
                s.highColor = color(
                    uint8(r.GetItem(0,  8).GetInt32()),
                    uint8(r.GetItem(0,  9).GetInt32()),
                    uint8(r.GetItem(0, 10).GetInt32()),
                    uint8(r.GetItem(0, 11).GetInt32()));
            }
        }

        return s;
    }

    // Stamps the meta table with CURRENT_SCHEMA_VERSION. Called by Save.
    void WriteSchemaMeta(Scene::VimData@ db, const string&in alias)
    {
        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE " + alias + "." + META_TABLE
            + " (schema_version INTEGER)");
        db.DataQueryGeneric(
            "INSERT INTO " + alias + "." + META_TABLE
            + " VALUES (" + CURRENT_SCHEMA_VERSION + ")");
    }

    // Writes CostSettings in the current schema (all columns).
    void WriteSettings(Scene::VimData@ db, const string&in alias, Settings@ s)
    {
        db.DataQueryGeneric(
            "CREATE OR REPLACE TABLE " + alias + ".CostSettings ("
            "lowValue DOUBLE, midValue DOUBLE, highValue DOUBLE, "
            "lowR UTINYINT, lowG UTINYINT, lowB UTINYINT, lowA UTINYINT, "
            "midR UTINYINT, midG UTINYINT, midB UTINYINT, midA UTINYINT, "
            "highR UTINYINT, highG UTINYINT, highB UTINYINT, highA UTINYINT)");

        db.DataQueryGeneric(
            "INSERT INTO " + alias + ".CostSettings VALUES ("
            + formatFloat(s.lowValue,  "", 0, 6) + ", "
            + formatFloat(s.midValue,  "", 0, 6) + ", "
            + formatFloat(s.highValue, "", 0, 6) + ", "
            + int(s.lowColor.r)  + ", " + int(s.lowColor.g)  + ", "
            + int(s.lowColor.b)  + ", " + int(s.lowColor.a)  + ", "
            + int(s.midColor.r)  + ", " + int(s.midColor.g)  + ", "
            + int(s.midColor.b)  + ", " + int(s.midColor.a)  + ", "
            + int(s.highColor.r) + ", " + int(s.highColor.g) + ", "
            + int(s.highColor.b) + ", " + int(s.highColor.a) + ")");
    }
}
