# Vérifie les rappels : la veille à 20 h, le matin même à 8 h, N minutes avant ; une seule fois chacun, rien pour ce qui
# est déjà fait. Lot 3 : dits à voix haute et gardés à l'écran, rattrapés après la veille du PC ou un PC allumé tard,
# sans doublon après une relance, « Dans 10 min » retenu sur disque. Rien ne s'affiche ni ne parle : tout est noté.
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
$script:Dits = New-Object System.Collections.ArrayList
# (remis après chaque relance simulée : alerte.ps1 redéfinit Show-Alerte)
$fauxAffichage = {
    function Show-Alerte { param($Titre, $Texte, $Etiquette, $Type, $RV, $Quand, $Secondes = 9) [void]$script:Vues.Add([pscustomobject]@{ Titre = $Titre; Texte = $Texte; Etiquette = $Etiquette; Secondes = $Secondes }) }
}
. $fauxAffichage
function Invoke-Parole([string]$Texte) { [void]$script:Dits.Add($Texte) }
# Evermind relancé : l'état des rappels relu sur disque, rien gardé en mémoire
function Reset-Memoire { $script:RappelsFaits = @{}; if ($script:ReportsRappels) { $script:ReportsRappels.Clear() }; $script:DernierPassage = $null; $script:Vues.Clear(); $script:Dits.Clear() }

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
# Tout premier démarrage (aucun passage connu) : un rappel vieux de plus de 2 minutes n'arrive pas en retard
Reset-Memoire
[void](Invoke-RappelsDus $j.AddHours(14).AddMinutes(10))
Test-Cas 'premier démarrage : pas de vieux rappel' (-not (Get-Vus 'Dentiste').Count)
# Un rendez-vous qui revient : le rappel de la bonne fois
Reset-Memoire
$raid = Add-RendezVous 'Raid' $j.AddHours(21) ([ordered]@{ Type = 'semaine'; Jour = [int]$j.DayOfWeek }) 'jeu' $false @{ Rappels = @('m60') }
[void](Invoke-RappelsDus $j.AddDays(7).AddHours(20).AddSeconds(5))
Test-Cas 'qui revient : 1 h avant la semaine suivante' ((Get-Vus 'Raid').Count -eq 1)
# « dans ... »
$n = [datetime]'2026-10-11 10:00'
Test-Cas 'textes « dans... »' ((Get-TexteDans $n.AddMinutes(25) $n $false) -eq 'dans 25 min' -and (Get-TexteDans $n.AddHours(1) $n $false) -eq 'dans 1 h' -and (Get-TexteDans $n.AddMinutes(90) $n $false) -eq 'dans 1 h 30' -and (Get-TexteDans $n.AddDays(1) $n $false) -eq 'demain' -and (Get-TexteDans $n $n $false) -eq "c'est l'heure") "($(Get-TexteDans $n.AddMinutes(90) $n $false))"

# ---------------------------------------------------------------------------
# Lot 3 : rappels dits à voix haute et gardés à l'écran, rattrapés après la veille du PC, retenus après une relance
# ---------------------------------------------------------------------------
$relance = { $script:RappelsFaits = @{}; $script:DernierPassage = $null; if ($script:ReportsRappels) { $script:ReportsRappels.Clear() }; . (Join-Path $modules 'alerte.ps1'); . $fauxAffichage; $script:Vues.Clear(); $script:Dits.Clear() }
$k = (Get-Date).Date.AddDays(20)   # un autre jour, loin des rendez-vous du dessus
$kine = Add-RendezVous 'Kiné' $k.AddHours(10) $null 'sante' $false @{}
$phar = Add-RendezVous 'Pharmacie de garde' $k.AddHours(10) $null 'rdv' $false @{ Rappels = @('m60') }

# Muet et effacé au bout de 12 s : il est dit (une seule phrase pour deux rappels) et reste jusqu'à un clic
Reset-Memoire
[void](Invoke-RappelsDus $k.AddHours(9).AddSeconds(5))
Test-Cas 'rappel gardé à l''écran jusqu''à un clic' ((Get-Vus 'Kiné').Count -eq 1 -and (Get-Vus 'Kiné')[0].Secondes -eq 0) "($((Get-Vus 'Kiné').Secondes))"
Test-Cas 'rappel dit à voix haute, une phrase pour deux' ($script:Dits.Count -eq 1 -and $script:Dits[0] -match 'Kiné' -and $script:Dits[0] -match 'Pharmacie de garde' -and $script:Dits[0] -match 'dans 1 h') "($($script:Dits -join ' / '))"
[void](Invoke-RappelsDus $k.AddHours(9).AddSeconds(25))
Test-Cas 'pas redit 20 s plus tard' ($script:Dits.Count -eq 1)
# Pendant un jeu : la carte, mais pas de voix par-dessus le jeu
Reset-Memoire
$script:ModeJeu = $true
[void](Invoke-RappelsDus $k.AddHours(9).AddSeconds(5))
$script:ModeJeu = $false
Test-Cas 'en jeu : rappel affiché mais pas dit' ((Get-Vus 'Kiné').Count -eq 1 -and $script:Dits.Count -eq 0) "($($script:Dits -join ' / '))"

# Le PC dort de 7 h à 15 h 30 : ce qui reste à venir est rattrapé une fois, ce qui est fini ne l'est pas
Reset-Memoire
$banq = Add-RendezVous 'Banque' $k.AddDays(1).AddHours(16) $null 'rdv' $false @{}
$medi = Add-RendezVous 'Prendre les gouttes' $k.AddDays(1).AddHours(13) $null 'rappel' $false @{}
$coif = Add-RendezVous 'Coiffeur' $k.AddDays(1).AddHours(12) $null 'rdv' $false @{}
[void](Invoke-RappelsDus $k.AddDays(1).AddHours(7))
Test-Cas 'avant la veille : rien' (-not (Get-Vus 'Banque').Count)
[void](Invoke-RappelsDus $k.AddDays(1).AddHours(15).AddMinutes(30))
Test-Cas 'réveil du PC : le rendez-vous à venir rattrapé une fois' ((Get-Vus 'Banque').Count -eq 1 -and (Get-Vus 'Banque')[0].Etiquette -match 'dans 30 min') "($((Get-Vus 'Banque').Etiquette -join ' | '))"
Test-Cas 'réveil du PC : la chose à faire manquée' ((Get-Vus 'Prendre les gouttes').Count -eq 1 -and (Get-Vus 'Prendre les gouttes')[0].Etiquette -eq 'Rappel manqué') "($((Get-Vus 'Prendre les gouttes').Etiquette))"
Test-Cas 'réveil du PC : rien pour un rendez-vous déjà passé' (-not (Get-Vus 'Coiffeur').Count)
Test-Cas 'réveil du PC : dit en une fois' ($script:Dits.Count -eq 1 -and $script:Dits[0] -match "Rappel manqué : Prendre les gouttes, c'était à 13 h") "($($script:Dits -join ' / '))"
[void](Invoke-RappelsDus $k.AddDays(1).AddHours(15).AddMinutes(30).AddSeconds(20))
Test-Cas 'réveil du PC : pas deux fois' ((Get-Vus 'Banque').Count -eq 1 -and (Get-Vus 'Prendre les gouttes').Count -eq 1)

# PC éteint le soir, rallumé à 9 h 30 : l'anniversaire du jour arrive quand même (relu sur disque)
Reset-Memoire
$malo = Add-RendezVous 'Anniversaire de Malo' $k.AddDays(3) $null 'anniv' $true @{}
[void](Invoke-RappelsDus $k.AddDays(2).AddHours(20).AddSeconds(10))
[void](Invoke-RappelsDus $k.AddDays(2).AddHours(23))
Test-Cas 'la veille au soir : l''anniversaire' ((Get-Vus 'Anniversaire de Malo').Count -eq 1)
. $relance
Test-Cas 'dernier passage relu sur disque' ($script:DernierPassage -eq $k.AddDays(2).AddHours(23)) "($script:DernierPassage)"
[void](Invoke-RappelsDus $k.AddDays(3).AddHours(9).AddMinutes(30))
Test-Cas 'PC allumé tard : l''anniversaire du jour' ((Get-Vus 'Anniversaire de Malo').Count -eq 1 -and (Get-Vus 'Anniversaire de Malo')[0].Etiquette -match "aujourd'hui") "($((Get-Vus 'Anniversaire de Malo').Etiquette))"

# Éteint plus de 2 jours : une chose à faire tous les jours n'arrive qu'une fois (la dernière)
Reset-Memoire
$arro = Add-RendezVous 'Arroser les tomates' $k.AddDays(4).AddHours(18) ([ordered]@{ Type = 'jour' }) 'rappel' $false @{}
$script:DernierPassage = $k.AddDays(4).AddHours(8)
[void](Invoke-RappelsDus $k.AddDays(7).AddHours(12))
Test-Cas 'longue absence : une seule alerte pour une chose quotidienne' ((Get-Vus 'Arroser les tomates').Count -eq 1 -and $script:Dits[0] -match "c'était hier") "($((Get-Vus 'Arroser les tomates').Count) : $($script:Dits -join ' / '))"
Remove-RendezVous $arro.Id

# Relance juste après un rappel : pas de doublon
Reset-Memoire
$veto = Add-RendezVous 'Vétérinaire' $k.AddDays(9).AddHours(11) $null 'sante' $false @{ Rappels = @('m30') }
[void](Invoke-RappelsDus $k.AddDays(9).AddHours(10).AddMinutes(30).AddSeconds(5))
Test-Cas 'relance : rappel donné' ((Get-Vus 'Vétérinaire').Count -eq 1)
. $relance
[void](Invoke-RappelsDus $k.AddDays(9).AddHours(10).AddMinutes(31))
Test-Cas 'relance : pas de doublon' (-not (Get-Vus 'Vétérinaire').Count)

# « Dans 10 min » puis relance : il revient quand même, une seule fois
Add-ReportRappel $veto $veto.Quand $k.AddDays(9).AddHours(10).AddMinutes(41)
. $relance
[void](Invoke-RappelsDus $k.AddDays(9).AddHours(10).AddMinutes(40).AddSeconds(50))
Test-Cas '« Dans 10 min » : pas avant l''heure' (-not (Get-Vus 'Vétérinaire').Count)
[void](Invoke-RappelsDus $k.AddDays(9).AddHours(10).AddMinutes(41).AddSeconds(10))
Test-Cas '« Dans 10 min » gardé après une relance' ((Get-Vus 'Vétérinaire').Count -eq 1 -and (Get-Vus 'Vétérinaire')[0].Etiquette -match 'dans 19 min' -and $script:Dits.Count -eq 1) "($((Get-Vus 'Vétérinaire').Etiquette))"
[void](Invoke-RappelsDus $k.AddDays(9).AddHours(10).AddMinutes(41).AddSeconds(30))
Test-Cas '« Dans 10 min » : une seule fois' ((Get-Vus 'Vétérinaire').Count -eq 1)
# Reporté puis Evermind fermé jusqu'au lendemain : rien (le rendez-vous est passé)
Add-ReportRappel $veto $veto.Quand $k.AddDays(9).AddHours(10).AddMinutes(55)
. $relance
[void](Invoke-RappelsDus $k.AddDays(10).AddHours(9))
Test-Cas '« Dans 10 min » trop vieux : oublié' (-not (Get-Vus 'Vétérinaire').Count -and -not $script:ReportsRappels.Count)
# Reporté puis supprimé : rien
$plom = Add-RendezVous 'Plombier' $k.AddDays(11).AddHours(15) $null 'rdv' $false @{}
Add-ReportRappel $plom $plom.Quand $k.AddDays(11).AddHours(14).AddMinutes(10)
Remove-RendezVous $plom.Id
[void](Invoke-RappelsDus $k.AddDays(11).AddHours(14).AddMinutes(11))
Test-Cas '« Dans 10 min » d''un rendez-vous supprimé : rien' (-not (Get-Vus 'Plombier').Count -and -not $script:ReportsRappels.Count)

exit $(if ($ok) { 0 } else { 1 })
