#!/usr/bin/env python3
"""
ChatQC bridge — raccordage chatbox VIM <-> Claude local.

Surveille le fichier inbox.json ecrit par le plugin ChatQC dans VIM Flex.
Des qu'une nouvelle question arrive (handled == false), lance `claude -p` en
sous-processus avec le serveur MCP "vim-flex" branche, en utilisant les
credentials de l'ABONNEMENT (env scrubbe de toute cle API). Le Claude headless
analyse la maquette et POUSSE les resultats dans VIM via les outils MCP
(qc_set_chat_response, qc_add_result, qc_select_violations, vim_query).

Pattern du raccordage repris de appels-offres-monitor-Canada
(src/digging/synthesizer.py : _claude_executable / _subscription_env / _run_claude).

Aucun /loop interactif n'est requis : ce demon declenche claude -p par question.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
LOCALAPPDATA = os.environ.get("LOCALAPPDATA", "")
INBOX = Path(LOCALAPPDATA) / "VIM" / "VIM Flex" / "UserPlugins" / "ChatQC" / "inbox.json"
REPO = Path(__file__).resolve().parent

# Bridge stdio<->TCP du serveur MCP de VIM Flex (port 3012 code en dur dedans).
VIM_BRIDGE = os.environ.get(
    "CHATQC_VIM_BRIDGE", r"C:\Program Files\VIM\VIM Flex\mcp-vim-bridge.js")

# Modele a contexte standard (eviter les variantes 1M qui exigent "extra usage").
MODEL = os.environ.get("CHATQC_MODEL", "sonnet")
CLAUDE_TIMEOUT_S = int(os.environ.get("CHATQC_TIMEOUT_S", "240"))
POLL_S = float(os.environ.get("CHATQC_POLL_S", "1.0"))


# --------------------------------------------------------------------------
# Raccordage claude -p (style appels-offres)
# --------------------------------------------------------------------------
def find_claude():
    """Localise le CLI claude. Prefere le .exe natif au wrapper .cmd sous Windows."""
    return (shutil.which("claude.exe")
            or shutil.which("claude")
            or shutil.which("claude.cmd"))


def subscription_env():
    """Copie de l'env scrubbee de toute cle API -> claude -p retombe sur l'abonnement."""
    env = os.environ.copy()
    for key in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
                "ANTHROPIC_BASE_URL", "CLAUDE_API_KEY"):
        env.pop(key, None)
    return env


def write_mcp_config():
    """Ecrit une config MCP temporaire exposant le serveur vim-flex (stdio)."""
    cfg = {"mcpServers": {"vim-flex": {"command": "node", "args": [VIM_BRIDGE]}}}
    fd, path = tempfile.mkstemp(suffix=".json", prefix="chatqc_mcp_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cfg, f)
    return path


def build_prompt(question, bep):
    bep_line = ""
    if bep:
        bep_line = (f'\nUn document d\'exigences (BEP) est lie : "{bep}". '
                    f'Lis-le via la skill qc-bep-reader si la question le justifie.')
    return f"""Tu es l'orchestrateur qualite ChatQC, integre a VIM Flex via le serveur MCP "vim-flex".

ETAPE OBLIGATOIRE D'ABORD : appelle vim_info, puis vim_requirements_met avec le token
retourne dans sa reponse (sinon les autres outils restent bloques).

Outils pour analyser : vim_query (SQL DuckDB sur la maquette), vim_get_loaded_file, etc.
Outils pour POUSSER le resultat dans VIM (c'est le but) :
  - qc_set_chat_response(text)  -> affiche LA reponse dans le chatbox (obligatoire, une seule fois)
  - qc_add_result(module, status, detail, ruleId)  -> module: georef|params|structure|loin ; status: pass|warn|fail
  - qc_select_violations(ruleId)  -> selectionne/isole les violations en 3D

Applique la skill qc-orchestrator en mode RAPIDE : ne lance que les requetes vim_query
strictement necessaires a la question. Termine TOUJOURS par UN SEUL qc_set_chat_response
concis (en francais), et ajoute qc_add_result par module audite si pertinent.{bep_line}

Question de l'utilisateur :
{question}
"""


def run_claude(claude, prompt, mcp_cfg, use_format=True):
    args = [claude, "-p", "--model", MODEL]
    if use_format:
        args += ["--output-format", "text"]
    args += ["--mcp-config", mcp_cfg, "--strict-mcp-config",
             "--dangerously-skip-permissions",
             "--add-dir", str(REPO)]
    return subprocess.run(
        args,
        input=prompt,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=CLAUDE_TIMEOUT_S,
        env=subscription_env(),
        cwd=str(REPO),
    )


# --------------------------------------------------------------------------
# Inbox
# --------------------------------------------------------------------------
def read_inbox():
    try:
        return json.loads(INBOX.read_text(encoding="utf-8"))
    except Exception:
        return None


def claim(data):
    """Marque la question comme prise en charge (anti double-spawn)."""
    data["handled"] = True
    try:
        INBOX.write_text(json.dumps(data, ensure_ascii=False, indent=2),
                         encoding="utf-8")
    except Exception as e:
        print(f"[chatqc] avertissement: impossible de marquer handled: {e}")


def handle_question(claude, mcp_cfg, data):
    qid = data.get("id")
    question = (data.get("question") or "").strip()
    bep = data.get("bep") or ""
    print(f"[chatqc] question #{qid}: {question!r}" + (f"  (BEP: {bep})" if bep else ""))

    claim(data)  # claim AVANT de spawner pour ne pas la retraiter

    t0 = time.time()
    try:
        res = run_claude(claude, build_prompt(question, bep), mcp_cfg, use_format=True)
        # Vieilles versions du CLI : --output-format inconnu -> retry sans.
        if res.returncode != 0 and "output-format" in (res.stderr or ""):
            print("[chatqc] retry sans --output-format")
            res = run_claude(claude, build_prompt(question, bep), mcp_cfg, use_format=False)
    except subprocess.TimeoutExpired:
        print(f"[chatqc] TIMEOUT apres {CLAUDE_TIMEOUT_S}s (question #{qid})")
        return
    except OSError as e:
        print(f"[chatqc] subprocess: {e}")
        return

    dt = round(time.time() - t0, 1)
    if res.returncode != 0:
        print(f"[chatqc] claude -p exit {res.returncode} ({dt}s) | "
              f"stderr={(res.stderr or '').strip()[:500]}")
    else:
        out = (res.stdout or "").strip()
        print(f"[chatqc] OK en {dt}s (stdout {len(out)} car.) — resultats pousses dans VIM via MCP.")


# --------------------------------------------------------------------------
# Boucle principale
# --------------------------------------------------------------------------
def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    claude = find_claude()
    if not claude:
        print("[chatqc] ERREUR : CLI 'claude' introuvable sur le PATH.")
        sys.exit(1)
    if not Path(VIM_BRIDGE).exists():
        print(f"[chatqc] AVERTISSEMENT : bridge vim-flex introuvable : {VIM_BRIDGE}")

    print("[chatqc] ===== ChatQC bridge demarre =====")
    print(f"[chatqc] claude  = {claude}")
    print(f"[chatqc] inbox   = {INBOX}")
    print(f"[chatqc] repo    = {REPO}")
    print(f"[chatqc] modele  = {MODEL}   timeout = {CLAUDE_TIMEOUT_S}s   poll = {POLL_S}s")
    print("[chatqc] En attente de questions du chatbox VIM... (Ctrl+C pour arreter)")

    mcp_cfg = write_mcp_config()
    try:
        while True:
            data = read_inbox()
            if data and not data.get("handled", True) and (data.get("question") or "").strip():
                handle_question(claude, mcp_cfg, data)
            time.sleep(POLL_S)
    except KeyboardInterrupt:
        print("\n[chatqc] arret demande.")
    finally:
        try:
            os.unlink(mcp_cfg)
        except Exception:
            pass


if __name__ == "__main__":
    main()
