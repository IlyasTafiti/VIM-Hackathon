// ElementTaggerView.as - Assign custom tags/labels to selected elements
//
// Tags are stored in a DuckDB table (_ExTagUserTags) keyed by Element UniqueId
// so they survive model updates.
// Each element can have one tag. Provides a text input for tag entry, applies
// tags to the current selection, displays all tagged elements in a sortable
// table, and supports Save to CSV / Load from CSV via DuckDB COPY / read_csv.

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/Card.as"

class TagEntry
{
    string uniqueId;
    uint elementIndex;
    bool resolved;
    string tag;
    string familyName;
    string familyTypeName;
    string categoryName;
    int elementId;
}

class TagCard : Card
{
    private ElementTaggerView@ _view;

    TagCard(ElementTaggerView@ view)
    {
        @_view = view;
        title = "Tags";
        fillHeight = true;
    }

    bool RenderBody(const float2&in availableDimensions) override
    {
        return _view.RenderTagBody(availableDimensions);
    }

    void Destroy() override
    {
        @_view = null;
        Card::Destroy();
    }
}

class ElementTaggerView : Window
{
    private AppScene@ _appScene;
    private TagCard@ _card;

    // DuckDB table name for tag storage
    private string _tableName = "_ExTagUserTags";

    // Flat list for display -- one row per (uniqueId, tag) pair
    private array<TagEntry> _displayRows;

    // Unique tag summary
    private array<string> _uniqueTagNames;
    private array<uint> _uniqueTagCounts;
    private set<string> _activeTagFilters;

    // Input state
    private string _tagInput = "";
    private int _lastClickedFilteredIdx = -1;

    // Sort state
    private uint16 _sortColumn = 0;
    private bool _sortAscending = true;

    // Scroll-to state
    private bool _scrollToTag = false;
    private string _scrollToTagName = "";
    private bool _scrollToSelection = false;
    private bool _suppressScrollToSelection = false;


    // Selection tracking
    private set<uint> _selectedElements;

    // Events
    private Scene::EventToken@ _dataChangedToken = null;
    private Scene::EventToken@ _selectionChangedToken = null;
    private Message::MessageToken@ _keyToken = null;
    private bool _destroyed = false;

    ElementTaggerView(App@ app)
    {
        super("Tags", ImGuiWindowFlags_None, false, true);
        @_appScene = app.GetAppScene();
        @_card = TagCard(this);
    }

    // ── Lifecycle ──

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;

        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }
        if (_selectionChangedToken !is null)
        {
            _selectionChangedToken.Unsubscribe();
            @_selectionChangedToken = null;
        }
        if (_keyToken !is null)
        {
            _keyToken.Unsubscribe();
            @_keyToken = null;
        }

        if (_card !is null)
        {
            _card.Destroy();
            @_card = null;
        }

        @_appScene = null;
        Window::Destroy();
        VimFlex::Console::Log("ElementTaggerView Destroyed");
    }

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;

        EnsureTable();

        auto@ vimData = _appScene.GetVimData();
        if (_dataChangedToken is null && vimData !is null)
        {
            @_dataChangedToken = vimData.GetDataUpdatedCallbacks().Subscribe(
                Scene::Event::EventCallback(HandleDataUpdated));
        }
        if (_selectionChangedToken is null)
        {
            @_selectionChangedToken = _appScene.GetSelectionService()
                .OnSelectionChanged()
                .Subscribe(Scene::Event::EventCallback(HandleSelectionChanged));
        }
        // Consume keyboard events when an ImGui text input is active
        if (_keyToken is null)
        {
            @_keyToken = VimFlex::GetMessageBox()
                .RegisterMessageHandleFront(
                    Message::MessageBox::KeyMessage(OnKeyMessage));
        }

        UpdateSelectedElements();
    }

    void Close() override
    {
        if (_dataChangedToken !is null)
        {
            _dataChangedToken.Unsubscribe();
            @_dataChangedToken = null;
        }
        if (_selectionChangedToken !is null)
        {
            _selectionChangedToken.Unsubscribe();
            @_selectionChangedToken = null;
        }
        if (_keyToken !is null)
        {
            _keyToken.Unsubscribe();
            @_keyToken = null;
        }
        Window::Close();
    }

    private void HandleDataUpdated()
    {
        EnsureTable();
        RebuildDisplayRows();
    }

    private void HandleSelectionChanged()
    {
        UpdateSelectedElements();
        if (_suppressScrollToSelection || ImGui::IsWindowFocused(1))
        {
            _suppressScrollToSelection = false;
        }
        else
        {
            _scrollToSelection = true;
        }
    }

    private bool OnKeyMessage(int key, bool down)
    {
        // Consume key events when any ImGui text input has focus
        if (ImGui::WantTextInput())
            return true;
        return false;
    }

    private void UpdateSelectedElements()
    {
        _selectedElements.clear();
        auto@ selSet = _appScene.GetSelectionService().GetSelectionSet();
        if (selSet !is null && selSet.Count() > 0)
        {
            array<uint>@ elems = selSet.GetElements();
            if (elems !is null)
            {
                _selectedElements.insert(elems);
            }
        }
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionRight);
    }

    // ── DuckDB helpers ──

    private Scene::VimData@ GetData()
    {
        auto@ vimData = _appScene.GetVimData();
        if (vimData is null) return null;
        return vimData.GetData();
    }

    private void EnsureTable()
    {
        auto@ data = GetData();
        if (data is null) return;
        data.DataQueryGeneric(
            "CREATE TABLE IF NOT EXISTS " + _tableName
            + " (uniqueId VARCHAR, tag VARCHAR)");
    }

    // ── Core logic ──

    private void ApplyTagToSelection()
    {
        if (_tagInput.isEmpty()) return;

        auto@ data = GetData();
        if (data is null) return;

        auto@ scene = _appScene.GetScene();
        if (scene is null) return;

        const Scene::SceneItemSet@ selSet = scene.selectionService.GetSelectionSet();
        if (selSet is null || selSet.Count() == 0) return;

        array<uint>@ elements = selSet.GetElements();
        if (elements is null || elements.isEmpty()) return;

        // Build IN list of selected element indices
        string inList = "" + elements[0];
        for (uint i = 1; i < elements.length(); i++)
        {
            inList += "," + elements[i];
        }

        string escapedTag = Core::EscapeSql(_tagInput);

        // Remove existing tags for these elements, then insert new ones
        data.DataQueryGeneric(
            "DELETE FROM " + _tableName + " WHERE uniqueId IN "
            "(SELECT e.uniqueId FROM Elements e "
            "WHERE e.\"index\" IN (" + inList + ") "
            "AND e.uniqueId IS NOT NULL AND e.uniqueId != '')");

        data.DataQueryGeneric(
            "INSERT INTO " + _tableName + " "
            "SELECT e.uniqueId, '" + escapedTag + "' "
            "FROM Elements e "
            "WHERE e.\"index\" IN (" + inList + ") "
            "AND e.uniqueId IS NOT NULL AND e.uniqueId != ''");

        RebuildDisplayRows();
        if (_activeTagFilters.size() > 0)
        {
            _activeTagFilters.insert(_tagInput);
        }
        SelectElementsByTag(_tagInput);
        _scrollToTag = true;
        _scrollToTagName = _tagInput;
    }

    private void ClearAllTags()
    {
        auto@ data = GetData();
        if (data !is null)
        {
            data.DataQueryGeneric("DELETE FROM " + _tableName);
        }
        _displayRows.resize(0);
        _uniqueTagNames.resize(0);
        _uniqueTagCounts.resize(0);
        _activeTagFilters.clear();
    }

    private void DeleteTagsForElements(const set<uint>&in elementIndices)
    {
        if (elementIndices.size() == 0) return;

        // Collect uniqueIds of resolved display rows whose element is selected
        array<string> uidsToDelete;
        for (uint i = 0; i < _displayRows.length(); i++)
        {
            if (_displayRows[i].resolved && elementIndices.exists(_displayRows[i].elementIndex))
            {
                uidsToDelete.insertLast(_displayRows[i].uniqueId);
            }
        }
        if (uidsToDelete.isEmpty()) return;

        string inList = "'" + Core::EscapeSql(uidsToDelete[0]) + "'";
        for (uint i = 1; i < uidsToDelete.length(); i++)
        {
            inList += ",'" + Core::EscapeSql(uidsToDelete[i]) + "'";
        }

        auto@ data = GetData();
        if (data !is null)
        {
            data.DataQueryGeneric(
                "DELETE FROM " + _tableName
                + " WHERE uniqueId IN (" + inList + ")");
        }
    }

    private void SelectTaggedElements()
    {
        if (_displayRows.isEmpty()) return;

        // Collect unique resolved element indices matching active filters
        set<uint> uniqueIndices;
        for (uint i = 0; i < _displayRows.length(); i++)
        {
            if (_displayRows[i].resolved
                && (_activeTagFilters.size() == 0 || _activeTagFilters.exists(_displayRows[i].tag)))
            {
                uniqueIndices.insert(_displayRows[i].elementIndex);
            }
        }

        array<uint>@ arr = uniqueIndices.toArray();
        if (arr.isEmpty()) return;

        Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
        itemSet.Add(arr);
        _appScene.GetSelectionService().Apply(itemSet);
    }

    // ── Display row building ──

    private void RebuildDisplayRows()
    {
        _displayRows.resize(0);

        auto@ data = GetData();
        if (data is null)
        {
            RebuildUniqueTagList();
            return;
        }

        auto@ result = data.DataQueryGeneric(
            "SELECT t.uniqueId, "
            "COALESCE(e.\"index\", 0), "
            "CASE WHEN e.uniqueId IS NOT NULL THEN 1 ELSE 0 END, "
            "t.tag, "
            "COALESCE(e.familyName, ''), "
            "COALESCE(e.familyTypeName, ''), "
            "COALESCE(c.name, ''), "
            "COALESCE(e.id, 0) "
            "FROM " + _tableName + " t "
            "LEFT JOIN Elements e ON t.uniqueId = e.uniqueId "
            "LEFT JOIN Categories c ON e.categoryIndex = c.index");

        if (result !is null)
        {
            for (uint r = 0; r < result.GetRowCount(); r++)
            {
                TagEntry entry;
                entry.uniqueId = result.GetItem(r, 0).GetString();
                entry.elementIndex = result.GetItem(r, 1).GetUInt32();
                entry.resolved = (result.GetItem(r, 2).GetInt32() != 0);
                entry.tag = result.GetItem(r, 3).GetString();
                entry.familyName = result.GetItem(r, 4).GetString();
                entry.familyTypeName = result.GetItem(r, 5).GetString();
                entry.categoryName = result.GetItem(r, 6).GetString();
                entry.elementId = result.GetItem(r, 7).GetInt32();
                _displayRows.insertLast(entry);
            }
        }

        RebuildUniqueTagList();
    }

    private void RebuildUniqueTagList()
    {
        _uniqueTagNames.resize(0);
        _uniqueTagCounts.resize(0);

        dictionary tagCounts;
        for (uint i = 0; i < _displayRows.length(); i++)
        {
            string t = _displayRows[i].tag;
            if (tagCounts.exists(t))
            {
                uint c;
                tagCounts.get(t, c);
                tagCounts.set(t, c + 1);
            }
            else
            {
                tagCounts.set(t, uint(1));
            }
        }

        array<string>@ tagKeys = tagCounts.getKeys();
        if (tagKeys !is null)
        {
            tagKeys.sortAsc();
            for (uint i = 0; i < tagKeys.length(); i++)
            {
                _uniqueTagNames.insertLast(tagKeys[i]);
                uint c;
                tagCounts.get(tagKeys[i], c);
                _uniqueTagCounts.insertLast(c);
            }
        }

        // Remove stale filters
        array<string>@ filterArr = _activeTagFilters.toArray();
        for (uint i = 0; i < filterArr.length(); i++)
        {
            if (!tagCounts.exists(filterArr[i]))
            {
                _activeTagFilters.remove(filterArr[i]);
            }
        }
    }

    private void SelectElementsByTag(const string&in tag)
    {
        set<uint> uniqueIndices;
        for (uint i = 0; i < _displayRows.length(); i++)
        {
            if (_displayRows[i].tag == tag && _displayRows[i].resolved)
            {
                uniqueIndices.insert(_displayRows[i].elementIndex);
            }
        }

        array<uint>@ arr = uniqueIndices.toArray();
        if (arr.isEmpty()) return;

        Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
        itemSet.Add(arr);
        _appScene.GetSelectionService().Apply(itemSet);
    }

    // ── Sorting ──

    private void SortDisplayRows(uint16 columnIndex, bool ascending)
    {
        for (uint i = 1; i < _displayRows.length(); i++)
        {
            TagEntry key = _displayRows[i];
            int j = int(i) - 1;
            while (j >= 0)
            {
                bool swap = false;
                if (columnIndex == 0) // Tag
                {
                    swap = ascending
                        ? (_displayRows[j].tag > key.tag)
                        : (_displayRows[j].tag < key.tag);
                }
                else if (columnIndex == 1) // ID
                {
                    swap = ascending
                        ? (_displayRows[j].elementId > key.elementId)
                        : (_displayRows[j].elementId < key.elementId);
                }
                else if (columnIndex == 2) // Name
                {
                    string a = _displayRows[j].familyName + _displayRows[j].familyTypeName;
                    string b = key.familyName + key.familyTypeName;
                    swap = ascending ? (a > b) : (a < b);
                }
                else if (columnIndex == 3) // Category
                {
                    swap = ascending
                        ? (_displayRows[j].categoryName > key.categoryName)
                        : (_displayRows[j].categoryName < key.categoryName);
                }

                if (!swap) break;
                _displayRows[j + 1] = _displayRows[j];
                j--;
            }
            _displayRows[j + 1] = key;
        }
    }

    // ── CSV Export (DuckDB COPY) ──

    private void SaveToCsv()
    {
        if (_displayRows.isEmpty()) return;

        string path = VimFlex::SaveFileDialog("Save Tags to CSV", "CSV files (*.csv)\0*.csv\0");
        if (path.isEmpty()) return;

        auto@ data = GetData();
        if (data is null) return;

        string escapedPath = Core::EscapeSql(path);
        data.DataQueryGeneric(
            "COPY ("
            "SELECT t.uniqueId AS UniqueId, "
            "COALESCE(e.id, 0) AS ElementId, "
            "COALESCE(e.familyName, '') AS Family, "
            "COALESCE(e.familyTypeName, '') AS FamilyType, "
            "COALESCE(c.name, '') AS Category, "
            "t.tag AS Tag "
            "FROM " + _tableName + " t "
            "LEFT JOIN Elements e ON t.uniqueId = e.uniqueId "
            "LEFT JOIN Categories c ON e.categoryIndex = c.index"
            ") TO '" + escapedPath + "' (FORMAT CSV, HEADER)");

        VimFlex::Console::Log("ElementTagger: Saved tags to " + path);
    }

    // ── CSV Import (DuckDB read_csv) ──

    private void LoadFromCsv()
    {
        string path = VimFlex::OpenFileDialog("Load Tags from CSV", "CSV files (*.csv)\0*.csv\0");
        if (path.isEmpty()) return;

        if (!IO::FileExists(path)) return;

        auto@ data = GetData();
        if (data is null) return;

        string escapedPath = Core::EscapeSql(path);

        // Replace all tags with contents of CSV
        data.DataQueryGeneric("DELETE FROM " + _tableName);
        data.DataQueryGeneric(
            "INSERT INTO " + _tableName + " "
            "SELECT \"UniqueId\", \"Tag\" "
            "FROM read_csv('" + escapedPath + "', header=true, all_varchar=true) "
            "WHERE \"UniqueId\" IS NOT NULL AND \"UniqueId\" != '' "
            "AND \"Tag\" IS NOT NULL AND \"Tag\" != ''");

        RebuildDisplayRows();
        _activeTagFilters.clear();

        VimFlex::Console::Log("ElementTagger: Loaded tags from " + path);
    }

    // ── Rendering ──

    bool Render(const IRenderContext& ctx) override
    {
        _card.Render();
        return true;
    }

    bool RenderTagBody(const float2&in availableDimensions)
    {
        bool inChild = availableDimensions.y > 0;
        if (inChild)
        {
            ImGui::PushStyleColor(ImGuiCol_ChildBg, color(0, 0, 0, 0));
            ImGui::BeginChild("##TagCardBody", float2(availableDimensions.x, availableDimensions.y), 0, 0);
            ImGui::PopStyleColor();
        }

        float availWidth = ImGui::GetContentRegionAvail().x;

        // ── Tag input section ──
        ImGui::PushFont(Style::GetFontBold());
        ImGui::Text("Tag Selected Elements");
        ImGui::PopFont();
        Style::VSpaceSmall();

        // Text input + Apply button
        float applyWidth = 74.0f;
        float itemSpacing = ImGui::GetStyle().ItemSpacing.x;
        ImGui::SetNextItemWidth(availWidth - applyWidth - itemSpacing);

        ImGui::PushStyleColor(ImGuiCol_FrameBg, Style::GetColorBackground());
        ImGui::PushStyleColor(ImGuiCol_FrameBgHovered, Style::GetColorBackground());
        string tagOut = _tagInput;
        if (ImGui::InputText("##TagInput", _tagInput, tagOut))
        {
            _tagInput = tagOut;
        }
        ImGui::PopStyleColor(2);

        // Enter: apply tag
        if (ImGui::IsKeyPressed(ImGuiKey_Enter) && !_tagInput.isEmpty())
        {
            ApplyTagToSelection();
        }

        ImGui::SameLine();
        if (VimFlex::ButtonPrimary("Apply", true, float2(applyWidth, 0)))
        {
            if (!_tagInput.isEmpty())
            {
                ApplyTagToSelection();
            }
        }

        Style::VSpaceSmall();

        // ── Action buttons ──
        if (VimFlex::ButtonSecondary("Save CSV", true, true))
        {
            SaveToCsv();
        }
        ImGui::SameLine();
        if (VimFlex::ButtonSecondary("Load CSV", true, true))
        {
            LoadFromCsv();
        }
        ImGui::SameLine();
        if (VimFlex::ButtonDestructive("Clear All Tags", !_displayRows.isEmpty()))
        {
            ClearAllTags();
        }

        Style::VSpace();

        // ── Tag filter dropdown ──
        if (_uniqueTagNames.length() > 0)
        {
            ImGui::PushFont(Style::GetFontBold());
            ImGui::Text("Tag Filters");
            ImGui::PopFont();
            Style::VSpaceSmall();

            // Build preview label
            string filterPreview = "All Tags";
            if (_activeTagFilters.size() > 0)
            {
                array<string>@ sel = _activeTagFilters.toArray();
                sel.sortAsc();
                filterPreview = sel[0];
                for (uint s = 1; s < sel.length(); s++)
                {
                    filterPreview += ", " + sel[s];
                }
            }

            ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
            ImGui::PushStyleColor(ImGuiCol_FrameBg, Style::GetColorBackground());
            ImGui::PushStyleColor(ImGuiCol_FrameBgHovered, Style::GetColorBackground());
            float itemH = ImGui::GetFrameHeight() + ImGui::GetStyle().ItemSpacing.y;
            float desiredH = float(_uniqueTagNames.length() + 1) * itemH + ImGui::GetStyle().WindowPadding.y * 2;
            float maxH = 300.0f * VimFlex::DpiScale.y;
            float minH = (desiredH < maxH ? desiredH : maxH);
            ImGui::SetNextWindowSizeConstraints(float2(0, minH), float2(99999, maxH));
            ImGui::SetNextWindowInThisViewport();
            if (ImGui::BeginCombo("##TagFilter", filterPreview))
            {
                if (VimFlex::ButtonPrimary("All"))
                {
                    for (uint t = 0; t < _uniqueTagNames.length(); t++)
                    {
                        _activeTagFilters.insert(_uniqueTagNames[t]);
                    }
                }
                ImGui::SameLine();
                if (VimFlex::ButtonPrimary("Clear"))
                {
                    _activeTagFilters.clear();
                }
                ImGui::Separator();

                for (uint t = 0; t < _uniqueTagNames.length(); t++)
                {
                    string label = _uniqueTagNames[t] + " (" + _uniqueTagCounts[t] + ")";
                    bool wasChecked = _activeTagFilters.exists(_uniqueTagNames[t]);
                    bool isChecked = wasChecked;
                    if (ImGui::Checkbox(label, wasChecked, isChecked))
                    {
                        if (isChecked)
                        {
                            _activeTagFilters.insert(_uniqueTagNames[t]);
                        }
                        else
                        {
                            _activeTagFilters.remove(_uniqueTagNames[t]);
                        }
                    }
                }
                ImGui::EndCombo();
            }
            ImGui::PopStyleColor(2);

            Style::VSpace();
        }

        // ── Tagged elements table ──
        array<int> filteredIndices;
        for (uint fi = 0; fi < _displayRows.length(); fi++)
        {
            if (_activeTagFilters.size() == 0 || _activeTagFilters.exists(_displayRows[fi].tag))
            {
                filteredIndices.insertLast(int(fi));
            }
        }

        ImGui::PushFont(Style::GetFontBold());
        if (_activeTagFilters.size() == 0)
        {
            ImGui::Text("Tagged Elements (" + _displayRows.length() + ")");
        }
        else
        {
            ImGui::Text("Tagged Elements (" + filteredIndices.length() + ")");
        }
        ImGui::PopFont();
        Style::VSpaceSmall();

        if (VimFlex::ButtonSecondary("Select All", true, !filteredIndices.isEmpty()))
        {
            SelectTaggedElements();
        }
        bool hasSelectedTags = false;
        for (uint si = 0; si < filteredIndices.length(); si++)
        {
            auto@ fRow = _displayRows[filteredIndices[si]];
            if (fRow.resolved && _selectedElements.exists(fRow.elementIndex))
            {
                hasSelectedTags = true;
                break;
            }
        }
        float deleteWidth = ImGui::CalcTextSize("Delete").x + ImGui::GetStyle().FramePadding.x * 2;
        ImGui::SameLine(ImGui::GetContentRegionAvail().x - deleteWidth + ImGui::GetCursorPos().x);
        bool deletePressed = ImGui::IsWindowFocused(1)
            && !ImGui::WantTextInput()
            && ImGui::IsKeyPressed(ImGuiKey_Delete)
            && hasSelectedTags;
        if (VimFlex::ButtonDestructive("Delete", hasSelectedTags) || deletePressed)
        {
            // Batch-delete tags for selected elements visible in filtered rows
            set<uint> toDelete;
            for (uint si = 0; si < filteredIndices.length(); si++)
            {
                auto@ delRow = _displayRows[filteredIndices[si]];
                if (delRow.resolved && _selectedElements.exists(delRow.elementIndex))
                {
                    toDelete.insert(delRow.elementIndex);
                }
            }
            DeleteTagsForElements(toDelete);
            RebuildDisplayRows();
            ImGui::SetWindowFocus();
        }
        Style::VSpaceSmall();

        if (_displayRows.isEmpty())
        {
            ImGui::TextDisabled("No elements tagged yet. Select elements and enter a tag above.");
            if (inChild) ImGui::EndChild();
            return true;
        }

        float tableHeight = ImGui::GetContentRegionAvail().y;
        int tableFlags = ImGuiTableFlags_RowBg
            | ImGuiTableFlags_BordersInnerH
            | ImGuiTableFlags_BordersOuter
            | ImGuiTableFlags_ScrollY
            | ImGuiTableFlags_Resizable
            | ImGuiTableFlags_Sortable
            | ImGuiTableFlags_SizingStretchProp;

        if (ImGui::BeginTable("##TaggedTable", 4, tableFlags, float2(availWidth, tableHeight)))
        {
            ImGui::TableSetupColumn("Tag", ImGuiTableColumnFlags_WidthStretch | ImGuiTableColumnFlags_DefaultSort, 4.0f);
            ImGui::TableSetupColumn("ID", ImGuiTableColumnFlags_WidthFixed, 60);
            ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch, 1.0f);
            ImGui::TableSetupColumn("Category", ImGuiTableColumnFlags_WidthStretch, 1.0f);
            ImGui::TableSetupScrollFreeze(0, 1);
            ImGui::TableHeadersRow();

            // Handle sorting
            auto@ sortSpecs = ImGui::TableGetSortSpecs();
            if (sortSpecs.SpecsDirty && sortSpecs.SpecsCount > 0)
            {
                auto@ spec = sortSpecs.GetSpec(0);
                _sortColumn = spec.ColumnIndex;
                _sortAscending = (spec.SortDirection == ImGuiSortDirection_Ascending);
                sortSpecs.SpecsDirty = false;
            }
            SortDisplayRows(_sortColumn, _sortAscending);
            filteredIndices.resize(0);
            for (uint fi = 0; fi < _displayRows.length(); fi++)
            {
                if (_activeTagFilters.size() == 0 || _activeTagFilters.exists(_displayRows[fi].tag))
                {
                    filteredIndices.insertLast(int(fi));
                }
            }

            // Scroll to first selected/tagged row
            int scrollToFilteredIdx = -1;
            if (_scrollToTag)
            {
                for (uint si = 0; si < filteredIndices.length(); si++)
                {
                    auto@ scrollRow = _displayRows[filteredIndices[si]];
                    if (scrollRow.tag == _scrollToTagName
                        && scrollRow.resolved
                        && _selectedElements.exists(scrollRow.elementIndex))
                    {
                        scrollToFilteredIdx = int(si);
                        break;
                    }
                }
                _scrollToTag = false;
                _scrollToSelection = false;
            }
            else if (_scrollToSelection)
            {
                for (uint si = 0; si < filteredIndices.length(); si++)
                {
                    auto@ scrollRow = _displayRows[filteredIndices[si]];
                    if (scrollRow.resolved && _selectedElements.exists(scrollRow.elementIndex))
                    {
                        scrollToFilteredIdx = int(si);
                        break;
                    }
                }
                _scrollToSelection = false;
            }

            ImGui::ListClipper clipper;
            clipper.Begin(int(filteredIndices.length()));
            if (scrollToFilteredIdx >= 0)
            {
                clipper.IncludeItemByIndex(scrollToFilteredIdx);
            }
            while (clipper.Step())
            {
                for (int ci = clipper.DisplayStart; ci < clipper.DisplayEnd; ci++)
                {
                    int i = filteredIndices[ci];
                    auto@ row = _displayRows[i];
                    ImGui::PushID(i);

                    bool isSelected = row.resolved && _selectedElements.exists(row.elementIndex);

                    ImGui::TableNextRow();

                    if (ci == scrollToFilteredIdx)
                    {
                        ImGui::SetScrollHereY(0.5f);
                    }

                    if (isSelected)
                    {
                        ImGui::TableSetBgColor(ImGuiTableBgTarget_RowBg1, Style::GetColorHeaderActive());
                    }

                    if (!row.resolved)
                    {
                        ImGui::PushStyleColor(ImGuiCol_Text, Style::GetColorDisabled());
                    }

                    // Tag
                    ImGui::TableNextColumn();
                    ImGui::AlignTextToFramePadding();
                    ImGui::PushFont(Style::GetFontBold());
                    if (row.resolved)
                    {
                        if (ImGui::Selectable(row.tag + "##sel", false, ImGuiSelectableFlags_SpanAllColumns | ImGuiSelectableFlags_AllowOverlap))
                        {
                            _suppressScrollToSelection = true;
                            bool ctrlHeld = ImGui::IsKeyDown(ImGuiMod_Ctrl);
                            bool shiftHeld = ImGui::IsKeyDown(ImGuiMod_Shift);

                            if (shiftHeld && _lastClickedFilteredIdx >= 0 && _lastClickedFilteredIdx < int(filteredIndices.length()))
                            {
                                int rangeStart = _lastClickedFilteredIdx;
                                int rangeEnd = ci;
                                if (rangeStart > rangeEnd)
                                {
                                    int tmp = rangeStart;
                                    rangeStart = rangeEnd;
                                    rangeEnd = tmp;
                                }

                                set<uint> rangeSet;
                                for (int ri = rangeStart; ri <= rangeEnd; ri++)
                                {
                                    int idx = filteredIndices[ri];
                                    if (_displayRows[idx].resolved)
                                    {
                                        rangeSet.insert(_displayRows[idx].elementIndex);
                                    }
                                }

                                array<uint>@ rangeArr = rangeSet.toArray();
                                if (!rangeArr.isEmpty())
                                {
                                    Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
                                    itemSet.Add(rangeArr);
                                    _appScene.GetSelectionService().Apply(itemSet);
                                }
                            }
                            else if (ctrlHeld)
                            {
                                Scene::SceneItem item(row.elementIndex);
                                _appScene.GetScene().selectionService.Toggle(item);
                            }
                            else
                            {
                                array<uint> single = { row.elementIndex };
                                Scene::SceneItemSet@ itemSet = Scene::SceneItemSet();
                                itemSet.Add(single);
                                _appScene.GetSelectionService().Apply(itemSet);
                            }

                            _lastClickedFilteredIdx = ci;
                        }
                    }
                    else
                    {
                        ImGui::Text(row.tag);
                        if (ImGui::IsItemHovered())
                        {
                            ImGui::SetTooltip("Not found in current model\n" + row.uniqueId);
                        }
                    }
                    ImGui::PopFont();

                    // ID
                    ImGui::TableNextColumn();
                    ImGui::AlignTextToFramePadding();
                    if (row.resolved)
                    {
                        ImGui::Text("" + row.elementId);
                    }
                    else
                    {
                        ImGui::Text("?");
                    }

                    // Name: Family > FamilyType
                    ImGui::TableNextColumn();
                    ImGui::AlignTextToFramePadding();
                    string displayName = "";
                    if (!row.familyName.isEmpty() && !row.familyTypeName.isEmpty())
                    {
                        displayName = row.familyName + " > " + row.familyTypeName;
                    }
                    else if (!row.familyName.isEmpty())
                    {
                        displayName = row.familyName;
                    }
                    else if (!row.familyTypeName.isEmpty())
                    {
                        displayName = row.familyTypeName;
                    }
                    else
                    {
                        displayName = "-";
                    }
                    ImGui::Text(displayName);

                    // Category
                    ImGui::TableNextColumn();
                    ImGui::AlignTextToFramePadding();
                    ImGui::Text(row.categoryName.isEmpty() ? "-" : row.categoryName);

                    if (!row.resolved)
                    {
                        ImGui::PopStyleColor();
                    }

                    ImGui::PopID();
                }
            }
            clipper.End();

            ImGui::EndTable();
        }

        if (inChild)
        {
            ImGui::EndChild();
        }

        return true;
    }
}
