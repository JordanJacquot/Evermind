# Vérifie qu'Evermind ne perd jamais de rendez-vous : fichier abîmé (repris de sa sauvegarde ou mis de côté), rendez-vous
# illisible gardé dans le fichier, répétition « tous les 2 jours » gardée par le formulaire, réponse de l'assistant
# appliquée par différences (avec un faux assistant), « annule » après une suppression faite à la main.
# Revue du 25/10 : répétition abîmée gardée de côté et signalée, changement pas enregistré défait en mémoire, fichier
# pris par un autre programme (lecture seule, jamais la bonne version écrasée), « c'est fait » dit à l'assistant.
# Rien ne s'affiche et rien ne touche au vrai PC : un dossier de test, des fenêtres remplacées par des faux.
#
#   .\outils\tester-donnees.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
Add-Type -AssemblyName PresentationFramework
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$Fr = [Globalization.CultureInfo]'fr-FR'
$EnTest = $true
$env:EVERMIND_DONNEES = Join-Path $racine '_test\donnees-surete'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
foreach ($m in 'donnees', 'fichiers', 'comprendre', 'agenda', 'details', 'cerveau') { . (Join-Path $modules "$m.ps1") }

# Sans fenêtre : ce qu'Evermind dirait ou montrerait est seulement retenu
$Colors = @{ ok = '#3DDC97'; bad = '#FF5C7A'; accent = '#00E5FF'; dim = '#8A84A3' }
$script:Dit = ''; $script:Montre = ''
function Invoke-Parole([string]$Texte) { $script:Dit = $Texte }
function Show-FormMessage([string]$Text) { $script:Montre = $Text }
function Show-FMessage([string]$Text) { $script:Montre = $Text }
function Show-Bulle { }
function Set-VoixEtat { }
function Show-MainWindow { }
function Update-Agenda { }
function Select-JourCalendrier { }
function Update-FCalendrier { }
function Update-FHeureInfo { }
function Update-FDetailsVisibles { }
function Update-FFinInfo { }
function Set-FDetails { }
function Read-FDetails { @{ Detail = @{} } }
function Set-FType([string]$Type) { $script:FType = $Type }
function Set-FJournee([bool]$On) { $script:FJournee = $On }
$script:CerveauDemande = $false
function Start-Cerveau { $script:CerveauDemande = $true; $false }
function New-Faux { $o = [pscustomobject]@{ Text = ''; Tag = $null; Visibility = ''; Content = ''; IsDefault = $false; Foreground = $null }; $o | Add-Member ScriptMethod Focus { $true }; $o }
$ui = @{ InPhrase = New-Object System.Windows.Controls.TextBox; FTitre = New-Object System.Windows.Controls.TextBox; FHeure = New-Object System.Windows.Controls.TextBox }
foreach ($n in 'FRepUne', 'FRepJour', 'FRepSemaine', 'FRepMois', 'FRepAn', 'FDernierPanel', 'FormTitre', 'BtnFEnregistrer', 'BtnAjouter', 'FMessage', 'Formulaire') { $ui[$n] = New-Faux }

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}
function Get-RV([string]$Titre) { , @($script:Agenda | Where-Object { $_.Titre -eq $Titre }) }   # (« , » : une liste même pour un seul)
function Get-Fichier { [IO.File]::ReadAllText($AgendaFile, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function Reset-Agenda {
    foreach ($f in @(Get-ChildItem -LiteralPath $env:EVERMIND_DONNEES -Filter 'rendez-vous.json*')) { Remove-Item -LiteralPath $f.FullName -Force }
    Import-Agenda
    $script:Annulations = $null
}
$j = (Get-Date).Date.AddDays(3)

# --- 1. Fichier abîmé
Reset-Agenda
[void](Add-RendezVous 'Dentiste' $j.AddHours(15) $null 'sante')
[void](Add-RendezVous 'Foot' $j.AddHours(19) $null 'sport')
[IO.File]::WriteAllText($AgendaFile, '')   # coupé net (panne pendant l'écriture)
Import-Agenda
Test-Cas 'fichier vide : repris de sa sauvegarde' ((Get-RV 'Dentiste').Count -eq 1) "($(@($script:Agenda).Count) rendez-vous)"
Test-Cas 'fichier vide : mis de côté (.abime)' (@(Get-ChildItem -LiteralPath $env:EVERMIND_DONNEES -Filter 'rendez-vous.json.abime-*').Count -ge 1)
Reset-Agenda
[IO.File]::WriteAllText($AgendaFile, '{ "Version": 2, "RendezVous": [ {"Id": "x"')
[IO.File]::WriteAllText("$AgendaFile.bak", 'pas du json')
Import-Agenda
$abimes = @(Get-ChildItem -LiteralPath $env:EVERMIND_DONNEES -Filter '*.abime-*')
Test-Cas 'fichier et sauvegarde abîmés : les deux mis de côté' ($abimes.Count -ge 2 -and @($script:Agenda).Count -eq 0) "($($abimes.Name -join ', '))"
Test-Cas 'fichier abîmé : noté au journal' ([IO.File]::ReadAllText($LogFile, [Text.Encoding]::UTF8) -match 'Fichier abîmé mis de côté')

# --- 2. Un rendez-vous illisible reste dans le fichier
Reset-Agenda
$q = $j.AddHours(10).ToString($DateFormat)
[IO.File]::WriteAllText($AgendaFile, "{ ""Version"": 2, ""RendezVous"": [ { ""Id"": ""a1"", ""Titre"": ""Coiffeur"", ""Type"": ""rdv"", ""Quand"": ""$q"" }, { ""Id"": ""b2"", ""Titre"": ""Mariage de Paul"", ""Type"": ""rdv"", ""Quand"": ""le 12 mai"" } ] }", $Utf8NoBom)
Import-Agenda
Test-Cas 'rendez-vous illisible : pas affiché' (@($script:Agenda).Count -eq 1)
[void](Add-RendezVous 'Garage' $j.AddHours(9) $null 'rdv')
$f = Get-Fichier
$mariage = @($f.RendezVous | Where-Object { $_.Id -eq 'b2' })
Test-Cas 'rendez-vous illisible : gardé tel quel à la sauvegarde' ($mariage.Count -eq 1 -and $mariage[0].Quand -eq 'le 12 mai' -and @($f.RendezVous).Count -eq 3) "($(@($f.RendezVous).Count) dans le fichier)"
Import-Agenda; Remove-RendezVous (Get-RV 'Garage')[0].Id
Test-Cas 'rendez-vous illisible : toujours là après une suppression' (@((Get-Fichier).RendezVous | Where-Object { $_.Id -eq 'b2' }).Count -eq 1)

# --- 3. Formulaire : « tous les 2 jours » gardé
Reset-Agenda
$med = Add-RendezVous 'Médicaments' $j.AddHours(8) ([ordered]@{ Type = 'jour'; Intervalle = 2; Jusqua = $j.AddDays(60).ToString('yyyy-MM-dd') }) 'rappel'
Open-Formulaire -RV $med
Test-Cas 'formulaire : « Tous les jours » choisi à l''ouverture' ($script:FRepet -eq 'jour' -and $ui.FRepJour.Tag -eq 'on' -and $ui.FRepUne.Tag -ne 'on') "(choisi : $($script:FRepet))"
$ui.FTitre.Text = 'Médicaments du matin'
Save-Formulaire
$r = (Get-RV 'Médicaments du matin')[0]
Test-Cas 'formulaire : la répétition reste après une modification' ($r -and $r.Repetition.Type -eq 'jour' -and [int]$r.Repetition.Intervalle -eq 2 -and $r.Repetition.Jusqua -eq $j.AddDays(60).ToString('yyyy-MM-dd')) "($($r.Repetition | ConvertTo-Json -Compress))"
Import-Agenda
$r = (Get-RV 'Médicaments du matin')[0]
Test-Cas 'formulaire : la répétition est bien enregistrée' ($r -and $r.Repetition.Type -eq 'jour' -and [int]$r.Repetition.Intervalle -eq 2)
Open-Formulaire -Jour $j
$ui.FTitre.Text = 'Vitamines'; $ui.FHeure.Text = '9 h'
Set-FRepet 'jour'
Save-Formulaire
$r = (Get-RV 'Vitamines')[0]
Test-Cas 'formulaire : nouveau rendez-vous « Tous les jours »' ($r -and $r.Repetition.Type -eq 'jour') "($($r.Repetition | ConvertTo-Json -Compress))"

# --- 4. « annule » après une suppression faite à la main (comme le bouton Supprimer)
Reset-Agenda
$den = Add-RendezVous 'Dentiste' $j.AddHours(15) $null 'sante'
Save-Annulation; Remove-RendezVous $den.Id
Test-Cas '« annule le dentiste » n''est pas « annule »' (-not (Test-AnnuleTexte 'annule le dentiste') -and (Test-AnnuleTexte 'Annule.') -and (Test-AnnuleTexte 'tu peux annuler ça ?') -and (Test-AnnuleTexte 'reviens en arrière'))
$script:CerveauDemande = $false
[void](Invoke-Commande 'annule' 'barre')
Test-Cas '« annule » remet le rendez-vous supprimé à la main' ((Get-RV 'Dentiste').Count -eq 1 -and $script:Montre -match 'annulé') "($($script:Montre))"
Test-Cas '« annule » ne passe pas par l''assistant' (-not $script:CerveauDemande)
Test-Cas '« annule » enregistré dans le fichier' (@((Get-Fichier).RendezVous | Where-Object { $_.Titre -eq 'Dentiste' }).Count -eq 1)
[void](Invoke-AnnuleTexte 'annule' 'voix')
Test-Cas 'plus rien à annuler : il le dit' ($script:Dit -match 'rien à annuler')

# --- 5. La réponse de l'assistant : seulement ses différences (faux assistant)
function New-Reponse($Agenda, [string]$Ecrit = 'C''est fait.') { [pscustomobject]@{ compris = $true; dit = $Ecrit; ecrit = $Ecrit; change = $true; aCorriger = $null; agenda = @($Agenda) } }
function Get-Envoye { ConvertTo-Json -InputObject @(Get-AgendaDonnees) -Depth 8 -Compress }
Reset-Agenda
$den = Add-RendezVous 'Dentiste' $j.AddHours(15) $null 'sante'
$foot = Add-RendezVous 'Foot' $j.AddHours(19) $null 'sport'
$raid = Add-RendezVous 'Raid' $j.AddHours(21) ([ordered]@{ Type = 'semaine'; Jour = [int]$j.DayOfWeek }) 'jeu'
$envoye = Get-Envoye
# Pendant qu'il réfléchit : un rendez-vous ajouté à la main, un lieu changé à la main
[void](Add-RendezVous 'Coiffeur' $j.AddHours(10) $null 'rdv')
Set-RendezVousDetail $den.Id 'Notes' 'Carte Vitale'
Set-RendezVousDetail $foot.Id 'Lieu' 'Stade'
# Sa réponse : le dentiste décalé d'un jour, une piscine ajoutée (le reste comme on le lui a envoyé)
$recu = @(ConvertFrom-Json $envoye | ForEach-Object { $_ })
($recu | Where-Object { $_.Id -eq $den.Id }).Quand = $j.AddDays(1).AddHours(15).ToString($DateFormat)
$recu += [pscustomobject]@{ Id = 'nouveau1'; Titre = 'Piscine'; Type = 'sport'; Journee = $false; Quand = $j.AddHours(18).ToString($DateFormat); Fin = $null; Repetition = $null; Lieu = ''; Avec = @(); Lien = ''; Notes = ''; APreparer = @(); Rappels = $null; Important = $false; Fait = $false; Naissance = $null; Fichiers = @(); OuvrirAuDebut = $false; Cree = '2026-10-24T10:00:00' }
Invoke-ReponseAssistant (New-Reponse $recu 'Le dentiste passe au lendemain.') 'décale le dentiste à demain et ajoute piscine' 'barre' $envoye
$d = (Get-RV 'Dentiste')[0]
Test-Cas 'assistant : son changement est fait' ($d.Quand -eq $j.AddDays(1).AddHours(15)) "($($d.Quand))"
Test-Cas 'assistant : son ajout est fait' ((Get-RV 'Piscine').Count -eq 1)
Test-Cas 'assistant : le rendez-vous ajouté à la main entre-temps reste' ((Get-RV 'Coiffeur').Count -eq 1)
Test-Cas 'assistant : les détails changés à la main entre-temps restent' ($d.Notes -eq 'Carte Vitale' -and (Get-RV 'Foot')[0].Lieu -eq 'Stade') "(notes : $($d.Notes), lieu : $((Get-RV 'Foot')[0].Lieu))"
Test-Cas 'assistant : la répétition du raid est intacte' ((Get-RV 'Raid')[0].Repetition.Type -eq 'semaine')
# « annule » défait sa dernière action, sans effacer ce qui a été fait à la main avant
[void](Invoke-AnnuleTexte 'annule' 'barre')
Test-Cas '« annule » après l''assistant : son changement défait' ((Get-RV 'Dentiste')[0].Quand -eq $j.AddHours(15) -and -not (Get-RV 'Piscine').Count -and (Get-RV 'Coiffeur').Count -eq 1 -and (Get-RV 'Foot')[0].Lieu -eq 'Stade')
# Un rendez-vous qu'il n'a pas su lire (absent de sa réponse) sans qu'on ait demandé de supprimer : rien n'est touché
$envoye = Get-Envoye
$recu = @(ConvertFrom-Json $envoye | ForEach-Object { $_ } | Where-Object { $_.Titre -ne 'Raid' })
($recu | Where-Object { $_.Titre -eq 'Dentiste' }).Quand = $j.AddDays(2).AddHours(15).ToString($DateFormat)
Invoke-ReponseAssistant (New-Reponse $recu 'Le dentiste est décalé.') 'décale le dentiste à vendredi' 'barre' $envoye
Test-Cas 'assistant : un rendez-vous manquant sans suppression demandée n''est pas effacé' ((Get-RV 'Raid').Count -eq 1 -and (Get-RV 'Dentiste')[0].Quand -eq $j.AddHours(15)) "($(@($script:Agenda).Count) rendez-vous)"
Test-Cas 'assistant : il dit qu''il n''a rien changé' ($script:Montre -match 'rien changé')
# Une vraie suppression demandée : faite, et seulement elle
$envoye = Get-Envoye
[void](Add-RendezVous 'Garage' $j.AddHours(8) $null 'rdv')   # (ajouté pendant qu'il réfléchit)
$recu = @(ConvertFrom-Json $envoye | ForEach-Object { $_ } | Where-Object { $_.Titre -ne 'Raid' })
Invoke-ReponseAssistant (New-Reponse $recu 'J''ai supprimé le raid.') 'supprime le raid' 'barre' $envoye
Test-Cas 'assistant : la suppression demandée est faite' (-not (Get-RV 'Raid').Count -and (Get-RV 'Garage').Count -eq 1 -and (Get-RV 'Dentiste').Count -eq 1)
# Deux rendez-vous manquants pour « supprime le foot » : seul le foot est nommé, rien n'est touché
$envoye = Get-Envoye
$recu = @(ConvertFrom-Json $envoye | ForEach-Object { $_ } | Where-Object { $_.Titre -notin 'Foot', 'Coiffeur' })
Invoke-ReponseAssistant (New-Reponse $recu 'J''ai supprimé le foot.') 'supprime le foot' 'barre' $envoye
Test-Cas 'assistant : un rendez-vous non nommé n''est pas emporté avec la suppression' ((Get-RV 'Coiffeur').Count -eq 1 -and (Get-RV 'Foot').Count -eq 1)

# ---------------------------------------------------------------------------
# Revue du 25/10
# ---------------------------------------------------------------------------
$ui.AgendaBandeau = New-Faux; $ui.AgendaBandeauTexte = New-Faux

# --- 6. Une répétition abîmée dans le fichier : gardée de côté (et réécrite), et c'est dit
Reset-Agenda
$q = $j.AddHours(10).ToString($DateFormat)
$texte6 = @"
{ "Version": 2, "RendezVous": [
  { "Id": "ok1", "Titre": "Kiné", "Type": "sante", "Quand": "$q" },
  { "Id": "an0", "Titre": "Fête", "Type": "rdv", "Quand": "$q", "Repetition": { "Type": "an", "Jour": 5, "Mois": 0 } },
  { "Id": "fin1", "Titre": "Cours", "Type": "rdv", "Quand": "$q", "Repetition": { "Type": "semaine", "Jour": 1, "Jusqua": "n'importe quoi" } },
  { "Id": "sem9", "Titre": "Yoga", "Type": "rdv", "Quand": "$q", "Repetition": { "Type": "semaine", "Jour": 9 } }
] }
"@
[IO.File]::WriteAllText($AgendaFile, $texte6, $Utf8NoBom)
Import-Agenda
Test-Cas 'répétition abîmée : pas chargée (mois 0, fin illisible, jour 9)' (@($script:Agenda).Count -eq 1 -and @($script:AgendaIllisibles).Count -eq 3) "($(@($script:Agenda).Count) chargés, $(@($script:AgendaIllisibles).Count) de côté)"
[void](Add-RendezVous 'Garage' $j.AddHours(9) $null 'rdv')
$ids = @((Get-Fichier).RendezVous | ForEach-Object { $_.Id })
Test-Cas 'répétition abîmée : réécrite à l''enregistrement, jamais perdue' (($ids -contains 'an0') -and ($ids -contains 'fin1') -and ($ids -contains 'sem9') -and $ids.Count -eq 5) "($($ids -join ', '))"
Update-AgendaBandeau
Test-Cas 'répétition abîmée : la fenêtre le dit' ($ui.AgendaBandeau.Visibility -eq 'Visible' -and $ui.AgendaBandeauTexte.Text -match '3 rendez-vous .* abîmés' -and $ui.AgendaBandeauTexte.Text -match 'rien n''est perdu') "($($ui.AgendaBandeauTexte.Text))"
Test-Cas 'répétitions correctes toujours lues' (-not (Get-ErreurRepetition ([pscustomobject]@{ Type = 'mois'; Jour = 1; Rang = -1 })) -and -not (Get-ErreurRepetition ([ordered]@{ Type = 'semaine'; Jour = $null; Intervalle = 2 })) -and -not (Get-ErreurRepetition ([ordered]@{ Type = 'jour'; Intervalle = 2; Jusqua = '2027-01-31'; Sauf = @('2026-12-25') })))

# --- 7. Pas enregistré (fichier .tmp bloqué) : rien n'a changé en mémoire non plus
Reset-Agenda
$den = Add-RendezVous 'Dentiste' $j.AddHours(15) $null 'sante'
$pou = Add-RendezVous 'Poubelles' $j.AddHours(19) ([ordered]@{ Type = 'semaine'; Jour = [int]$j.DayOfWeek }) 'rappel'
$verrou = [IO.File]::Open("$AgendaFile.tmp", 'OpenOrCreate', 'ReadWrite', 'None')
$erreurs7 = 0
try { [void](Add-RendezVous 'Coiffeur' $j.AddHours(10) $null 'rdv') } catch { $erreurs7++ }
try { Remove-RendezVous $den.Id } catch { $erreurs7++ }
try { [void](Update-RendezVous $den.Id 'Dentiste du lundi' $j.AddHours(16) $null 'sante' $false @{ Lieu = 'Rue des Lilas' }) } catch { $erreurs7++ }
try { Set-RendezVousDetail $den.Id 'Notes' 'Carte Vitale' } catch { $erreurs7++ }
try { Set-FaitRV $pou.Id $pou.Quand $true } catch { $erreurs7++ }
$verrou.Dispose()
$d7 = Get-RendezVous $den.Id
Test-Cas 'pas enregistré : chaque changement le dit (erreur)' ($erreurs7 -eq 5) "($erreurs7 erreurs)"
Test-Cas 'pas enregistré : ajout défait' (-not (Get-RV 'Coiffeur').Count -and @($script:Agenda).Count -eq 2)
Test-Cas 'pas enregistré : suppression défaite' ($d7 -and $script:Agenda.IndexOf($d7) -eq 0)
Test-Cas 'pas enregistré : modification défaite' ($d7.Titre -eq 'Dentiste' -and $d7.Quand -eq $j.AddHours(15) -and -not $d7.Lieu -and -not $d7.Notes) "($($d7.Titre), $($d7.Quand), $($d7.Lieu), $($d7.Notes))"
Test-Cas 'pas enregistré : « c''est fait » défait' (-not (Test-FaitRV (Get-RendezVous $pou.Id) $pou.Quand))
[void](Add-RendezVous 'Garage' $j.AddHours(8) $null 'rdv')
$f7 = @((Get-Fichier).RendezVous | ForEach-Object { $_.Titre })
Test-Cas 'pas enregistré : rien de fantôme au prochain enregistrement' ($f7.Count -eq 3 -and $f7 -notcontains 'Coiffeur' -and $f7 -contains 'Dentiste') "($($f7 -join ', '))"
# L'assistant aussi
$envoye = Get-Envoye
$recu = @(ConvertFrom-Json $envoye | ForEach-Object { $_ })
($recu | Where-Object { $_.Titre -eq 'Dentiste' }).Quand = $j.AddDays(1).AddHours(15).ToString($DateFormat)
$verrou = [IO.File]::Open("$AgendaFile.tmp", 'OpenOrCreate', 'ReadWrite', 'None')
try { [void](Merge-AgendaAssistant $envoye $recu 'décale le dentiste à demain' 'Le dentiste passe à demain.') } catch {}
$verrou.Dispose()
Test-Cas 'pas enregistré : le changement de l''assistant défait' ((Get-RV 'Dentiste')[0].Quand -eq $j.AddHours(15))

# --- 24. Fichier pris par un autre programme au démarrage : lecture seule, jamais la bonne version écrasée
Reset-Agenda
[void](Add-RendezVous 'Ancien' $j.AddHours(9) $null 'rdv')
[void](Add-RendezVous 'Dernier ajouté' $j.AddHours(11) $null 'rdv')
$avant24 = [IO.File]::ReadAllText($AgendaFile)
$verrou = [IO.File]::Open($AgendaFile, 'Open', 'ReadWrite', 'None')
$chrono = [Diagnostics.Stopwatch]::StartNew()
Import-Agenda
$chrono.Stop()
Test-Cas 'fichier pris : 3 essais avant d''abandonner' ($chrono.ElapsedMilliseconds -ge 380) "($($chrono.ElapsedMilliseconds) ms)"
Test-Cas 'fichier pris : en lecture seule, la sauvegarde montrée (pas un agenda vide)' ($script:AgendaPris -and (Get-RV 'Ancien').Count -eq 1)
Test-Cas 'fichier pris : pas mis de côté comme abîmé' (-not @(Get-ChildItem -LiteralPath $env:EVERMIND_DONNEES -Filter 'rendez-vous.json.abime-*').Count)
$e24 = $null
try { [void](Add-RendezVous 'Pendant' $j.AddHours(12) $null 'rdv') } catch { $e24 = $_ }
Test-Cas 'fichier pris : enregistrement bloqué, et dit' ($e24 -and -not (Get-RV 'Pendant').Count -and (Get-TexteNonEnregistre) -match 'lecture seule') "($e24)"
Update-AgendaBandeau
Test-Cas 'fichier pris : bandeau « lecture seule, nouvel essai dans 10 s »' ($ui.AgendaBandeau.Visibility -eq 'Visible' -and $ui.AgendaBandeauTexte.Text -match 'lecture seule' -and $ui.AgendaBandeauTexte.Text -match '10 s' -and $script:AgendaReessai) "($($ui.AgendaBandeauTexte.Text))"
$verrou.Dispose()
# Libéré, mais pas encore relu : l'agenda en mémoire vient de la sauvegarde, l'écrire perdrait « Dernier ajouté »
try { [void](Add-RendezVous 'Entre-deux' $j.AddHours(14) $null 'rdv') } catch {}
Test-Cas 'fichier pris : la bonne version n''est pas touchée' ([IO.File]::ReadAllText($AgendaFile) -eq $avant24)
Import-Agenda   # (le nouvel essai)
Test-Cas 'fichier libéré : relu en entier, enregistrement permis' (-not $script:AgendaPris -and (Get-RV 'Dernier ajouté').Count -eq 1)
[void](Add-RendezVous 'Après' $j.AddHours(13) $null 'rdv')
$f24 = @((Get-Fichier).RendezVous | ForEach-Object { $_.Titre })
Test-Cas 'fichier libéré : rien de perdu' ($f24 -contains 'Dernier ajouté' -and $f24 -contains 'Après') "($($f24 -join ', '))"
Update-AgendaBandeau
Test-Cas 'fichier libéré : bandeau parti' ($ui.AgendaBandeau.Visibility -eq 'Collapsed')

# --- 2. « c'est fait » dit à l'assistant pour une chose qui revient : la fois en cours ou la dernière en retard
Reset-Agenda
$p0 = (Get-Date).Date.AddDays(-3).AddHours(7)
$med = Add-RendezVous 'Arroser' $p0 ([ordered]@{ Type = 'semaine'; Jour = [int]$p0.DayOfWeek }) 'rappel'
[void](Invoke-ActionsIA ([pscustomobject]@{ actions = @([pscustomobject]@{ action = 'fait'; id = 'c1' }); reponse = '' }) @{ c1 = $med.Id } 'j''ai arrosé' 'barre')
$m2 = Get-RendezVous $med.Id
Test-Cas 'assistant « c''est fait » : la dernière fois en retard, pas la prochaine' (@($m2.FaitPour).Count -eq 1 -and @($m2.FaitPour)[0] -eq (Get-CleFait $p0) -and -not $m2.Fait) "($($m2.FaitPour -join ', '))"
$fut = Add-RendezVous 'Vaccin' (Get-Date).Date.AddDays(5).AddHours(9) ([ordered]@{ Type = 'an'; Jour = (Get-Date).AddDays(5).Day; Mois = (Get-Date).AddDays(5).Month }) 'rappel'
[void](Invoke-ActionsIA ([pscustomobject]@{ actions = @([pscustomobject]@{ action = 'fait'; id = 'c2' }); reponse = '' }) @{ c2 = $fut.Id } 'vaccin fait' 'barre')
Test-Cas 'assistant « c''est fait » : jamais une fois à venir' (-not @((Get-RendezVous $fut.Id).FaitPour).Count -and $script:Montre -match 'pas encore commencé') "($($script:Montre))"

exit $(if ($ok) { 0 } else { 1 })
