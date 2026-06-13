# deploy_sampleplugins.ps1 — Copie les plugins de plugins/ dans SamplePlugins de VIM Flex.
# Cible : C:\Program Files\VIM\VIM Flex\SamplePlugins (necessite des droits administrateur).
# Ecrit un journal lisible par la session.

$src = "C:\Users\Ilyes\Downloads\VIM-Hackathon\plugins"
$dst = "C:\Program Files\VIM\VIM Flex\SamplePlugins"
$log = "C:\Users\Ilyes\Downloads\VIM-Hackathon\deploy_sampleplugins.log"

"Source : $src"  | Out-File $log -Encoding utf8
"Cible  : $dst" | Out-File $log -Append -Encoding utf8

$plugins = Get-ChildItem -Path $src -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "vxp.json") }

foreach ($p in $plugins) {
    $target = Join-Path $dst $p.Name
    try {
        Copy-Item -Path $p.FullName -Destination $target -Recurse -Force -ErrorAction Stop
        "OK   : $($p.Name)" | Out-File $log -Append -Encoding utf8
    } catch {
        "FAIL : $($p.Name) -> $($_.Exception.Message)" | Out-File $log -Append -Encoding utf8
    }
}

"Termine ($($plugins.Count) plugins)." | Out-File $log -Append -Encoding utf8
