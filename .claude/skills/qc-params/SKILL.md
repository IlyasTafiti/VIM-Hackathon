---
name: qc-params
description: Module QC parametres. Detecte les parametres/proprietes manquants ou generiques (types non renommes, valeurs vides) au regard des conventions du BEP. Interroge VIM/DuckDB via vim_query et renvoie status + detail (+ ruleId) a qc-orchestrator. A utiliser pour les questions de parametres / proprietes vides / completude / conventions de nommage.
---

# qc-params

Audit de la completude des parametres et du respect des conventions.

## Ce que tu verifies
1. **Types generiques / non renommes** (signal fort de parametres non renseignes) :
   ```sql
   SELECT COUNT(*) AS n
   FROM Elements e
   WHERE e.domain = 'Physical-Visible'
     AND ( e.familyTypeName LIKE '%Default%' OR e.familyTypeName LIKE '%Generic%'
        OR e.familyName     LIKE '%Default%' OR e.familyName     LIKE '%Generic%' );
   ```
   ruleId associe : `params_generic_type`.
2. **Repartition par categorie** des elements concernes (pour le `detail`) :
   ```sql
   SELECT COALESCE(c.name,'<inconnu>') AS name, COUNT(*) AS count
   FROM Elements e
   LEFT JOIN Categories c ON e.categoryIndex = c.index
   WHERE e.domain='Physical-Visible'
     AND (e.familyTypeName LIKE '%Default%' OR e.familyTypeName LIKE '%Generic%')
   GROUP BY name ORDER BY count DESC;
   ```
3. **Parametres obligatoires du BEP** (`params.required`) : si une propriete requise
   n'existe pas dans le modele, signale-le dans le `detail`.

## Decision
- 0 type generique + tous les parametres requis presents -> `pass`.
- Quelques cas isoles -> `warn`.
- Volume significatif de types generiques / parametres requis manquants -> `fail`
  (ruleId `params_generic_type`).

## Retour a l'orchestrateur
`module="params"`, `status`, `detail` (nb + categories principales), `ruleId`.

Voir aussi : [[qc-orchestrator]], [[qc-bep-reader]].
