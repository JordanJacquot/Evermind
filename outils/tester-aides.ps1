# Vérifie les programmes d'aide et le micro, sans vrai micro ni vrai son :
#   1. un programme d'aide (Whisper, la voix, l'assistant) s'arrête avec Evermind, même arrêté de force (job de Windows) ;
#   2. micro débranché pendant l'écoute : l'écoute s'arrête toute seule et le dit (horloge réelle, faux micro) ;
#   3. le son d'une phrase dictée n'est jamais gardé (« ta voix n'est jamais gardée ») ;
#   4. Whisper est arrêté en premier à la fermeture ;
#   5. l'écoute de « OK Evermind » arrêtée rend son modèle Vosk (sinon chaque reprise en charge un de plus).
# Les programmes lancés ici sont de petits programmes de test (powershell.exe et ping.exe sur cette machine), suivis par
# leur numéro (PID) : rien n'est jamais arrêté par son nom.
#
#   .\outils\tester-aides.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$test = Join-Path $racine '_test\aides'
Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $test | Out-Null

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}
function Test-Vivant([int]$Id) { [bool](Get-Process -Id $Id -ErrorAction SilentlyContinue) }

# Les fonctions d'Evermind sont prises telles quelles dans les modules (sans charger toute l'appli)
function Import-Fonctions([string]$Fichier, [string[]]$Noms) {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $modules $Fichier), [ref]$null, [ref]$null)
    foreach ($n in $Noms) {
        $f = $ast.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $n }, $true)
        if (-not $f) { Test-Cas "$Fichier : $n existe" $false; continue }
        . ([scriptblock]::Create($f.Extent.Text))
        Set-Item -Path "function:script:$n" -Value (Get-Item "function:$n").ScriptBlock
    }
}

# ---------------------------------------------------------------------------
# 1. Programmes d'aide reliés à Evermind par un job de Windows
# ---------------------------------------------------------------------------
# Un faux Evermind (powershell.exe caché) compile natif.cs, lance un programme d'aide (ping.exe, qui dure 2 minutes),
# le relie avec Add-ProgrammeAide (la vraie fonction de voix.ps1), note son numéro, puis attend. Le test l'arrête de
# force, comme Mindset le fait : le programme d'aide doit s'arrêter avec lui.
$voixAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $modules 'voix.ps1'), [ref]$null, [ref]$null)
$fAide = $voixAst.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Add-ProgrammeAide' }, $true)
Test-Cas 'voix.ps1 : Add-ProgrammeAide existe' ([bool]$fAide)
$hote = Join-Path $test 'faux-evermind.ps1'
$natif = Join-Path $modules 'natif.cs'
[IO.File]::WriteAllText($hote, @"
param([string]`$Sortie, [switch]`$SansJob)
`$ErrorActionPreference = 'Stop'
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText('$natif', [Text.Encoding]::UTF8))
    `$script:Journal = @()
    function Write-Log([string]`$t) { `$script:Journal += `$t }
    $(if ($fAide) { $fAide.Extent.Text })
    `$p = `$null
    `$psi = New-Object Diagnostics.ProcessStartInfo
    `$psi.FileName = "`$env:SystemRoot\System32\PING.EXE"; `$psi.Arguments = '-n 120 127.0.0.1'
    `$psi.UseShellExecute = `$false; `$psi.CreateNoWindow = `$true; `$psi.RedirectStandardOutput = `$true
    `$p = [Diagnostics.Process]::Start(`$psi)
    if (-not `$SansJob) { Add-ProgrammeAide `$p 'Test' }
    [IO.File]::WriteAllText(`$Sortie, "`$(`$p.Id)|`$(`$script:Journal -join ' / ')")
} catch { [IO.File]::WriteAllText(`$Sortie, "`$(if (`$p) { `$p.Id } else { 0 })|`$_") }   # (numéro noté : le test l'arrête)
Start-Sleep -Seconds 120
"@, (New-Object Text.UTF8Encoding $true))

function Test-Orphelin([switch]$SansJob) {
    $sortie = Join-Path $test "pid-$([bool]$SansJob).txt"
    $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$hote`"", '-Sortie', "`"$sortie`"")
    if ($SansJob) { $arg += '-SansJob' }
    $h = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arg -WindowStyle Hidden -PassThru
    $limite = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $sortie) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Milliseconds 300
    $lu = if (Test-Path -LiteralPath $sortie) { [IO.File]::ReadAllText($sortie) } else { '0|faux Evermind sans réponse' }
    $enfant = [int]($lu -split '\|')[0]
    $vivantAvant = $enfant -and (Test-Vivant $enfant)
    # Arrêté de force, comme par Mindset (par son numéro)
    try { Stop-Process -Id $h.Id -Force -ErrorAction Stop } catch {}
    $limite = (Get-Date).AddSeconds(5)
    while ($enfant -and (Test-Vivant $enfant) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 100 }
    $vivantApres = $enfant -and (Test-Vivant $enfant)
    if ($vivantApres) { try { Stop-Process -Id $enfant -Force -ErrorAction Stop } catch {} }   # (seulement notre programme de test)
    [pscustomobject]@{ Avant = $vivantAvant; Apres = $vivantApres; Detail = $lu }
}
$r = Test-Orphelin
Test-Cas 'le programme d''aide tournait avec Evermind' $r.Avant "($($r.Detail))"
Test-Cas 'Evermind arrêté de force : le programme d''aide s''arrête avec lui' ($r.Avant -and -not $r.Apres) "($($r.Detail))"
# Contre-épreuve : sans le job, il resterait seul en mémoire (ce que le test doit savoir voir)
$r = Test-Orphelin -SansJob
Test-Cas 'contre-épreuve : sans job, le programme d''aide resterait seul' ($r.Avant -and $r.Apres) "($($r.Detail))"

# Chaque programme d'aide lancé par Evermind est relié (Whisper serveur et en ligne de commande, la voix, l'assistant)
foreach ($f in 'voix.ps1', 'cerveau.ps1') {
    $lignes = [IO.File]::ReadAllLines((Join-Path $modules $f), [Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lignes.Count; $i++) {
        if ($lignes[$i] -notmatch '\[Diagnostics\.Process\]::Start\(') { continue }
        $suite = ($lignes[$i..([math]::Min($lignes.Count - 1, $i + 2))]) -join "`n"
        Test-Cas "$f ligne $($i + 1) : programme relié à Evermind" ($suite -match 'Add-ProgrammeAide') "($($lignes[$i].Trim()))"
    }
}

# 4. À la fermeture : Whisper d'abord (arrêté tout de suite), puis la voix et l'assistant
$sys = [Management.Automation.Language.Parser]::ParseFile((Join-Path $modules 'systeme.ps1'), [ref]$null, [ref]$null)
$exit = $sys.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Exit-App' }, $true).Extent.Text
$iW = $exit.IndexOf('Stop-WhisperServeur'); $iK = $exit.IndexOf('Stop-KokoroServeur'); $iC = $exit.IndexOf('Stop-Cerveau')
Test-Cas 'fermeture : Whisper arrêté en premier' ($iW -ge 0 -and $iW -lt $iK -and $iW -lt $iC)

# ---------------------------------------------------------------------------
# 2. Micro débranché pendant l'écoute (faux micro : la durée enregistrée ne bouge plus, l'horloge avance)
# ---------------------------------------------------------------------------
$tempAvant = $env:TEMP
$DataDir = Join-Path $test 'donnees'
New-Item -ItemType Directory -Force $DataDir | Out-Null
$env:TEMP = Join-Path $test 'temp'
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
Import-Fonctions 'voix.ps1' 'Step-Ecoute', 'Stop-Ecoute', 'Stop-EcouteSansSuite', 'Remove-SonDictee', 'Step-Transcription'
$script:Journal = New-Object System.Collections.ArrayList
function Write-Log([string]$t) { [void]$script:Journal.Add($t) }
$script:Dits = New-Object System.Collections.ArrayList
function Invoke-Parole([string]$t) { [void]$script:Dits.Add($t) }
function Invoke-Bip { }
function Set-VoixEtat([string]$t) { $script:Etat = $t }
function Show-Bulle { }
function Hide-Bulle { }
$script:Transcrits = New-Object System.Collections.ArrayList
function Start-Transcription([string]$Wav) { [void]$script:Transcrits.Add($Wav) }
$script:Dictees = New-Object System.Collections.ArrayList
function Invoke-Dictee([string]$t) { [void]$script:Dictees.Add($t) }
function Invoke-Reveil { }
function Confirm-Reveil { }
$ui = @{ BtnMicro = [pscustomobject]@{ Tag = $null }; MicHalo = [pscustomobject]@{ Opacity = 0 } }
$script:EcouteTimer = [pscustomobject]@{}; $script:EcouteTimer | Add-Member ScriptMethod Stop { }
$script:TranscriptionTimer = [pscustomobject]@{}; $script:TranscriptionTimer | Add-Member ScriptMethod Stop { }
$script:Bulle = $null

function New-FauxMicro([int]$Millis, [bool]$Voix = $false, [int]$Silence = 0) {
    $m = [pscustomobject]@{ Millis = $Millis; HeardVoice = $Voix; MillisSinceVoice = $Silence; Level = 0.0; Arrete = $false }
    $m | Add-Member ScriptMethod Stop { $this.Arrete = $true }
    $m | Add-Member ScriptMethod SaveWav { param($p) [IO.File]::WriteAllBytes($p, [byte[]](1, 2, 3)) }
    $m
}
function New-FausseHorloge([int]$Ms) { [pscustomobject]@{ ElapsedMilliseconds = [long]$Ms; Elapsed = [TimeSpan]::FromMilliseconds($Ms) } }
function Test-Ecoute([string]$Nom, $Ecoute, [bool]$DoitArreter, [scriptblock]$Verif = { $true }) {
    $script:Dits.Clear(); $script:Transcrits.Clear(); $script:Etat = ''
    $script:Ecoute = $Ecoute
    Step-Ecoute
    $arrete = -not $script:Ecoute
    Test-Cas $Nom ($arrete -eq $DoitArreter -and (& $Verif)) "(arrêtée : $arrete ; dit : $($script:Dits -join ' | ') ; état : $script:Etat)"
    $script:Ecoute = $null
}
# Micro débranché juste après le bip : 4 secondes passées, 0,3 seconde de son reçue
Test-Ecoute 'micro débranché : l''écoute s''arrête' @{ Mic = (New-FauxMicro 300); Source = 'bouton'; Debut = (New-FausseHorloge 4000); Tenu = $false; Mode = 'silence'; Silencieux = $false } $true
Test-Ecoute 'micro débranché : Evermind le dit' @{ Mic = (New-FauxMicro 300); Source = 'bouton'; Debut = (New-FausseHorloge 4000); Tenu = $false; Mode = 'silence'; Silencieux = $false } $true { @($script:Dits | Where-Object { $_ -match 'micro' }).Count -eq 1 -and $script:Etat -match 'branché' }
# Débranché au milieu de la phrase : ce qui a été dit est quand même écrit
Test-Ecoute 'débranché en pleine phrase : ce qui a été dit est écrit' @{ Mic = (New-FauxMicro 2500 $true 400); Source = 'bouton'; Debut = (New-FausseHorloge 6000); Tenu = $false; Mode = 'silence'; Silencieux = $false } $true { $script:Transcrits.Count -eq 1 }
# Après « OK Evermind », en attendant la confirmation (silencieux) : arrêt sans rien dire
Test-Ecoute 'débranché après « OK Evermind » : arrêt sans un mot' @{ Mic = (New-FauxMicro 1000); Source = 'eveil'; Debut = (New-FausseHorloge 5000); Tenu = $false; Mode = 'silence'; Silencieux = $true } $true { $script:Dits.Count -eq 0 }
# Raccourci gardé appuyé, micro débranché : l'écoute ne reste pas ouverte
Test-Ecoute 'raccourci gardé appuyé, micro débranché : arrêt' @{ Mic = (New-FauxMicro 800); Source = 'raccourci'; Debut = (New-FausseHorloge 3900); Tenu = $true; Mode = 'tenu'; Silencieux = $false } $true
# Le son arrive mais l'écoute dure trop (raccourci gardé 31 secondes) : arrêt quand même
Test-Ecoute 'écoute trop longue (31 s) : arrêt' @{ Mic = (New-FauxMicro 30800 $true 0); Source = 'raccourci'; Debut = (New-FausseHorloge 31000); Tenu = $true; Mode = 'tenu'; Silencieux = $false } $true
# Cas normaux : rien ne doit changer
Test-Ecoute 'micro qui démarre lentement (0,9 s sans son) : on écoute encore' @{ Mic = (New-FauxMicro 0); Source = 'bouton'; Debut = (New-FausseHorloge 900); Tenu = $false; Mode = 'silence'; Silencieux = $false } $false
Test-Ecoute 'on parle, le son arrive : on écoute encore' @{ Mic = (New-FauxMicro 4800 $true 200); Source = 'bouton'; Debut = (New-FausseHorloge 5000); Tenu = $false; Mode = 'silence'; Silencieux = $false } $false
Test-Ecoute 'silence normal de 7 s : « Je n''ai rien entendu »' @{ Mic = (New-FauxMicro 7100); Source = 'bouton'; Debut = (New-FausseHorloge 7300); Tenu = $false; Mode = 'silence'; Silencieux = $false } $true { @($script:Dits | Where-Object { $_ -match 'rien entendu' }).Count -eq 1 }
Test-Ecoute 'attente de « OK Evermind » qui suit son cours' @{ Mic = (New-FauxMicro 2900); Source = 'eveil'; Debut = (New-FausseHorloge 3000); Tenu = $false; Mode = 'silence'; Silencieux = $true } $false

# ---------------------------------------------------------------------------
# 3. Le son d'une phrase n'est jamais gardé
# ---------------------------------------------------------------------------
# Phrase écrite par whisper-cli (faux programme déjà fini) : le son est effacé, rien dans le dossier de données
$wav = Join-Path $env:TEMP "evermind-$PID.wav"; [IO.File]::WriteAllBytes($wav, [byte[]](1, 2, 3))
$out = Join-Path $env:TEMP 'texte.txt'; [IO.File]::WriteAllText($out, 'ajoute dentiste demain', [Text.Encoding]::UTF8)
$script:Dictees.Clear()
$script:Transcription = @{ Wav = $wav; Mode = ''; Debut = [Diagnostics.Stopwatch]::StartNew(); Process = [pscustomobject]@{ HasExited = $true }; Out = $out }
Step-Transcription
Test-Cas 'phrase écrite : elle est bien comprise' ($script:Dictees.Count -eq 1 -and $script:Dictees[0] -match 'dentiste')
Test-Cas 'phrase écrite : son effacé' (-not (Test-Path -LiteralPath $wav))
Test-Cas 'aucun son gardé dans les données (derniere-dictee.wav)' (-not @(Get-ChildItem -LiteralPath $DataDir -Recurse -Filter '*.wav').Count) "($(@(Get-ChildItem -LiteralPath $DataDir -Recurse -Filter '*.wav').Name -join ', '))"
# Après « OK Evermind » : le début de phrase gardé à part est effacé une fois relu avec la suite
$debut = Join-Path $env:TEMP "evermind-$PID-eveil-debut.wav"; [IO.File]::WriteAllBytes($debut, [byte[]](1, 2, 3))
function Join-Wav { }
$script:Ecoute = @{ Mic = (New-FauxMicro 3000 $true 1200); Source = 'eveil'; Debut = (New-FausseHorloge 3100); Tenu = $false; Mode = 'silence'; Silencieux = $false; Prefixe = $debut }
Stop-Ecoute
Test-Cas '« OK Evermind » : début de phrase effacé après relecture' (-not (Test-Path -LiteralPath $debut))
# Faux réveil : l'écoute s'arrête sans suite, le début de phrase est effacé aussi
[IO.File]::WriteAllBytes($debut, [byte[]](1, 2, 3)); $script:EveilDebut = $debut
$script:Ecoute = @{ Mic = (New-FauxMicro 1000); Source = 'eveil'; Debut = (New-FausseHorloge 1000); Tenu = $false; Mode = 'silence'; Silencieux = $true }
Stop-EcouteSansSuite
Test-Cas 'faux réveil : début de phrase effacé' (-not (Test-Path -LiteralPath $debut))
# Rien entendu après « OK Evermind » : le début de phrase n'attend pas
[IO.File]::WriteAllBytes($debut, [byte[]](1, 2, 3))
$script:Ecoute = @{ Mic = (New-FauxMicro 7000); Source = 'eveil'; Debut = (New-FausseHorloge 7000); Tenu = $false; Mode = 'silence'; Silencieux = $false; Prefixe = $debut }
Stop-Ecoute
Test-Cas 'rien dit après « OK Evermind » : début de phrase effacé' (-not (Test-Path -LiteralPath $debut))
# Les anciennes versions gardaient derniere-dictee.wav : il est effacé au démarrage, et le réglage dit vrai
$texteVoix = [IO.File]::ReadAllText((Join-Path $modules 'voix.ps1'), [Text.Encoding]::UTF8)
Test-Cas 'voix.ps1 : l''ancien derniere-dictee.wav est effacé' ($texteVoix -match "Delete\(\(Join-Path \`$DataDir 'derniere-dictee\.wav'\)\)" -and $texteVoix -notmatch 'Move-Item[^\r\n]*derniere-dictee')
$texteEveil = [IO.File]::ReadAllText((Join-Path $modules 'eveil.ps1'), [Text.Encoding]::UTF8)
Test-Cas 'réglage « OK Evermind » : texte vrai' ($texteEveil -match 'ta voix n''''est jamais gardée')

$env:TEMP = $tempAvant

# ---------------------------------------------------------------------------
# 5. Écoute arrêtée : le modèle Vosk est rendu (dans un powershell.exe à part : Vosk n'est pas installé ici, l'appel
#    à vosk_model_free se voit à l'erreur « libvosk.dll introuvable »)
# ---------------------------------------------------------------------------
$sortie5 = Join-Path $test 'vosk.txt'
$essai5 = Join-Path $test 'vosk.ps1'
[IO.File]::WriteAllText($essai5, @"
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText('$natif', [Text.Encoding]::UTF8))
    `$e = New-Object EMEveil
    `$champ = [EMEveil].GetField('model', [Reflection.BindingFlags]'NonPublic, Instance')
    `$champ.SetValue(`$e, [IntPtr]1)   # (un faux modèle : jamais donné à un vrai Vosk)
    `$r = try { `$e.Stop(); if ([IntPtr]`$champ.GetValue(`$e) -eq [IntPtr]::Zero) { 'rendu' } else { 'garde' } } catch { if ("`$_" -match 'vosk') { 'rendu' } else { "erreur `$_" } }
    [IO.File]::WriteAllText('$sortie5', `$r)
} catch { [IO.File]::WriteAllText('$sortie5', "erreur `$_") }
"@, (New-Object Text.UTF8Encoding $true))
$p5 = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$essai5`"" -WindowStyle Hidden -PassThru
if (-not $p5.WaitForExit(60000)) { $p5.Kill() }
$lu5 = if (Test-Path -LiteralPath $sortie5) { [IO.File]::ReadAllText($sortie5) } else { 'pas de réponse' }
Test-Cas 'écoute arrêtée : le modèle Vosk est rendu' ($lu5 -eq 'rendu') "($lu5)"
$eveilTexte = [IO.File]::ReadAllText((Join-Path $modules 'eveil.ps1'), [Text.Encoding]::UTF8)
Test-Cas 'micro indisponible au départ : le modèle est rendu aussi' ($eveilTexte -match 'micro indisponible \(code \$err\)"; try \{ \$e\.Stop\(\) \}')

# ---------------------------------------------------------------------------
# 6. Écoute arrêtée pendant que la boucle d'écoute est encore dans Vosk (PC très occupé) : rien n'est rendu sous
#    elle, la fenêtre n'attend pas plus d'une seconde, et c'est la boucle qui rend tout en sortant.
#    Une fausse boucle (un fil qui dure 3 s, puis 0,1 s) remplace celle du micro ; Vosk n'est pas installé ici :
#    chaque libération se voit à l'erreur « libvosk.dll introuvable ».
# 7. Chemin du modèle Vosk donné dans la page de code de Windows (nom d'utilisateur accentué), ou par son nom court.
# ---------------------------------------------------------------------------
$sortie6 = Join-Path $test 'boucle.txt'
$essai6 = Join-Path $test 'boucle.ps1'
$dossierAutre = Join-Path $test ('modele-' + [char]0x0414 + [char]0x0438 + [char]0x043C + [char]0x0430)   # (lettres russes)
New-Item -ItemType Directory -Force $dossierAutre | Out-Null
[IO.File]::WriteAllText($essai6, @'
param([string]$Natif, [string]$Sortie, [string]$Autre)
$r = @()
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($Natif, [Text.Encoding]::UTF8))
    Add-Type -TypeDefinition @"
using System; using System.Reflection; using System.Threading;
public static class FausseBoucle {
    public static string Note = "";
    public static Thread Lancer(object e, int ms) {
        Thread t = new Thread(() => {
            Thread.Sleep(ms);
            try {
                MethodInfo m = e.GetType().GetMethod("FinDeBoucle", BindingFlags.NonPublic | BindingFlags.Instance);
                if (m == null) { Note = "pas de fin de boucle"; return; }
                m.Invoke(e, null); Note = "sortie sans rien rendre";
            } catch (Exception x) { Exception y = x.InnerException ?? x; Note = (y is DllNotFoundException) ? "rendu par la boucle" : "erreur " + y.Message; }
        });
        t.IsBackground = true; t.Start(); return t;
    }
}
"@
    $bf = [Reflection.BindingFlags]'NonPublic, Instance'
    foreach ($ms in 3000, 100) {
        [FausseBoucle]::Note = ''
        $e = New-Object EMEveil
        [EMEveil].GetField('model', $bf).SetValue($e, [IntPtr]1)   # (faux modèle et faux recognizer : jamais donnés à un vrai Vosk)
        [EMEveil].GetField('rec', $bf).SetValue($e, [IntPtr]2)
        $t = [FausseBoucle]::Lancer($e, $ms)
        [EMEveil].GetField('th', $bf).SetValue($e, $t)
        $chrono = [Diagnostics.Stopwatch]::StartNew()
        $arret = try { $e.Stop(); 'rien rendu' } catch { if ($_.Exception.InnerException -is [DllNotFoundException] -or $_.Exception -is [DllNotFoundException]) { 'rendu' } else { "erreur $_" } }
        $duree = $chrono.ElapsedMilliseconds
        $vivant = $t.IsAlive
        [void]$t.Join(10000)
        $r += "$ms;$arret;$vivant;$(if ($duree -lt 2000) { 'vite' } else { "lent $duree" });$([FausseBoucle]::Note)"
    }
    $acp = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
    $nom = 'C:\Users\J' + [char]0xE9 + 'r' + [char]0xF4 + 'me\modele'
    $b = [EMEveil]::CheminVosk($nom)
    $r += "accent;$(([Convert]::ToBase64String($b)) -eq [Convert]::ToBase64String($acp.GetBytes($nom + [char]0)))"
    $b = [EMEveil]::CheminVosk($Autre)
    $court = $acp.GetString($b, 0, $b.Length - 1)
    $sansNomCourt = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($Autre).ShortPath -eq $Autre
    $r += "autre;$((Test-Path -LiteralPath $court) -or $sansNomCourt)"
} catch { $r += "erreur $_" }
[IO.File]::WriteAllLines($Sortie, [string[]]$r)
'@, (New-Object Text.UTF8Encoding $true))
$p6 = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$essai6`"", '-Natif', "`"$natif`"", '-Sortie', "`"$sortie6`"", '-Autre', "`"$dossierAutre`"" -WindowStyle Hidden -PassThru
if (-not $p6.WaitForExit(60000)) { $p6.Kill() }
$lu6 = if (Test-Path -LiteralPath $sortie6) { @([IO.File]::ReadAllLines($sortie6)) } else { @('pas de réponse') }
Test-Cas 'écoute arrêtée, boucle encore dans Vosk : rien rendu sous elle, sans attendre' ($lu6 -contains '3000;rien rendu;True;vite;rendu par la boucle') "($($lu6 -join ' / '))"
Test-Cas 'écoute arrêtée, boucle sortie à temps : tout est rendu tout de suite' ($lu6 -contains '100;rendu;False;vite;sortie sans rien rendre') "($($lu6 -join ' / '))"
Test-Cas 'modèle Vosk dans un dossier accentué : chemin dans la page de code de Windows' ($lu6 -contains 'accent;True') "($($lu6 -join ' / '))"
Test-Cas 'modèle Vosk dans un dossier en lettres étrangères : nom court' ($lu6 -contains 'autre;True') "($($lu6 -join ' / '))"

# ---------------------------------------------------------------------------
# 8. Assistant arrêté de force (occupé, il ne lit plus son entrée) : le modèle qu'il avait lancé (llama-server) s'arrête
#    avec lui, sans attendre la fermeture d'Evermind. Un faux assistant (petit programme compilé ici) lance ping.exe
#    comme l'assistant lance llama-server, puis n'écoute plus ; un faux Evermind le démarre et l'arrête avec les
#    vraies fonctions Start-Cerveau et Stop-Cerveau.
# ---------------------------------------------------------------------------
$fauxAssistant = Join-Path $test 'faux-assistant.exe'
Add-Type -OutputType ConsoleApplication -OutputAssembly $fauxAssistant -TypeDefinition @'
using System; using System.Diagnostics; using System.IO; using System.Threading;
public static class FauxAssistant {
    public static void Main() {
        ProcessStartInfo psi = new ProcessStartInfo(Environment.GetEnvironmentVariable("SystemRoot") + "\\System32\\PING.EXE", "-n 120 127.0.0.1");
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = true;
        Process p = Process.Start(psi);
        File.WriteAllText(Environment.GetEnvironmentVariable("EVERMIND_TEST_MODELE_PID"), p.Id.ToString());
        Thread.Sleep(120000);
    }
}
'@
$sortie8 = Join-Path $test 'assistant.txt'
$essai8 = Join-Path $test 'assistant.ps1'
[IO.File]::WriteAllText($essai8, @'
param([string]$Natif, [string]$Modules, [string]$Exe, [string]$Sortie, [string]$Dossier)
$r = 'pas fini'
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($Natif, [Text.Encoding]::UTF8))
    $script:Journal = @()
    function Write-Log([string]$t) { $script:Journal += $t }
    foreach ($f in @(@('voix.ps1', 'Add-ProgrammeAide'), @('cerveau.ps1', 'Start-Cerveau'), @('cerveau.ps1', 'Stop-Cerveau'))) {
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Modules $f[0]), [ref]$null, [ref]$null)
        $d = $ast.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $f[1] }, $true)
        . ([scriptblock]::Create($d.Extent.Text))
    }
    function Test-CerveauInstalle { $true }
    function Get-CopieMindset($e) { $e }
    $JavaExe = $Exe; $AssistantLib = $Dossier; $LlamaExe = $Exe; $IaModele = $Exe; $DataDir = $Dossier; $IaDir = $Dossier
    $pidFichier = Join-Path $Dossier 'modele-pid.txt'
    $env:EVERMIND_TEST_MODELE_PID = $pidFichier
    if (-not (Start-Cerveau)) { throw "assistant pas démarré : $($script:Journal -join ' ')" }
    $limite = (Get-Date).AddSeconds(20)
    while (-not (Test-Path -LiteralPath $pidFichier) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 200
    $modele = [int][IO.File]::ReadAllText($pidFichier)
    $assistant = $script:Cerveau.Process.Id
    Stop-Cerveau
    $limite = (Get-Date).AddSeconds(3)
    while ((Get-Process -Id $modele -ErrorAction SilentlyContinue) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 100 }
    $vivant = [bool](Get-Process -Id $modele -ErrorAction SilentlyContinue)
    $r = "$modele;$assistant;$(if ($vivant) { 'modèle vivant' } else { 'modèle arrêté' })"
} catch { $r = "erreur $_" }
[IO.File]::WriteAllText($Sortie, $r)
'@, (New-Object Text.UTF8Encoding $true))
$p8 = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$essai8`"", '-Natif', "`"$natif`"", '-Modules', "`"$modules`"", '-Exe', "`"$fauxAssistant`"", '-Sortie', "`"$sortie8`"", '-Dossier', "`"$test`"" -WindowStyle Hidden -PassThru
if (-not $p8.WaitForExit(60000)) { $p8.Kill() }
$lu8 = if (Test-Path -LiteralPath $sortie8) { [IO.File]::ReadAllText($sortie8) } else { 'pas de réponse' }
# (ménage : seulement les numéros notés par ce test)
foreach ($n in @($lu8 -split ';' | Select-Object -First 2)) { if ($n -match '^\d+$') { Get-Process -Id ([int]$n) -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in 'PING', 'faux-assistant' } | Stop-Process -Force -ErrorAction SilentlyContinue } }
Test-Cas 'assistant arrêté de force : le modèle qu''il avait lancé s''arrête avec lui' ($lu8 -match ';modèle arrêté$') "($lu8)"

# ---------------------------------------------------------------------------
# 9. Whisper n'est « prêt » que si c'est bien lui qui écoute sur son port (vraie fonction Read-WhisperServeur) :
#    un autre programme qui a pris le port (ici, ce test lui-même) ne reçoit jamais la phrase dictée.
# ---------------------------------------------------------------------------
$sortie9 = Join-Path $test 'port.txt'
$essai9 = Join-Path $test 'port.ps1'
[IO.File]::WriteAllText($essai9, @'
param([string]$Natif, [string]$Modules, [string]$Sortie)
$r = @()
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($Natif, [Text.Encoding]::UTF8))
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Modules 'voix.ps1'), [ref]$null, [ref]$null)
    $d = $ast.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Read-WhisperServeur' }, $true)
    . ([scriptblock]::Create($d.Extent.Text))
    $muet = [pscustomobject]@{}; $muet | Add-Member ScriptMethod Suivante { $false }
    $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port
    $autre = 4   # (un autre numéro de programme : celui de Windows lui-même)
    foreach ($cas in @(@('autre programme', $autre), @('lui', $PID))) {
        $s = @{ Port = $port; Pret = $false; Process = [pscustomobject]@{ Id = $cas[1] }; Sortie = $muet; Erreurs = $muet }
        Read-WhisperServeur $s
        $r += "$($cas[0]);$($s.Pret)"
    }
    $l.Stop()
    $s = @{ Port = $port; Pret = $false; Process = [pscustomobject]@{ Id = $PID }; Sortie = $muet; Erreurs = $muet }
    Read-WhisperServeur $s
    $r += "personne;$($s.Pret)"
} catch { $r += "erreur $_" }
[IO.File]::WriteAllLines($Sortie, [string[]]$r)
'@, (New-Object Text.UTF8Encoding $true))
$p9 = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$essai9`"", '-Natif', "`"$natif`"", '-Modules', "`"$modules`"", '-Sortie', "`"$sortie9`"" -WindowStyle Hidden -PassThru
if (-not $p9.WaitForExit(60000)) { $p9.Kill() }
$lu9 = if (Test-Path -LiteralPath $sortie9) { @([IO.File]::ReadAllLines($sortie9)) } else { @('pas de réponse') }
Test-Cas 'Whisper : port pris par un autre programme, pas prêt' ($lu9 -contains 'autre programme;False') "($($lu9 -join ' / '))"
Test-Cas 'Whisper : c''est lui qui écoute, prêt' ($lu9 -contains 'lui;True') "($($lu9 -join ' / '))"
Test-Cas 'Whisper : personne n''écoute, pas prêt' ($lu9 -contains 'personne;False') "($($lu9 -join ' / '))"

Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
exit $(if ($ok) { 0 } else { 1 })
