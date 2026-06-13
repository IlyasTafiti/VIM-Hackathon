// ChatQCView.as — Le chatbox du controleur qualite, monte dans VIM Flex.
//
// L'utilisateur tape sa question directement dans VIM. Le panneau ecrit la
// question dans un fichier "inbox" (pont plugin -> Claude) que l'orchestrateur
// qc-orchestrator lit (via /loop ou invocation). Claude repond en appelant les
// outils MCP qc_set_chat_response (texte) et qc_add_result (resultats par
// module), qui reviennent s'afficher ici et dans QCResultsView.
//
//   Utilisateur (VIM)  --(inbox.json)-->  Claude / qc-orchestrator
//   Claude  --(MCP qc_set_chat_response)-->  ChatQCView (cette vue)

#include "../core/Window.as"
#include "../core/App.as"
#include "../widgets/cards/CardUtils.as"

const color CHAT_USER   = color(165, 180, 252, 255);  // indigo clair
const color CHAT_AI     = color(210, 225, 245, 255);  // bleu clair
const color CHAT_SYS    = color(150, 160, 175, 255);  // gris
const color CHAT_ACCENT = color(99, 102, 241, 255);   // indigo

class ChatMessage
{
    string role;   // "user" | "assistant" | "system"
    string text;

    ChatMessage(const string&in r, const string&in t) { role = r; text = t; }
}

class ChatQCView : Window
{
    private App@               _app;
    private AppScene@          _appScene;
    private Scene::EventToken@ _dataToken;
    private bool               _destroyed;

    private array<ChatMessage@> _history;
    private string              _input;
    private string              _bepPath;
    private string              _status;
    private int                 _msgId;       // compteur monotone pour l'inbox
    private bool                _scrollToEnd;

    ChatQCView(App@ app)
    {
        super("ChatQC", ImGuiWindowFlags::ImGuiWindowFlags_None, false, true);
        @_app      = app;
        @_appScene = app.GetAppScene();
        _destroyed = false;
        _input     = "";
        _bepPath   = "";
        _status    = "Chargez un modele VIM pour demarrer.";
        _msgId     = 0;
        _scrollToEnd = false;

        _history.insertLast(ChatMessage("system",
            "Bonjour. Posez une question de controle qualite (ex : "
            "\"verifie la georeference\", \"audit complet vs le BEP\"). "
            "Indiquez le chemin du BEP ci-dessous si vous voulez un audit contre les exigences."));
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
        _status = "Pret. Posez votre question.";
    }

    // ── API appelee par les outils MCP ──

    void AppendAssistant(const string&in text)
    {
        _history.insertLast(ChatMessage("assistant", text));
        _status = "Reponse recue.";
        _scrollToEnd = true;
    }

    void AppendSystem(const string&in text)
    {
        _history.insertLast(ChatMessage("system", text));
        _scrollToEnd = true;
    }

    void SetStatus(const string&in text) { _status = text; }

    string GetBepPath() { return _bepPath; }

    // ── Envoi d'une question (pont plugin -> Claude via fichier inbox) ──

    private void _Send()
    {
        if (_input.isEmpty()) return;

        _history.insertLast(ChatMessage("user", _input));
        _msgId += 1;

        // Ecrit l'inbox que qc-orchestrator surveille.
        string payload =
            "{\n"
            "  \"id\": " + _msgId + ",\n"
            "  \"question\": \"" + _JsonEscape(_input) + "\",\n"
            "  \"bep\": \"" + _JsonEscape(_bepPath) + "\"\n"
            "}\n";

        string path = _InboxPath();
        IO::WriteFile(path, payload);

        _status = "Question envoyee a Claude (qc-orchestrator)...";
        _input = "";
        _scrollToEnd = true;
    }

    private string _InboxPath()
    {
        return VimFlex::GetUserPluginsPath() + "/ChatQC/inbox.json";
    }

    private string _JsonEscape(const string&in s)
    {
        string o = "";
        for (uint i = 0; i < s.length(); i++)
        {
            uint8 c = s[i];
            if      (c == 34) o += "\\\"";   // "
            else if (c == 92) o += "\\\\";   // backslash
            else if (c == 10) o += "\\n";    // LF
            else if (c == 13) o += "\\r";    // CR
            else if (c == 9)  o += "\\t";    // tab
            else o += s.substr(i, 1);
        }
        return o;
    }

    // ── Rendu ──

    bool Render(const IRenderContext& ctx) override
    {
        // En-tete
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CHAT_ACCENT);
        ImGui::PushFont(Style::GetFontBold());
        ImGui::Text("ChatQC  --  Controleur qualite BIM");
        ImGui::PopFont();
        ImGui::PopStyleColor();
        ImGui::Separator();
        Style::VSpaceSmall();

        // Chemin du BEP
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text("Document BEP / cahier des charges (optionnel)");
        ImGui::PopStyleColor();
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
        string bepOut = _bepPath;
        if (ImGui::InputText("##chatqc_bep", _bepPath, bepOut))
            _bepPath = bepOut;
        Style::VSpaceSmall();

        // Zone de conversation (scrollable), laisse de la place pour la saisie.
        float inputBlock = 92.0f;
        float histH = ImGui::GetContentRegionAvail().y - inputBlock;
        if (histH < 80.0f) histH = 80.0f;

        ImGui::PushStyleColor(ImGuiCol_ChildBg, color(0, 0, 0, 0));
        ImGui::BeginChild("##chatqc_hist", float2(ImGui::GetContentRegionAvail().x, histH), 0, 0);
        _RenderHistory();
        if (_scrollToEnd) { ImGui::SetScrollHereY(1.0f); _scrollToEnd = false; }
        ImGui::EndChild();
        ImGui::PopStyleColor();

        Style::VSpaceSmall();
        ImGui::Separator();

        // Ligne de saisie + boutons
        float sendW  = 70.0f;
        float clearW = 70.0f;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - sendW - clearW - spacing * 2);

        string inOut = _input;
        bool entered = ImGui::InputText("##chatqc_in", _input, inOut,
            ImGuiInputTextFlags::ImGuiInputTextFlags_EnterReturnsTrue);
        if (inOut != _input) _input = inOut;
        if (entered) _Send();

        ImGui::SameLine();
        if (VimFlex::ButtonPrimary("Envoyer", !_input.isEmpty(), float2(sendW, 0)))
            _Send();

        ImGui::SameLine();
        if (VimFlex::ButtonSecondary("Effacer", true, true, float2(clearW, 0)))
        {
            _history.resize(0);
            _history.insertLast(ChatMessage("system", "Conversation effacee."));
        }

        // Statut
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text(_status);
        ImGui::PopStyleColor();

        return true;
    }

    private void _RenderHistory()
    {
        for (uint i = 0; i < _history.length(); i++)
        {
            ChatMessage@ m = _history[i];
            color  c;
            string who;
            if      (m.role == "user")      { c = CHAT_USER; who = "Vous"; }
            else if (m.role == "assistant") { c = CHAT_AI;   who = "ChatQC"; }
            else                            { c = CHAT_SYS;  who = "Info"; }

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, c);
            ImGui::PushFont(Style::GetFontBoldSmall());
            ImGui::Text(who);
            ImGui::PopFont();
            ImGui::PopStyleColor();

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text,
                m.role == "system" ? CardTextDim() : CHAT_AI);
            ImGui::TextWrapped(m.text);
            ImGui::PopStyleColor();

            Style::VSpaceSmall();
        }
    }
}
