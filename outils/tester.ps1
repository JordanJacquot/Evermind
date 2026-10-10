# Teste Evermind automatiquement : lance l'app hors de l'écran avec des données à part (_test\donnees),
# vérifie qu'elle démarre sans erreur et enregistre une capture d'écran de la fenêtre.
# Rien n'est modifié sur le PC (ni démarrage avec Windows, ni icône près de l'horloge).
#
#   .\outils\tester.ps1           avec quelques rendez-vous d'exemple
#   .\outils\tester.ps1 -Vide     sans aucun rendez-vous
#
# Code de sortie : 0 si tout est bon, 1 sinon.

param([switch]$Vide, [int]$Delai = 60)
$ErrorActionPreference = 'Stop'
$racine = Split-Path $PSScriptRoot -Parent
$main = Join-Path $racine 'Evermind\fichiers\Evermind.ps1'
$test = Join-Path $racine '_test'
$donnees = Join-Path $test 'donnees'
$capture = Join-Path $test "capture$(if ($Vide) { '-vide' }).png"

if (Test-Path -LiteralPath $donnees) { Remove-Item -LiteralPath $donnees -Recurse -Force }
New-Item -ItemType Directory -Force -Path $donnees | Out-Null
Remove-Item -LiteralPath $capture -ErrorAction SilentlyContinue

# Rendez-vous d'exemple : aujourd'hui, demain, dans quelques jours, un passé (qui ne doit pas s'afficher)
if (-not $Vide) {
    $now = Get-Date
    $f = 'yyyy-MM-ddTHH:mm'
    $ex = @(
        @{ Titre = 'dentiste'; Quand = $now.Date.AddDays(3).AddHours(15) },
        @{ Titre = 'Appeler maman'; Quand = $now.AddHours(2).AddMinutes(-$now.Minute) },
        @{ Titre = 'Raid avec les potes'; Quand = $now.Date.AddDays(1).AddHours(21).AddMinutes(30) },
        @{ Titre = 'Anniversaire de Léa'; Quand = $now.Date.AddDays(40).AddHours(19) },
        @{ Titre = 'Rendez-vous déjà passé'; Quand = $now.AddDays(-2) }
    ) | ForEach-Object { [ordered]@{ Id = [guid]::NewGuid().ToString('N'); Titre = $_.Titre; Quand = $_.Quand.ToString($f); Repetition = $null; Rappels = $null; Cree = (Get-Date -Format s) } }
    [IO.File]::WriteAllText((Join-Path $donnees 'rendez-vous.json'), (ConvertTo-Json -InputObject ([ordered]@{ Version = 1; RendezVous = @($ex) }) -Depth 5), (New-Object Text.UTF8Encoding($false)))
}

Write-Host 'Test d''Evermind en cours, patiente...'
$env:EVERMIND_TEST = '1'
$env:EVERMIND_DONNEES = $donnees
$env:EVERMIND_CAPTURE = $capture
$err = Join-Path $test 'erreurs.txt'
$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$main`"" -PassThru -WindowStyle Hidden -RedirectStandardError $err
if (-not $p.WaitForExit($Delai * 1000)) { $p.Kill(); Write-Host "ÉCHEC : l'app ne s'est pas fermée en $Delai s." -ForegroundColor Red; exit 1 }

$ok = $true
$stderr = if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Raw } else { '' }
if ($stderr -and $stderr.Trim()) {
    Write-Host 'Erreurs PowerShell :' -ForegroundColor Red
    Write-Host ($stderr.Trim() -split "`r?`n" | Select-Object -First 20 | Out-String)
    $ok = $false
}
if (Test-Path -LiteralPath $capture) { Write-Host "Capture : $capture" -ForegroundColor DarkGray }
else { Write-Host 'ÉCHEC : pas de capture, la fenêtre ne s''est pas affichée.' -ForegroundColor Red; $ok = $false }
$journal = Join-Path $donnees 'journal.txt'
if (Test-Path -LiteralPath $journal) { Get-Content -LiteralPath $journal -Encoding UTF8 | ForEach-Object { Write-Host "  journal : $_" -ForegroundColor DarkGray } }

if ($ok) { Write-Host 'Tout est bon.' -ForegroundColor Green; exit 0 }
Write-Host 'Des tests ont échoué.' -ForegroundColor Red
exit 1
