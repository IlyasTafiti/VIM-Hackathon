// DemoDataService.as - Data queries for BIM Analytics Dashboard
//
// Provides category, family type, and BIM document statistics for
// Physical-Visible and Topography elements.
// Pre-builds SceneItemSets at load time for instant selection and coloring.

#include "DemoMaterialService.as"

// Proxy classes for SQL query deserialization
class CategoryStats
{
    string name;
    int count;
}

class FamilyTypeStats
{
    string typeName;
    int count;
}

class BimDocumentStats
{
    string title;
    int count;
}

class LevelStats
{
    string name;
    int count;
    float elevation;
}

class RoomStats
{
    string name;
    string number;
    string levelName;
    float area;
    float volume;
    int count;
}

class MaterialStats
{
    string name;
    int elements;
    float totalArea;
    float totalVolume;
    float color_x;
    float color_y;
    float color_z;
    int hasPaint;     // 1 = at least one isPaint=true row
    int hasNonPaint;  // 1 = at least one isPaint=false row
}

// Main data service

class DS_Params { DemoDataService@ ds; }
void DS_LoadSummaryTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadSummaryStats(); }
void DS_LoadCategoryTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadCategoryData(); }
void DS_LoadFamilyTypeTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadFamilyTypeData(); }
void DS_LoadBimDocTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadBimDocumentData(); }
void DS_LoadLevelTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadLevelData(); }
void DS_LoadRoomTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadRoomData(); }
void DS_LoadMaterialTask(any@ d) { DS_Params@ p; d.retrieve(@p); p.ds.LoadMaterialData(); }

class DemoDataService
{
    // Cached statistics (top 15 for donut charts)
    array<CategoryStats> categoryStats;
    array<FamilyTypeStats> familyTypeStats;
    array<BimDocumentStats> bimDocumentStats;
    array<LevelStats> levelStats;
    array<RoomStats> roomStats;

    // Totals
    int totalElements = 0;
    int totalCategories = 0;
    int totalFamilyTypes = 0;
    int totalBimDocuments = 0;
    int totalLevels = 0;
    int totalRooms = 0;

    // Summary stats for dashboard cards
    int summaryPhysicalElements = 0;
    float summaryTriangles = 0;
    int summaryParameters = 0;
    int summaryCategories = 0;
    int summaryFamilies = 0;
    int summaryFamilyTypes = 0;
    int summaryLevels = 0;
    int summaryRooms = 0;
    int summaryWorksets = 0;
    int summaryWarnings = 0;
    int summaryAreas = 0;
    int summaryViews = 0;
    int summaryMaterials = 0;
    int summaryGrids = 0;

    // Pre-built SceneItemSets keyed by group name.
    // Built once at load time for O(1) lookup during selection and coloring.
    private dictionary _categoryToSet;
    private dictionary _familyTypeToSet;
    private dictionary _bimDocumentToSet;
    private dictionary _levelToSet;
    // Room sets are split by domain to support the glass material invariant:
    //   _roomToSet         - all domains (Physical + Topography + Rooms) - used for selection
    //   _roomPhysicalToSet - Physical + Topography only - used for color application (avoids overwriting glass)
    //   _roomGeometryToSet - Rooms domain only - used by DemoMaterialService for glass override
    private dictionary _roomToSet;
    private dictionary _roomPhysicalToSet;
    private dictionary _roomGeometryToSet;

    // All stats (no limit) for coloring
    private array<CategoryStats> _allCategoryStats;
    private array<FamilyTypeStats> _allFamilyTypeStats;
    private array<BimDocumentStats> _allBimDocumentStats;
    private array<LevelStats> _allLevelStats;
    private array<RoomStats> _allRoomStats;
    private array<MaterialStats> _allMaterialStats;
    private dictionary _materialToSet;

    private Scene::VimData@ _vimData;
    private DemoMaterialService@ _matService;
    private bool _dataLoaded = false;

    DemoDataService() {}

    void SetMaterialService(DemoMaterialService@ matService)
    {
        @_matService = matService;
    }

    void SetVimData(Scene::VimData@ vimData)
    {
        ClearData();
        @_vimData = vimData;
    }

    void ClearData()
    {
        CancelLoadAllAsync();
        categoryStats.resize(0);
        familyTypeStats.resize(0);
        bimDocumentStats.resize(0);
        levelStats.resize(0);
        roomStats.resize(0);
        _allCategoryStats.resize(0);
        _allFamilyTypeStats.resize(0);
        _allBimDocumentStats.resize(0);
        _allLevelStats.resize(0);
        _allRoomStats.resize(0);
        _allMaterialStats.resize(0);
        _categoryToSet.deleteAll();
        _familyTypeToSet.deleteAll();
        _bimDocumentToSet.deleteAll();
        _levelToSet.deleteAll();
        _roomToSet.deleteAll();
        _roomPhysicalToSet.deleteAll();
        _roomGeometryToSet.deleteAll();
        _materialToSet.deleteAll();
        if (_matService !is null)
            _matService.ClearRoomGeometry();
        @_vimData = null;
        _dataLoaded = false;
        totalElements = 0;
        totalCategories = 0;
        totalFamilyTypes = 0;
        totalBimDocuments = 0;
        totalLevels = 0;
        totalRooms = 0;
        summaryPhysicalElements = 0;
        summaryTriangles = 0;
        summaryParameters = 0;
        summaryCategories = 0;
        summaryFamilies = 0;
        summaryFamilyTypes = 0;
        summaryLevels = 0;
        summaryRooms = 0;
        summaryWorksets = 0;
        summaryWarnings = 0;
        summaryAreas = 0;
        summaryViews = 0;
        summaryMaterials = 0;
        summaryGrids = 0;
    }

    bool IsDataLoaded() { return _dataLoaded; }

    void LoadAll()
    {
        if (_vimData is null) return;

        VimFlex::Console::Log("DemoDataService: Loading...");

        LoadSummaryStats();
        LoadCategoryData();
        LoadFamilyTypeData();
        LoadBimDocumentData();
        LoadLevelData();
        LoadRoomData();
        LoadMaterialData();

        ApplyRoomGeometry();
        _dataLoaded = true;
        VimFlex::Console::Log("DemoDataService: Done");
    }

    // --- Async loading ---

    private array<Core::Job@> _loadJobs;
    private bool _loading = false;

    void StartLoadAllAsync()
    {
        if (_vimData is null) return;

        VimFlex::Console::Log("DemoDataService: Starting parallel load...");

        DS_Params p;
        @p.ds = this;

        _loadJobs.resize(7);
        @_loadJobs[0] = Parallel::Run("LoadSummary", @DS_LoadSummaryTask, @p);
        @_loadJobs[1] = Parallel::Run("LoadCategory", @DS_LoadCategoryTask, @p);
        @_loadJobs[2] = Parallel::Run("LoadFamilyType", @DS_LoadFamilyTypeTask, @p);
        @_loadJobs[3] = Parallel::Run("LoadBimDoc", @DS_LoadBimDocTask, @p);
        @_loadJobs[4] = Parallel::Run("LoadLevel", @DS_LoadLevelTask, @p);
        @_loadJobs[5] = Parallel::Run("LoadRoom", @DS_LoadRoomTask, @p);
        @_loadJobs[6] = Parallel::Run("LoadMaterial", @DS_LoadMaterialTask, @p);
        _loading = true;
    }

    bool IsLoading() { return _loading; }

    bool IsLoadingComplete()
    {
        if (!_loading) return false;
        for (uint i = 0; i < _loadJobs.length(); i++)
        {
            if (!_loadJobs[i].IsCompleted())
                return false;
        }
        return true;
    }

    void FinishLoadAllAsync()
    {
        _loadJobs.resize(0);
        _loading = false;
        ApplyRoomGeometry();
        _dataLoaded = true;
        VimFlex::Console::Log("DemoDataService: Parallel load complete");
    }

    void CancelLoadAllAsync()
    {
        for (uint i = 0; i < _loadJobs.length(); i++)
        {
            if (_loadJobs[i] !is null)
                _loadJobs[i].Cancel();
        }
        _loadJobs.resize(0);
        _loading = false;
    }

    // --- Summary Stats ---

    void LoadSummaryStats()
    {
        // Physical element count
        auto@ r1 = _vimData.DataQueryGeneric(
            "SELECT COUNT(*) as cnt FROM Elements WHERE domain IN ('Physical-Visible', 'Topography')");
        if (r1 !is null && r1.GetRowCount() > 0)
            summaryPhysicalElements = r1.GetItem(0, 0).GetInt32();

        // Triangles (cast to DOUBLE to avoid UINTEGER SUM overflow)
        auto@ r2 = _vimData.DataQueryGeneric(
            "SELECT SUM(fc) as triangles FROM "
            "(SELECT CAST(faceCount AS DOUBLE) as fc FROM Elements WHERE domain IN ('Physical-Visible', 'Topography'))");
        if (r2 !is null && r2.GetRowCount() > 0)
            summaryTriangles = r2.GetItem(0, 0).GetFloat();

        // Entity counts
        auto@ r3 = _vimData.DataQueryGeneric(
            "SELECT "
            "(SELECT COUNT(*) FROM Parameters) as parameters, "
            "(SELECT COUNT(DISTINCT c.name) FROM Elements e JOIN Categories c ON e.categoryIndex = c.index WHERE e.domain IN ('Physical-Visible', 'Topography') AND c.name IS NOT NULL) as categories, "
            "(SELECT COUNT(DISTINCT name) FROM Families WHERE name IS NOT NULL) as families, "
            "(SELECT COUNT(DISTINCT name) FROM FamilyTypes WHERE name IS NOT NULL) as familyTypes, "
            "(SELECT COUNT(DISTINCT name) FROM Levels WHERE name IS NOT NULL) as levels, "
            "(SELECT COUNT(*) FROM Rooms) as rooms, "
            "(SELECT COUNT(*) FROM Worksets WHERE kind = 'UserWorkset') as worksets, "
            "(SELECT COUNT(*) FROM Warnings) as warnings, "
            "(SELECT COUNT(*) FROM Areas) as areas, "
            "(SELECT COUNT(*) FROM Views) as views, "
            "(SELECT COUNT(DISTINCT name) FROM Materials WHERE name IS NOT NULL) as materials, "
            "(SELECT COUNT(*) FROM Grids) as grids");
        if (r3 !is null && r3.GetRowCount() > 0)
        {
            summaryParameters = r3.GetItem(0, 0).GetInt32();
            summaryCategories = r3.GetItem(0, 1).GetInt32();
            summaryFamilies = r3.GetItem(0, 2).GetInt32();
            summaryFamilyTypes = r3.GetItem(0, 3).GetInt32();
            summaryLevels = r3.GetItem(0, 4).GetInt32();
            summaryRooms = r3.GetItem(0, 5).GetInt32();
            summaryWorksets = r3.GetItem(0, 6).GetInt32();
            summaryWarnings = r3.GetItem(0, 7).GetInt32();
            summaryAreas = r3.GetItem(0, 8).GetInt32();
            summaryViews = r3.GetItem(0, 9).GetInt32();
            summaryMaterials = r3.GetItem(0, 10).GetInt32();
            summaryGrids = r3.GetItem(0, 11).GetInt32();
        }
    }

    // --- Category ---

    void LoadCategoryData()
    {
        // Single query for all categories — slice top 15 for donut
        _allCategoryStats.DeserializeFromQuery(_vimData,
            "SELECT c.name as name, COUNT(*) as count "
            "FROM Elements e "
            "LEFT JOIN Categories c ON e.categoryIndex = c.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') AND c.name IS NOT NULL "
            "GROUP BY c.name "
            "ORDER BY count DESC");

        uint top = Math::Min(_allCategoryStats.length(), 15);
        categoryStats.resize(top);
        totalElements = 0;
        for (uint i = 0; i < top; i++)
        {
            categoryStats[i] = _allCategoryStats[i];
            totalElements += _allCategoryStats[i].count;
        }
        totalCategories = _allCategoryStats.length();

        // Bulk query: all elements with their category name — build SceneItemSets
        auto@ result = _vimData.DataQueryGeneric(
            "SELECT c.name, e.index "
            "FROM Elements e "
            "LEFT JOIN Categories c ON e.categoryIndex = c.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') AND c.name IS NOT NULL");

        if (result !is null)
            BuildSetsFromResult(result, _categoryToSet);
    }

    Scene::SceneItemSet@ GetItemSetForCategory(const string&in name)
    {
        if (_categoryToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_categoryToSet[name]);
        return null;
    }

    array<CategoryStats>@ GetAllCategoryStats()
    {
        return _allCategoryStats;
    }

    // --- Family Type ---

    void LoadFamilyTypeData()
    {
        _allFamilyTypeStats.DeserializeFromQuery(_vimData,
            "SELECT e.familyTypeName as typeName, COUNT(*) as count "
            "FROM Elements e "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') AND e.familyTypeName IS NOT NULL "
            "GROUP BY e.familyTypeName "
            "ORDER BY count DESC");

        uint top = Math::Min(_allFamilyTypeStats.length(), 15);
        familyTypeStats.resize(top);
        for (uint i = 0; i < top; i++)
            familyTypeStats[i] = _allFamilyTypeStats[i];
        totalFamilyTypes = _allFamilyTypeStats.length();

        auto@ result = _vimData.DataQueryGeneric(
            "SELECT e.familyTypeName, e.index "
            "FROM Elements e "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') AND e.familyTypeName IS NOT NULL");

        if (result !is null)
            BuildSetsFromResult(result, _familyTypeToSet);
    }

    Scene::SceneItemSet@ GetItemSetForFamilyType(const string&in name)
    {
        if (_familyTypeToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_familyTypeToSet[name]);
        return null;
    }

    array<FamilyTypeStats>@ GetAllFamilyTypeStats()
    {
        return _allFamilyTypeStats;
    }

    // --- BIM Document ---

    void LoadBimDocumentData()
    {
        _allBimDocumentStats.DeserializeFromQuery(_vimData,
            "SELECT bd.title as title, COUNT(*) as count "
            "FROM Elements e "
            "LEFT JOIN BimDocuments bd ON e.bimDocumentIndex = bd.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') AND bd.title IS NOT NULL "
            "GROUP BY bd.title "
            "ORDER BY count DESC");

        uint top = Math::Min(_allBimDocumentStats.length(), 15);
        bimDocumentStats.resize(top);
        for (uint i = 0; i < top; i++)
            bimDocumentStats[i] = _allBimDocumentStats[i];
        totalBimDocuments = _allBimDocumentStats.length();

        auto@ result = _vimData.DataQueryGeneric(
            "SELECT bd.title, e.index "
            "FROM Elements e "
            "LEFT JOIN BimDocuments bd ON e.bimDocumentIndex = bd.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') AND bd.title IS NOT NULL");

        if (result !is null)
            BuildSetsFromResult(result, _bimDocumentToSet);
    }

    Scene::SceneItemSet@ GetItemSetForBimDocument(const string&in name)
    {
        if (_bimDocumentToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_bimDocumentToSet[name]);
        return null;
    }

    array<BimDocumentStats>@ GetAllBimDocumentStats()
    {
        return _allBimDocumentStats;
    }

    // --- Level ---

    void LoadLevelData()
    {
        // Group by level name, merging duplicates. MIN(elevation) for sort order.
        // COALESCE maps NULL level names to '<unknown>' so every element is counted.
        _allLevelStats.DeserializeFromQuery(_vimData,
            "SELECT COALESCE(l.name, '<unknown>') as name, COUNT(*) as count, "
            "COALESCE(MIN(l.elevation), 999999.0) as elevation "
            "FROM Elements e "
            "LEFT JOIN Levels l ON e.levelIndex = l.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography') "
            "GROUP BY COALESCE(l.name, '<unknown>') "
            "ORDER BY elevation ASC");

        // Show all levels
        uint levelCount = _allLevelStats.length();
        levelStats.resize(levelCount);
        for (uint i = 0; i < levelCount; i++)
            levelStats[i] = _allLevelStats[i];
        totalLevels = levelCount;

        // Build SceneItemSets keyed by level name (merges all indices with same name)
        auto@ result = _vimData.DataQueryGeneric(
            "SELECT COALESCE(l.name, '<unknown>'), e.index "
            "FROM Elements e "
            "LEFT JOIN Levels l ON e.levelIndex = l.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography')");

        if (result !is null)
            BuildSetsFromResult(result, _levelToSet);
    }

    Scene::SceneItemSet@ GetItemSetForLevel(const string&in name)
    {
        if (_levelToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_levelToSet[name]);
        return null;
    }

    array<LevelStats>@ GetAllLevelStats()
    {
        return _allLevelStats;
    }

    // --- Room ---

    void LoadRoomData()
    {
        // Per-room stats with number and level name, ordered by element count descending.
        // Uses room index as the unique grouping key (stringified for set lookup).
        _allRoomStats.DeserializeFromQuery(_vimData,
            "SELECT COALESCE(r.name, '<unknown>') as name, "
            "COALESCE(r.number, '') as number, "
            "COALESCE(l.name, '') as levelName, "
            "COALESCE(r.area, 0) as area, "
            "COALESCE(r.volume, 0) as volume, "
            "COUNT(*) as count "
            "FROM Elements e "
            "LEFT JOIN Rooms r ON e.roomIndex = r.index "
            "LEFT JOIN Elements re ON r.elementIndex = re.index "
            "LEFT JOIN Levels l ON re.levelIndex = l.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography', 'Rooms') "
            "GROUP BY r.index, r.name, r.number, l.name, r.area, r.volume "
            "ORDER BY count DESC");

        uint roomCount = _allRoomStats.length();
        roomStats.resize(roomCount);
        for (uint i = 0; i < roomCount; i++)
            roomStats[i] = _allRoomStats[i];
        totalRooms = roomCount;

        // Build SceneItemSets keyed by room name (all domains)
        auto@ result = _vimData.DataQueryGeneric(
            "SELECT COALESCE(r.name, '<unknown>'), e.index "
            "FROM Elements e "
            "LEFT JOIN Rooms r ON e.roomIndex = r.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography', 'Rooms')");

        if (result !is null)
            BuildSetsFromResult(result, _roomToSet);

        // Build sets for physical/topography elements only (for selection without overriding glass)
        auto@ physResult = _vimData.DataQueryGeneric(
            "SELECT COALESCE(r.name, '<unknown>'), e.index "
            "FROM Elements e "
            "LEFT JOIN Rooms r ON e.roomIndex = r.index "
            "WHERE e.domain IN ('Physical-Visible', 'Topography')");

        if (physResult !is null)
            BuildSetsFromResult(physResult, _roomPhysicalToSet);

        // Build separate sets for room geometry only (for transparent glass material)
        auto@ geoResult = _vimData.DataQueryGeneric(
            "SELECT COALESCE(r.name, '<unknown>'), e.index "
            "FROM Elements e "
            "LEFT JOIN Rooms r ON e.roomIndex = r.index "
            "WHERE e.domain = 'Rooms'");

        if (geoResult !is null)
            BuildSetsFromResult(geoResult, _roomGeometryToSet);
    }

    void ApplyRoomGeometry()
    {
        if (_matService !is null)
        {
            Scene::SceneItemSet mergedGeo;
            auto@ geoKeys = _roomGeometryToSet.getKeys();
            for (uint k = 0; k < geoKeys.length(); k++)
            {
                Scene::SceneItemSet@ geoItems = cast<Scene::SceneItemSet@>(_roomGeometryToSet[geoKeys[k]]);
                if (geoItems !is null && geoItems.Count() > 0)
                    mergedGeo.Add(geoItems);
            }
            _matService.SetRoomGeometry(mergedGeo);
        }
    }

    Scene::SceneItemSet@ GetItemSetForRoom(const string&in name)
    {
        if (_roomToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_roomToSet[name]);
        return null;
    }

    Scene::SceneItemSet@ GetPhysicalItemSetForRoom(const string&in name)
    {
        if (_roomPhysicalToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_roomPhysicalToSet[name]);
        return null;
    }

    Scene::SceneItemSet@ GetRoomGeometrySet(const string&in name)
    {
        if (_roomGeometryToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_roomGeometryToSet[name]);
        return null;
    }

    array<RoomStats>@ GetAllRoomStats()
    {
        return _allRoomStats;
    }

    // --- Material ---

    void LoadMaterialData()
    {
        _allMaterialStats.DeserializeFromQuery(_vimData,
            "SELECT m.name as name, "
            "COUNT(DISTINCT mie.elementIndex) as elements, "
            "ROUND(SUM(mie.area), 1) as totalArea, "
            "ROUND(SUM(mie.volume), 1) as totalVolume, "
            "COALESCE(m.color_x, 0.5) as color_x, "
            "COALESCE(m.color_y, 0.5) as color_y, "
            "COALESCE(m.color_z, 0.5) as color_z, "
            "MAX(CASE WHEN mie.isPaint = true THEN 1 ELSE 0 END) as hasPaint, "
            "MAX(CASE WHEN mie.isPaint = false THEN 1 ELSE 0 END) as hasNonPaint "
            "FROM MaterialsInElement mie "
            "JOIN Materials m ON mie.materialIndex = m.index "
            "JOIN Elements e ON mie.elementIndex = e.index "
            "WHERE m.name IS NOT NULL "
            "AND e.domain IN ('Physical-Visible', 'Topography') "
            "GROUP BY m.name, m.color_x, m.color_y, m.color_z "
            "ORDER BY totalVolume DESC");

        // Build SceneItemSets keyed by material name
        auto@ result = _vimData.DataQueryGeneric(
            "SELECT m.name, mie.elementIndex "
            "FROM MaterialsInElement mie "
            "JOIN Materials m ON mie.materialIndex = m.index "
            "JOIN Elements e ON mie.elementIndex = e.index "
            "WHERE m.name IS NOT NULL "
            "AND e.domain IN ('Physical-Visible', 'Topography')");

        if (result !is null)
            BuildSetsFromResult(result, _materialToSet);
    }

    Scene::SceneItemSet@ GetItemSetForMaterial(const string&in name)
    {
        if (_materialToSet.exists(name))
            return cast<Scene::SceneItemSet@>(_materialToSet[name]);
        return null;
    }

    array<MaterialStats>@ GetAllMaterialStats()
    {
        return _allMaterialStats;
    }

    // --- Shared ---

    // Builds SceneItemSets from a 2-column query result (col 0 = group name, col 1 = element index).
    // Groups elements by name and creates one SceneItemSet per group.
    private void BuildSetsFromResult(Scene::DataQueryResult@ result, dictionary& sets)
    {
        uint rowCount = result.GetRowCount();
        if (rowCount == 0) return;

        // First pass: count elements per group
        dictionary groupCounts;
        for (uint r = 0; r < rowCount; r++)
        {
            string groupName = result.GetItem(r, 0).GetString();
            if (groupCounts.exists(groupName))
            {
                uint c = uint(groupCounts[groupName]);
                groupCounts[groupName] = c + 1;
            }
            else
            {
                groupCounts[groupName] = uint(1);
            }
        }

        // Second pass: pre-size arrays and fill by index
        dictionary indexArrays;
        dictionary fillPos;
        auto@ keys = groupCounts.getKeys();
        for (uint k = 0; k < keys.length(); k++)
        {
            uint count = uint(groupCounts[keys[k]]);
            @indexArrays[keys[k]] = array<uint32>(count);
            fillPos[keys[k]] = uint(0);
        }

        for (uint r = 0; r < rowCount; r++)
        {
            string groupName = result.GetItem(r, 0).GetString();
            uint32 elemIdx = result.GetItem(r, 1).GetUInt32();
            uint pos = uint(fillPos[groupName]);
            cast<array<uint32>@>(indexArrays[groupName])[pos] = elemIdx;
            fillPos[groupName] = pos + 1;
        }

        // Third pass: build SceneItemSets from pre-sized arrays
        for (uint k = 0; k < keys.length(); k++)
        {
            auto@ indices = cast<array<uint32>@>(indexArrays[keys[k]]);
            Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
            itemSet.Add(indices);
            @sets[keys[k]] = itemSet;
        }
    }
}
