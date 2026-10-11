# Vérifie les dossiers reliés aux rendez-vous : retrouver le dossier d'une personne, et l'ouvrir tout seul à l'heure
# (une seule fois, seulement si c'est demandé). Rien n'est ouvert pour de vrai : les ouvertures sont notées.
#
#   .\outils\tester-fichiers.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$Fr = [Globalization.CultureInfo]'fr-FR'
$EnTest = $true
$env:EVERMIND_DONNEES = Join-Path $racine '_test\fichiers'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
$compta = Join-Path $racine '_test\comptabilite-fichiers'
Remove-Item $compta -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in 'Monsieur Richard', 'Madame Dupont', 'Clients 2025\M. Lefèvre', '_test\Monsieur Richard', '.copie\Madame Dupont', 'Comptabilité\Monsieur Martin', 'Juridique\Monsieur Martin') { New-Item -ItemType Directory -Force -Path (Join-Path $compta $d) | Out-Null }
$env:EVERMIND_DOSSIERS = $compta
foreach ($m in 'donnees', 'fichiers', 'comprendre') { . (Join-Path $modules "$m.ps1") }
function Get-TitreAffiche([string]$t) { $t }
$script:Dits = @(); function Invoke-Parole([string]$t) { $script:Dits += $t }
function Show-Notify { }
function Show-Alerte { }
function Get-HeureAlerte { '' }
$script:Ouvertures = New-Object System.Collections.ArrayList
function Open-Fichier([string]$Chemin) { [void]$script:Ouvertures.Add($Chemin); $true }

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}

# 1. Retrouver le dossier d'une personne
foreach ($c in @(@('Monsieur Richard', 'Monsieur Richard'), @('M. Richard', 'Monsieur Richard'), @('Richard', 'Monsieur Richard'), @('Mme Dupont', 'Madame Dupont'), @('Monsieur Lefevre', 'M. Lefèvre'), @('Paul', ''))) {
    $t = Find-DossierPersonne $c[0]
    Test-Cas "dossier de « $($c[0]) »" ($(if ($c[1]) { $t -and (Split-Path $t -Leaf) -eq $c[1] } else { -not $t })) "(trouvé : $t)"
}
# Deux dossiers du même nom : pas de choix au hasard, mais le dossier au-dessus départage (« comptabilité de... »)
foreach ($c in @(@('Monsieur Martin', ''), @('comptabilité de Monsieur Martin', 'Comptabilité'), @('Martin juridique', 'Juridique'))) {
    $t = Find-DossierPersonne $c[0]
    Test-Cas "dossier de « $($c[0]) »" ($(if ($c[1]) { $t -and (Split-Path (Split-Path $t -Parent) -Leaf) -eq $c[1] } else { -not $t })) "(trouvé : $t)"
}
$s = Resolve-Dossiers @('Monsieur Martin', 'Monsieur Personne')
Test-Cas 'dit quand il y a plusieurs dossiers, ou aucun' ($s.Soucis.Count -eq 2 -and $s.Soucis[0] -match 'plusieurs' -and $s.Soucis[1] -match "pas trouvé") "($($s.Soucis -join ' | '))"
$auto = @(Get-DossiersAuto 'réunion' @('Monsieur Richard'))
Test-Cas 'relié tout seul : réunion avec Monsieur Richard' ($auto.Count -eq 1 -and $auto[0] -like '*\Monsieur Richard')
$p = Read-Phrase 'réunion avec Madame Dupont demain à 10 h'
Test-Cas 'phrase : réunion avec Madame Dupont' (@((Get-DossiersAuto $p.Titre $p.Avec)).Count -eq 1)

# 2. Ouverture à l'heure : une fois, seulement si demandé, pas avant l'heure
$script:Agenda = New-Object System.Collections.ArrayList
$now = Get-Date
$a = Add-RendezVous 'Réunion Richard' $now.AddMinutes(-1) $null 'travail' $false @{ Fichiers = @("$compta\Monsieur Richard"); OuvrirAuDebut = $true }
$b = Add-RendezVous 'Réunion Dupont' $now.AddMinutes(-1) $null 'travail' $false @{ Fichiers = @("$compta\Madame Dupont"); OuvrirAuDebut = $false }
$c = Add-RendezVous 'Réunion plus tard' $now.AddMinutes(30) $null 'travail' $false @{ Fichiers = @("$compta\Madame Dupont"); OuvrirAuDebut = $true }
$faits = @(Invoke-OuverturesDues $now)
Test-Cas 'à l''heure : le dossier de Monsieur Richard s''ouvre' ($faits.Count -eq 1 -and $script:Ouvertures.Count -eq 1 -and $script:Ouvertures[0] -like '*\Monsieur Richard') "($($script:Ouvertures -join ', '))"
Test-Cas 'à l''heure : Evermind le dit' (@($script:Dits | Where-Object { $_ -match "J'ouvre le dossier Monsieur Richard" }).Count -eq 1) "($($script:Dits -join ' | '))"
$faits = @(Invoke-OuverturesDues $now.AddSeconds(20))
Test-Cas 'pas deux fois' (-not $faits.Count -and $script:Ouvertures.Count -eq 1)
$faits = @(Invoke-OuverturesDues $now.AddMinutes(30))
Test-Cas '30 minutes plus tard : l''autre réunion s''ouvre' ($faits.Count -eq 1 -and $script:Ouvertures.Count -eq 2)
# Les fichiers sont gardés dans l'agenda enregistré
Import-Agenda
$r = @($script:Agenda | Where-Object { $_.Titre -eq 'Réunion Richard' })[0]
Test-Cas 'enregistré : dossiers et « ouvrir à l''heure »' ($r -and @($r.Fichiers).Count -eq 1 -and $r.OuvrirAuDebut)

exit $(if ($ok) { 0 } else { 1 })
