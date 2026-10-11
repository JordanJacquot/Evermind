# Vérifie les rappels : la veille à 20 h, le matin même à 8 h, N minutes avant ; une seule fois chacun, pas de vieux
# rappels au démarrage, rien pour ce qui est déjà fait. Rien ne s'affiche : les alertes sont notées.
#
#   .\outils\tester-rappels.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$Fr = [Globalization.CultureInfo]'fr-FR'
$EnTest = $true
$env:EVERMIND_DONNEES = Join-Path $racine '_test\rappels'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
foreach ($m in 'donnees', 'comprendre', 'alerte') { . (Join-Path $modules "$m.ps1") }
function Get-TitreAffiche([string]$t) { $t }
function Get-Majuscule([string]$t) { if ($t) { $t.Substring(0, 1).ToUpper() + $t.Substring(1) } else { $t } }
$script:Vues = New-Object System.Collections.ArrayList
function Show-Alerte { param($Titre, $Texte, $Etiquette) [void]$script:Vues.Add([pscustomobject]@{ Titre = $Titre; Texte = $Texte; Etiquette = $Etiquette }) }

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}
function Get-Vus([string]$Titre) { , @($script:Vues | Where-Object { $_.Titre -eq $Titre }) }   # (« , » : une liste même pour un seul)

$script:Agenda = New-Object System.Collections.ArrayList
$j = (Get-Date).Date.AddDays(3)   # un jour fixe, dans 3 jours
$den = Add-RendezVous 'Dentiste' $j.AddHours(15) $null 'sante' $false @{ Lieu = '12 rue des Lilas'; APreparer = @('Carte Vitale') }
$ann = Add-RendezVous 'Anniversaire de Léa' $j $null 'anniv' $true @{}
$tot = Add-RendezVous 'Footing' $j.AddHours(7) $null 'sport' $false @{ Rappels = @('matin', 'm30') }
$fait = Add-RendezVous 'Appeler maman' $j.AddHours(11) $null 'rappel' $false @{ Fait = $true }
$sans = Add-RendezVous 'Sieste' $j.AddHours(14) $null 'rdv' $false @{ Rappels = @() }

# La veille à 20 h : le dentiste (défaut : veille, matin, 1 h avant) et l'anniversaire
[void](Invoke-RappelsDus $j.AddDays(-1).AddHours(20).AddSeconds(5))
Test-Cas 'la veille à 20 h : le dentiste' ((Get-Vus 'Dentiste').Count -eq 1 -and (Get-Vus 'Dentiste')[0].Etiquette -match 'demain') "($((Get-Vus 'Dentiste').Etiquette))"
Test-Cas 'la veille à 20 h : l''anniversaire' ((Get-Vus 'Anniversaire de Léa').Count -eq 1)
Test-Cas 'pas de rappel « la veille » pour le footing (pas demandé)' (-not (Get-Vus 'Footing').Count)
Test-Cas 'rien pour une chose déjà faite' (-not (Get-Vus 'Appeler maman').Count)
$attendu = (Get-Majuscule $j.ToString('dddd d MMMM', $Fr)) + ', 15 h'
Test-Cas 'court : juste le jour et l''heure' ((Get-Vus 'Dentiste')[0].Texte -eq $attendu) "($((Get-Vus 'Dentiste')[0].Texte) au lieu de $attendu)"
# 20 secondes plus tard : pas une deuxième fois
[void](Invoke-RappelsDus $j.AddDays(-1).AddHours(20).AddSeconds(25))
Test-Cas 'pas deux fois' ((Get-Vus 'Dentiste').Count -eq 1)
# Le matin même à 8 h : le dentiste et l'anniversaire, pas le footing (à 7 h, déjà commencé)
[void](Invoke-RappelsDus $j.AddHours(8).AddSeconds(5))
Test-Cas 'le matin même : le dentiste' ((Get-Vus 'Dentiste').Count -eq 2)
Test-Cas 'le matin même : l''anniversaire (aujourd''hui)' ((Get-Vus 'Anniversaire de Léa').Count -eq 2 -and (Get-Vus 'Anniversaire de Léa')[1].Etiquette -match "aujourd'hui")
Test-Cas 'pas de « matin même » après le début (footing à 7 h)' (-not @((Get-Vus 'Footing') | Where-Object { $_.Etiquette -notmatch '30 min' }).Count)
# 30 minutes avant le footing
[void](Invoke-RappelsDus $j.AddHours(6).AddMinutes(30).AddSeconds(3))
Test-Cas '30 min avant : le footing' ((Get-Vus 'Footing').Count -eq 1 -and (Get-Vus 'Footing')[0].Etiquette -match 'dans 30 min') "($((Get-Vus 'Footing').Etiquette))"
# 1 h avant le dentiste
[void](Invoke-RappelsDus $j.AddHours(14).AddSeconds(10))
Test-Cas '1 h avant : le dentiste' ((Get-Vus 'Dentiste').Count -eq 3 -and (Get-Vus 'Dentiste')[2].Etiquette -match 'dans 1 h') "($((Get-Vus 'Dentiste').Etiquette -join ' | '))"
Test-Cas 'aucun rappel quand il n''en veut pas' (-not (Get-Vus 'Sieste').Count)
Import-Agenda
$s = @($script:Agenda | Where-Object { $_.Titre -eq 'Sieste' })[0]
Test-Cas '« aucun rappel » gardé après enregistrement' ($s -and $null -ne $s.Rappels -and -not @(Get-RappelsRV $s).Count) "($($s.Rappels | ConvertTo-Json -Compress))"
# Démarrage tardif : un rappel manqué de plus de 2 minutes n'arrive pas en retard
$script:RappelsFaits = @{}; $script:Vues.Clear()
[void](Invoke-RappelsDus $j.AddHours(14).AddMinutes(10))
Test-Cas 'pas de vieux rappel au démarrage' (-not (Get-Vus 'Dentiste').Count)
# Un rendez-vous qui revient : le rappel de la bonne fois
$script:RappelsFaits = @{}; $script:Vues.Clear()
$raid = Add-RendezVous 'Raid' $j.AddHours(21) ([ordered]@{ Type = 'semaine'; Jour = [int]$j.DayOfWeek }) 'jeu' $false @{ Rappels = @('m60') }
[void](Invoke-RappelsDus $j.AddDays(7).AddHours(20).AddSeconds(5))
Test-Cas 'qui revient : 1 h avant la semaine suivante' ((Get-Vus 'Raid').Count -eq 1)
# « dans ... »
$n = [datetime]'2026-10-11 10:00'
Test-Cas 'textes « dans... »' ((Get-TexteDans $n.AddMinutes(25) $n $false) -eq 'dans 25 min' -and (Get-TexteDans $n.AddHours(1) $n $false) -eq 'dans 1 h' -and (Get-TexteDans $n.AddMinutes(90) $n $false) -eq 'dans 1 h 30' -and (Get-TexteDans $n.AddDays(1) $n $false) -eq 'demain' -and (Get-TexteDans $n $n $false) -eq "c'est l'heure") "($(Get-TexteDans $n.AddMinutes(90) $n $false))"

exit $(if ($ok) { 0 } else { 1 })
