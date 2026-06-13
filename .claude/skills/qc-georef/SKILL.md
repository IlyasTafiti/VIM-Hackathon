---
name: qc-georef
description: Module QC georeference. Verifie le systeme de coordonnees, les unites et la coherence spatiale du modele VIM charge (elements hors-niveau, positions aberrantes). Interroge VIM/DuckDB via vim_query et renvoie status + detail (+ ruleId) a qc-orchestrator. A utiliser pour les questions de georeferencement / coordonnees / projection / point de base.
---

# qc-georef

Audit du georeferencement et de la coherence spatiale.

## Ce que tu verifies
1. **Systeme de coordonnees / unites** — depuis les metadonnees du modele (`BimDocuments`)
   et le BEP (`qc-bep-reader` -> `georef.crs`, `georef.units`). VIM/DuckDB n'expose pas
   toujours le CRS : si indisponible, status `warn` avec explication, `ruleId=""`.
2. **Elements sans niveau** (proxy de mauvais rattachement spatial) :
   ```sql
   SELECT COUNT(*) AS n
   FROM Elements
   WHERE domain = 'Physical-Visible' AND levelIndex IS NULL;
   ```
   ruleId associe : `structure_no_level`.
3. **Documents lies / origines multiples** (incoherence de georef entre maquettes) :
   ```sql
   SELECT title, isLinked FROM BimDocuments;
   ```

## Decision
- 0 element hors-niveau + CRS/unites conformes au BEP -> `pass`.
- CRS/unites inconnus ou non verifiables -> `warn`.
- Elements hors-niveau presents, ou CRS/unites non conformes -> `fail` (ruleId `structure_no_level`).

## Retour a l'orchestrateur
`module="georef"`, `status`, `detail` (1-2 phrases concretes : ce qui manque, combien),
`ruleId` (`structure_no_level` ou `""`).

Voir aussi : [[qc-orchestrator]], [[qc-bep-reader]].
