# Evermind : grand catalogue de demandes à l'assistant.
# Chaque demande part de l'agenda d'exemple (celui des tests) et passe par exactement le même chemin que dans
# l'appli : consignes et agenda envoyés à l'IA, contrôles d'Evermind (verbe, nouvel essai, garde-fous), puis les
# actions sur l'agenda. On vérifie ensuite l'agenda obtenu, pas seulement ce que l'IA a répondu.
# Familles : créer (jours, heures, répétitions, plusieurs jours, années, listes), supprimer (tout, une date,
# une période), modifier (heure, jour, personnes, choses à prendre, plusieurs jours, arrêter une série),
# fait, annuler, questions, discussion, phrases mal dictées, demandes doubles.
#
#   .\outils\catalogue-assistant.ps1 [-Voix <dossier contenant ia\>] [-Filtre <mot>]
#
# Code de sortie : 0 si tout va bien, 1 sinon.
param([string]$Voix = (Join-Path $env:LOCALAPPDATA 'Evermind\voix'), [string]$Filtre = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$env:EVERMIND_VOIX = $Voix
$env:EVERMIND_TEST = '1'
$env:EVERMIND_DONNEES = Join-Path $racine '_test\catalogue-ia'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
$exemple = Join-Path $racine '_test\donnees-agenda\rendez-vous.json'
if (-not (Test-Path $exemple)) { throw 'Lance d''abord outils\tester.ps1 (il crée l''agenda d''exemple).' }
$Fr = [Globalization.CultureInfo]'fr-FR'
foreach ($m in 'donnees', 'comprendre', 'agenda', 'details', 'voix', 'cerveau') { . (Join-Path $modules "$m.ps1") }

# Sans fenêtre : ce qu'Evermind dirait ou montrerait est seulement retenu
$script:Dit = ''
function Invoke-Parole([string]$Texte) { $script:Dit = $Texte }
function Show-FormMessage { }
function Show-Bulle { }
function Set-VoixEtat { }
function Show-MainWindow { }
function Update-Agenda { }
$ui = @{ InPhrase = New-Object System.Windows.Controls.TextBox }

$port = 8098
$serveur = Start-Process $LlamaExe -ArgumentList "-m `"$IaModele`" --host 127.0.0.1 --port $port -ngl 99 -c 8192 --no-webui" -PassThru -WindowStyle Hidden
$script:Cerveau = @{ Process = $serveur; Port = $port; Dernier = Get-Date }

function Invoke-IA([string]$Corps) {
    $r = Invoke-RestMethod "http://127.0.0.1:$port/v1/chat/completions" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Corps))
    $r.choices[0].message.content | ConvertFrom-Json
}

# Une phrase, comme dans l'appli : question, réponse, contrôles (un nouvel essai au plus), actions
function Invoke-Demande([string]$Texte) {
    $relance = $null
    $journal = @()
    for ($essai = 0; $essai -lt 2; $essai++) {
        $q = Get-QuestionIA $Texte $relance
        $rep = Invoke-IA $q.Corps
        $journal += ($rep | ConvertTo-Json -Depth 6 -Compress)
        $d = @{ Texte = $Texte; Relance = [bool]$relance; Messages = $q.Messages; Codes = $q.Ctx.Codes }
        $dec = Get-DecisionIA $d $rep
        if ($dec.Relance -and -not $relance) { $relance = $dec.Relance; continue }
        $final = $dec.Reponse
        [void]$script:Conversation.Add(@{ role = 'user'; content = $Texte })
        [void]$script:Conversation.Add(@{ role = 'assistant'; content = ($final | ConvertTo-Json -Depth 6 -Compress) })
        $script:ConversationQuand = Get-Date
        Invoke-ActionsIA $final $q.Ctx.Codes $Texte 'voix'
        break
    }
    $journal -join ' => '
}

# Aides pour les vérifications
$auj = (Get-Date).Date
function Get-RV([string]$Titre) { @($script:Agenda | Where-Object { $_.Titre -like $Titre }) }
function Get-Prochain([int]$Jour) { $e = (($Jour - [int]$auj.DayOfWeek) + 7) % 7; if ($e -eq 0) { $e = 7 }; $auj.AddDays($e) }   # « mardi » : le prochain mardi
function Get-Le([int]$Jour, [int]$Mois) { $d = [datetime]::new($auj.Year, $Mois, $Jour); if ($d -lt $auj) { $d = $d.AddYears(1) }; $d }
function Test-Jour($r, [datetime]$Jour, $Heure) {
    if (-not $r) { return $false }
    $q = [datetime]$r.Quand
    if ($q.Date -ne $Jour.Date) { return $false }
    if ($null -eq $Heure) { return [bool]$r.Journee }
    $q.TimeOfDay -eq [timespan]$Heure
}
$dentiste = $auj.AddDays(3); $foot = $auj.AddDays(4); $soiree = $auj.AddDays(6); $lea = $auj.AddDays(1)
$moisProchain = $auj.AddDays(1 - $auj.Day).AddMonths(1)
$nomMois = { param($d) $d.ToString('MMMM', $Fr) }
$anSuivant = $auj.Year + 1

# Famille, phrases (une conversation), vérification de l'agenda à la fin
$cas = @(
    # --- Créer : jours, heures, façons de le dire
    , @('créer', @('Ajoute un rendez-vous chez le garagiste vendredi à 10 h.'), { $r = Get-RV '*garag*'; (Test-Jour $r[0] (Get-Prochain 5) '10:00') })
    , @('créer', @('Mets-moi coiffeur mardi à 14 h 30.'), { $r = Get-RV 'Coiffeur'; @($r | Where-Object { Test-Jour $_ (Get-Prochain 2) '14:30' }).Count -eq 1 })
    , @('créer', @('Note que j''ai piscine demain à 18 h.'), { $r = Get-RV '*iscine*'; Test-Jour $r[0] $auj.AddDays(1) '18:00' })
    , @('créer', @('Rappelle-moi d''appeler le plombier demain à 9 h.'), { $r = Get-RV '*plombier*'; Test-Jour $r[0] $auj.AddDays(1) '09:00' })
    , @('créer', @('Il faut que je pense à acheter du pain demain.'), { $r = Get-RV '*pain*'; Test-Jour $r[0] $auj.AddDays(1) $null })
    , @('créer', @('Crée un événement cinéma avec Léa samedi prochain à 20 h 30.'), { $r = Get-RV 'Cin*'; (Test-Jour $r[0] (Get-Prochain 6) '20:30') -and @($r[0].Avec) -contains 'Léa' })
    , @('créer', @('J''ai un entretien d''embauche le 3 novembre à 11 h.'), { $r = Get-RV '*ntretien*'; Test-Jour $r[0] (Get-Le 3 11) '11:00' })
    , @('créer', @("Mets un rendez-vous chez le kiné le 1er $(& $nomMois $moisProchain) à 8 h 45."), { $r = Get-RV '*kin*'; Test-Jour $r[0] $moisProchain '08:45' })
    , @('créer', @('Ajoute dentiste dans deux semaines à 15 h.'), { $r = @(Get-RV '*entiste*' | Where-Object { ([datetime]$_.Quand).Date -eq $auj.AddDays(14) }); $r.Count -eq 1 -and ([datetime]$r[0].Quand).Hour -eq 15 })
    , @('créer', @('Programme une réunion demain de 14 h à 16 h.'), { $r = Get-RV 'R*union*'; (Test-Jour $r[0] $auj.AddDays(1) '14:00') -and ([datetime]$r[0].Fin).Hour -eq 16 })
    , @('créer', @('Mets-moi un rappel dans deux heures pour sortir le linge.'), { $r = Get-RV '*linge*'; $r -and [math]::Abs((([datetime]$r[0].Quand) - (Get-Date).AddHours(2)).TotalMinutes) -lt 3 })
    , @('créer', @('Ajoute un rendez-vous chez le médecin le 3 mars à 10 h en ' + $anSuivant + '.'), { $r = Get-RV '*decin*'; Test-Jour $r[0] ([datetime]::new($anSuivant, 3, 3)) '10:00' })
    , @('créer', @('Crée un événement dentiste le 3 mars de l''année prochaine à 9 h.'), { $r = @(Get-RV '*entiste*' | Where-Object { ([datetime]$_.Quand).Year -eq $anSuivant }); $r.Count -eq 1 -and ([datetime]$r[0].Quand).Month -eq 3 })
    , @('créer', @('Ajoute un événement sans heure : faire le ménage samedi.'), { $r = Get-RV '*nage*'; Test-Jour $r[0] (Get-Prochain 6) $null })
    , @('créer', @('Crée l''anniversaire de Paul le 2 mai, il aura 30 ans.'), { $r = Get-RV 'Anniversaire de Paul'; $r -and $r[0].Type -eq 'anniv' -and $r[0].Naissance -eq ((Get-Le 2 5).Year - 30) })
    , @('créer', @('Fais-moi un événement courses samedi avec la liste : lait, œufs, pain et beurre.'), { $r = Get-RV '*ourses*'; $r -and @($r[0].APreparer).Count -eq 4 })
    , @('créer', @('Ajoute un truc important : rendre le dossier vendredi à 12 h.'), { $r = Get-RV '*dossier*'; $r -and $r[0].Important })
    , @('créer', @('Ajoute réunion lundi à 10 h dans la salle B, avec Paul et Sophie.'), { $r = Get-RV 'R*union*'; $r -and @($r[0].Avec).Count -ge 2 })
    # --- Créer : répétitions
    , @('répéter', @('Mets-moi le sport tous les mardis à 18 h.'), { $r = Get-RV '*port*'; $r -and $r[0].Repetition.Type -eq 'semaine' -and [int]$r[0].Repetition.Jour -eq 2 })
    , @('répéter', @('Ajoute médicaments tous les jours à 8 h.'), { $r = Get-RV '*dicament*'; $r -and $r[0].Repetition.Type -eq 'jour' })
    , @('répéter', @('Crée badminton toutes les deux semaines le jeudi à 19 h.'), { $r = Get-RV '*adminton*'; $r -and [int]$r[0].Repetition.Intervalle -eq 2 -and [int]$r[0].Repetition.Jour -eq 4 })
    , @('répéter', @('Mets réveil en semaine à 7 h.'), { $r = Get-RV '*veil*'; $r -and @($r[0].Repetition.Jours).Count -eq 5 })
    , @('répéter', @('Ajoute vélo tous les week-ends à 9 h.'), { $r = Get-RV 'V*lo'; $r -and @($r[0].Repetition.Jours).Count -eq 2 })
    , @('répéter', @('Crée salle de sport le lundi et le jeudi à 18 h.'), { $r = Get-RV '*alle*'; $r -and @($r[0].Repetition.Jours).Count -eq 2 })
    , @('répéter', @('Ajoute réunion d''équipe le premier lundi du mois à 9 h.'), { $r = Get-RV '*quipe*'; $r -and [int]$r[0].Repetition.Rang -eq 1 })
    , @('répéter', @('Mets afterwork le dernier vendredi du mois à 18 h.'), { $r = Get-RV '*fterwork*'; $r -and [int]$r[0].Repetition.Rang -eq -1 })
    , @('répéter', @('Crée un rappel payer l''électricité le 10 de chaque mois.'), { $r = Get-RV '*lectricit*'; $r -and $r[0].Repetition.Type -eq 'mois' -and [int]$r[0].Repetition.Jour -eq 10 })
    , @('répéter', @("Mets un événement courses tous les lundis d'octobre et de novembre $($auj.Year)."), { $r = Get-RV '*ourses*'; $r -and @($r).Count -eq 1 -and [string]$r[0].Repetition.Jusqua -eq "$($auj.Year)-11-30" })
    , @('répéter', @("Ajoute yoga tous les mercredis jusqu'au 15 décembre à 19 h."), { $r = Get-RV '*oga*'; $r -and ([string]$r[0].Repetition.Jusqua) -like '*-12-15' })
    # --- Créer : plusieurs jours
    , @('plusieurs jours', @('Ajoute un événement ElleFest sur le 27, le 28 et le 29 octobre.'), { $r = @(Get-RV '*Fest*'); $r.Count -eq 1 -and ([datetime]$r[0].Fin).Day -eq 29 })
    , @('plusieurs jours', @('Mets vacances du 20 décembre au 3 janvier.'), { $r = @(Get-RV '*acances*'); $r.Count -eq 1 -and ([datetime]$r[0].Fin).Month -eq 1 })
    , @('plusieurs jours', @('Crée un salon pendant 3 jours à partir du 5 novembre.'), { $r = @(Get-RV '*alon*'); $r.Count -eq 1 -and ((([datetime]$r[0].Fin).Date - ([datetime]$r[0].Quand).Date).Days -eq 2) })
    , @('plusieurs jours', @('Ajoute cours de guitare les 3 et 10 novembre à 18 h.'), { @(Get-RV '*uitare*').Count -eq 2 })
    # --- Supprimer
    , @('supprimer', @('Supprime le foot.'), { -not (Get-RV 'Foot') -and (Get-RV 'Dentiste') })
    , @('supprimer', @('Efface le rendez-vous chez le dentiste.'), { -not (Get-RV 'Dentiste') -and (Get-RV 'Foot') })
    , @('supprimer', @("Enlève l'événement du $($soiree.Day) $(& $nomMois $soiree)."), { -not (Get-RV 'Soirée chez Max') -and (Get-RV 'Foot') })
    , @('supprimer', @('Je veux que tu supprimes l''événement.', 'Le foot.'), { -not (Get-RV 'Foot') -and (Get-RV 'Dentiste') })
    , @('supprimer', @('Supprime tout ce que j''ai demain.'), { $demain = @(Get-AgendaEntre $lea $lea.AddDays(1)); -not $demain.Count -and (Get-RV 'Foot') })   # plus rien demain (les séries peuvent juste sauter ce jour-là)
    , @('supprimer', @('Supprime les raids de novembre.'), { $r = Get-RV 'Raid avec les potes'; $r -and @($r[0].Repetition.Sauf | Where-Object { $_ -like "*-11-*" }).Count -ge 4 })
    , @('supprimer', @('Arrête le raid à partir de décembre.'), { $r = Get-RV 'Raid avec les potes'; $r -and ([string]$r[0].Repetition.Jusqua) -like '*-11-30' })
    , @('supprimer', @('Supprime le raid de demain seulement.'), { $r = Get-RV 'Raid avec les potes'; $r -and (@($r[0].Repetition.Sauf) -contains $lea.ToString('yyyy-MM-dd') -or ([datetime]$r[0].Quand).Date -gt $lea) })
    , @('supprimer', @('Supprime tous les raids.'), { -not (Get-RV 'Raid avec les potes') })
    , @('supprimer', @('Supprime le coiffeur.'), { -not (Get-RV 'Coiffeur') })
    , @('supprimer', @('Sucrime le foot.'), { -not (Get-RV 'Foot') })
    , @('supprimer', @('Suprime le dentiste stp.'), { -not (Get-RV 'Dentiste') })
    # --- Modifier
    , @('modifier', @('Décale le foot à 20 h.'), { $r = Get-RV 'Foot'; Test-Jour $r[0] $foot '20:00' })
    , @('modifier', @('Décale mon dentiste à jeudi, même heure.'), { $r = Get-RV 'Dentiste'; Test-Jour $r[0] (Get-Prochain 4) '15:00' })
    , @('modifier', @('Le dentiste, c''est plutôt à 16 h.'), { $r = Get-RV 'Dentiste'; Test-Jour $r[0] $dentiste '16:00' })
    , @('modifier', @('Repousse la soirée chez Max d''une heure.'), { $r = Get-RV 'Soirée chez Max'; Test-Jour $r[0] $soiree '22:00' })
    , @('modifier', @('Avance le foot à 18 h.'), { $r = Get-RV 'Foot'; Test-Jour $r[0] $foot '18:00' })
    , @('modifier', @('Ajoute Paul à la soirée chez Max.'), { $r = Get-RV 'Soirée chez Max'; @($r[0].Avec) -contains 'Paul' })
    , @('modifier', @('Pour le dentiste, pense à prendre mes radios.'), { $r = Get-RV 'Dentiste'; @($r[0].APreparer | Where-Object { $_.Texte -match 'radio' }).Count -eq 1 })
    , @('modifier', @('Renomme le foot en match de foot.'), { (Get-RV '*atch de foot*') })
    , @('modifier', @('Le foot, c''est au stade Gerland.'), { $r = Get-RV 'Foot'; [string]$r[0].Lieu -match 'Gerland' })
    , @('modifier', @('Le raid de demain, mets-le plutôt à 22 h, et ajoute Tom.'), { $r = Get-RV 'Raid avec les potes'; ([datetime]$r[0].Quand).Hour -eq 22 -and @($r[0].Avec) -contains 'Tom' })
    , @('modifier', @('Mets la soirée chez Max sur deux jours.'), { $r = Get-RV 'Soirée chez Max'; $r[0].Fin -and ([datetime]$r[0].Fin).Date -gt $soiree })
    , @('modifier', @('Le raid, c''est fini après novembre.'), { $r = Get-RV 'Raid avec les potes'; $r -and ([string]$r[0].Repetition.Jusqua) -like '*-11-30' })
    , @('modifier', @('Marque le dentiste comme important.'), { $r = Get-RV 'Dentiste'; $r[0].Important })
    , @('modifier', @('Décade le foot à 20 h.'), { $r = Get-RV 'Foot'; Test-Jour $r[0] $foot '20:00' })
    # --- Fait, annuler
    , @('fait', @('J''ai payé le loyer.'), { $r = Get-RV 'Payer le loyer'; $r[0].Fait })
    , @('fait', @('C''est bon, j''ai appelé maman.'), { $r = Get-RV 'Appeler maman'; $r[0].Fait })
    , @('annuler', @('Supprime le foot.', 'Annule.'), { (Get-RV 'Foot') })
    , @('annuler', @('Crée un tennis demain à 10 h.', 'Non, annule.'), { -not (Get-RV '*ennis*') })
    , @('annuler', @('Crée un tennis demain à 10 h.', 'Finalement, efface-le.'), { -not (Get-RV '*ennis*') })
    # --- Questions et discussion : rien ne change
    , @('question', @('Qu''est-ce que j''ai demain ?'), { @($script:Agenda).Count -eq 8 -and $script:Dit -match 'Léa|raid' })
    , @('question', @('C''est quand mon prochain dentiste ?'), { @($script:Agenda).Count -eq 8 -and $script:Dit -match "$($dentiste.Day)|$($dentiste.ToString('dddd', $Fr))" })
    , @('question', @('Qu''est-ce que je dois apporter chez le dentiste ?'), { @($script:Agenda).Count -eq 8 -and $script:Dit -match 'Ordonnance|Vitale' })
    , @('question', @('Où est le dentiste ?'), { @($script:Agenda).Count -eq 8 -and $script:Dit -match 'Lilas' })
    , @('question', @('Est-ce que je suis libre samedi soir ?'), { @($script:Agenda).Count -eq 8 })
    , @('discussion', @('Salut, ça va ?'), { @($script:Agenda).Count -eq 8 })
    , @('discussion', @('Merci beaucoup !'), { @($script:Agenda).Count -eq 8 })
    , @('discussion', @('Supprime-moi l''événement Troke Tops.'), { @($script:Agenda).Count -eq 8 })
    # --- Demandes doubles
    , @('double', @('Supprime le foot et ajoute un tennis jeudi à 19 h.'), { -not (Get-RV 'Foot') -and (Get-RV '*ennis*') })
    , @('double', @('Crée un événement ElleFest le 29 octobre.', 'Supprime le ElleFest du 29 et mets-le sur 3 jours, le 27, le 28 et le 29 octobre.'), { $r = @(Get-RV '*Fest*'); $r.Count -eq 1 -and ([datetime]$r[0].Quand).Day -eq 27 -and ([datetime]$r[0].Fin).Day -eq 29 })
    , @('double', @('Décale le foot à 20 h et ajoute Tom.'), { $r = Get-RV 'Foot'; (Test-Jour $r[0] $foot '20:00') -and @($r[0].Avec) -contains 'Tom' })
    # --- Deuxième série : formules piégeuses
    , @('piège', @('Annule le foot.'), { -not (Get-RV 'Foot') -and (Get-RV 'Dentiste') })
    , @('piège', @('Le dentiste est annulé.'), { -not (Get-RV 'Dentiste') })
    , @('piège', @('Je ne vais plus au foot jeudi, enlève-le.'), { -not (Get-RV 'Foot') })
    , @('piège', @('Retire Tom de la soirée chez Max.'), { $r = Get-RV 'Soirée chez Max'; $r -and @($r[0].Avec) -notcontains 'Tom' -and @($r[0].Avec) -contains 'Max' })
    , @('piège', @('Préviens-moi 2 heures avant le foot.'), { $r = Get-RV 'Foot'; @($r[0].Rappels) -contains 'm120' })
    , @('piège', @('Rappelle-moi la veille pour la soirée chez Max.'), { $r = Get-RV 'Soirée chez Max'; @($r[0].Rappels) -contains 'veille' })
    , @('piège', @('Déplace le foot à la semaine prochaine, même jour même heure.'), { $r = Get-RV 'Foot'; Test-Jour $r[0] $foot.AddDays(7) '19:00' })
    , @('piège', @('Change l''heure du dentiste, mets 16 h 30.'), { $r = Get-RV 'Dentiste'; Test-Jour $r[0] $dentiste '16:30' })
    , @('piège', @('Ajoute une note au dentiste : demander pour la couronne.'), { $r = Get-RV 'Dentiste'; [string]$r[0].Notes -match 'couronne' })
    , @('piège', @('Mets le foot en important.'), { $r = Get-RV 'Foot'; $r[0].Important })
    , @('piège', @('Le foot n''est plus important.'), { $r = Get-RV 'Foot'; -not $r[0].Important -and (Get-RV 'Foot') })
    , @('piège', @('Peux-tu me rajouter un rendez-vous chez l''ophtalmo jeudi prochain à 11 h, s''il te plaît ?'), { $r = Get-RV '*phtalmo*'; Test-Jour $r[0] (Get-Prochain 4) '11:00' })
    , @('piège', @('Euh, ok, donc tu me mets genre resto avec Inès vendredi soir.'), { $r = Get-RV 'Resto*'; Test-Jour $r[0] (Get-Prochain 5) '20:00' })
    , @('piège', @('J''ai rendez-vous à la banque mardi à 9 h, note-le.'), { $r = Get-RV '*anque*'; Test-Jour $r[0] (Get-Prochain 2) '09:00' })
    , @('piège', @('Supprime mes rendez-vous de la semaine prochaine.'), { $l = $auj.AddDays(7 - ((([int]$auj.DayOfWeek) + 6) % 7)); -not @(Get-AgendaEntre $l $l.AddDays(7) | Where-Object { -not $_.RV.Repetition -or $_.RV.Type -ne 'anniv' }).Count })
    , @('piège', @('Qu''est-ce que j''ai de prévu jeudi ?'), { @($script:Agenda).Count -eq 8 -and $script:Dit -match 'foot' })
    , @('piège', @('Tu peux me dire ce que j''ai demain ?'), { @($script:Agenda).Count -eq 8 })
    , @('piège', @('Combien de rendez-vous j''ai cette semaine ?'), { @($script:Agenda).Count -eq 8 })
    , @('piège', @('Ajoute dentiste vendredi à 15 h.'), { @(Get-RV 'Dentiste').Count -eq 2 })
    , @('piège', @('Mets le foot à 20 h.'), { $r = Get-RV 'Foot'; @($r).Count -eq 1 -and (Test-Jour $r[0] $foot '20:00') })
    , @('piège', @('Mets un rendez-vous foot samedi à 10 h.'), { @(Get-RV 'Foot').Count -eq 2 })
    , @('piège', @('Le loyer, c''est le 3 maintenant.'), { $r = Get-RV 'Payer le loyer'; [int]$r[0].Repetition.Jour -eq 3 })
    , @('piège', @('Le raid passe au mardi.'), { $r = Get-RV 'Raid avec les potes'; [int]$r[0].Repetition.Jour -eq 2 })
    , @('piège', @('Mets le raid toutes les deux semaines.'), { $r = Get-RV 'Raid avec les potes'; @($r).Count -eq 1 -and [int]$r[0].Repetition.Intervalle -eq 2 })
    , @('piège', @('Supprime le raid du 26 octobre.'), { $r = Get-RV 'Raid avec les potes'; $r -and @($r[0].Repetition.Sauf) -contains "$($auj.Year)-10-26" })
    , @('piège', @('Efface tout le raid.'), { -not (Get-RV 'Raid avec les potes') })
    , @('piège', @('Ajoute un événement Noël chez mamie le 24 décembre.'), { $r = Get-RV '*mamie*'; Test-Jour $r[0] (Get-Le 24 12) $null })
    , @('piège', @('Crée un rappel : rendre les livres à la médiathèque avant samedi.'), { (Get-RV '*livres*') })
)

$bons = 0; $total = 0; $parFamille = [ordered]@{}
try {
    while ($true) { try { if ((Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch { Start-Sleep -Milliseconds 300 } }
    foreach ($c in $cas) {
        $famille = $c[0]; $phrases = $c[1]; $verif = $c[2]
        if ($Filtre -and $famille -notlike "*$Filtre*" -and ($phrases -join ' ') -notlike "*$Filtre*") { continue }
        # Agenda d'exemple tout neuf, conversation oubliée
        Copy-Item $exemple (Join-Path $env:EVERMIND_DONNEES 'rendez-vous.json') -Force
        Import-Agenda
        $script:Conversation = New-Object System.Collections.ArrayList; $script:Annulation = $null; $script:Dit = ''
        $traces = @()
        foreach ($ph in $phrases) { $traces += "« $ph » -> $(Invoke-Demande $ph)" }
        $bon = $false
        try { $bon = [bool](& $verif) } catch {}
        $total++; if ($bon) { $bons++ }
        if (-not $parFamille.Contains($famille)) { $parFamille[$famille] = @{ Total = 0; Bon = 0 } }
        $parFamille[$famille].Total++; if ($bon) { $parFamille[$famille].Bon++ }
        if (-not $bon) {
            Write-Host "ÉCHEC  [$famille] $($phrases -join ' / ')" -ForegroundColor Red
            foreach ($t in $traces) { Write-Host "        $t" }
            Write-Host "        Evermind a dit : $($script:Dit)"
        }
    }
} finally { Stop-Process -Id $serveur.Id -Force -ErrorAction SilentlyContinue }

Write-Host ''
foreach ($f in $parFamille.Keys) { $x = $parFamille[$f]; Write-Host ("{0,-18} {1,3} / {2}" -f $f, $x.Bon, $x.Total) -ForegroundColor $(if ($x.Bon -eq $x.Total) { 'Green' } else { 'Yellow' }) }
Write-Host "Assistant : $bons / $total demandes réussies" -ForegroundColor $(if ($bons -eq $total) { 'Green' } else { 'Yellow' })
exit $(if ($bons -eq $total) { 0 } else { 1 })
