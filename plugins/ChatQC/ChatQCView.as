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

// Palette inspiree de Claude (Anthropic)
const color CHAT_USER   = color(180, 172, 160, 255);  // taupe chaud (utilisateur)
const color CHAT_AI     = color(237, 233, 224, 255);  // ivoire (texte des messages)
const color CHAT_SYS    = color(160, 152, 140, 255);  // gris chaud (info)
const color CHAT_ACCENT = color(217, 119, 87, 255);   // corail Claude (#D97757)
const color CHAT_GREEN  = color(70,  200, 100, 255);  // vert "lie"

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
    private string              _lastQuestion;// derniere question (pour reecrire l'inbox a l'acquittement)
    private string              _lastBep;     // dernier bep envoye (idem)
    private bool                _scrollToEnd;
    private bool                _pending;     // une question attend la reponse de Claude

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
        _lastQuestion = "";
        _lastBep   = "";
        _scrollToEnd = false;
        _pending   = false;

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
        _pending = false;
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
        _lastQuestion = _input;
        _lastBep      = _bepPath;

        // Ecrit l'inbox que la boucle qc-orchestrator surveille (handled = false).
        _WriteInbox(false);

        _status = "Question envoyee a Claude (qc-orchestrator)...";
        _input = "";
        _pending = true;
        _scrollToEnd = true;
    }

    // Serialise l'inbox. handled=false : nouvelle question a traiter.
    // handled=true : Claude a poste sa reponse, la boucle ne doit plus
    // retraiter cet id (handshake anti double-reponse).
    private void _WriteInbox(bool handled)
    {
        string h = handled ? "true" : "false";
        string payload =
            "{\n"
            "  \"id\": " + _msgId + ",\n"
            "  \"question\": \"" + _JsonEscape(_lastQuestion) + "\",\n"
            "  \"bep\": \"" + _JsonEscape(_lastBep) + "\",\n"
            "  \"handled\": " + h + "\n"
            "}\n";
        IO::WriteFile(_InboxPath(), payload);
    }

    // Appelee par l'outil MCP qc_set_chat_response : la reponse vient d'arriver,
    // on acquitte l'inbox pour que la boucle /loop ne reponde pas deux fois.
    void MarkHandled()
    {
        if (_msgId <= 0) return;
        _WriteInbox(true);
        _pending = false;
        _status  = "Reponse recue (question " + _msgId + " traitee).";
    }

    private string _InboxPath()
    {
        return VimFlex::GetUserPluginsPath() + "/ChatQC/inbox.json";
    }

    // Ouvre un dialogue pour lier un document d'exigences (BEP / PGB) au chat,
    // et donne un retour immediat dans la conversation.
    private void _PickBep()
    {
        string path = VimFlex::OpenFileDialog("Lier un document BEP / PGB au chat",
            "Documents (*.docx;*.pdf;*.doc)\0*.docx;*.pdf;*.doc\0Tous les fichiers (*.*)\0*.*\0");
        if (path.isEmpty()) return;
        _bepPath = path;
        _history.insertLast(ChatMessage("assistant",
            "OK - document lie : " + IO::GetFileName(path) + ".\n"
            "Je peux auditer le modele contre ce document :\n"
            "  - Georeference : systeme de coordonnees, unites, rattachement\n"
            "  - Parametres : types generiques, proprietes requises du BEP\n"
            "  - Structure IFC : worksets, niveaux, nommage\n"
            "  - LOI / LOIN : proprietes requises par categorie\n"
            "Pose ta question (ex : \"audit complet vs ce BEP\") puis Envoyer."));
        _status = "Document lie : " + IO::GetFileName(path);
        _scrollToEnd = true;
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

        // Chemin du BEP + bouton icone (lie un document au chat)
        ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CardTextDim());
        ImGui::Text("Document BEP / PGB / cahier des charges (optionnel)");
        ImGui::PopStyleColor();

        float browseW   = Style::GetIconButtonSize(Style::Icons::OpenFolder).x;
        float bepSpacing = ImGui::GetStyle().ItemSpacing.x;
        ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - browseW - bepSpacing);
        string bepOut = _bepPath;
        if (ImGui::InputText("##chatqc_bep", _bepPath, bepOut))
            _bepPath = bepOut;
        ImGui::SameLine();
        if (VimFlex::IconButtonSecondary(Style::Icons::OpenFolder, true, true, float2(0, 0),
            "Lier un document BEP / PGB au chat"))
            _PickBep();

        // Indicateur "lie" quand un document est attache
        if (!_bepPath.isEmpty())
        {
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, CHAT_GREEN);
            ImGui::Text("[OK] Lie : " + IO::GetFileName(_bepPath));
            ImGui::PopStyleColor();
            ImGui::SameLine();
            if (VimFlex::IconButtonSecondary(Style::Icons::Close, true, true, float2(0, 0),
                "Delier le document"))
            {
                _bepPath = "";
                _history.insertLast(ChatMessage("system", "Document delie du chat."));
                _scrollToEnd = true;
            }
        }
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
            _RenderMessage(_history[i], i);

        // Carte transitoire "analyse en cours" tant qu'une reponse est attendue
        if (_pending)
        {
            int dots = (int(VimFlex::GetUiUpdateTime() * 2.0f) % 3) + 1;
            string d = "";
            for (int k = 0; k < dots; k++) d += ".";
            ChatMessage@ p = ChatMessage("assistant", "Analyse en cours" + d);
            _RenderMessage(p, _history.length());
        }
    }

    // Une carte de message : fond colore par role, barre d'accent a gauche,
    // expediteur en gras, corps en retour a la ligne. Chaque message est dans
    // son propre child dimensionne pour que le fond colle toujours au texte.
    private void _RenderMessage(ChatMessage@ m, uint idx)
    {
        float avail = ImGui::GetContentRegionAvail().x;
        if (avail < 80.0f) avail = 80.0f;

        float pad    = 8.0f;
        float indent = 12.0f;
        float wrapW  = avail - indent - pad;
        if (wrapW < 40.0f) wrapW = 40.0f;

        color accent; color nameCol; color bodyCol; color bg; string who;
        if (m.role == "user")
        {
            accent  = CHAT_USER;                       // taupe chaud
            nameCol = CHAT_USER;
            bodyCol = CHAT_AI;                         // ivoire
            bg      = color(180, 172, 160, 30);        // taupe translucide
            who     = "Vous";
        }
        else if (m.role == "assistant")
        {
            accent  = CHAT_ACCENT;                     // corail Claude
            nameCol = CHAT_ACCENT;
            bodyCol = CHAT_AI;                         // ivoire
            bg      = color(217, 119, 87, 32);         // corail translucide
            who     = "ChatQC";
        }
        else
        {
            accent  = CHAT_SYS;                        // gris chaud
            nameCol = CHAT_SYS;
            bodyCol = CHAT_SYS;
            bg      = color(255, 255, 255, 12);
            who     = "Info";
        }

        // Mesure pour dimensionner la carte (meme largeur de wrap que le rendu)
        ImGui::PushFont(Style::GetFontBoldSmall());
        float2 nameSz = ImGui::CalcTextSize(who, false, wrapW);
        ImGui::PopFont();
        float2 bodySz = ImGui::CalcTextSize(m.text, false, wrapW);
        float rowH = pad + nameSz.y + 6.0f + bodySz.y + pad + 6.0f;

        ImGui::PushStyleColor(ImGuiCol_ChildBg, bg);
        ImGui::BeginChild("##qcmsg" + idx, float2(avail, rowH), 0, 0);

            float2 cp = ImGui::GetCursorScreenPos();
            auto@ dl = ImGui::GetWindowDrawList();
            dl.AddRectFilled(cp, float2(cp.x + 3.0f, cp.y + rowH), accent, 0.0f, ImDrawFlags_None);

            ImGui::Dummy(float2(0, pad - 4.0f));
            ImGui::Indent(indent);

            ImGui::PushFont(Style::GetFontBoldSmall());
            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, nameCol);
            ImGui::Text(who);
            ImGui::PopStyleColor();
            ImGui::PopFont();

            ImGui::PushStyleColor(ImGuiCol::ImGuiCol_Text, bodyCol);
            ImGui::PushTextWrapPos(ImGui::GetCursorPosX() + wrapW);
            ImGui::TextWrapped(m.text);
            ImGui::PopTextWrapPos();
            ImGui::PopStyleColor();

            ImGui::Unindent(indent);

        ImGui::EndChild();
        ImGui::PopStyleColor();
        Style::VSpaceSmall();
    }
}
