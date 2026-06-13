# Tests

Scénarios et jeux de test pour le contrôle qualité ChatQC.

Y placer :
- **Scénarios QC** — questions types et résultats attendus par module
  (`georef`, `params`, `structure`, `loin`).
- **Cas de référence** — extraits de modèles `ifc/` avec violations connues, pour
  valider les requêtes SQL des skills (`qc-*`) et la sélection 3D du plugin.
- **Fixtures** — exemples d'`inbox.json` et de réponses MCP attendues.

> Il n'existe pas de compilateur AngelScript hors-ligne : la validation du plugin
> se fait via `vim_compile` (MCP) sur un modèle chargé. Documenter ici la
> procédure de test manuel de chaque module.
