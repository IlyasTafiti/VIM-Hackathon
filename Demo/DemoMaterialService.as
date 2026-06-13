// DemoMaterialService.as - Centralized material override service for Demo Dashboard
//
// Wraps the engine's MaterialService to maintain the glass material invariant:
// all room geometry stays transparent while the Demo Dashboard workflow is active.
// Every ClearColors() call automatically re-applies the glass override.
//
// Lifecycle: created at plugin init, destroyed at plugin shutdown.
// Room geometry set is provided by DemoDataService when VIM data loads.

#include "../core/App.as"

class DemoMaterialService
{
    private AppScene@ _appScene;

    // Glass material for room geometry transparency
    private uint64 _glassMaterial = 0;
    private Scene::SceneItemSet _roomGeoSet;
    private bool _hasRoomGeo = false;

    // Cached StandardOpaque material instances keyed by color string.
    // Instances persist across clear/apply cycles and are destroyed on Destroy().
    private array<string> _colorMaterialKeys;
    private array<uint64> _colorMaterialHandles;

    void Init(AppScene@ appScene)
    {
        @_appScene = appScene;
    }

    // Called by DemoDataService when room geometry data is available.
    // Creates the glass material lazily and applies it immediately.
    void SetRoomGeometry(Scene::SceneItemSet&in geoSet)
    {
        _roomGeoSet = geoSet;
        _hasRoomGeo = (_roomGeoSet.Count() > 0);

        if (_hasRoomGeo)
        {
            CreateGlassMaterial();
            ApplyGlass();
        }
    }

    // Called by DemoDataService when VIM data is unloaded.
    void ClearRoomGeometry()
    {
        DestroyColorMaterials();
        _roomGeoSet = Scene::SceneItemSet();
        _hasRoomGeo = false;
    }

    // Clear all material overrides, then re-apply glass to room geometry.
    // All cards should call this instead of engine ClearMaterialOverrides().
    void ClearColors()
    {
        if (_appScene is null) return;
        _appScene.GetMaterialService().ClearMaterialOverrides();
        ApplyGlass();
    }

    // Apply an opaque color override to a set of elements.
    // Uses StandardOpaque material instances to avoid the bug where elements
    // with transparent submeshes become fully transparent under SetColor().
    // All cards should call this instead of engine SetColor().
    void ApplyColor(Scene::SceneItemSet@ itemSet, const color&in col)
    {
        if (_appScene is null || itemSet is null || itemSet.Count() == 0) return;

        uint64 matHandle = GetOrCreateOpaqueMaterial(col);
        if (matHandle == 0) return;

        _appScene.GetMaterialService().SetMaterialOverride(itemSet, matHandle);
    }

    void Destroy()
    {
        DestroyColorMaterials();
        DestroyGlassMaterial();
        _roomGeoSet = Scene::SceneItemSet();
        _hasRoomGeo = false;
        @_appScene = null;
    }

    // --- Private ---

    // Returns a cached StandardOpaque material instance for the given color,
    // creating one if it does not already exist.
    private uint64 GetOrCreateOpaqueMaterial(const color&in col)
    {
        string key = "" + col.r + "," + col.g + "," + col.b + "," + col.a;

        // Check cache
        for (uint i = 0; i < _colorMaterialKeys.length(); i++)
        {
            if (_colorMaterialKeys[i] == key)
                return _colorMaterialHandles[i];
        }

        // Create new StandardOpaque instance
        // materialParams: r=roughness, g=metallic, b=unused, a=opacity
        uint64 handle = _appScene.GetMaterialService().CreateMaterialInstance(
            "StandardOpaque",
            col,
            color(180, 0, 0, 255));

        if (handle == 0) return 0;

        _colorMaterialKeys.insertLast(key);
        _colorMaterialHandles.insertLast(handle);
        return handle;
    }

    private void DestroyColorMaterials()
    {
        if (_appScene is null) return;

        auto@ matService = _appScene.GetMaterialService();
        for (uint i = 0; i < _colorMaterialHandles.length(); i++)
        {
            if (_colorMaterialHandles[i] != 0)
                matService.DestroyMaterialInstance(_colorMaterialHandles[i]);
        }

        _colorMaterialKeys.resize(0);
        _colorMaterialHandles.resize(0);
    }

    private void CreateGlassMaterial()
    {
        if (_glassMaterial != 0 || _appScene is null) return;
        _glassMaterial = _appScene.GetMaterialService().CreateMaterialInstance(
            "StandardGlass",
            color(200, 220, 240, 252),
            color(75, 255, 0, 0));
    }

    private void DestroyGlassMaterial()
    {
        if (_glassMaterial == 0 || _appScene is null) return;
        _appScene.GetMaterialService().DestroyMaterialInstance(_glassMaterial);
        _glassMaterial = 0;
    }

    private void ApplyGlass()
    {
        if (!_hasRoomGeo || _glassMaterial == 0 || _appScene is null) return;
        _appScene.GetMaterialService().SetMaterialOverride(_roomGeoSet, _glassMaterial);
    }
}
