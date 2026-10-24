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

# 3. Rendez-vous sur plusieurs jours : les dossiers s'ouvrent au début seulement, pas à minuit les jours suivants
$script:Agenda = New-Object System.Collections.ArrayList; $script:Ouverts = @{}; $script:Ouvertures.Clear(); $script:Dits = @()
$j = (Get-Date).Date.AddDays(3)
$v = Add-RendezVous 'Salon de l''auto' $j.AddHours(9) $null 'rdv' $false @{ Fichiers = @("$compta\Monsieur Richard"); OuvrirAuDebut = $true }
$v.Fin = $j.AddDays(2).AddHours(18)
$faits = @(Invoke-OuverturesDues $j.AddHours(9))
Test-Cas 'plusieurs jours : ouvert au début' ($faits.Count -eq 1 -and $script:Ouvertures.Count -eq 1)
$faits = @(Invoke-OuverturesDues $j.AddDays(1).AddSeconds(30))
Test-Cas 'plusieurs jours : rien à minuit le 2e jour' (-not $faits.Count -and $script:Ouvertures.Count -eq 1) "($($script:Ouvertures.Count) ouverture(s))"
$faits = @(Invoke-OuverturesDues $j.AddDays(2).AddMinutes(1))
Test-Cas 'plusieurs jours : rien à minuit le dernier jour' (-not $faits.Count -and $script:Ouvertures.Count -eq 1)
# Un rendez-vous qui revient chaque jour s'ouvre bien chaque jour (lui n'est pas « sur plusieurs jours »)
$script:Agenda = New-Object System.Collections.ArrayList; $script:Ouverts = @{}; $script:Ouvertures.Clear()
[void](Add-RendezVous 'Point du matin' $j.AddHours(8.5) ([pscustomobject]@{ Type = 'jour' }) 'travail' $false @{ Fichiers = @("$compta\Madame Dupont"); OuvrirAuDebut = $true })
[void](Invoke-OuverturesDues $j.AddHours(8.5)); [void](Invoke-OuverturesDues $j.AddDays(1).AddHours(8.5))
Test-Cas 'chaque jour : ouvert chaque jour' ($script:Ouvertures.Count -eq 2) "($($script:Ouvertures.Count) ouverture(s))"

# 4. Pendant un jeu en plein écran : le rappel est donné, les dossiers attendent la fin du jeu
$script:Agenda = New-Object System.Collections.ArrayList; $script:Ouverts = @{}; $script:Ouvertures.Clear(); $script:Dits = @()
$g = Add-RendezVous 'Réunion Dupont' $j.AddHours(14) $null 'travail' $false @{ Fichiers = @("$compta\Madame Dupont"); OuvrirAuDebut = $true }
$h = Add-RendezVous 'Appel Richard' $j.AddHours(14) $null 'travail' $false @{ Fichiers = @("$compta\Monsieur Richard"); OuvrirAuDebut = $true }
$script:ModeJeu = $true
$faits = @(Invoke-OuverturesDues $j.AddHours(14))
Test-Cas 'en jeu : rien ne s''ouvre' ($faits.Count -eq 2 -and $script:Ouvertures.Count -eq 0) "($($script:Ouvertures -join ', '))"
Test-Cas 'en jeu : Evermind dit qu''il ouvrira après' (@($script:Dits | Where-Object { $_ -match "J'ouvrirai .* à la fin de ton jeu" }).Count -eq 2) "($($script:Dits -join ' | '))"
[void](Invoke-OuverturesDues $j.AddHours(14).AddMinutes(1))
Test-Cas 'toujours en jeu : rien ne s''ouvre' ($script:Ouvertures.Count -eq 0)
[void]$script:Agenda.Remove($h)   # supprimé pendant le jeu : il ne s'ouvrira pas
$script:ModeJeu = $false
[void](Invoke-OuverturesDues $j.AddHours(16))
Test-Cas 'jeu fini : le dossier s''ouvre (une fois)' ($script:Ouvertures.Count -eq 1 -and $script:Ouvertures[0] -like '*\Madame Dupont') "($($script:Ouvertures -join ', '))"
[void](Invoke-OuverturesDues $j.AddHours(16).AddSeconds(15))
Test-Cas 'jeu fini : pas deux fois' ($script:Ouvertures.Count -eq 1)

exit $(if ($ok) { 0 } else { 1 })
