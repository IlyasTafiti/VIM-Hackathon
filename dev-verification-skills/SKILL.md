---
name: qc-params
description: Module QC parametres. Detecte les parametres/proprietes manquants ou generiques (types non renommes, valeurs vides) au regard des conventions du BEP Snowdon (SNW_CODE_GMAO, GBQ_CODE, Uniformat II, Pset_GBQ_Exploitation). Interroge VIM/DuckDB via vim_query et renvoie status + detail (+ ruleId) a qc-orchestrator. A utiliser pour les questions de parametres / proprietes vides / completude / conventions de nommage / CODE_GMAO.
---

# qc-params

Audit de la complétude des paramètres — **projet Snowdon**.

## Exigences de référence (CdC §2.1.7, §5.5 + PEB §7.2.2, §7.2.3)

### Paramètre critique : SNW_CODE_GMAO
**Format obligatoire :** `GBQ_<Code Uniformat II niveau 3>`
**Exemples valides :** `GBQ_D3040` (CVC), `GBQ_D5020` (éclairage), `GBQ_D2010` (sanitaires)
**Export IFC :** dans `Pset_GBQ_Exploitation`
**Catégories concernées :** Équipements mécaniques, Appareils sanitaires, Équipements électriques, Luminaires, Terminaux (diffuseurs, gicleurs)
Toute valeur ne commençant pas par `GBQ_` est **non exploitable par la GMAO**.

### Paramètre : SNW_Code_Uniformat
Code Uniformat II niveau 3 minimum sur **tous** les objets physiques.
Export IFC via `IfcClassificationReference`.

### Paramètre : SNW_Resistance_Au_Feu
Export IFC dans `Pset_SNW_Securite` (pas dans le champ natif IFC `FireRating`).

### Paramètres maintenance (jalon Réception)
`SNW_Fabricant`, `SNW_Modele`, `SNW_Date_Installation`, `SNW_Garantie` — priorité CVC et électricité principaux.
⚠️ PEB §7.8.1 signale des valeurs incomplètes sur mobilier fixe et équipements terminaux au jalon Réception.

## Ce que tu vérifies

### 1. Types génériques / non renommés (signal fort de paramètres non renseignés)

```sql
SELECT COUNT(*) AS n
FROM Elements e
WHERE e.domain = 'Physical-Visible'
  AND ( e.familyTypeName LIKE '%Default%' OR e.familyTypeName LIKE '%Generic%'
     OR e.familyName     LIKE '%Default%' OR e.familyName     LIKE '%Generic%' );
```

ruleId associé : `params_generic_type`.

### 2. Répartition par catégorie des éléments génériques

```sql
SELECT COALESCE(c.name, '<inconnu>') AS name, COUNT(*) AS count
FROM Elements e
LEFT JOIN Categories c ON e.categoryIndex = c.index
WHERE e.domain = 'Physical-Visible'
  AND (e.familyTypeName LIKE '%Default%' OR e.familyTypeName LIKE '%Generic%'
    OR e.familyName     LIKE '%Default%' OR e.familyName     LIKE '%Generic%')
GROUP BY name ORDER BY count DESC LIMIT 10;
```

### 3. Paramètres obligatoires du BEP (`params.required` de qc-bep-reader)

Si `qc-bep-reader` a fourni une liste `params.required`, vérifier par échantillonnage (10 éléments aléatoires) que ces paramètres sont présents :

```sql
SELECT e.index, e.familyName, COUNT(p.index) as nb_params
FROM Elements e
LEFT JOIN Parameters p ON p.elementIndex = e.index
WHERE e.domain = 'Physical-Visible'
GROUP BY e.index, e.familyName
ORDER BY RANDOM() LIMIT 10;
```

### 4. Vérification CODE_GMAO sur équipements (si paramètre accessible)

```sql
SELECT COALESCE(c.name, '<inconnu>') AS Category,
       COUNT(*) AS nb_sans_params
FROM Elements e
LEFT JOIN Categories c ON e.categoryIndex = c.index
WHERE e.domain = 'Physical-Visible'
  AND c.name IN ('Mechanical Equipment', 'Electrical Equipment',
                 'Lighting Fixtures', 'Plumbing Fixtures', 'Air Terminals')
  AND NOT EXISTS (
    SELECT 1 FROM Parameters p
    JOIN ParameterDescriptors pd ON p.descriptorIndex = pd.index
    WHERE p.elementIndex = e.index AND pd.name = 'SNW_CODE_GMAO'
  )
GROUP BY c.name ORDER BY nb_sans_params DESC;
```

## Décision

| Situation | Status | ruleId |
|-----------|--------|--------|
| 0 type générique + paramètres requis présents | `pass` | `""` |
| Quelques cas isolés (< 5% des éléments) | `warn` | `params_generic_type` |
| Volume significatif de génériques / paramètres requis manquants | `fail` | `params_generic_type` |
| CODE_GMAO absent ou mal formaté sur équipements | `fail` | `params_generic_type` |

## Retour à l'orchestrateur

```
module  = "params"
status  = "pass" | "warn" | "fail"
detail  = ex: "312 éléments avec type générique (Walls 180, Doors 132). SNW_CODE_GMAO absent sur 45 équipements CVC."
ruleId  = "params_generic_type" ou ""
```

Voir aussi : [[qc-orchestrator]], [[qc-bep-reader]].
