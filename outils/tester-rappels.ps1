# Vérifie les rappels : la veille à 20 h, le matin même à 8 h, N minutes avant ; une seule fois chacun, rien pour ce qui
# est déjà fait. Lot 3 : dits à voix haute et gardés à l'écran, rattrapés après la veille du PC ou un PC allumé tard,
# sans doublon après une relance, « Dans 10 min » retenu sur disque. Rien ne s'affiche ni ne parle : tout est noté.
# Revue du 25/10 : « c'est fait » d'une chose qui revient vaut pour une seule fois, rappels « 2 semaines avant »,
# rendez-vous abîmé sans effet sur les autres, changement d'heure (fuseau de Paris imposé, horloge simulée).
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

# ---------------------------------------------------------------------------
# Revue du 25/10, constat 2 : « c'est fait » sur une chose qui revient ne vaut que pour cette fois
# ---------------------------------------------------------------------------
Reset-Memoire
$p0 = (Get-Date).Date.AddDays(-7).AddHours(19)   # mardi dernier (ou le jour qu'il faut), 19 h : la première fois
$pou = Add-RendezVous 'Poubelles' $p0 ([ordered]@{ Type = 'semaine'; Jour = [int]$p0.DayOfWeek }) 'rappel' $false @{}
Set-FaitRV $pou.Id $p0 $true
Test-Cas 'poubelles : cochée pour la première fois seulement' ((Test-FaitRV $pou $p0) -and -not (Test-FaitRV $pou $p0.AddDays(7)) -and -not $pou.Fait) "($($pou.FaitPour -join ', '))"
[void](Invoke-RappelsDus $p0.AddDays(7).AddSeconds(5))
Test-Cas 'poubelles : rappel la semaine suivante' ((Get-Vus 'Poubelles').Count -eq 1)
Reset-Memoire
[void](Invoke-RappelsDus $p0.AddDays(28).AddSeconds(5))
Test-Cas 'poubelles : rappel 4 semaines après' ((Get-Vus 'Poubelles').Count -eq 1)
$av = @(Get-Upcoming | Where-Object { $_.RV.Id -eq $pou.Id })
Test-Cas 'poubelles : dans « à venir »' ($av.Count -eq 1 -and $av[0].Prochain -gt (Get-Date)) "($($av.Prochain))"
Test-Cas 'poubelles : validée cette fois-là seulement' ((Test-Valide $pou $p0) -and -not (Test-Valide $pou $p0.AddDays(7)))
# La fois d'après cochée en avance : « à venir » montre celle d'encore après
Set-FaitRV $pou.Id $av[0].Prochain $true
$av2 = @(Get-Upcoming | Where-Object { $_.RV.Id -eq $pou.Id })
Test-Cas 'poubelles : cochée en avance, « à venir » passe à la suivante' ($av2.Count -eq 1 -and $av2[0].Prochain -eq $av[0].Prochain.AddDays(7)) "($($av2.Prochain))"
# Décocher
Set-FaitRV $pou.Id $p0 $false
Test-Cas 'poubelles : décochée' (-not (Test-FaitRV $pou $p0) -and (Test-FaitRV $pou $av[0].Prochain))
Import-Agenda
$pf = @($script:Agenda | Where-Object { $_.Titre -eq 'Poubelles' })[0]
Test-Cas 'poubelles : gardé dans le fichier' ($pf -and @($pf.FaitPour).Count -eq 1 -and @($pf.FaitPour)[0] -eq (Get-CleFait $av[0].Prochain) -and -not $pf.Fait) "($($pf.FaitPour -join ', '))"
# Les fois cochées de plus de 90 jours sont oubliées
Set-RendezVousDetail $pf.Id 'FaitPour' @('2001-01-01', (Get-CleFait $av[0].Prochain))
Set-FaitRV $pf.Id $p0 $true
$pf = Get-RendezVous $pf.Id
Test-Cas 'poubelles : vieilles fois oubliées' (@($pf.FaitPour) -notcontains '2001-01-01' -and @($pf.FaitPour).Count -eq 2) "($($pf.FaitPour -join ', '))"
# « c'est fait » sans date : la fois en cours ou la dernière en retard, jamais une à venir
Set-RendezVousDetail $pf.Id 'FaitPour' @()
$pf = Get-RendezVous $pf.Id
Test-Cas 'sans date : la dernière en retard' ((Get-FoisAFaire $pf $p0.AddDays(3)) -eq $p0) "($(Get-FoisAFaire $pf $p0.AddDays(3)))"
Test-Cas 'sans date : celle du jour' ((Get-FoisAFaire $pf $p0.AddDays(7).Date.AddHours(9)) -eq $p0.AddDays(7)) "($(Get-FoisAFaire $pf $p0.AddDays(7).Date.AddHours(9)))"
Test-Cas 'sans date : rien avant la première fois' ($null -eq (Get-FoisAFaire $pf $p0.AddDays(-2)))
# Ancien fichier (Fait = oui sur une chose qui revient) : devient « faite pour sa dernière fois passée »
$vieux = [pscustomobject]@{ Id = 'vieux1'; Titre = 'Sortir le verre'; Type = 'rappel'; Journee = $false; Quand = $p0.AddDays(-14).ToString($DateFormat); Repetition = [pscustomobject]@{ Type = 'semaine'; Jour = [int]$p0.DayOfWeek }; Fait = $true }
$mig = ConvertTo-RendezVous $vieux
$derniere = if ((Get-Date) -ge $p0.AddDays(7)) { $p0.AddDays(7) } else { $p0 }
Test-Cas 'ancien « fait » : migré vers la dernière fois passée' (-not $mig.Fait -and @($mig.FaitPour).Count -eq 1 -and @($mig.FaitPour)[0] -eq (Get-CleFait $derniere)) "($($mig.Fait) / $($mig.FaitPour -join ', '))"
[void]$script:Agenda.Add($mig)
Reset-Memoire
[void](Invoke-RappelsDus $derniere.AddDays(7).AddSeconds(5))
Test-Cas 'ancien « fait » : la semaine suivante sonne' ((Get-Vus 'Sortir le verre').Count -eq 1)
$script:Agenda.Remove($mig); Remove-RendezVous $pou.Id

# ---------------------------------------------------------------------------
# Constat 5 : un rappel « 2 semaines avant » (ou 10 jours) sonne, même au delà de 8 jours
# ---------------------------------------------------------------------------
Reset-Memoire
$q5 = (Get-Date).Date.AddDays(40).AddHours(14)
$ctl = Add-RendezVous 'Contrôle technique' $q5 $null 'rdv' $false @{ Rappels = @('m20160') }
$imp = Add-RendezVous 'Impôts' $q5.AddDays(1) $null 'rdv' $false @{ Rappels = @('m14400') }
[void](Invoke-RappelsDus $q5.AddDays(-14).AddSeconds(5))
Test-Cas '2 semaines avant : rappel donné' ((Get-Vus 'Contrôle technique').Count -eq 1)
[void](Invoke-RappelsDus $q5.AddDays(1).AddDays(-10).AddSeconds(5))
Test-Cas '10 jours avant : rappel donné' ((Get-Vus 'Impôts').Count -eq 1)
Remove-RendezVous $ctl.Id; Remove-RendezVous $imp.Id

# ---------------------------------------------------------------------------
# Constat 6 : un rendez-vous abîmé (répétition illisible) ne coupe pas les autres
# ---------------------------------------------------------------------------
Reset-Memoire
$q6 = (Get-Date).Date.AddDays(50).AddHours(10)
$kin6 = Add-RendezVous 'Ostéo' $q6 $null 'sante' $false @{ Rappels = @('m60') }
$abime = Add-RendezVous 'Abîmé' $q6.AddDays(-30) ([ordered]@{ Type = 'semaine'; Jour = 1 }) 'rdv' $false @{}
$abime.Repetition = [pscustomobject]@{ Type = 'semaine'; Jour = 1; Jusqua = 'n''importe quoi' }   # (abîmé après coup)
$erreur6 = $null
try { [void](Invoke-RappelsDus $q6.AddHours(-1).AddSeconds(5)) } catch { $erreur6 = $_ }
Test-Cas 'abîmé : les rappels des autres sont donnés' (-not $erreur6 -and (Get-Vus 'Ostéo').Count -eq 1) "($erreur6)"
$erreur6 = $null
try { $av6 = @(Get-Upcoming); $mois6 = @(Get-AgendaEntre $q6.Date $q6.Date.AddDays(1)) } catch { $erreur6 = $_ }
Test-Cas 'abîmé : « à venir » et le calendrier marchent' (-not $erreur6 -and @($av6 | Where-Object { $_.RV.Titre -eq 'Ostéo' }).Count -eq 1 -and @($mois6 | Where-Object { $_.RV.Titre -eq 'Ostéo' }).Count -eq 1) "($erreur6)"
[void](Invoke-RappelsDus $q6.AddHours(-1).AddSeconds(25))
$lignes6 = @([IO.File]::ReadAllLines($LogFile, [Text.Encoding]::UTF8) | Where-Object { $_ -match "sauté.*$($abime.Id)" })
Test-Cas 'abîmé : noté une seule fois au journal' ($lignes6.Count -eq 1) "($($lignes6.Count) lignes)"
$script:Agenda.Remove($abime); Remove-RendezVous $kin6.Id

# ---------------------------------------------------------------------------
# Constat 21 : changement d'heure (fuseau de Paris, quel que soit celui de la machine)
# ---------------------------------------------------------------------------
$script:FuseauRappels = [TimeZoneInfo]::FindSystemTimeZoneById('Romance Standard Time')
$utc = { param([string]$t) [datetime]::SpecifyKind([datetime]::ParseExact($t, 'yyyy-MM-dd HH:mm:ss', $null), 'Utc') }
Test-Cas 'heure qui n''existe pas : la suivante' ((ConvertTo-UtcRappel ([datetime]'2027-03-28 02:30')) -eq (& $utc '2027-03-28 01:00:00')) "($(ConvertTo-UtcRappel ([datetime]'2027-03-28 02:30')))"
Test-Cas 'heure qui existe deux fois : la première' ((ConvertTo-UtcRappel ([datetime]'2026-10-25 02:30')) -eq (& $utc '2026-10-25 00:30:00')) "($(ConvertTo-UtcRappel ([datetime]'2026-10-25 02:30')))"
# Automne : rendez-vous à 3 h 30, « 1 h avant » = la deuxième 2 h 30 (une vraie heure avant), pas la première
Reset-Memoire
$auto = Add-RendezVous 'Train de nuit' ([datetime]'2026-10-25 03:30') $null 'rdv' $false @{ Rappels = @('m60') }
[void](Invoke-RappelsDus (& $utc '2026-10-25 00:31:00'))
Test-Cas 'automne : rien à la première 2 h 30 (2 h avant)' (-not (Get-Vus 'Train de nuit').Count)
[void](Invoke-RappelsDus (& $utc '2026-10-25 01:31:00'))
Test-Cas 'automne : rappel à la deuxième 2 h 30 (1 h avant)' ((Get-Vus 'Train de nuit').Count -eq 1 -and (Get-Vus 'Train de nuit')[0].Etiquette -match 'dans 59 min|dans 1 h') "($((Get-Vus 'Train de nuit').Etiquette))"
# Printemps : chose à faire à 2 h 30 (heure qui n'existe pas) : donnée à 3 h, pas « manquée »
Reset-Memoire
$prin = Add-RendezVous 'Médicament de nuit' ([datetime]'2027-03-28 02:30') $null 'rappel' $false @{}
[void](Invoke-RappelsDus (& $utc '2027-03-28 00:59:00'))
Test-Cas 'printemps : rien avant 3 h' (-not (Get-Vus 'Médicament de nuit').Count)
[void](Invoke-RappelsDus (& $utc '2027-03-28 01:00:30'))
Test-Cas 'printemps : donnée à 3 h, pas « manquée »' ((Get-Vus 'Médicament de nuit').Count -eq 1 -and (Get-Vus 'Médicament de nuit')[0].Etiquette -ne 'Rappel manqué') "($((Get-Vus 'Médicament de nuit').Etiquette))"
$script:FuseauRappels = $null
Remove-RendezVous $auto.Id; Remove-RendezVous $prin.Id

exit $(if ($ok) { 0 } else { 1 })
