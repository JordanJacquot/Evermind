# Vérifie qu'Evermind ne perd jamais de rendez-vous : fichier abîmé (repris de sa sauvegarde ou mis de côté), rendez-vous
# illisible gardé dans le fichier, répétition « tous les 2 jours » gardée par le formulaire, réponse de l'assistant
# appliquée par différences (avec un faux assistant), « annule » après une suppression faite à la main.
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

exit $(if ($ok) { 0 } else { 1 })
