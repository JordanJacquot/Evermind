# Teste Evermind automatiquement : d'abord la compréhension des phrases, puis l'app lancée hors de l'écran
# avec des données à part (_test), dans plusieurs situations, avec une capture d'écran pour chacune.
# Rien n'est modifié sur le PC (ni démarrage avec Windows, ni raccourci, ni icône près de l'horloge).
#
#   .\outils\tester.ps1                 tous les tests
#   .\outils\tester.ps1 -Voix <dossier> + dictée d'une phrase dite par la voix de Windows,
#                                         avec le module de dictée installé dans ce dossier
#                                         (par défaut celui d'Evermind, s'il est installé)
#
# Code de sortie : 0 si tout est bon, 1 sinon.

param([string]$Voix = (Join-Path $env:LOCALAPPDATA 'Evermind\voix'), [int]$Delai = 90, [switch]$AssistantSeul)
$ErrorActionPreference = 'Stop'
$racine = Split-Path $PSScriptRoot -Parent
$main = Join-Path $racine 'Evermind\fichiers\Evermind.ps1'
$test = Join-Path $racine '_test'
New-Item -ItemType Directory -Force -Path $test | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

# Compréhension des phrases
& (Join-Path $PSScriptRoot 'tester-phrases.ps1')
$ok = $LASTEXITCODE -eq 0
# Le grand catalogue : des milliers de façons de dire un rendez-vous
& (Join-Path $PSScriptRoot 'catalogue-phrases.ps1') -Exemples 3
$ok = ($LASTEXITCODE -eq 0) -and $ok

# Rendez-vous d'exemple : aujourd'hui, demain (qui revient chaque semaine), dans quelques jours, un passé
function New-DonneesExemple([string]$Dossier) {
    $now = Get-Date
    $ex = @(
        @{ Titre = 'Dentiste'; Type = 'sante'; Quand = $now.Date.AddDays(3).AddHours(15); Fin = $now.Date.AddDays(3).AddHours(15.5); Lieu = '12 rue des Lilas, Lyon'; Avec = @('Maman'); Important = $true
           Notes = 'Code de la porte : 4521B. Deuxième étage.'; Rappels = @('veille', 'm60'); APreparer = @([ordered]@{ Texte = 'Carte Vitale'; Fait = $true }, [ordered]@{ Texte = 'Ordonnance'; Fait = $false }) },
        @{ Titre = 'Appeler maman'; Type = 'rappel'; Quand = $now.AddHours(2).AddMinutes(-$now.Minute) },
        @{ Titre = 'Raid avec les potes'; Type = 'jeu'; Quand = $now.Date.AddDays(1).AddHours(21).AddMinutes(30); Repetition = [ordered]@{ Type = 'semaine'; Jour = [int]$now.AddDays(1).DayOfWeek } },
        @{ Titre = 'Payer le loyer'; Type = 'rappel'; Quand = $now.Date.AddDays(5).AddHours(10); Repetition = [ordered]@{ Type = 'mois'; Jour = $now.AddDays(5).Day } },
        @{ Titre = 'Anniversaire de Léa'; Type = 'anniv'; Journee = $true; Naissance = $now.Year - 24; Notes = 'Idée cadeau : le nouveau Zelda'; Quand = $now.Date.AddDays(1); Repetition = [ordered]@{ Type = 'an'; Jour = $now.AddDays(1).Day; Mois = $now.AddDays(1).Month } },
        @{ Titre = 'Soirée chez Max'; Type = 'sortie'; Quand = $now.Date.AddDays(6).AddHours(21); Avec = @('Max', 'Inès', 'Tom'); Lien = 'https://discord.gg/abc123' },
        @{ Titre = 'Foot'; Type = 'sport'; Quand = $now.Date.AddDays(4).AddHours(19) },
        @{ Titre = 'Coiffeur'; Type = 'rdv'; Quand = $now.AddDays(-2) }
    ) | ForEach-Object { [ordered]@{ Id = [guid]::NewGuid().ToString('N'); Titre = $_.Titre; Type = $_.Type; Journee = [bool]$_.Journee; Quand = $_.Quand.ToString('yyyy-MM-ddTHH:mm'); Repetition = $_.Repetition; Rappels = $_.Rappels; Cree = (Get-Date -Format s)
        Fin = $(if ($_.Fin) { $_.Fin.ToString('yyyy-MM-ddTHH:mm') } else { $null }); Lieu = $_.Lieu; Avec = @($_.Avec | Where-Object { $_ }); Lien = $_.Lien; Notes = $_.Notes; APreparer = @($_.APreparer | Where-Object { $_ }); Important = [bool]$_.Important; Naissance = $_.Naissance } }
    [IO.File]::WriteAllText((Join-Path $Dossier 'rendez-vous.json'), (ConvertTo-Json -InputObject ([ordered]@{ Version = 1; RendezVous = @($ex) }) -Depth 5), $utf8)
}

# Lance l'app hors de l'écran dans une situation donnée, attend sa capture et vérifie les erreurs
function Invoke-Scenario([string]$Nom, [hashtable]$Env, [switch]$Exemples) {
    $donnees = Join-Path $test "donnees-$Nom"
    if (Test-Path -LiteralPath $donnees) { Remove-Item -LiteralPath $donnees -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $donnees | Out-Null
    if ($Exemples) { New-DonneesExemple $donnees }
    $capture = Join-Path $test "capture-$Nom.png"
    Remove-Item -LiteralPath $capture -ErrorAction SilentlyContinue
    foreach ($k in 'EVERMIND_PHRASE', 'EVERMIND_AJOUTER', 'EVERMIND_FORMULAIRE', 'EVERMIND_REGLAGES', 'EVERMIND_CONFIRMATION', 'EVERMIND_FICHE', 'EVERMIND_FORMULAIRE_RV', 'EVERMIND_TEST_PAROLE', 'EVERMIND_COMMANDE', 'EVERMIND_EVEIL_WAV', 'EVERMIND_DICTEE_WAV', 'EVERMIND_VOIX') { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    $env:EVERMIND_TEST = '1'; $env:EVERMIND_DONNEES = $donnees; $env:EVERMIND_CAPTURE = $capture
    $env:EVERMIND_VOIX = Join-Path $donnees 'voix-absente'
    foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] }
    $err = Join-Path $test "erreurs-$Nom.txt"
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$main`"" -PassThru -WindowStyle Hidden -RedirectStandardError $err
    if (-not $p.WaitForExit($Delai * 1000)) { $p.Kill(); Write-Host "ÉCHEC  $Nom : l'app ne s'est pas fermée en $Delai s." -ForegroundColor Red; return $false }
    $bon = $true
    $stderr = if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Raw } else { '' }
    if ($stderr -and $stderr.Trim()) {
        Write-Host "ÉCHEC  $Nom : erreurs PowerShell" -ForegroundColor Red
        Write-Host ($stderr.Trim() -split "`r?`n" | Select-Object -First 20 | Out-String)
        $bon = $false
    }
    if (-not (Test-Path -LiteralPath $capture)) { Write-Host "ÉCHEC  $Nom : pas de capture, la fenêtre ne s'est pas affichée." -ForegroundColor Red; $bon = $false }
    $journal = Join-Path $donnees 'journal.txt'
    $script:Journal = if (Test-Path -LiteralPath $journal) { [IO.File]::ReadAllText($journal, [Text.Encoding]::UTF8) } else { '' }
    $script:Donnees = $donnees
    if ($bon) { Write-Host "OK     $Nom   ($capture)" -ForegroundColor Green }
    $bon
}

Write-Host 'Test de la fenêtre en cours, patiente...'
if (-not $AssistantSeul) {
$ok = (Invoke-Scenario 'agenda' @{ EVERMIND_PHRASE = 'tous les mardis à 20 h 30 raid avec les potes' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'vide' @{}) -and $ok
$ok = (Invoke-Scenario 'formulaire' @{ EVERMIND_PHRASE = 'demain dentiste'; EVERMIND_FORMULAIRE = '1' } -Exemples) -and $ok
if (Invoke-Scenario 'reglages' @{ EVERMIND_REGLAGES = '1'; EVERMIND_VOIX = $Voix; EVERMIND_TEST_PAROLE = 'K30' }) {
    if (Test-Path -LiteralPath (Join-Path $Voix 'kokoro\modele\model.onnx')) {
        $pv = ([regex]::Match($script:Journal, 'Voix naturelle prête : (.*)')).Groups[1].Value
        if ($pv) { Write-Host "       voix naturelle (Kokoro) : $pv" -ForegroundColor DarkGray } else { Write-Host 'ÉCHEC  reglages : la voix naturelle n''a rien produit' -ForegroundColor Red; $ok = $false }
    }
} else { $ok = $false }
$ok = (Invoke-Scenario 'fiche' @{ EVERMIND_FICHE = 'Dentiste' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'confirmation' @{ EVERMIND_CONFIRMATION = 'Raid avec les potes' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'fiche-anniversaire' @{ EVERMIND_FICHE = 'Anniversaire de Léa' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'formulaire-details' @{ EVERMIND_FORMULAIRE_RV = 'Dentiste' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'apercu-details' @{ EVERMIND_PHRASE = 'concert au Zénith demain de 21 h à 23 h avec Paul et Léa, rappelle-moi la veille, c''est important' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'anniversaire' @{ EVERMIND_PHRASE = 'Créer un rdv anniversaire Jordan le 12 mars'; EVERMIND_AJOUTER = '1' } -Exemples) -and $ok
if (Invoke-Scenario 'ajout' @{ EVERMIND_PHRASE = 'le 5 de chaque mois à 10 h payer le loyer'; EVERMIND_AJOUTER = '1' }) {
    $j = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))
    $r = @($j.RendezVous)[0]
    if ($r.Titre -eq 'Payer le loyer' -and $r.Repetition.Type -eq 'mois' -and $r.Repetition.Jour -eq 5) { Write-Host '       rendez-vous bien enregistré' -ForegroundColor DarkGray }
    else { Write-Host "ÉCHEC  ajout : enregistré $($r | ConvertTo-Json -Compress)" -ForegroundColor Red; $ok = $false }
} else { $ok = $false }

# Dictée : une phrase dite par la voix française de Windows, écrite par Whisper, puis comprise et ajoutée
if (Test-Path -LiteralPath (Join-Path $Voix 'whisper-cli.exe')) {
    Add-Type -AssemblyName System.Speech
    $wav = Join-Path $test 'dictee.wav'
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $fr = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'fr-FR' } | Select-Object -First 1
    if ($fr) { $s.SelectVoice($fr.VoiceInfo.Name) }
    $s.SetOutputToWaveFile($wav, (New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, 'Sixteen', 'Mono')))
    $s.Speak('Mardi prochain à seize heures trente, rendez-vous chez le garagiste.'); $s.SetOutputToNull(); $s.Dispose()
    if (Invoke-Scenario 'dictee' @{ EVERMIND_VOIX = $Voix; EVERMIND_DICTEE_WAV = $wav }) {
        $dit = ([regex]::Match($script:Journal, 'Dictée \([^)]*\) : (.*)')).Groups[1].Value
        $j = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))
        $r = @($j.RendezVous)[0]
        Write-Host "       Whisper a écrit : « $dit »" -ForegroundColor DarkGray
        if ($r -and $r.Titre -match 'garag' -and $r.Quand -match 'T16:30$') { Write-Host "       compris et ajouté : $($r.Titre), $($r.Quand)" -ForegroundColor DarkGray }
        else { Write-Host "ÉCHEC  dictée : rendez-vous enregistré $($r | ConvertTo-Json -Compress)" -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
} else { Write-Host "(dictée non testée : pas de module de dictée dans $Voix)" -ForegroundColor DarkGray }
}

# Assistant : une vraie demande à l'IA, puis on regarde si l'agenda a changé comme il faut
function Get-RV([string]$Titre) { @(@((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous) | Where-Object { $_.Titre -like $Titre }) }
function Test-Assistant([string]$Nom, [string]$Demande, [scriptblock]$Verif) {
    if (-not (Invoke-Scenario $Nom @{ EVERMIND_VOIX = $Voix; EVERMIND_COMMANDE = $Demande } -Exemples)) { return $false }
    foreach ($m in [regex]::Matches($script:Journal, 'Assistant \([^)]*\) : .*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
    $bon = & $Verif
    if (-not $bon) { Write-Host "ÉCHEC  $Nom : l'agenda n'a pas changé comme prévu" -ForegroundColor Red }
    $bon
}
if (-not $env:EVERMIND_EVEIL_SEUL -and (Test-Path -LiteralPath (Join-Path $Voix 'ia\llama-server.exe'))) {
    $jeudi = (Get-Date).Date.AddDays(((4 - [int](Get-Date).DayOfWeek) + 7) % 7); if ($jeudi -eq (Get-Date).Date) { $jeudi = $jeudi.AddDays(7) }
    $ok = (Test-Assistant 'ia-decaler' 'Décale mon dentiste à jeudi, même heure.' { $r = Get-RV 'Dentiste'; $r.Quand -eq $jeudi.AddHours(15).ToString('yyyy-MM-ddTHH:mm') -and $r.Fin -eq $jeudi.AddHours(15.5).ToString('yyyy-MM-ddTHH:mm') }) -and $ok
    $ok = (Test-Assistant 'ia-creer' 'J''aimerais que tu me crée un rendez-vous pour le 23 octobre et que tu mettes un anniversaire Jordan.' { $r = Get-RV 'Anniversaire de Jordan'; $r -and $r[0].Type -eq 'anniv' -and $r[0].Quand -like '*-10-23T00:00' }) -and $ok
    $ok = (Test-Assistant 'ia-preparer' 'Pour le dentiste, pense à prendre mes radios.' { $r = Get-RV 'Dentiste'; @($r.APreparer | Where-Object { $_.Texte -match 'radio' }).Count -eq 1 }) -and $ok
    $ok = (Test-Assistant 'ia-supprimer' 'Supprime le foot.' { -not (Get-RV 'Foot') -and (Get-RV 'Dentiste') }) -and $ok
    $ok = (Test-Assistant 'ia-effacer-date' ('J''aimerais que tu effaces l''événement du ' + (Get-Date).Date.AddDays(6).Day + ' ' + (Get-Date).Date.AddDays(6).ToString('MMMM', [Globalization.CultureInfo]'fr-FR') + ', s''il te plaît.') { -not (Get-RV 'Soirée chez Max') -and (Get-RV 'Dentiste') }) -and $ok
    $ok = (Test-Assistant 'ia-lequel' 'Je veux que tu supprimes l''événement.||L''anniversaire de Léa.' { -not (Get-RV 'Anniversaire de Léa') -and (Get-RV 'Dentiste') -and @((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous).Count -eq 7 }) -and $ok
    $ok = (Test-Assistant 'ia-creer-puis-annuler' 'Je veux que tu me crées l''événement anniversaire de Jordan le 23 octobre.||Annule.' { $script:Journal -match 'Rendez-vous ajouté : Anniversaire de Jordan' -and $script:Journal -match 'Dernière action annulée' -and -not (Get-RV 'Anniversaire de Jordan') -and @((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous).Count -eq 8 }) -and $ok
    $ok = (Test-Assistant 'ia-creer-puis-effacer' 'J''aimerais que tu me crées un rendez-vous pour le 23 octobre et que tu mettes un anniversaire Jordan.||Finalement, efface-le.' { $script:Journal -match 'Rendez-vous ajouté : Anniversaire de Jordan' -and -not (Get-RV 'Anniversaire de Jordan') -and (Get-RV 'Anniversaire de Léa') }) -and $ok
    $ok = (Test-Assistant 'ia-fait' 'C''est bon, j''ai appelé maman.' { (Get-RV 'Appeler maman')[0].Fait -eq $true }) -and $ok
    $ok = (Test-Assistant 'ia-courses' 'Crée-moi un événement faire les courses samedi, avec la liste : lait, œufs, farine et beurre.' { $r = Get-RV 'Faire les courses'; $r -and $r[0].Journee -and @($r[0].APreparer).Count -eq 4 }) -and $ok
    $ok = (Test-Assistant 'ia-courses-octobre' 'Mets-moi un événement courses tous les lundis d''octobre 2026.' { $r = Get-RV 'Courses*'; $r -and [string]$r[0].Repetition.Jusqua -eq '2026-10-31' }) -and $ok
    $ok = (Test-Assistant 'ia-courses-deux-mois' 'Mets un événement course tous les lundis d''octobre 2026 et de novembre 2026.' { $r = Get-RV 'Course*'; @($r).Count -eq 1 -and $r[0].Titre -notmatch 'novembre' -and [string]$r[0].Repetition.Jusqua -eq '2026-11-30' }) -and $ok
    $ok = (Test-Assistant 'ia-plusieurs-jours' 'Ajoute un événement ElleFest sur le 27, le 28 et le 29 octobre.' { $r = @(Get-RV 'Elle*'); $r.Count -eq 1 -and $r[0].Quand -like '*-10-27T00:00' -and $r[0].Fin -like '*-10-29T00:00' }) -and $ok
    $ok = (Test-Assistant 'ia-mettre-sur-3-jours' 'Crée un événement ElleFest le 29 octobre.||Supprime le ElleFest du 29 octobre et je t''ai dit qu''il faut mettre l''événement sur 3 jours, le 27, le 28 et le 29 octobre.' { $r = @(Get-RV 'Elle*'); $r.Count -eq 1 -and $r[0].Quand -like '*-10-27T00:00' -and $r[0].Fin -like '*-10-29T00:00' }) -and $ok
    $ok = (Test-Assistant 'ia-courses-supprimer-mois' 'Mets-moi un événement courses tous les lundis d''octobre 2026.||Supprime tous les événements courses d''octobre 2026.' { -not (Get-RV 'Courses*') }) -and $ok
    $ok = (Test-Assistant 'ia-raid-sauf-novembre' 'Supprime tous les raids de novembre.' { $r = Get-RV 'Raid avec les potes'; $r -and @($r[0].Repetition.Sauf | Where-Object { $_ -like '2026-11-*' }).Count -ge 4 -and -not $r[0].Repetition.Jusqua }) -and $ok
    $ok = (Test-Assistant 'ia-raid-apres' 'Enlève le raid à partir de décembre.' { $r = Get-RV 'Raid avec les potes'; $r -and [string]$r[0].Repetition.Jusqua -eq '2026-11-30' }) -and $ok
    $ok = (Test-Assistant 'ia-question' 'Qu''est-ce que j''ai demain ?' { $script:Journal -match 'Raid' -and (@((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous).Count -eq 8) }) -and $ok
    # Le grand catalogue de demandes à l'assistant (sans fenêtre, même chemin que dans l'appli)
    Write-Host 'Catalogue de l''assistant en cours, patiente...'
    & (Join-Path $PSScriptRoot 'catalogue-assistant.ps1') -Voix $Voix
    $ok = ($LASTEXITCODE -eq 0) -and $ok
} else { Write-Host "(assistant non testé : pas d'IA dans $Voix)" -ForegroundColor DarkGray }

# « OK Eve » : une phrase dite par une voix naturelle (Piper) passe par l'écoute, comme si elle venait du micro
function New-WavPiper([string]$Texte, [string]$Fichier) {
    $psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = (Join-Path $Voix 'piper\piper.exe')
    $psi.Arguments = "-m `"$(Join-Path $Voix 'fr_FR-upmc-medium.onnx')`" -f `"$Fichier`" -q -s 1"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.WorkingDirectory = (Join-Path $Voix 'piper')
    $pr = [Diagnostics.Process]::Start($psi); $w = New-Object IO.StreamWriter($pr.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false))); $w.WriteLine($Texte); $w.Close(); $pr.WaitForExit()
}
if ((Test-Path -LiteralPath (Join-Path $Voix 'eveil\vosk-win64-0.3.45\libvosk.dll')) -and (Test-Path -LiteralPath (Join-Path $Voix 'ia\llama-server.exe'))) {
    $wav = Join-Path $test 'eveil-demande.wav'; New-WavPiper 'OK Eve, supprime le dentiste.' $wav
    $passe = Invoke-Scenario 'eveil-demande' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples
    if ($passe -and (Get-RV 'Dentiste')) { Write-Host '       (mal entendu par la voix de synthèse, nouvel essai)' -ForegroundColor DarkGray; New-WavPiper 'OK Eve, supprime le dentiste.' $wav; $passe = Invoke-Scenario 'eveil-demande' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples }
    if ($passe) {
        foreach ($m in [regex]::Matches($script:Journal, '(Écoute de test|OK Eve|Dictée \(|Assistant \(|Faux réveil)[^\r\n]*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
        if ((Get-RV 'Dentiste') -or -not (Get-RV 'Foot')) { Write-Host 'ÉCHEC  eveil-demande : le dentiste aurait dû être supprimé' -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
    $wav = Join-Path $test 'eveil-faux.wav'; New-WavPiper 'OK, on y va.' $wav
    if (Invoke-Scenario 'eveil-faux' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples) {
        foreach ($m in [regex]::Matches($script:Journal, '(Écoute de test|OK Eve|Dictée \(|Assistant \(|Faux réveil)[^\r\n]*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
        if ($script:Journal -match 'Assistant \(|Rendez-vous (ajouté|supprimé)') { Write-Host 'ÉCHEC  eveil-faux : un faux réveil a déclenché quelque chose' -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
} else { Write-Host "(« OK Eve » non testé : pas d'écoute ou pas d'IA dans $Voix)" -ForegroundColor DarkGray }
if ($ok) { Write-Host 'Tout est bon.' -ForegroundColor Green; exit 0 }
Write-Host 'Des tests ont échoué.' -ForegroundColor Red
exit 1
