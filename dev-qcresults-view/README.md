# Dev — QCResultsView (vue résultats dans VIM)

**Périmètre :** le panneau VIM Flex qui affiche les résultats du contrôle qualité
par module et qui isole les violations en 3D.

> ⚠️ Les fichiers `.as` **doivent** vivre dans `plugins/ChatQC/` pour être compilés
> avec le plugin par VIM Flex. Ce dossier-ci est ton cahier de charge ; tu **édites
> les fichiers à leur emplacement réel** ci-dessous.

## Fichiers que tu possèdes

| Fichier réel | Rôle |
|---|---|
| `plugins/ChatQC/QCResultsView.as` | La vue : score global, 4 lignes de module, TreeTable de détail, sélection 3D. |
| `plugins/ChatQC/QCDataService.as` | Stockage des résultats + requêtes de violations DuckDB (`QCViolations_<ruleId>`). |

> `ChatQCView.as` (chatbox) et `QCMcpTools.as` (outils MCP) appartiennent aux autres devs.

## Contrat d'intégration

**Entrée** — Claude pousse les résultats via les outils MCP (déjà câblés dans
`QCMcpTools.as`, qui appellent tes méthodes publiques) :

| Outil MCP | Méthode appelée | Effet |
|---|---|---|
| `qc_add_result(module, status, detail, ruleId)` | `QCResultsView.AddResult(...)` | Met à jour une ligne de module |
| `qc_select_violations(ruleId)` | `QCResultsView.SelectViolations(...)` | Sélectionne + isole + cadre en 3D |
| `qc_clear_results()` | `QCResultsView.ClearResults()` | Remet les 4 modules à « non audité » |

**Modules affichés (ordre fixe) :** `georef`, `params`, `structure`, `loin`.
**Statuts :** `pass` (vert), `warn` (jaune), `fail` (rouge), `pending` (gris).

**Données 3D / TreeTable** — `QCDataService.BuildViolationTable(ruleId)` crée la
table `QCViolations_<ruleId>` (colonnes `elementIndex, Category, Family, Count`),
réutilisée directement par le `TreeTable` `{"Category","Family"},{"Count"}` et par
la sélection (`GetSelectionService().Apply` + `GetInteractionService()`).

## Tâches
- [ ] Soigner le rendu (badges de statut, barre de conformité, états vides).
- [ ] Brancher de nouveaux `ruleId` côté `QCDataService._GetRuleQuery()` en coordination avec le Dev Skills.
- [ ] Gérer le clic module → sélection 3D + ouverture du TreeTable de détail.
- [ ] Bouton « tout réafficher » (`GetInteractionService().ShowAll()`) après isolation.

## Critères d'acceptation
- `qc_add_result` met à jour la bonne ligne sans rebuild complet de la vue.
- Cliquer un module à `fail` isole ses violations en 3D et affiche le TreeTable.
- `qc_clear_results` réinitialise proprement (détruit le TreeTable, libère les tokens).
- Conforme aux pièges du `CLAUDE.md` racine (désabonnements, `string` SQL, `TreeTable.Destroy()`).

## Rappels API (voir `as.predefined`)
- Vue = sous-classe de `Window` ; `Render()` chaque frame (pas de `Begin/End`).
- Désabonner les `EventToken` dans `Close()` **et** `Destroy()` ; `TreeTable.Destroy()` au nettoyage.
- `SetFilterColumns` / agrégations **avant** `Init()`.
