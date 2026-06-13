// BIMCopilotView.as

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/CardUtils.as"

class CopilotElemCount { int n; }

class BIMCopilotView : Window
{
    private App@               _app;
    private AppScene@          _appScene;
    private Scene::EventToken@ _dataToken;
    private bool               _destroyed;
    private string             _response;
    private string             _status;
    private bool               _hasResponse;

    BIMCopilotView(App@ app)
    {
        super("BIM Copilot", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app        = app;
        @_appScene   = app.GetAppScene();
        _destroyed   = false;
        _response    = "";
        _status      = "Chargez un modele VIM...";
        _hasResponse = false;
    }

    void RegisterDockingRegion() override
    {
        ImGui::DockBuilderDockWindow(_windowName, VimFlex::Docking::RegionLeft);
    }

    void Destroy() override
    {
        if (_destroyed) return;
        _destroyed = true;
        _Unsub();
        @_appScene = null;
        @_app = null;
        Window::Destroy();
    }

    void Open() override
    {
        Window::Open();
        if (_destroyed) return;
        if (_dataToken is null)
            @_dataToken = _appScene.GetVimDataService().OnVimDataChanged()
                .Subscribe(Scene::Event::EventCallback(OnData));
        OnData();
    }

    void Close() override { _Unsub(); Window::Close(); }

    private void _Unsub()
    {
        if (_dataToken !is null) { _dataToken.Unsubscribe(); @_dataToken = null; }
    }

    private void OnData()
    {
        if (_destroyed) return;
        auto@ w = _appScene.GetVimData();
        if (w is null) { _status = "Chargez un modele VIM..."; return; }
        auto@ d = w.GetData();
        if (d is null) return;
        array<CopilotElemCount> r;
        r.DeserializeFromQuery(d, "SELECT COUNT(*) as n FROM Elements WHERE domain='Physical-Visible'");
        int n = r.length() > 0 ? r[0].n : 0;
        _status = "Pret  |  " + n + " elements physiques";
        _hasResponse = false;
        _response = "";
    }

    void SetResponse(const string&in text) { _response = text; _hasResponse = true; _status = "Reponse recue"; }
    void SetStatus(const string&in text)   { _status = text; }

    bool Render(const IRenderContext& ctx) override
    {
        // Header
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, color(90, 170, 255, 255));
        ImGui::Text("BIM COPILOT  --  Claude connecte via MCP");
        ImGui::PopStyleColor();
        ImGui::Separator();
        Style::VSpace();

        if (!_hasResponse)
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::TextWrapped(
                "Posez une question dans Claude Cowork.\n\n"
                "Exemples :\n"
                "  > Qu'est-ce qui ne va pas dans ce modele ?\n"
                "  > Montre les murs avec avertissements\n"
                "  > Lance un audit PGB complet\n\n"
                "Claude analysera le modele, selectionnera les\n"
                "elements en 3D et affichera sa reponse ici."
            );
            ImGui::PopStyleColor();
        }
        else
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
            ImGui::Text("Analyse IA :");
            ImGui::PopStyleColor();
            Style::VSpace();
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, color(210, 225, 245, 255));
            ImGui::TextWrapped(_response);
            ImGui::PopStyleColor();
        }

        ImGui::Separator();
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text(_status);
        ImGui::PopStyleColor();

        return true;
    }
}
