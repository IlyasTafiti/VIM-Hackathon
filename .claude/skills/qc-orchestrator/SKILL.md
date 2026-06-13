---
name: qc-orchestrator
description: Orchestre un controle qualite BIM dans VIM Flex. Recoit une question du chatbox ChatQC (fichier inbox.json) ou directement de l'utilisateur, lit le BEP via qc-bep-reader, delegue aux skills de module (qc-georef, qc-params, qc-ifc-structure, qc-loin), puis poste les resultats dans le plugin via les outils MCP qc_add_result / qc_set_chat_response / qc_select_violations. A utiliser des qu'une question de qualite/conformite BIM est posee.
---

# qc-orchestrator

Chef d'orchestre du controleur qualite ChatQC. Tu transformes une question en
langage naturel en un audit structure du modele VIM charge, et tu renvoies les
resultats dans le plugin VIM Flex.

## Pont d'entree : le chatbox VIM

Quand l'utilisateur tape dans le panneau **ChatQC**, le plugin ecrit sa question
dans :

```
<UserPlugins>/ChatQC/inbox.json      # UserPlugins = vim_get_user_plugins_path (MCP) ou %LOCALAPPDATA%\VIM\VIM Flex\UserPlugins
```

Format :
```json
{ "id": 3, "question": "verifie la georeference", "bep": "C:/.../BEP.docx" }
```

- Lis `inbox.json`. Si `id` est nouveau (different du dernier traite), traite la question.
- En mode `/loop`, relis le fichier a chaque tick et ne traite que les `id` nouveaux.
- Si l'utilisateur te parle directement dans Claude Code, ignore l'inbox et traite la question directement.

## Sortie : outils MCP du serveur vim-flex

| Outil | Usage |
|---|---|
| `qc_set_chat_response(text)` | Reponse en langage naturel affichee dans le chatbox. **Toujours appeler en dernier.** |
| `qc_add_result(module, status, detail, ruleId)` | Un appel par module audite. |
| `qc_select_violations(ruleId)` | Selectionne/isole les violations en 3D (optionnel, sur demande). |
| `qc_clear_results()` | Vide le panneau avant un nouvel audit complet. |

`module` ∈ `georef` · `params` · `structure` · `loin`
`status` ∈ `pass` · `warn` · `fail`
`ruleId` connus : `structure_no_level`, `structure_no_workset`, `params_generic_type`, `loin_unnamed_type`, `loin_rooms_no_area` (ou `""`).

## Procedure

1. **Comprendre la portee.** Question ciblee (un module) ou audit complet ? Mots-cles :
   georef/coordonnees/projection → `qc-georef` ; parametres/proprietes vides → `qc-params` ;
   nommage/workset/niveau/IFC → `qc-ifc-structure` ; LOI/LOIN/niveau d'info → `qc-loin`.
2. **Lire les exigences** si un `bep` est fourni : appelle **qc-bep-reader** pour extraire
   les regles applicables (JSON). Sinon, applique les regles par defaut de chaque module.
3. **Auditer.** Pour chaque module concerne, suis le skill correspondant (requetes
   `vim_query` MCP contre le modele). Determine `status`, redige un `detail` court et,
   si pertinent, choisis un `ruleId`.
4. **Poster.** `qc_clear_results()` si audit complet, puis un `qc_add_result(...)` par module.
5. **Repondre.** `qc_set_chat_response(...)` : synthese lisible (score, points bloquants,
   actions recommandees). Mentionne que l'utilisateur peut cliquer un module pour voir
   les violations en 3D.

## Regles
- Ne jamais inventer de chiffres : chaque `status`/`count` vient d'une requete reelle.
- `detail` court et actionnable (1-2 phrases). La synthese detaillee va dans `qc_set_chat_response`.
- Un module sans donnees exploitables (ex: georef sans systeme de coordonnees) → `warn`
  avec explication, `ruleId=""`.
- Voir aussi : [[qc-bep-reader]], [[qc-georef]], [[qc-params]], [[qc-ifc-structure]], [[qc-loin]].
