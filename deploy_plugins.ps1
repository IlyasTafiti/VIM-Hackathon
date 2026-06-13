# deploy_plugins.ps1 — Copie BIMCopilot et PGBAudit dans le UserPlugins de VIM Flex

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = "$env:LOCALAPPDATA\VIM\VIM Flex\UserPlugins"

Write-Host "Source : $source"
Write-Host "Cible  : $target"

# Créer UserPlugins si absent
if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host "Dossier UserPlugins cree."
}

# Copier les plugins
foreach ($plugin in @("BIMCopilot", "PGBAudit")) {
    $src = Join-Path $source $plugin
    $dst = Join-Path $target $plugin
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Recurse -Force
        Write-Host "OK : $plugin copie"
    } else {
        Write-Host "MANQUANT : $src introuvable"
    }
}

Write-Host ""
Write-Host "Deploiement termine. Redemarrez VIM Flex pour charger les plugins."
