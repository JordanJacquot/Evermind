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

# (par défaut : la voix d'Evermind, ou celle d'une copie installée par Mindset)
param([string]$Voix = $(@(@('Evermind\voix', 'Mindset\Evermind\voix') | ForEach-Object { Join-Path $env:LOCALAPPDATA $_ } | Where-Object { Test-Path -LiteralPath $_ }) + (Join-Path $env:LOCALAPPDATA 'Evermind\voix'))[0], [int]$Delai = 90, [switch]$AssistantSeul)
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
# Dossiers reliés aux rendez-vous, ouverture à l'heure
& (Join-Path $PSScriptRoot 'tester-fichiers.ps1')
$ok = ($LASTEXITCODE -eq 0) -and $ok
# Couleurs des thèmes personnalisés : seules des couleurs bien écrites passent dans la fenêtre
& (Join-Path $PSScriptRoot 'tester-themes.ps1')
$ok = ($LASTEXITCODE -eq 0) -and $ok
# Rappels : la veille, le matin même, N minutes avant, une seule fois
& (Join-Path $PSScriptRoot 'tester-rappels.ps1')
$ok = ($LASTEXITCODE -eq 0) -and $ok
# Horaires de travail en postes : matin, journée, soir, nuit
& (Join-Path $PSScriptRoot 'tester-horaires.ps1')
$ok = ($LASTEXITCODE -eq 0) -and $ok
# Démarrage avec Windows : le réglage gardé tel quel quand Mindset gère Evermind (Mindset le lit)
& (Join-Path $PSScriptRoot 'tester-demarrage.ps1')
$ok = ($LASTEXITCODE -eq 0) -and $ok
# Une seule ligne « Mindset » dans le Gestionnaire des tâches : relais Evermind.exe, programmes d'aide sous le nom Mindset.exe
& (Join-Path $PSScriptRoot 'tester-regroupement.ps1')
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
# (-Programme : par un programme construit, Evermind.exe ou Mindset.exe, au lieu de PowerShell)
function Invoke-Scenario([string]$Nom, [hashtable]$Env, [switch]$Exemples, [string]$Programme) {
    $donnees = Join-Path $test "donnees-$Nom"
    if (Test-Path -LiteralPath $donnees) { Remove-Item -LiteralPath $donnees -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $donnees | Out-Null
    if ($Exemples) { New-DonneesExemple $donnees }
    $capture = Join-Path $test "capture-$Nom.png"
    Remove-Item -LiteralPath $capture -ErrorAction SilentlyContinue
    foreach ($k in 'EVERMIND_DOSSIERS', 'EVERMIND_PACKS', 'EVERMIND_THEME', 'EVERMIND_FERMER', 'EVERMIND_PHRASE', 'EVERMIND_AJOUTER', 'EVERMIND_FORMULAIRE', 'EVERMIND_REGLAGES', 'EVERMIND_CONFIRMATION', 'EVERMIND_FICHE', 'EVERMIND_FORMULAIRE_RV', 'EVERMIND_JOUR', 'EVERMIND_DECALER', 'EVERMIND_FICHE_SUPPRIMER', 'EVERMIND_CONFIRMATION_OUI', 'EVERMIND_CAPTURE_ALERTE', 'EVERMIND_ALERTE_RV', 'EVERMIND_MAJ_VERSION', 'EVERMIND_MAJ_ZIP', 'EVERMIND_MAJ_AUTO', 'EVERMIND_MAJ_INSTALLER', 'EVERMIND_MAJ_PAS_DE_RELANCE', 'EVERMIND_TEST_TELECHARGEMENT', 'EVERMIND_COULEURS', 'EVERMIND_VOIR', 'EVERMIND_LOGO', 'EVERMIND_TEST_PAROLE', 'EVERMIND_COMMANDE', 'EVERMIND_EVEIL_WAV', 'EVERMIND_DICTEE_WAV', 'EVERMIND_VOIX', 'EVERMIND_SUITE', 'EVERMIND_TEST_BLOCAGE', 'EVERMIND_TEST_TRAVAIL', 'EVERMIND_TEST_QUITTER', 'EVERMIND_TEST_MINDSET_HOTE', 'EVERMIND_TEST_DEMARRAGE', 'EVERMIND_TEST_PLANTAGE') { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    $env:EVERMIND_TEST = '1'; $env:EVERMIND_DONNEES = $donnees; $env:EVERMIND_CAPTURE = $capture
    $env:EVERMIND_VOIX = Join-Path $donnees 'voix-absente'
    foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] }
    $err = Join-Path $test "erreurs-$Nom.txt"
    Remove-Item -LiteralPath $err -ErrorAction SilentlyContinue
    $script:Processus = @()
    if ($Programme) {
        $dossierApp = Split-Path $Programme -Parent
        $hote = Join-Path $dossierApp 'Mindset.exe'
        $p = Start-Process -FilePath $Programme -PassThru
        if ($Programme -ine $hote) {
            # Le relais (Evermind.exe) lance Mindset.exe de son dossier puis se ferme aussitôt : Mindset.exe est ensuite
            # suivi par son numéro (PID) et son chemin, jamais par son nom
            if (-not $p.WaitForExit(10000)) { $p.Kill(); Write-Host "ÉCHEC  $Nom : le relais $Programme ne s'est pas fermé" -ForegroundColor Red; return $false }
            $h = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" | Where-Object { $_.ExecutablePath -ieq $hote })
            if ($h.Count -ne 1) { Write-Host "ÉCHEC  $Nom : le relais n'a pas lancé $hote" -ForegroundColor Red; return $false }
            $p = Get-Process -Id ([int]$h[0].ProcessId) -ErrorAction SilentlyContinue
            if (-not $p) { Write-Host "ÉCHEC  $Nom : $hote s'est arrêté tout de suite" -ForegroundColor Red; return $false }
        }
        # Les programmes qui tournent depuis le dossier d'Evermind (nom et chemin), pendant que l'app est ouverte
        Start-Sleep -Seconds 2
        $script:Processus = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -like "$dossierApp\*" } | ForEach-Object { "$($_.Name) (PID $($_.ProcessId), parent $($_.ParentProcessId)) $($_.ExecutablePath)" })
    } else {
        $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$main`"" -PassThru -WindowStyle Hidden -RedirectStandardError $err
    }
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
    if ($Programme -and $script:Journal -match 'Erreurs :|Arrêt inattendu') { Write-Host "ÉCHEC  $Nom : erreurs dans le journal" -ForegroundColor Red; $bon = $false }
    if ($bon) { Write-Host "OK     $Nom   ($capture)" -ForegroundColor Green }
    $bon
}

# Les rendez-vous enregistrés par la dernière situation lancée
function Get-RV([string]$Titre) { @(@((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous) | Where-Object { $_.Titre -like $Titre }) }
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
$ok = (Invoke-Scenario 'reglages-voix' @{ EVERMIND_REGLAGES = 'Voix'; EVERMIND_VOIX = $Voix }) -and $ok
$ok = (Invoke-Scenario 'reglages-general' @{ EVERMIND_REGLAGES = 'General' }) -and $ok
$ok = (Invoke-Scenario 'reglages-theme' @{ EVERMIND_REGLAGES = 'Theme' }) -and $ok
# Chaque thème de couleurs, sur l'agenda d'exemple
foreach ($th in 'crepuscule', 'terminal', 'arcade', 'rubis') { $ok = (Invoke-Scenario "theme-$th" @{ EVERMIND_THEME = $th } -Exemples) -and $ok }
# Thèmes personnalisés : ceux du bureau (Thème-Evermind), installés dans _test\packs (jamais dans le dépôt)
$zips = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Thème-Evermind'
if (Test-Path -LiteralPath $zips) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $packs = Join-Path $test 'packs'
    Remove-Item -LiteralPath $packs -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($z in Get-ChildItem -LiteralPath $zips -Filter '*.zip') {
        $id = (($z.BaseName -replace '^(?i)th[eè]me-', '').Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '' -replace '[^\w\-]', '-').ToLower()
        [IO.Compression.ZipFile]::ExtractToDirectory($z.FullName, (Join-Path $packs $id))
        $ok = (Invoke-Scenario "pack-$id" @{ EVERMIND_PACKS = $packs; EVERMIND_THEME = "pack:$id" } -Exemples) -and $ok
    }
    $ok = (Invoke-Scenario 'pack-reglages' @{ EVERMIND_PACKS = $packs; EVERMIND_THEME = "pack:$((@(Get-ChildItem -LiteralPath $packs -Directory) | Select-Object -First 1).Name)"; EVERMIND_REGLAGES = 'Theme' }) -and $ok   # (le premier pack trouvé : aucun nom de thème dans le code)
} else { Write-Host '(thèmes personnalisés non testés : pas de dossier Thème-Evermind sur le bureau)' -ForegroundColor DarkGray }
$ok = (Invoke-Scenario 'fiche' @{ EVERMIND_FICHE = 'Dentiste' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'fermer' @{ EVERMIND_FERMER = '1' } -Exemples) -and $ok
# L'alerte d'Evermind (à la place des bulles de Windows) : un rappel, et une alerte simple
foreach ($s in @(@('alerte-rappel', 'Dentiste'), @('alerte-simple', 'personne'))) {
    $img = Join-Path $test "capture-$($s[0])-carte.png"; Remove-Item -LiteralPath $img -ErrorAction SilentlyContinue
    $passe = Invoke-Scenario $s[0] @{ EVERMIND_CAPTURE_ALERTE = $img; EVERMIND_ALERTE_RV = $s[1] } -Exemples
    if ($passe -and -not (Test-Path -LiteralPath $img)) { Write-Host "ÉCHEC  $($s[0]) : pas d'image de l'alerte" -ForegroundColor Red; $passe = $false }
    elseif ($passe) { Write-Host "       alerte : $img" -ForegroundColor DarkGray }
    $ok = $passe -and $ok
}
# Nouvelle version disponible : le bandeau « Mettre à jour » (version imaginaire, rien n'est téléchargé ; le zip
# « en ligne » est fait ici à partir du dossier d'Evermind)
$zipTest = Join-Path $test 'maj-evermind.zip'
Compress-Archive -Path (Join-Path $racine 'Evermind') -DestinationPath $zipTest -Force
$ok = (Invoke-Scenario 'maj-bandeau' @{ EVERMIND_MAJ_VERSION = '9.9.9'; EVERMIND_MAJ_ZIP = $zipTest } -Exemples) -and $ok
if ($script:Journal -notmatch 'Mise à jour disponible : 9\.9\.9') { Write-Host 'ÉCHEC  maj-bandeau : la nouvelle version n''a pas été vue' -ForegroundColor Red; $ok = $false }
# Dossier de travail : pas de mise à jour automatique (elle écraserait le code source), et Réglages qui le disent
if (Invoke-Scenario 'travail' @{ EVERMIND_TEST_TRAVAIL = '1'; EVERMIND_MAJ_VERSION = '9.9.9'; EVERMIND_MAJ_ZIP = $zipTest; EVERMIND_REGLAGES = 'General'; EVERMIND_VOIR = 'ReglagesTravail' } -Exemples) {
    if ($script:Journal -match 'Mise à jour disponible' -or $script:Journal -notmatch 'Dossier de travail : pas de mise à jour') { Write-Host 'ÉCHEC  travail : la mise à jour n''est pas coupée' -ForegroundColor Red; $ok = $false }
    else { Write-Host '       pas de mise à jour dans un dossier de travail' -ForegroundColor DarkGray }
} else { $ok = $false }
# Signature des mises à jour : un zip sans signature, puis avec une fausse, est refusé et rien n'est installé
$nonSigne = Join-Path $test 'maj-non-signee.zip'
Copy-Item -LiteralPath $zipTest -Destination $nonSigne -Force
Remove-Item -LiteralPath "$nonSigne.sig" -ErrorAction SilentlyContinue
foreach ($s in @(@('maj-sans-signature', 'sa signature est introuvable'), @('maj-signature-fausse', 'sa signature n''est pas valide'))) {
    if ($s[0] -eq 'maj-signature-fausse') { [IO.File]::WriteAllBytes("$nonSigne.sig", [byte[]](1..384 | ForEach-Object { $_ % 256 })) }
    if (Invoke-Scenario $s[0] @{ EVERMIND_MAJ_VERSION = '9.9.9'; EVERMIND_MAJ_ZIP = $nonSigne; EVERMIND_MAJ_AUTO = '1' } -Exemples) {
        if ($script:Journal -notmatch ('Mise à jour 9\.9\.9 refusée : ' + [regex]::Escape($s[1]))) { Write-Host "ÉCHEC  $($s[0]) : la mise à jour n'a pas été refusée" -ForegroundColor Red; $ok = $false }
        else { Write-Host '       mise à jour refusée, rien d''installé' -ForegroundColor DarkGray }
    } else { $ok = $false }
}
# Mindset : copie gérée (faux suite.json qui donne ce dossier) : thème, micro et casque de la suite pris ; dans Réglages,
# Son et Thème, le bouton qui ouvre les réglages de Mindset à la place des choix. Evermind lit suite.json sans jamais
# l'écrire (le thème se choisit seulement dans Mindset ; détail dans tester-themes.ps1).
$suite = Join-Path $test 'suite.json'
[IO.File]::WriteAllText($suite, (ConvertTo-Json -InputObject ([ordered]@{ theme = 'arcade'; applis = [ordered]@{ evermind = (Join-Path $racine 'Evermind\'); nevermind = 'C:\Program Files\Mindset\Nevermind' }; micro = 'Micro de test (USB)'; casque = ''; modifie = '2026-10-14T16:00:00' })), $utf8)
# Une nouvelle version imaginaire est « en ligne » : une copie gérée ne doit pas la chercher elle-même (c'est Mindset
# qui le fait ; la page Code signing policy le promet)
$suiteTexte = [IO.File]::ReadAllText($suite, [Text.Encoding]::UTF8)
foreach ($s in @(@('mindset-gere', 'Son'), @('mindset-gere-theme', 'Theme'))) {
    if (Invoke-Scenario $s[0] @{ EVERMIND_SUITE = $suite; EVERMIND_REGLAGES = $s[1]; EVERMIND_MAJ_VERSION = '9.9.9'; EVERMIND_MAJ_ZIP = $zipTest } -Exemples) {
        $reg = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'reglages.json'), [Text.Encoding]::UTF8))
        if ($script:Journal -notmatch 'Thème de la suite \(Mindset\) : arcade' -or $script:Journal -notmatch 'Géré par Mindset' -or $reg.Micro -ne 'Micro de test (USB)' -or [string]$reg.Casque -ne '') { Write-Host "ÉCHEC  $($s[0]) : thème, micro ou casque de la suite pas pris" -ForegroundColor Red; $ok = $false }
        elseif ($script:Journal -match 'Mise à jour (disponible|: recherche|: téléchargement)') { Write-Host "ÉCHEC  $($s[0]) : une copie gérée par Mindset a cherché sa mise à jour elle-même" -ForegroundColor Red; $ok = $false }
        elseif ([IO.File]::ReadAllText($suite, [Text.Encoding]::UTF8) -ne $suiteTexte) { Write-Host "ÉCHEC  $($s[0]) : suite.json a été modifié par Evermind" -ForegroundColor Red; $ok = $false }
        else { Write-Host '       thème (arcade), micro et casque de la suite pris, mises à jour par Mindset (aucune recherche par Evermind)' -ForegroundColor DarkGray }
    } else { $ok = $false }
}
# Mindset : thème personnalisé de la suite (« pack:<id> » dans suite.json), installé par Mindset dans nos packs : il est
# appliqué ; absent, le thème actuel reste
$packsSuite = Join-Path $test 'packs-suite'
Remove-Item -LiteralPath $packsSuite -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $packsSuite 'suite-test') | Out-Null
[IO.File]::WriteAllText((Join-Path $packsSuite 'suite-test\pack.json'), (ConvertTo-Json -InputObject ([ordered]@{ Name = 'Pack de la suite (test)'; Desc = 'Thème personnalisé installé par Mindset'; Base = 'rubis'; Hello = '{0} ! Thème de la suite.' })), $utf8)
foreach ($s in @(@('mindset-gere-pack', 'pack:suite-test'), @('mindset-gere-pack-absent', 'pack:absent'))) {
    [IO.File]::WriteAllText($suite, (ConvertTo-Json -InputObject ([ordered]@{ theme = $s[1]; applis = [ordered]@{ evermind = (Join-Path $racine 'Evermind\') }; modifie = '2026-10-14T16:00:00' })), $utf8)
    if (Invoke-Scenario $s[0] @{ EVERMIND_SUITE = $suite; EVERMIND_PACKS = $packsSuite; EVERMIND_REGLAGES = 'Theme' } -Exemples) {
        $fr = Join-Path $script:Donnees 'reglages.json'
        $reg = if (Test-Path -LiteralPath $fr) { ConvertFrom-Json ([IO.File]::ReadAllText($fr, [Text.Encoding]::UTF8)) } else { [pscustomobject]@{ Theme = $null } }
        $bon = if ($s[0] -eq 'mindset-gere-pack') { $script:Journal -match 'Thème de la suite \(Mindset\) : pack:suite-test' -and $reg.Theme -eq 'pack:suite-test' }
               else { $script:Journal -match 'pack:absent introuvable' -and $reg.Theme -ne 'pack:absent' }
        if (-not $bon) { Write-Host "ÉCHEC  $($s[0]) : thème de la suite mal pris (Theme = $($reg.Theme))" -ForegroundColor Red; $ok = $false }
        else { Write-Host "       thème de la suite : $(if ($s[0] -eq 'mindset-gere-pack') { 'pack appliqué' } else { 'pack absent, thème actuel gardé' })" -ForegroundColor DarkGray }
    } else { $ok = $false }
}
# Quitter Mindset ferme aussi Evermind : quitter.demande apparaît dans le dossier de données, Evermind quitte tout seul,
# proprement et vite. Un vieux quitter.demande laissé avant le lancement est effacé (sinon il se refermerait aussitôt).
$donnees = Join-Path $test 'donnees-quitter-demande'
Remove-Item -LiteralPath $donnees -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $donnees | Out-Null
New-DonneesExemple $donnees
[IO.File]::WriteAllText((Join-Path $donnees 'quitter.demande'), 'vieux')
foreach ($k in 'EVERMIND_CAPTURE', 'EVERMIND_SUITE', 'EVERMIND_REGLAGES', 'EVERMIND_PACKS', 'EVERMIND_THEME', 'EVERMIND_MAJ_VERSION', 'EVERMIND_TEST_BLOCAGE', 'EVERMIND_TEST_TRAVAIL', 'EVERMIND_VOIR') { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
$env:EVERMIND_TEST = '1'; $env:EVERMIND_DONNEES = $donnees; $env:EVERMIND_VOIX = Join-Path $donnees 'voix-absente'; $env:EVERMIND_TEST_QUITTER = '1'
$env:EVERMIND_CAPTURE = Join-Path $test 'capture-quitter-demande.png'   # (jamais faite : Evermind se ferme avant, la fenêtre reste hors de l'écran)
$err = Join-Path $test 'erreurs-quitter-demande.txt'
$chrono = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$main`"" -PassThru -WindowStyle Hidden -RedirectStandardError $err
$fini = $p.WaitForExit(60000)
Remove-Item env:EVERMIND_TEST_QUITTER -ErrorAction SilentlyContinue
$journal = [IO.File]::ReadAllText((Join-Path $donnees 'journal.txt'), [Text.Encoding]::UTF8)
$stderr = if (Test-Path -LiteralPath $err) { [string](Get-Content -LiteralPath $err -Raw) } else { '' }
$demandes = ([regex]::Matches($journal, 'Fermeture demandée par Mindset')).Count
if (-not $fini) { $p.Kill(); Write-Host 'ÉCHEC  quitter-demande : Evermind ne s''est pas fermé' -ForegroundColor Red; $ok = $false }
elseif ("$stderr".Trim() -or $journal -match 'Erreurs|Arrêt inattendu' -or $demandes -ne 1 -or $journal -notmatch 'Fermeture\r?\n' -or (Test-Path -LiteralPath (Join-Path $donnees 'quitter.demande')) -or $chrono.Elapsed.TotalSeconds -lt 1.5) {
    Write-Host "ÉCHEC  quitter-demande : fermeture pas propre (demandes vues : $demandes, $([math]::Round($chrono.Elapsed.TotalSeconds, 1)) s)" -ForegroundColor Red; if ("$stderr".Trim()) { Write-Host $stderr }; $ok = $false
} else { Write-Host "OK     quitter-demande   (fermé tout seul, $([math]::Round($chrono.Elapsed.TotalSeconds, 1)) s après le lancement, vieux fichier ignoré)" -ForegroundColor Green }
# Affiché dans Mindset (fenêtre accrochée dans une autre, comme le fait Mindset) : plus de taille minimale, réduite à
# l'échelle si besoin, logo à sa place même s'il avait été déplacé ; décrochée (et cachée par Mindset) : tout revient.
# Deuxième fois en partant d'un Evermind lancé caché (-Demarrage, comme Mindset au démarrage de Windows) : la fenêtre
# doit être montrée pour WPF (sinon Mindset n'affiche qu'un fond noir) et la capture la montre bien.
foreach ($s in @(@('mindset-hote', @{ EVERMIND_TEST_MINDSET_HOTE = '900x640'; EVERMIND_LOGO = '0.45;0.5;90' }, 'place=Collapsed'),
                 @('mindset-hote-cache', @{ EVERMIND_TEST_MINDSET_HOTE = '960x700'; EVERMIND_TEST_DEMARRAGE = '1' }, 'place=Visible'))) {
    if (Invoke-Scenario $s[0] $s[1] -Exemples) {
        $acc = [regex]::Match($script:Journal, 'Test Mindset accroché : (.*)').Groups[1].Value
        $dec = [regex]::Match($script:Journal, 'Test Mindset décroché : (.*)').Groups[1].Value
        $bon = $acc -match '^visible=True dans=True .*min=0x0 .*place=Visible' -and $dec -match ('^visible=False dans=False .*min=1040x760 .*' + $s[2])
        if ($s[0] -eq 'mindset-hote-cache') { $bon = $bon -and $script:Journal -match 'lancé avec Windows' -and $script:Journal -match 'fenêtre montrée \(lancé caché\)' }
        if (-not $bon) { Write-Host "ÉCHEC  $($s[0]) : accroché « $acc », décroché « $dec »" -ForegroundColor Red; $ok = $false }
        else { Write-Host "       accroché : $acc" -ForegroundColor DarkGray; Write-Host "       décroché : $dec" -ForegroundColor DarkGray }
    } else { $ok = $false }
}
# Les programmes construits (outils\construire.ps1) : Evermind.exe n'est plus qu'un relais qui lance Mindset.exe (le
# programme Evermind, nommé comme ceux de toute la suite : une seule ligne « Mindset » dans le Gestionnaire des tâches)
# puis se ferme aussitôt. Pendant que l'app tourne, seul Mindset.exe doit tourner depuis le dossier d'Evermind.
$exeRelais = Join-Path $racine 'Evermind\Evermind.exe'; $exeHote = Join-Path $racine 'Evermind\Mindset.exe'
if ((Test-Path -LiteralPath $exeRelais) -and (Test-Path -LiteralPath $exeHote)) {
    foreach ($s in @(@('programme-relais', $exeRelais), @('programme-mindset', $exeHote))) {
        if (Invoke-Scenario $s[0] @{} -Exemples -Programme $s[1]) {
            foreach ($l in $script:Processus) { Write-Host "       processus : $l" -ForegroundColor DarkGray }
            if ($script:Processus.Count -ne 1 -or $script:Processus[0] -notmatch '^Mindset\.exe ' -or $script:Journal -notmatch 'Démarrage Evermind') { Write-Host "ÉCHEC  $($s[0]) : processus inattendus ($($script:Processus.Count))" -ForegroundColor Red; $ok = $false }
        } else { $ok = $false }
    }
} else { Write-Host '(programmes non testés : Evermind.exe et Mindset.exe pas construits, lance outils\construire.ps1)' -ForegroundColor DarkGray }
# Filet contre les plantages : une erreur imprévue après le démarrage (qui revient 12 fois, dans un clic, dans un
# minuteur) est notée au journal avec sa ligne, Evermind continue jusqu'à sa capture, et le message ne s'affiche qu'une fois
if (Invoke-Scenario 'plantage' @{ EVERMIND_TEST_PLANTAGE = '1' } -Exemples) {
    $j = $script:Journal; $pb = @()
    $n = ([regex]::Matches($j, 'Erreur imprévue \(fenêtre\) : Erreur de test qui revient \[')).Count
    if ($n -ne 3) { $pb += "erreur qui revient notée en entier $n fois au lieu de 3" }
    if ($j -notmatch 'la même erreur est revenue 10 fois : Erreur de test qui revient') { $pb += 'répétitions pas comptées' }
    if ($j -notmatch 'Erreur imprévue \(fenêtre\) : Fichier de test introuvable .*evenements\.ps1 ligne \d+') { $pb += 'erreur du clic absente ou sans sa ligne' }
    if ($j -notmatch 'Erreur imprévue \(fenêtre\) : Erreur de test dans un minuteur .*evenements\.ps1 ligne \d+') { $pb += 'erreur du minuteur absente ou sans sa ligne' }
    $n = ([regex]::Matches($j, 'Alerte : Un petit problème est survenu')).Count
    if ($n -ne 1) { $pb += "message montré $n fois au lieu d'une" }
    if ($pb) { Write-Host "ÉCHEC  plantage : $($pb -join ' ; ')" -ForegroundColor Red; $ok = $false }
    else { Write-Host '       15 erreurs notées (3 en entier, puis comptées), Evermind a continué, un seul message' -ForegroundColor DarkGray }
} else { $ok = $false }
# Une erreur au démarrage n'est pas cachée : Evermind s'arrête (avec le message du programme), elle est au journal
$donnees = Join-Path $test 'donnees-plantage-demarrage'
Remove-Item -LiteralPath $donnees -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $donnees | Out-Null
$env:EVERMIND_DONNEES = $donnees; $env:EVERMIND_TEST_PLANTAGE = 'demarrage'; $env:EVERMIND_CAPTURE = Join-Path $test 'capture-plantage-demarrage.png'
Remove-Item -LiteralPath $env:EVERMIND_CAPTURE -ErrorAction SilentlyContinue
$err = Join-Path $test 'erreurs-plantage-demarrage.txt'
$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$main`"" -PassThru -WindowStyle Hidden -RedirectStandardError $err
$fini = $p.WaitForExit(60000)
Remove-Item env:EVERMIND_TEST_PLANTAGE -ErrorAction SilentlyContinue
$journal = [IO.File]::ReadAllText((Join-Path $donnees 'journal.txt'), [Text.Encoding]::UTF8)
$stderr = if (Test-Path -LiteralPath $err) { [string](Get-Content -LiteralPath $err -Raw) } else { '' }
if (-not $fini) { $p.Kill(); Write-Host 'ÉCHEC  plantage-demarrage : l''erreur au démarrage a été cachée, Evermind a continué' -ForegroundColor Red; $ok = $false }
elseif ($stderr -notmatch 'Erreur de test au d' -or $journal -notmatch 'Erreur au démarrage \(fenêtre\) : Erreur de test au démarrage .*evenements\.ps1 ligne \d+' -or (Test-Path -LiteralPath $env:EVERMIND_CAPTURE)) {
    Write-Host 'ÉCHEC  plantage-demarrage : erreur au démarrage pas visible ou pas notée' -ForegroundColor Red; $ok = $false
} else { Write-Host 'OK     plantage-demarrage   (Evermind arrêté, erreur visible et notée au journal)' -ForegroundColor Green }
# Une erreur dans un fil d'arrière-plan arrête le programme (Mindset.exe) : elle est au moins notée au journal
if (Test-Path -LiteralPath $exeHote) {
    $donnees = Join-Path $test 'donnees-plantage-fil'
    Remove-Item -LiteralPath $donnees -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $donnees | Out-Null
    $env:EVERMIND_DONNEES = $donnees; $env:EVERMIND_TEST_PLANTAGE = 'fil'
    $p = Start-Process -FilePath $exeHote -PassThru
    $fini = $p.WaitForExit(60000)
    Remove-Item env:EVERMIND_TEST_PLANTAGE -ErrorAction SilentlyContinue
    $journal = [IO.File]::ReadAllText((Join-Path $donnees 'journal.txt'), [Text.Encoding]::UTF8)
    if (-not $fini) { $p.Kill(); Write-Host 'ÉCHEC  plantage-fil : Mindset.exe ne s''est pas arrêté' -ForegroundColor Red; $ok = $false }
    elseif ($journal -notmatch 'Arrêt : erreur dans un fil d''arrière-plan : .*Erreur de test dans un fil') { Write-Host 'ÉCHEC  plantage-fil : l''arrêt n''est pas noté au journal' -ForegroundColor Red; $ok = $false }
    else { Write-Host 'OK     plantage-fil   (arrêt noté au journal)' -ForegroundColor Green }
}
# Copie hors de Mindset (pas un dossier de travail) : la fenêtre « Evermind s'utilise maintenant avec Mindset », et rien ne démarre
if (Invoke-Scenario 'blocage' @{ EVERMIND_TEST_BLOCAGE = '1' } -Exemples) {
    if ($script:Journal) { Write-Host 'ÉCHEC  blocage : Evermind a démarré quand même' -ForegroundColor Red; $ok = $false }
    else { Write-Host '       bloqué : rien n''a démarré' -ForegroundColor DarkGray }
} else { $ok = $false }
# Horaires de travail : l'aperçu « Je comprends », puis l'ajout (un poste par jour)
$ok = (Invoke-Scenario 'horaires-apercu' @{ EVERMIND_PHRASE = 'boulot lundi matin, mardi journée et mercredi soir' } -Exemples) -and $ok
if (Invoke-Scenario 'horaires-ajout' @{ EVERMIND_PHRASE = 'je suis du matin lundi et mardi'; EVERMIND_AJOUTER = '1' } -Exemples) {
    if (@(Get-RV 'Travail (matin)').Count -ne 2) { Write-Host 'ÉCHEC  horaires-ajout : les deux postes du matin ne sont pas notés' -ForegroundColor Red; $ok = $false }
    else { Write-Host '       deux postes du matin notés' -ForegroundColor DarkGray }
} else { $ok = $false }
# Couleurs des sortes au choix : l'onglet Thème, puis l'agenda (une couleur choisie reste la même avec un autre thème)
$ok = (Invoke-Scenario 'couleurs-reglages' @{ EVERMIND_REGLAGES = 'Theme'; EVERMIND_COULEURS = 'sport=#FF4D6D;sante=#3B82F6'; EVERMIND_VOIR = 'CouleursSortes' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'couleurs-agenda' @{ EVERMIND_THEME = 'crepuscule'; EVERMIND_COULEURS = 'sport=#FF4D6D;sante=#3B82F6' } -Exemples) -and $ok
# Le logo déplacé (au milieu de la fenêtre) et agrandi
$ok = (Invoke-Scenario 'logo-deplace' @{ EVERMIND_LOGO = '0.45;0.5;90' } -Exemples) -and $ok
# Téléchargement en cours : barre qui avance, pourcentage, vitesse, temps restant
$ok = (Invoke-Scenario 'telechargement' @{ EVERMIND_TEST_TELECHARGEMENT = '1' } -Exemples) -and $ok
# Rendez-vous passé (le coiffeur, il y a 2 jours) : validé tout seul (✓), et on peut encore le décaler
$ok = (Invoke-Scenario 'valide-jour' @{ EVERMIND_JOUR = (Get-Date).Date.AddDays(-2).ToString('yyyy-MM-dd') } -Exemples) -and $ok
$ok = (Invoke-Scenario 'valide-fiche' @{ EVERMIND_FICHE = 'Coiffeur' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'valide-decaler' @{ EVERMIND_FORMULAIRE_RV = 'Coiffeur'; EVERMIND_DECALER = '1' } -Exemples) -and $ok
# Dossier relié tout seul (« réunion avec Monsieur Richard ») : la fiche et le formulaire
function Get-RV([string]$Titre) { @(@((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous) | Where-Object { $_.Titre -like $Titre }) }
$compta = Join-Path $test 'comptabilite'
foreach ($d in 'Monsieur Richard', 'Madame Dupont') { New-Item -ItemType Directory -Force -Path (Join-Path $compta $d) | Out-Null }
if (Invoke-Scenario 'fichiers-fiche' @{ EVERMIND_DOSSIERS = $compta; EVERMIND_PHRASE = 'réunion avec Monsieur Richard demain à 10 h'; EVERMIND_AJOUTER = '1'; EVERMIND_FICHE = 'R*union*' } -Exemples) {
    $r = @(Get-RV 'R*union*')
    if (-not ($r.Count -eq 1 -and @($r[0].Fichiers | Where-Object { $_ -like '*\Monsieur Richard' }).Count -eq 1)) { Write-Host 'ÉCHEC  fichiers-fiche : le dossier de Monsieur Richard n''est pas relié' -ForegroundColor Red; $ok = $false }
    else { Write-Host '       dossier relié tout seul : Monsieur Richard' -ForegroundColor DarkGray }
} else { $ok = $false }
$ok = (Invoke-Scenario 'fichiers-formulaire' @{ EVERMIND_DOSSIERS = $compta; EVERMIND_PHRASE = 'réunion avec Madame Dupont demain à 10 h'; EVERMIND_AJOUTER = '1'; EVERMIND_FORMULAIRE_RV = 'R*union*' } -Exemples) -and $ok
$ok = (Invoke-Scenario 'fichiers-reglages' @{ EVERMIND_DOSSIERS = $compta; EVERMIND_REGLAGES = 'General' }) -and $ok
$ok = (Invoke-Scenario 'confirmation' @{ EVERMIND_CONFIRMATION = 'Raid avec les potes' } -Exemples) -and $ok
# Supprimer pour de vrai : depuis la carte (confirmation), puis depuis la fiche
foreach ($s in @(@('supprimer-carte', @{ EVERMIND_CONFIRMATION = 'Foot'; EVERMIND_CONFIRMATION_OUI = '1' }), @('supprimer-fiche', @{ EVERMIND_FICHE = 'Foot'; EVERMIND_FICHE_SUPPRIMER = '1' }))) {
    if (Invoke-Scenario $s[0] $s[1] -Exemples) {
        if (@(Get-RV 'Foot').Count -or $script:Journal -match 'Erreurs') { Write-Host "ÉCHEC  $($s[0]) : le foot n'a pas été supprimé" -ForegroundColor Red; Write-Host (($script:Journal -split "`n" | Select-String 'Erreurs' | Select-Object -First 2) -join "`n"); $ok = $false }
        else { Write-Host '       le foot est bien supprimé' -ForegroundColor DarkGray }
    } else { $ok = $false }
}
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
    $ok = (Test-Assistant 'ia-raid-sauf-novembre' 'Supprime tous les raids de novembre.' { $r = Get-RV 'Raid avec les potes'; $r -and @($r[0].Repetition.Sauf | Where-Object { $_ -like '2026-11-*' }).Count -ge 4 -and -not @($r[0].Repetition.Sauf | Where-Object { $_ -notlike '2026-11-*' }).Count -and -not $r[0].Repetition.Jusqua }) -and $ok
    $ok = (Test-Assistant 'ia-raid-apres' 'Enlève le raid à partir de décembre.' { $r = Get-RV 'Raid avec les potes'; $r -and [string]$r[0].Repetition.Jusqua -eq '2026-11-30' }) -and $ok
    $ok = (Test-Assistant 'ia-question' 'Qu''est-ce que j''ai demain ?' { $script:Journal -match 'Raid' -and (@((ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $script:Donnees 'rendez-vous.json'), [Text.Encoding]::UTF8))).RendezVous).Count -eq 8) }) -and $ok
    # Le grand catalogue de demandes à l'assistant (sans fenêtre, même chemin que dans l'appli)
    Write-Host 'Catalogue de l''assistant en cours, patiente...'
    & (Join-Path $PSScriptRoot 'catalogue-assistant.ps1') -Voix $Voix
    $ok = ($LASTEXITCODE -eq 0) -and $ok
} else { Write-Host "(assistant non testé : pas d'IA dans $Voix)" -ForegroundColor DarkGray }

# « OK Evermind » : une phrase dite par une voix de synthèse (Piper, gardé seulement pour les tests dans _test\voix) passe
# par l'écoute, comme si elle venait du micro
$Piper = Join-Path $test 'voix'
function New-WavPiper([string]$Texte, [string]$Fichier) {
    $psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = (Join-Path $Piper 'piper\piper.exe')
    $psi.Arguments = "-m `"$(Join-Path $Piper 'fr_FR-upmc-medium.onnx')`" -f `"$Fichier`" -q -s 1"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.WorkingDirectory = (Join-Path $Piper 'piper')
    $pr = [Diagnostics.Process]::Start($psi); $w = New-Object IO.StreamWriter($pr.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false))); $w.WriteLine($Texte); $w.Close(); $pr.WaitForExit()
}
if ((Test-Path -LiteralPath (Join-Path $Voix 'eveil\vosk-win64-0.3.45\libvosk.dll')) -and (Test-Path -LiteralPath (Join-Path $Voix 'ia\llama-server.exe'))) {
    $wav = Join-Path $test 'eveil-demande.wav'; New-WavPiper 'OK Evermind, supprime le dentiste.' $wav
    $passe = Invoke-Scenario 'eveil-demande' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples
    if ($passe -and (Get-RV 'Dentiste')) { Write-Host '       (mal entendu par la voix de synthèse, nouvel essai)' -ForegroundColor DarkGray; New-WavPiper 'OK Evermind, supprime le dentiste.' $wav; $passe = Invoke-Scenario 'eveil-demande' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples }
    if ($passe) {
        foreach ($m in [regex]::Matches($script:Journal, '(Écoute de test|OK Evermind|Dictée \(|Assistant \(|Faux réveil)[^\r\n]*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
        if ((Get-RV 'Dentiste') -or -not (Get-RV 'Foot')) { Write-Host 'ÉCHEC  eveil-demande : le dentiste aurait dû être supprimé' -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
    $wav = Join-Path $test 'eveil-faux.wav'; New-WavPiper 'OK, on y va.' $wav
    if (Invoke-Scenario 'eveil-faux' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples) {
        foreach ($m in [regex]::Matches($script:Journal, '(Écoute de test|OK Evermind|Dictée \(|Assistant \(|Faux réveil)[^\r\n]*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
        if ($script:Journal -match 'Assistant \(|Rendez-vous (ajouté|supprimé)') { Write-Host 'ÉCHEC  eveil-faux : un faux réveil a déclenché quelque chose' -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
    # « Evermind » sans « OK » devant (le « OK » se perd souvent) : il se réveille aussi
    $wav = Join-Path $test 'eveil-sans-ok.wav'; New-WavPiper 'Evermind, supprime le dentiste.' $wav
    if (Invoke-Scenario 'eveil-sans-ok' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples) {
        foreach ($m in [regex]::Matches($script:Journal, '(Écoute de test|OK Evermind|Dictée \(|Assistant \(|Faux réveil)[^\r\n]*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
        if (Get-RV 'Dentiste') { Write-Host 'ÉCHEC  eveil-sans-ok : « Evermind, supprime le dentiste » n''a pas marché' -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
    # « OK Eve » est le mot d'Eve, l'autre assistant : Evermind ne doit pas réagir
    $wav = Join-Path $test 'eveil-eve.wav'; New-WavPiper 'OK Eve, supprime le dentiste.' $wav
    if (Invoke-Scenario 'eveil-eve' @{ EVERMIND_VOIX = $Voix; EVERMIND_EVEIL_WAV = $wav } -Exemples) {
        foreach ($m in [regex]::Matches($script:Journal, '(Écoute de test|OK Evermind|Dictée \(|Assistant \(|Faux réveil)[^\r\n]*')) { Write-Host "       $($m.Value)" -ForegroundColor DarkGray }
        if ($script:Journal -match 'Assistant \(|Rendez-vous (ajouté|supprimé)' -or -not (Get-RV 'Dentiste')) { Write-Host 'ÉCHEC  eveil-eve : « OK Eve » a réveillé Evermind' -ForegroundColor Red; $ok = $false }
    } else { $ok = $false }
} else { Write-Host "(« OK Evermind » non testé : pas d'écoute ou pas d'IA dans $Voix)" -ForegroundColor DarkGray }
if ($ok) { Write-Host 'Tout est bon.' -ForegroundColor Green; exit 0 }
Write-Host 'Des tests ont échoué.' -ForegroundColor Red
exit 1
