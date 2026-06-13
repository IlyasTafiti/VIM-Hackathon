---
name: qc-ifc-structure
description: Module QC structure IFC. Verifie l'organisation du modele VIM : rattachement aux worksets et aux niveaux, hierarchie et nommage des familles/types. Interroge VIM/DuckDB via vim_query et renvoie status + detail (+ ruleId) a qc-orchestrator. A utiliser pour les questions de structure / worksets / niveaux / nommage de familles / hierarchie IFC.
---

# qc-ifc-structure

Audit de la structure et de l'organisation du modele.

## Ce que tu verifies
1. **Elements sans workset** :
   ```sql
   SELECT COUNT(*) AS n
   FROM Elements
   WHERE domain = 'Physical-Visible' AND worksetIndex IS NULL;
   ```
   ruleId associe : `structure_no_workset`.
2. **Elements sans niveau** :
   ```sql
   SELECT COUNT(*) AS n
   FROM Elements
   WHERE domain = 'Physical-Visible' AND levelIndex IS NULL;
   ```
   ruleId associe : `structure_no_level`.
3. **Worksets / niveaux presents** et conformes au BEP (`structure.worksets_required`,
   `structure.levels_required`, conventions de nommage `naming.pattern`) :
   ```sql
   SELECT name FROM Worksets ORDER BY name;
   SELECT name, elevation FROM Levels ORDER BY elevation;
   ```

## Decision
- Tous les elements rattaches (workset + niveau) et organisation conforme -> `pass`.
- Manques mineurs -> `warn`.
- Elements non rattaches en volume, ou worksets/niveaux requis absents -> `fail`.
  Choisis le `ruleId` du probleme dominant (`structure_no_workset` ou `structure_no_level`).

## Retour a l'orchestrateur
`module="structure"`, `status`, `detail` (ce qui manque, combien), `ruleId`.

Voir aussi : [[qc-orchestrator]], [[qc-bep-reader]].
