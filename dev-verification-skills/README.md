# Dev — Skills de vérification Claude

**Périmètre :** les 4 skills de contrôle qualité par module, exécutés côté Claude.
Tu transformes une demande en audit réel du modèle (requêtes SQL) et tu renvoies
un verdict structuré à l'orchestrateur.

> ⚠️ Les skills **doivent** vivre dans `.claude/skills/` pour être chargés par
> Claude Code. Ce dossier-ci est ton cahier de charge ; tu **édites les fichiers
> à leur emplacement réel** ci-dessous.

## Fichiers que tu possèdes

| Skill | Fichier réel | Vérifie |
|---|---|---|
| `qc-georef` | `.claude/skills/qc-georef/SKILL.md` | Système de coordonnées, unités, éléments hors-niveau, docs liés |
| `qc-params` | `.claude/skills/qc-params/SKILL.md` | Types génériques/non renommés, paramètres requis du BEP |
| `qc-ifc-structure` | `.claude/skills/qc-ifc-structure/SKILL.md` | Worksets, niveaux, hiérarchie, nommage |
| `qc-loin` | `.claude/skills/qc-loin/SKILL.md` | Proprietés LOI/LOIN par catégorie, pièces sans surface |

> `qc-orchestrator` et `qc-bep-reader` appartiennent au Dev « Doc Reader + Orchestrateur ».

## Contrat d'intégration

**Entrée** — l'orchestrateur t'appelle avec la portée + (optionnel) les règles
extraites du BEP par `qc-bep-reader`.

**Outil** — tu interroges le modèle chargé via le MCP `vim-flex` :
`vim_query` (SQL DuckDB). Tables disponibles : `Elements`, `Categories`, `Levels`,
`Rooms`, `Worksets`, `Warnings`, `BimDocuments`… (schéma complet dans `README.md` racine).

**Sortie** — pour chaque module tu renvoies à l'orchestrateur un triplet :
```
module  ∈ {georef, params, structure, loin}
status  ∈ {pass, warn, fail}
detail  = 1–2 phrases actionnables (nb + catégories concernées)
ruleId  = identifiant de violation 3D, ou "" si aucun
```

`ruleId` connus du plugin (sélection 3D + TreeTable) :
`structure_no_level`, `structure_no_workset`, `params_generic_type`,
`loin_unnamed_type`, `loin_rooms_no_area`.

> Ces `ruleId` correspondent à des requêtes déjà câblées dans
> `plugins/ChatQC/QCDataService.as`. Si tu ajoutes une nouvelle règle, coordonne-toi
> avec le Dev QCResultsView pour ajouter la requête correspondante.

## Tâches
- [ ] Affiner les requêtes SQL de chaque skill et les tester via `vim_query` sur les maquettes `ifc/`.
- [ ] Mapper les règles du BEP (`exigences/`) vers les vérifications concrètes.
- [ ] Définir les seuils `pass`/`warn`/`fail` par module.
- [ ] Documenter dans `tests/` un scénario attendu par module (entrée → status attendu).

## Critères d'acceptation
- Chaque skill renvoie un verdict reproductible, jamais inventé (chiffres issus de `vim_query`).
- Les `ruleId` émis existent dans `QCDataService.as` (sélection 3D fonctionnelle).
- Un audit complet renseigne les 4 modules.
