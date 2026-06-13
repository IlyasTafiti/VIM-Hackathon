# Contribuer aux plugins VIM Flex

Ce dépôt contient des plugins **VIM Flex** écrits en AngelScript, plus les skills
Claude qui pilotent ces plugins via MCP. Lisez `CLAUDE.md` et `README.md` avant
de commencer — ils décrivent l'architecture, le cycle de vie d'un plugin et les
patterns SQL/TreeTable.

---

## Mise en place

1. Installer **VIM Flex** et activer le **Developer Mode** (Settings > Developer Settings).
2. Déployer les plugins dans le `UserPlugins` de VIM Flex :
   ```powershell
   .\deploy_plugins.ps1
   ```
   Redémarrer VIM Flex pour charger les plugins copiés.
3. Charger un modèle VIM, puis sélectionner le workflow du plugin dans le menu.

> Le dépôt est mappé sur `%LOCALAPPDATA%\VIM\VIM Flex\UserPlugins\` via le serveur
> MCP `vim-flex`. Il n'existe **pas** de compilateur hors-ligne : la boucle de dev
> passe par `vim_compile` (MCP), qui recompile tous les scripts en mémoire sans
> redémarrage.

---

## Boucle de développement

1. Éditer les `.as` (directement ou via `vim_write_script_file` / `vim_patch_script_file`).
2. `vim_compile` (MCP) — les erreurs reviennent au format `[ERR] chemin/fichier.as:LIGNE message`.
3. Tester les requêtes avec `vim_query` (MCP) contre le modèle chargé.

> Une erreur de compilation dans **n'importe quel** fichier sous `UserPlugins`
> casse le chargement de tous les plugins — vérifier tous les fichiers, pas
> seulement celui modifié.

---

## Structure d'un plugin

Chaque plugin vit dans son propre dossier et suit le même pattern (3 à 5 fichiers) :

| Fichier | Rôle |
|---|---|
| `*Plugin.as` | Namespace : `EventToken`s globaux sur `OnPluginInit()` / `OnPluginShutdown()`, enregistre les vues, le workflow et les outils MCP. |
| `*View.as` | Sous-classe de `Window`. `Render()` appelé chaque frame. S'abonne à `OnVimDataChanged()` dans `Open()`, se désabonne dans `Close()` **et** `Destroy()`. |
| `*DataService.as` | Requêtes SQL via `array.DeserializeFromQuery(vimData, query)` vers des proxy classes ; pré-construit des `Scene::SceneItemSet` pour la sélection 3D. |
| `*McpTools.as` | Enregistre les outils MCP (`mcp.RegisterScriptTool(...)`) qui exposent le plugin à Claude. C'est le **contrat d'intégration**. |
| `vxp.json` | Manifeste du plugin (auteur, version, description, `MinApiVersion`). |

---

## Conventions de code (pièges silencieux)

- **`string`, jamais `hstring`** dans les proxy classes SQL — `hstring` compile mais
  renvoie des chaînes vides à l'exécution. Les noms de champs doivent correspondre
  exactement aux alias des colonnes SQL.
- Utiliser des tableaux de **valeurs** (`array<MyRow>`), pas de handles.
- **Pas de virgule finale** dans les littéraux de tableau (ajoute une entrée nulle).
- `DeserializeFromQuery` attend `Scene::VimData@` (`wrapper.GetData()`), pas le wrapper.
- Ne jamais `GROUP_CONCAT` des IDs d'éléments — les modèles ont des millions
  d'éléments ; agréger des comptes et requêter les IDs à la demande.
- `Core::EscapeSql()` pour interpoler des chaînes utilisateur dans le SQL.
- Toujours se **désabonner** des `EventToken` dans `Destroy()` **et** `Close()` ;
  toujours appeler `TreeTable.Destroy()` au nettoyage.
- `string` AngelScript n'a pas de `.replace` ; `ImGui::TextUnformatted` n'est pas
  exposé (utiliser `ImGui::Text`) ; chaque `PushStyleColor` exige un `PopStyleColor`.
- Sortie de debug : `VimFlex::Console::Log()`.

Vérifier `as.predefined` pour la signature exacte d'une API avant d'écrire un helper.

---

## Skills Claude

Les skills sous `.claude/skills/` documentent comment Claude orchestre un audit
qualité (QC) en appelant les outils MCP du plugin. Chaque `SKILL.md` porte un
frontmatter `name` / `description`. L'orchestrateur (`qc-orchestrator`) délègue à
des skills par module (`qc-georef`, `qc-params`, `qc-ifc-structure`, `qc-loin`) et
lit les exigences via `qc-bep-reader`.

---

## Commits & PR

- Une branche par fonctionnalité ; ne pas committer directement sur `main`.
- Messages de commit à l'impératif, en décrivant le *quoi* et le *pourquoi*.
- Tester la compilation (`vim_compile`) avant d'ouvrir une PR.
- Une PR par plugin ou par skill autant que possible — garder les diffs lisibles.
