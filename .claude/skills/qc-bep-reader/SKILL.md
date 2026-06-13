---
name: qc-bep-reader
description: Lit un document d'exigences BIM (BEP, cahier des charges, convention) au format Word ou PDF et en extrait les regles de controle qualite sous forme de JSON structure exploitable par qc-orchestrator et les skills de module. A utiliser quand un chemin de document BEP est fourni dans la question ou l'inbox ChatQC.
---

# qc-bep-reader

Transforme un document d'exigences en regles QC exploitables.

## Entree
Un chemin de fichier (fourni dans `inbox.json` -> `bep`, ou directement). Formats :
`.docx`, `.doc`, `.pdf`. Si absent ou illisible, signale-le et laisse l'orchestrateur
appliquer les regles par defaut.

## Methode
1. Lis le document (Read pour .pdf/texte ; pour .docx, extrais le texte — convertis si besoin).
2. Repere les sections pertinentes : georeferencement / systeme de coordonnees / unites ;
   conventions de nommage (familles, types, fichiers) ; parametres/proprietes obligatoires ;
   organisation (worksets, niveaux, phases) ; LOI/LOIN par categorie ou par phase.
3. Extrais des regles atomiques et verifiables. Ignore le bla-bla non testable.

## Sortie (JSON)
```json
{
  "georef":    { "crs": "RGF93 / Lambert-93", "units": "m", "notes": "Point de base partage obligatoire" },
  "naming":    { "pattern": "DIS_TYPE_NIV", "forbidden": ["Default", "Generic"] },
  "params":    { "required": ["Code_Objet", "Materiau", "Niveau"] },
  "structure": { "worksets_required": true, "levels_required": true },
  "loin": [
    { "category": "Murs",     "phase": "DCE", "properties": ["Resistance_Feu", "Epaisseur"] },
    { "category": "Fenetres", "phase": "DCE", "properties": ["Uw", "Dimensions"] }
  ]
}
```

## Regles
- Ne retourne que ce qui est reellement dans le document ; ne pas halluciner d'exigences.
- Si une section est absente, omets la cle (l'orchestrateur utilisera ses defauts).
- Cite la section/page source dans `notes` quand c'est utile a la tracabilite.
- Voir aussi : [[qc-orchestrator]].
