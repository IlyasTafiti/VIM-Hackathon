# deploy_plugins.ps1 — Copie les plugins de plugins/ dans le UserPlugins de VIM Flex
#
# Deploie automatiquement chaque sous-dossier de plugins/ contenant un vxp.json
# (BIMCopilot, PGBAudit, Demo, CostDraft, ChatQC, ...).

$source     = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginsDir = Join-Path $source "plugins"
$target     = "$env:LOCALAPPDATA\VIM\VIM Flex\UserPlugins"

Write-Host "Source : $pluginsDir"
Write-Host "Cible  : $target"

if (-not (Test-Path $pluginsDir)) {
    Write-Host "ERREUR : dossier plugins/ introuvable."
    exit 1
}

# Creer UserPlugins si absent
if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host "Dossier UserPlugins cree."
}

# Copier chaque plugin (sous-dossier contenant un vxp.json)
$plugins = Get-ChildItem -Path $pluginsDir -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "vxp.json") }

foreach ($plugin in $plugins) {
    $dst = Join-Path $target $plugin.Name
    Copy-Item -Path $plugin.FullName -Destination $dst -Recurse -Force
    Write-Host "OK : $($plugin.Name) copie"
}

if ($plugins.Count -eq 0) {
    Write-Host "MANQUANT : aucun plugin (vxp.json) trouve dans plugins/"
}

Write-Host ""
Write-Host "Deploiement termine ($($plugins.Count) plugins). Redemarrez VIM Flex pour charger les plugins."
