# Mode live — répondre vite dans le chatbox ChatQC

Le chatbox VIM écrit chaque question dans `inbox.json`. Comme le MCP est
unidirectionnel (le plugin ne peut pas réveiller Claude), une session Claude doit
**surveiller** ce fichier et répondre. Voici comment la rendre quasi temps réel.

## Pré-requis
- Plugin **ChatQC chargé/compilé** dans VIM (sinon les outils `qc_*` n'existent pas).
- MCP **`vim-flex`** chargé dans la session Claude (redémarrer Claude Code après l'ajout du serveur).

## Handshake `handled` (depuis v2)

`inbox.json` porte desormais un flag `"handled"` :
```json
{ "id": 3, "question": "...", "bep": "", "handled": false }
```
- A l'envoi d'une question -> le plugin ecrit `handled: false`.
- Quand Claude appelle `qc_set_chat_response`, le plugin **reecrit** `handled: true`.

La boucle n'a donc plus besoin de memoriser le dernier id : l'etat est dans le
fichier. Une question est "a traiter" si et seulement si `handled == false`.
C'est robuste a un redemarrage de Claude Code (pas de double-reponse).

## Commande /loop (à coller dans la session Claude)

```
/loop 10s Lis le fichier "%LOCALAPPDATA%\VIM\VIM Flex\UserPlugins\ChatQC\inbox.json".
Si "handled" est false ET "question" non vide :
  1. lis "question" et "bep" ;
  2. applique qc-orchestrator en mode RAPIDE : ne lance que les requetes vim_query
     strictement necessaires a la question (pas d'audit complet si on demande un seul module) ;
  3. reponds en UN SEUL qc_set_chat_response concis ; ajoute qc_add_result par module
     audite si pertinent. (Poster la reponse met automatiquement handled=true.)
Si "handled" est true (ou fichier absent) : ne fais rien, ne re-reponds pas.
```

## Régler la vitesse vs le coût
- `10s` = ressenti quasi live. Chaque tick = 1 tour LLM → consomme des tokens même à vide.
- `5s` = plus réactif, plus coûteux. `30s` = économe, moins « live ».
- Astuce coût : le tick « rien à faire » doit être minimal (juste lire le fichier et comparer l'id, aucune autre action).

## Pourquoi ça paraît instantané côté VIM
Dès l'envoi, le plugin affiche une carte **« Analyse en cours… »** (animée) qui
disparaît à l'arrivée de la réponse via `qc_set_chat_response`. L'utilisateur a un
retour immédiat sans switcher d'application.

## Limite assumée
La latence plancher = l'intervalle du /loop (Claude Code n'est pas un serveur
événementiel ; il ne peut pas être « poussé » par le plugin). Pour du vrai temps
réel < 1 s, il faudrait que le serveur MCP de VIM Flex expose le *sampling* MCP
(non disponible dans l'API `VimMcpService` actuelle).
