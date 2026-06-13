---
name: qc-loin
description: Module QC LOI/LOIN. Verifie le niveau d'information : proprietes requises presentes par categorie/type selon la phase et le BEP (types non nommes, pieces sans surface, attributs LOIN manquants). Interroge VIM/DuckDB via vim_query et renvoie status + detail (+ ruleId) a qc-orchestrator. A utiliser pour les questions de LOI / LOIN / niveau d'information / proprietes requises.
---

# qc-loin

Audit du niveau d'information (Level of Information Need).

## Ce que tu verifies
1. **Types non nommes** (LOIN insuffisant : objet non specifie) :
   ```sql
   SELECT COUNT(*) AS n
   FROM Elements
   WHERE domain = 'Physical-Visible'
     AND (familyTypeName IS NULL OR familyTypeName = '');
   ```
   ruleId associe : `loin_unnamed_type`.
2. **Pieces sans surface calculee** (donnee LOIN attendue des la phase APS) :
   ```sql
   SELECT COUNT(*) AS n
   FROM Rooms
   WHERE area IS NULL OR area <= 0;
   ```
   ruleId associe : `loin_rooms_no_area`.
3. **Proprietes requises par categorie/phase** (`loin[]` du BEP) : pour chaque entree,
   verifie que les elements de la categorie portent bien les proprietes attendues.
   Decris les manques par categorie dans le `detail`.

## Decision
- Proprietes LOIN requises presentes, types nommes, pieces dimensionnees -> `pass`.
- Quelques manques -> `warn`.
- Manques significatifs -> `fail`. `ruleId` du probleme dominant (`loin_unnamed_type`
  ou `loin_rooms_no_area`).

## Retour a l'orchestrateur
`module="loin"`, `status`, `detail` (categories + proprietes manquantes), `ruleId`.

Voir aussi : [[qc-orchestrator]], [[qc-bep-reader]].
