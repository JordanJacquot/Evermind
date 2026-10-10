# Evermind : la voix. On appuie sur Ctrl + Maj + Espace (même en jeu) ou sur le micro, on parle,
# Whisper écrit ce qu'on a dit, Evermind le comprend et répond avec une voix naturelle (Piper).
# Tout se passe sur le PC : rien n'est envoyé sur Internet.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# ---------------------------------------------------------------------------
# Module de voix (dictée Whisper et voix Piper), téléchargé une seule fois dans le dossier de données
# ---------------------------------------------------------------------------
# Versions fixées et vérifiées : si un fichier téléchargé n'a pas exactement l'empreinte attendue, il est refusé.
$VoixDir   = if ($env:EVERMIND_VOIX) { $env:EVERMIND_VOIX } else { Join-Path $DataDir 'voix' }   # à part pour les tests
$WhisperExe = Join-Path $VoixDir 'whisper-cli.exe'
$WhisperModele = Join-Path $VoixDir 'ggml-small-q5_1.bin'
$PiperExe = Join-Path $VoixDir 'piper\piper.exe'
$HfPiper = 'https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR'
$IaDir = Join-Path $VoixDir 'ia'
$LlamaExe = Join-Path $IaDir 'llama-server.exe'
$IaModele = Join-Path $IaDir 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf'
#   Pack : « voix » (dictée et voix) ou « ia » (l'assistant qui comprend tout)
#   Extraire : fichiers gardés d'un zip (tout le reste est ignoré), rangés dans le sous-dossier Vers
#   Garder : le fichier qui montre que c'est déjà installé
$VoixFichiers = @(
    @{ Pack = 'voix'; Nom = 'programme de dictée'; Url = 'https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-bin-x64.zip'
       Sha256 = '49DCC16DE826F20BD53D44F947A1AE49DFA81F86CAD67A64D80820CB192D674A'; Taille = 8194445
       Extraire = '^Release/(whisper-cli\.exe|whisper\.dll|ggml[^/]*\.dll)$'; Vers = ''; Garder = $WhisperExe }
    @{ Pack = 'voix'; Nom = 'modèle de français'; Url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin'
       Sha256 = 'AE85E4A935D7A567BD102FE55AFC16BB595BDB618E11B2FC7591BC08120411BB'; Taille = 190085487; Garder = $WhisperModele }
    @{ Pack = 'voix'; Nom = 'programme de voix'; Url = 'https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip'
       Sha256 = 'F3C58906402B24F3A96D92145F58ACBA6D86C9B5DB896D207F78DC80811EFCEA'; Taille = 22477236
       Extraire = '^piper/(?!pkgconfig/).+[^/]$'; Vers = ''; Garder = $PiperExe }
    @{ Pack = 'voix'; Nom = 'voix de Siwis'; Url = "$HfPiper/siwis/medium/fr_FR-siwis-medium.onnx"
       Sha256 = '641D1AB097DA2B81128C076810EDB052B385DECC8BE3381814802A64A73BAF99'; Taille = 63201294; Garder = (Join-Path $VoixDir 'fr_FR-siwis-medium.onnx') }
    @{ Pack = 'voix'; Nom = 'voix de Siwis'; Url = "$HfPiper/siwis/medium/fr_FR-siwis-medium.onnx.json"
       Sha256 = '39479916C2DB192B5AC9764DADDD0C744D83E023AD890C6976C0633AE4DF8959'; Taille = 4875; Garder = (Join-Path $VoixDir 'fr_FR-siwis-medium.onnx.json') }
    @{ Pack = 'voix'; Nom = 'voix de Jessica et Pierre'; Url = "$HfPiper/upmc/medium/fr_FR-upmc-medium.onnx"
       Sha256 = '9ABB3800C199148897A9ED64E100D224F3DE83579F100044174AD19418F1786F'; Taille = 76733615; Garder = (Join-Path $VoixDir 'fr_FR-upmc-medium.onnx') }
    @{ Pack = 'voix'; Nom = 'voix de Jessica et Pierre'; Url = "$HfPiper/upmc/medium/fr_FR-upmc-medium.onnx.json"
       Sha256 = 'E8636EC15DFD5D72DB37A02CB5320A20F2B8D339F2A0E4337DA64C58A33A5868'; Taille = 4996; Garder = (Join-Path $VoixDir 'fr_FR-upmc-medium.onnx.json') }
    # L'assistant : llama.cpp (version Vulkan : carte graphique NVIDIA, AMD ou Intel, sinon le processeur) et le modèle Qwen3 4B
    @{ Pack = 'ia'; Nom = 'moteur de l''assistant'; Url = 'https://github.com/ggml-org/llama.cpp/releases/download/b11541/llama-b11541-bin-win-vulkan-x64.zip'
       Sha256 = '37BBA511D120222F13C3D520DD875F739A530CC124E78F7CBCE0026DE0173D8A'; Taille = 33464528
       Extraire = '^(llama-server\.exe|llama-server-impl\.dll|llama\.dll|llama-common\.dll|ggml[^/]*\.dll|mtmd\.dll|libomp\.dll)$'; Vers = 'ia'; Garder = $LlamaExe }
    @{ Pack = 'ia'; Nom = 'cerveau de l''assistant'; Url = 'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf'
       Sha256 = '3605803B982CB64AEAD44F6C1B2AE36E3ACDB41D8E46C8A94C6533BC4C67E597'; Taille = 2497281120; Garder = $IaModele }
)

# Voix au choix (réglages). Hortense est la voix de Windows : toujours là, mais robotique.
$VoixListe = [ordered]@{
    siwis   = @{ Nom = 'Siwis'; Desc = 'Voix de femme, douce'; Modele = 'fr_FR-siwis-medium.onnx'; Locuteur = $null }
    jessica = @{ Nom = 'Jessica'; Desc = 'Voix de femme, claire'; Modele = 'fr_FR-upmc-medium.onnx'; Locuteur = 0 }
    pierre  = @{ Nom = 'Pierre'; Desc = 'Voix d''homme'; Modele = 'fr_FR-upmc-medium.onnx'; Locuteur = 1 }
    windows = @{ Nom = 'Hortense'; Desc = 'Voix de Windows : plus robotique, mais sans téléchargement'; Modele = $null }
}

function Test-DicteeInstallee { (Test-Path -LiteralPath $WhisperExe) -and (Test-Path -LiteralPath $WhisperModele) }
function Get-VoixManquants([string]$Pack = 'voix') { @($VoixFichiers | Where-Object { $_.Pack -eq $Pack -and -not (Test-Path -LiteralPath $_.Garder) }) }
function Test-VoixInstallee { (Get-VoixManquants 'voix').Count -eq 0 }
function Test-CerveauInstalle { (Get-VoixManquants 'ia').Count -eq 0 }

# Téléchargement en arrière plan de ce qui manque : la fenêtre suit l'avancement grâce à $script:VoixDl
function Start-VoixInstall([string]$Pack) {
    if ($script:VoixDl -and -not $script:VoixDl.Fini) { return }
    if (-not $Pack) { $Pack = if (Test-VoixInstallee) { 'ia' } else { 'voix' } }
    $manquants = Get-VoixManquants $Pack
    $script:VoixDl = [hashtable]::Synchronized(@{ Recu = 0L; Total = [long](($manquants | ForEach-Object { $_.Taille }) | Measure-Object -Sum).Sum; Etape = ''; Erreur = ''; Fini = $false; Pack = $Pack })
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($Etat, $Fichiers, $Dossier)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            New-Item -ItemType Directory -Force -Path $Dossier | Out-Null
            $deja = 0L
            foreach ($f in $Fichiers) {
                $Etat.Etape = $f.Nom
                $tmp = Join-Path $Dossier ([IO.Path]::GetFileName($f.Url) + '.telechargement')
                $req = [Net.WebRequest]::Create($f.Url)
                $req.UserAgent = 'Evermind'
                $resp = $req.GetResponse()
                $in = $resp.GetResponseStream()
                $out = [IO.File]::Create($tmp)
                $sha = [Security.Cryptography.SHA256]::Create()
                $buf = New-Object byte[] 65536
                try {
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                        $out.Write($buf, 0, $n); [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
                        $Etat.Recu = $deja + $out.Length
                    }
                    [void]$sha.TransformFinalBlock($buf, 0, 0)
                } finally { $out.Dispose(); $in.Dispose(); $resp.Dispose() }
                $hash = -join ($sha.Hash | ForEach-Object { $_.ToString('X2') })
                if ($hash -ne $f.Sha256) { Remove-Item -LiteralPath $tmp -Force; throw "le fichier « $($f.Nom) » reçu n'est pas le bon (empreinte différente)" }
                $deja += $f.Taille
                if ($f.Extraire) {
                    # Seuls les fichiers utiles du zip sont gardés, à leur place
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    $zip = [IO.Compression.ZipFile]::OpenRead($tmp)
                    try {
                        foreach ($e in $zip.Entries) {
                            if ($e.FullName -notmatch $f.Extraire) { continue }
                            $rel = if ($e.FullName -like 'Release/*') { $e.Name } else { $e.FullName }
                            $dest = Join-Path (Join-Path $Dossier ([string]$f.Vers)) ($rel -replace '/', '\')
                            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                        }
                    } finally { $zip.Dispose() }
                    Remove-Item -LiteralPath $tmp -Force
                } else { New-Item -ItemType Directory -Force -Path (Split-Path $f.Garder) | Out-Null; Move-Item -LiteralPath $tmp -Destination $f.Garder -Force }
            }
        } catch { $Etat.Erreur = $_.Exception.Message }
        $Etat.Fini = $true
    }).AddArgument($script:VoixDl).AddArgument($manquants).AddArgument($VoixDir)
    $script:VoixDl.PS = $ps
    $script:VoixDl.Handle = $ps.BeginInvoke()
    Write-Log "Installation ($Pack, $([math]::Round($script:VoixDl.Total / 1MB)) Mo)"
    Update-VoixInstall
    if (-not $script:VoixDlTimer) {
        $script:VoixDlTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:VoixDlTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $script:VoixDlTimer.Add_Tick({ Update-VoixInstall })
    }
    $script:VoixDlTimer.Start()
}

# Panneau d'installation : ce qui manque (la voix d'abord, puis l'assistant), bouton, barre d'avancement
function Update-VoixInstall {
    $dl = $script:VoixDl
    $enCours = $dl -and -not $dl.Fini
    if ($dl -and $dl.Fini -and -not $dl.Annonce -and -not $dl.Erreur) {
        $dl.Annonce = $true
        if ($dl.Pack -eq 'eveil') {
            Write-Log 'Écoute « OK Eve » installée'
            Start-Eveil
            try { Update-EveilReglage } catch {}
            Invoke-Parole 'C''est prêt. Dis OK Eve quand tu veux me parler.'
        } elseif ($dl.Pack -eq 'ia') {
            Write-Log 'Assistant installé'
            Set-VoixEtat 'L''assistant est prêt : parle-lui comme à quelqu''un (« décale le dentiste à jeudi », « qu''est-ce que j''ai demain ? »).'
            Invoke-Parole 'L''assistant est prêt. Tu peux me demander ce que tu veux sur ton agenda.'
        } else {
            Write-Log 'Voix installée'
            Set-VoixEtat 'La voix est prête. Appuie sur le micro ou sur Ctrl + Maj + Espace et parle. (Réglages : choisir la voix qui te répond.)'
            Invoke-Parole 'C''est prêt ! Tu peux me parler.'
        }
    }
    $voix = Test-VoixInstallee
    $ia = Test-CerveauInstalle
    $plusTard = [bool](Get-Setting 'AssistantPlusTard' $false)
    if (-not $enCours -and $voix -and ($ia -or $plusTard)) {
        $ui.VoixInstall.Visibility = 'Collapsed'
        if ($script:VoixDlTimer) { $script:VoixDlTimer.Stop() }
        return
    }
    $ui.VoixInstall.Visibility = 'Visible'
    $ui.BtnVoixPlusTard.Visibility = 'Collapsed'
    if ($enCours) {
        $pct = if ($dl.Total) { [math]::Min(1, $dl.Recu / $dl.Total) } else { 0 }
        $ui.VoixBarre.Width = [math]::Max(4, $ui.VoixBarreFond.ActualWidth * $pct)
        $ui.VoixBarreFond.Visibility = 'Visible'
        $ui.VoixInstallTexte.Text = "Téléchargement : $($dl.Etape)... $([math]::Round($dl.Recu / 1MB)) Mo sur $([math]::Round($dl.Total / 1MB)) Mo"
        $ui.BtnVoixInstall.IsEnabled = $false
        return
    }
    $ui.VoixBarreFond.Visibility = 'Collapsed'
    $ui.BtnVoixInstall.IsEnabled = $true
    if ($script:VoixDlTimer) { $script:VoixDlTimer.Stop() }
    $pack = if ($voix) { 'ia' } else { 'voix' }
    $mo = [math]::Round(((Get-VoixManquants $pack | ForEach-Object { $_.Taille }) | Measure-Object -Sum).Sum / 1MB)
    if ($dl -and $dl.Erreur -and $dl.Pack -eq $pack) {
        $ui.VoixInstallTexte.Text = "Le téléchargement n'a pas marché ($($dl.Erreur)). Vérifie Internet et réessaie."
        $ui.BtnVoixInstall.Content = 'Réessayer'
        if (-not $dl.Annonce) { $dl.Annonce = $true; Write-Log "Installation ($($dl.Pack)) : $($dl.Erreur)" }
    } elseif ($pack -eq 'ia') {
        $go = [math]::Round($mo / 1024, 1).ToString($Fr)
        $ui.VoixInstallTexte.Text = "Nouveau : l'assistant qui comprend tout ce que tu dis (« décale le dentiste à jeudi », « supprime le foot », « qu'est-ce que j'ai demain ? »). C'est une petite IA qui tourne sur ton PC : $go Go à télécharger une fois, rien ne part sur Internet."
        $ui.BtnVoixInstall.Content = 'Installer l''assistant'
        $ui.BtnVoixPlusTard.Visibility = 'Visible'
    } else {
        $ui.VoixInstallTexte.Text = "Pour comprendre ta voix et te répondre avec une voix naturelle, il me faut un module de $mo Mo, téléchargé une seule fois. Ensuite tout se passe sur ton PC : ta voix ne part nulle part."
        $ui.BtnVoixInstall.Content = 'Installer la voix'
    }
}

# ---------------------------------------------------------------------------
# Parler (réponse à voix haute)
# ---------------------------------------------------------------------------
# Voix naturelle Piper (Siwis, Jessica ou Pierre) ; la voix de Windows si le module de voix n'est pas là.
# Piper écrit la phrase dans un fichier son en moins d'une seconde, puis Evermind la joue.
function Invoke-Parole([string]$Texte, [string]$Voix) {
    if ($EnTest -and -not $env:EVERMIND_TEST_PAROLE) { Write-Log "Parole : $Texte"; return }
    if (-not $Voix) { $Voix = [string](Get-Setting 'Voix' 'siwis') }
    $v = $VoixListe[$Voix]
    if (-not $v) { $v = $VoixListe['siwis'] }
    $modele = if ($v.Modele) { Join-Path $VoixDir $v.Modele }
    if ($modele -and (Test-Path -LiteralPath $PiperExe) -and (Test-Path -LiteralPath $modele)) {
        try { Start-PiperParole $Texte $modele $v.Locuteur; return } catch { Write-Log "Voix naturelle impossible : $_" }
    }
    Invoke-ParoleWindows $Texte
}

function Invoke-ParoleWindows([string]$Texte) {
    try {
        if (-not $script:Synth) {
            Add-Type -AssemblyName System.Speech
            $script:Synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $v = $script:Synth.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like 'fr*' } | Select-Object -First 1
            if ($v) { $script:Synth.SelectVoice($v.VoiceInfo.Name) }
            $script:Synth.SetOutputToDefaultAudioDevice()
        }
        Stop-Parole
        [void]$script:Synth.SpeakAsync($Texte)
    } catch { Write-Log "Parole impossible : $_" }
}

# Coupe ce qui est en train d'être dit (une nouvelle phrase remplace l'ancienne)
function Stop-Parole {
    try { if ($script:Synth) { $script:Synth.SpeakAsyncCancelAll() } } catch {}
    try { if ($script:Lecteur) { $script:Lecteur.Stop() } } catch {}
    if ($script:Piper) { try { if (-not $script:Piper.Process.HasExited) { $script:Piper.Process.Kill() } } catch {}; $script:Piper = $null }
}

function Start-PiperParole([string]$Texte, [string]$Modele, $Locuteur) {
    Stop-Parole
    $script:PiperNum = 1 - [int]$script:PiperNum   # deux fichiers en alternance : l'ancien peut encore être lu
    $wav = Join-Path $env:TEMP "evermind-$PID-parole$($script:PiperNum).wav"
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $PiperExe
    $psi.Arguments = "-m `"$Modele`" -f `"$wav`" -q" + $(if ($null -ne $Locuteur) { " -s $Locuteur" } else { '' })
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.WorkingDirectory = Split-Path $PiperExe
    $p = [Diagnostics.Process]::Start($psi)
    $w = New-Object IO.StreamWriter($p.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
    $w.WriteLine(($Texte -replace '\s+', ' ')); $w.Close()
    $script:Piper = @{ Process = $p; Wav = $wav; Debut = [Diagnostics.Stopwatch]::StartNew() }
    if (-not $script:PiperTimer) {
        $script:PiperTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:PiperTimer.Interval = [TimeSpan]::FromMilliseconds(60)
        $script:PiperTimer.Add_Tick({
            $pp = $script:Piper
            if (-not $pp) { $script:PiperTimer.Stop(); return }
            if (-not $pp.Process.HasExited) { if ($pp.Debut.Elapsed.TotalSeconds -gt 20) { try { $pp.Process.Kill() } catch {} }; return }
            $script:Piper = $null; $script:PiperTimer.Stop()
            if ($pp.Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pp.Wav)) { Write-Log "Voix naturelle : échec (code $($pp.Process.ExitCode))"; return }
            if ($EnTest) { Write-Log "Voix naturelle prête : $((Get-Item -LiteralPath $pp.Wav).Length) octets en $([math]::Round($pp.Debut.Elapsed.TotalSeconds, 2)) s"; return }   # test : pas de son
            try {
                $script:Lecteur = New-Object System.Media.SoundPlayer $pp.Wav
                $script:Lecteur.Play()
                # « OK Eve » reste en pause le temps que la phrase soit dite
                $oct = (Get-Item -LiteralPath $pp.Wav).Length; $fs = [IO.File]::OpenRead($pp.Wav); $hd = New-Object byte[] 44; [void]$fs.Read($hd, 0, 44); $fs.Close()
                $script:EveilReprise = (Get-Date).AddSeconds(($oct - 44) / [math]::Max(1, [BitConverter]::ToInt32($hd, 28)) + 0.8)
            } catch { Write-Log "Lecture de la voix : $_" }
        })
    }
    $script:PiperTimer.Start()
}

# « 15 h 30 » se dit « 15 heures 30 » ; un anniversaire n'a pas d'heure
function Format-QuandParle([datetime]$d, $RV) {
    $t = if ($RV) { Format-QuandRV $RV $d } else { Format-Quand $d }
    $t -replace '(\d+) h (\d+)', '$1 heures $2' -replace '(\d+) h$', '$1 heures'
}

# ---------------------------------------------------------------------------
# Réglages : choisir la voix, en l'écoutant
# ---------------------------------------------------------------------------
function Update-VoixChoix {
    $ui.VoixChoix.Children.Clear()
    $choisie = [string](Get-Setting 'Voix' 'siwis')
    $piper = Test-Path -LiteralPath $PiperExe
    foreach ($k in $VoixListe.Keys) {
        $v = $VoixListe[$k]
        $dispo = (-not $v.Modele) -or ($piper -and (Test-Path -LiteralPath (Join-Path $VoixDir $v.Modele)))
        $on = $k -eq $choisie
        $b = New-Object System.Windows.Controls.Border
        $b.CornerRadius = 16; $b.Padding = '16,12'; $b.Margin = '0,0,0,8'; $b.BorderThickness = 1.5; $b.Tag = $k
        $b.Background = Get-Brush $(if ($on) { '#2600E5FF' } else { '#0FFFFFFF' })
        $b.BorderBrush = if ($on) { $Window.FindResource('AccentBg') } else { Get-Brush '#1CFFFFFF' }
        $b.Cursor = if ($dispo) { 'Hand' } else { 'Arrow' }
        $b.Opacity = if ($dispo) { 1 } else { 0.45 }
        $dp = New-Object System.Windows.Controls.DockPanel
        $ec = New-Object System.Windows.Controls.TextBlock
        $ec.Text = if (-not $dispo) { 'à installer' } elseif ($on) { '✓ choisie' } else { '▶ écouter' }
        $ec.Foreground = Get-Brush $(if ($on) { '#7FF4FF' } else { $Colors.dim }); $ec.FontSize = 13; $ec.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($ec, 'Right')
        [void]$dp.Children.Add($ec)
        $sp = New-Object System.Windows.Controls.StackPanel
        $n = New-Object System.Windows.Controls.TextBlock; $n.Text = $v.Nom; $n.FontSize = 16; $n.FontWeight = 'SemiBold'; $n.Foreground = Get-Brush '#FFFFFF'
        $d = New-Object System.Windows.Controls.TextBlock; $d.Text = $v.Desc; $d.FontSize = 13; $d.Foreground = Get-Brush $Colors.dim
        [void]$sp.Children.Add($n); [void]$sp.Children.Add($d)
        [void]$dp.Children.Add($sp)
        $b.Child = $dp
        if ($dispo) {
            $b.Add_MouseLeftButtonUp({
                param($s)
                $k = [string]$s.Tag
                Set-Setting 'Voix' $k
                Update-VoixChoix
                Invoke-Parole "Salut ! Moi, c'est $($VoixListe[$k].Nom). C'est noté : dentiste, mardi à 15 heures 30." $k
            })
        }
        [void]$ui.VoixChoix.Children.Add($b)
    }
    $ui.VoixReglageInfo.Visibility = if ($piper) { 'Collapsed' } else { 'Visible' }
    $ui.VoixReglageInfo.Text = 'Les voix naturelles arrivent avec le module de voix : appuie sur « Installer la voix » sur l''écran principal.'
}

function Update-AssistantEtat {
    $ok = Test-CerveauInstalle
    $ui.BtnAssistant.Visibility = if ($ok) { 'Collapsed' } else { 'Visible' }
    $ui.AssistantEtat.Text = if ($ok) { 'Installé. Parle-lui comme à quelqu''un : « décale le dentiste à jeudi », « supprime le foot », « qu''est-ce que j''ai demain ? », « annule ». Tout se passe sur ton PC.' }
                             else { 'Une petite IA sur ton PC (2,3 Go) pour tout comprendre : décaler, supprimer, ajouter des détails, répondre à tes questions. Rien ne part sur Internet.' }
}

function Open-Reglages { Update-VoixChoix; Update-AssistantEtat; Update-EveilReglage; $ui.Reglages.Visibility = 'Visible' }
function Close-Reglages { $ui.Reglages.Visibility = 'Collapsed' }

# Petit son au début et à la fin de l'écoute
function Invoke-Bip([bool]$Debut) {
    if ($EnTest) { return }
    try {
        $rate = 22050; $ms = 90
        $notes = if ($Debut) { 660, 990 } else { 990, 660 }
        $mem = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $mem
        $n = [int]($rate * $ms / 1000) * $notes.Count
        $w.Write([char[]]'RIFF'); $w.Write([int](36 + $n * 2)); $w.Write([char[]]'WAVEfmt '); $w.Write(16)
        $w.Write([int16]1); $w.Write([int16]1); $w.Write($rate); $w.Write($rate * 2); $w.Write([int16]2); $w.Write([int16]16)
        $w.Write([char[]]'data'); $w.Write([int]($n * 2))
        foreach ($f in $notes) {
            $len = [int]($rate * $ms / 1000)
            for ($i = 0; $i -lt $len; $i++) {
                $env = [math]::Min(1, [math]::Min($i, $len - $i) / 300.0)
                $w.Write([int16](5000 * $env * [math]::Sin(2 * [math]::PI * $f * $i / $rate)))
            }
        }
        $mem.Position = 0
        (New-Object System.Media.SoundPlayer $mem).Play()
    } catch {}
}

# ---------------------------------------------------------------------------
# Bulle « Je t'écoute » : petite fenêtre en haut de l'écran qui ne prend pas le focus
# ---------------------------------------------------------------------------
function Get-Bulle {
    if ($script:Bulle) { return $script:Bulle }
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'; $w.AllowsTransparency = $true; $w.Background = [System.Windows.Media.Brushes]::Transparent
    $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false; $w.Focusable = $false
    $w.SizeToContent = 'WidthAndHeight'; $w.ResizeMode = 'NoResize'; $w.Title = 'Evermind'
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = 26; $b.Padding = '20,12,24,12'; $b.Margin = 18
    $b.Background = Get-Brush '#EE0E0B1C'; $b.BorderBrush = Get-Brush '#8000E5FF'; $b.BorderThickness = 1
    $b.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.Color]::FromRgb(0, 229, 255); BlurRadius = 24; ShadowDepth = 0; Opacity = 0.5 }
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    # Pastille qui grossit avec la voix
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 16; $dot.Height = 16; $dot.Fill = $Window.FindResource('AccentBg'); $dot.VerticalAlignment = 'Center'; $dot.Margin = '0,0,14,0'
    $dot.RenderTransformOrigin = '0.5,0.5'; $dot.RenderTransform = New-Object System.Windows.Media.ScaleTransform 1, 1
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.FontFamily = 'Segoe UI Variable Text, Segoe UI, Segoe UI Emoji'; $txt.FontSize = 16; $txt.Foreground = Get-Brush '#FFFFFF'
    $txt.VerticalAlignment = 'Center'; $txt.MaxWidth = 520; $txt.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($dot); [void]$sp.Children.Add($txt)
    $b.Child = $sp; $w.Content = $b
    $w.Add_SourceInitialized({ try { [EMNative]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $script:Bulle.Win).Handle) } catch {} })
    $w.Add_SizeChanged({
        $wa = [System.Windows.SystemParameters]::WorkArea
        $script:Bulle.Win.Left = $wa.Left + ($wa.Width - $script:Bulle.Win.ActualWidth) / 2
        $script:Bulle.Win.Top = $wa.Top + 24
    })
    $script:Bulle = @{ Win = $w; Dot = $dot; Text = $txt; Timer = $null }
    $script:Bulle
}

function Show-Bulle([string]$Texte, [int]$FermerApresMs = 0) {
    if ($EnTest) { return }
    $b = Get-Bulle
    $b.Text.Text = $Texte
    $b.Dot.RenderTransform.ScaleX = $b.Dot.RenderTransform.ScaleY = 1
    if (-not $b.Win.IsVisible) { $b.Win.Show() }
    if ($b.Timer) { $b.Timer.Stop(); $b.Timer = $null }
    if ($FermerApresMs) {
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds($FermerApresMs)
        $t.Add_Tick({ $script:Bulle.Timer.Stop(); $script:Bulle.Timer = $null; $script:Bulle.Win.Hide() })
        $b.Timer = $t; $t.Start()
    }
}

function Hide-Bulle { if ($script:Bulle) { $script:Bulle.Win.Hide() } }

# ---------------------------------------------------------------------------
# Écouter
# ---------------------------------------------------------------------------
# Source : 'raccourci' (Ctrl + Maj + Espace) ou 'bouton' (le micro dans la fenêtre).
# Avec le raccourci : on garde appuyé pendant qu'on parle et on relâche, ou on appuie une fois
# et Evermind s'arrête tout seul quand on se tait.
function Set-VoixEtat([string]$Texte) { $ui.VoixEtat.Text = $Texte; $ui.VoixEtat.Visibility = if ($Texte) { 'Visible' } else { 'Collapsed' } }

# -Silencieux : après un « OK Eve » pas encore confirmé, on enregistre sans bip ni bulle (rien n'est perdu si on parle tout de suite)
function Start-Ecoute([string]$Source, [switch]$Silencieux) {
    if ($script:Ecoute) { Stop-Ecoute; return }                 # deuxième appui : on arrête d'écouter
    if ($script:Transcription -and -not $Silencieux) { return }   # Evermind réfléchit encore à la phrase d'avant
    if (-not (Test-DicteeInstallee)) {
        Show-MainWindow
        Update-VoixInstall
        Invoke-Parole 'Pour comprendre ta voix, installe d''abord la voix dans Evermind.'
        return
    }
    $mic = New-Object EMMicro
    $err = if ([EMMicro]::HasDevice()) { $mic.Start() } else { -1 }
    if ($err -ne 0) {
        Write-Log "Micro indisponible (code $err)"
        $msg = 'Je n''ai pas accès au micro. Vérifie qu''il est branché, et dans les paramètres de Windows (Confidentialité, Microphone) que les applications de bureau ont le droit de l''utiliser.'
        Set-VoixEtat $msg; Show-Bulle 'Je n''ai pas accès au micro.' 4000
        Invoke-Parole 'Je n''ai pas accès au micro.'
        return
    }
    if (Test-CerveauInstalle) { [void](Start-Cerveau) }   # l'assistant se réveille pendant qu'on parle : prêt quand Whisper a fini
    $script:Ecoute = @{ Mic = $mic; Source = $Source; Debut = [Diagnostics.Stopwatch]::StartNew(); Tenu = $true; Mode = 'tenu'; Silencieux = [bool]$Silencieux }
    if (-not $Silencieux) { Show-Ecoute }
    if (-not $script:EcouteTimer) {
        $script:EcouteTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:EcouteTimer.Interval = [TimeSpan]::FromMilliseconds(80)
        $script:EcouteTimer.Add_Tick({ Step-Ecoute })
    }
    $script:EcouteTimer.Start()
}

# Bip, bulle « Je t'écoute » et bouton micro allumé
function Show-Ecoute {
    Invoke-Bip $true
    $ui.BtnMicro.Tag = 'ecoute'
    Set-VoixEtat 'Je t''écoute... (je m''arrête tout seul quand tu te tais)'
    Show-Bulle 'Je t''écoute...'
}

# « OK Eve » confirmé : l'écoute silencieuse devient une écoute normale
function Confirm-EcouteEveil {
    $e = $script:Ecoute
    if (-not $e -or -not $e.Silencieux) { return $false }
    $e.Silencieux = $false
    Show-Ecoute
    $true
}

# Faux réveil ou demande déjà entendue : l'écoute silencieuse s'arrête sans rien dire ni montrer
function Stop-EcouteSansSuite {
    $e = $script:Ecoute
    if (-not $e) { return }
    $script:Ecoute = $null
    $script:EcouteTimer.Stop()
    try { $e.Mic.Stop() } catch {}
    $ui.BtnMicro.Tag = $null; $ui.MicHalo.Opacity = 0
}

function Step-Ecoute {
    $e = $script:Ecoute
    if (-not $e) { $script:EcouteTimer.Stop(); return }
    # En attente de la confirmation de « OK Eve » : on garde tout ce qui est dit (25 secondes au plus)
    if ($e.Silencieux) { if ($e.Mic.Millis -gt 25000) { Stop-EcouteSansSuite }; return }
    # « OK Eve, supprime le foot » dit d'une traite : rien de plus après la confirmation, ce qui a été compris suffit
    if ($e.Reste -and $e.Confirme -and -not $e.Mic.HeardVoice -and $e.Confirme.ElapsedMilliseconds -gt 1200) {
        $r = $e.Reste; Stop-EcouteSansSuite; Invoke-Dictee $r; return
    }
    $m = $e.Mic
    # La pastille de la bulle et le bouton micro suivent la voix
    $s = 1 + 1.2 * $m.Level
    if ($script:Bulle) { $script:Bulle.Dot.RenderTransform.ScaleX = $script:Bulle.Dot.RenderTransform.ScaleY = $s }
    $ui.MicHalo.Opacity = [math]::Min(1, 0.3 + 2 * $m.Level)
    # Raccourci gardé appuyé : on s'arrête quand Espace est relâché. Appui bref : on attend le silence.
    if ($e.Source -eq 'raccourci' -and $e.Tenu) {
        if (-not [EMNative]::IsKeyDown(0x20)) {
            $e.Tenu = $false
            if ($e.Debut.ElapsedMilliseconds -gt 700) { Stop-Ecoute; return }
            $e.Mode = 'silence'
        }
    }
    $fin = $false
    if ($e.Source -ne 'raccourci' -or -not $e.Tenu) {
        if ($m.HeardVoice -and $m.MillisSinceVoice -gt 1300) { $fin = $true }
        elseif (-not $m.HeardVoice -and $m.Millis -gt 7000) { $fin = $true }
    }
    if ($m.Millis -gt 25000) { $fin = $true }
    if ($fin) { Stop-Ecoute }
}

function Stop-Ecoute {
    $e = $script:Ecoute
    if (-not $e) { return }
    $script:Ecoute = $null
    $script:EcouteTimer.Stop()
    $ui.BtnMicro.Tag = $null; $ui.MicHalo.Opacity = 0
    $e.Mic.Stop()
    Invoke-Bip $false
    if (-not $e.Mic.HeardVoice -and $e.Source -eq 'eveil') {
        if ($e.Reste) { Invoke-Dictee $e.Reste; return }      # la demande était déjà dans la phrase « OK Eve, ... »
        Hide-Bulle; Set-VoixEtat ''; return                    # réveillé pour rien : on se tait
    }
    if (-not $e.Mic.HeardVoice) {
        Set-VoixEtat 'Je n''ai rien entendu. Réessaie en parlant un peu plus fort.'
        Show-Bulle 'Je n''ai rien entendu.' 3000
        Invoke-Parole 'Je n''ai rien entendu.'
        return
    }
    $wav = Join-Path $env:TEMP "evermind-$PID.wav"
    try { $e.Mic.SaveWav($wav) } catch { Write-Log "Enregistrement : $_"; return }
    # Après « OK Eve » : le début de la phrase (entendu par l'écoute) et la suite (le micro) sont relus ensemble
    if ($e.Prefixe -and (Test-Path -LiteralPath $e.Prefixe)) { try { Join-Wav $e.Prefixe $wav } catch { Write-Log "Assemblage de la phrase : $_" } }
    Start-Transcription $wav
}

# Met le son de $Debut devant celui de $Fichier (même format : 16 bits mono, même fréquence)
function Join-Wav([string]$Debut, [string]$Fichier) {
    $a = [IO.File]::ReadAllBytes($Debut); $b = [IO.File]::ReadAllBytes($Fichier)
    $rate = [BitConverter]::ToInt32($b, 24)
    if ([BitConverter]::ToInt32($a, 24) -ne $rate) { return }
    $pcm = New-Object byte[] (($a.Length - 44) + ($b.Length - 44))
    [Array]::Copy($a, 44, $pcm, 0, $a.Length - 44); [Array]::Copy($b, 44, $pcm, $a.Length - 44, $b.Length - 44)
    $out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $out
    $w.Write([char[]]'RIFF'); $w.Write([int](36 + $pcm.Length)); $w.Write([char[]]'WAVEfmt '); $w.Write(16)
    $w.Write([int16]1); $w.Write([int16]1); $w.Write($rate); $w.Write($rate * 2); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([char[]]'data'); $w.Write([int]$pcm.Length); $w.Write($pcm); $w.Flush()
    [IO.File]::WriteAllBytes($Fichier, $out.ToArray())
}

# Whisper écrit ce qui a été dit (quelques secondes, en arrière plan)
# Mode 'eveil' : confirmer un « OK Eve » douteux, sans rien montrer (un faux réveil doit rester invisible)
function Start-Transcription([string]$Wav, [string]$Mode) {
    if ($Mode -ne 'eveil') { Set-VoixEtat 'Je réfléchis...'; Show-Bulle 'Je réfléchis...' }
    $out = Join-Path $env:TEMP "evermind-$PID-texte"
    Remove-Item -LiteralPath "$out.txt" -ErrorAction SilentlyContinue
    $threads = [math]::Max(2, [math]::Min(8, [int]([Environment]::ProcessorCount / 2)))
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $WhisperExe
    # Les mots attendus aident Whisper : les ordres et les titres de l'agenda (« Jordan » plutôt que « Jordane »)
    $titres = @($script:Agenda | ForEach-Object { $_.Titre -replace '^Anniversaire (?:de |d'')', '' } | Where-Object { $_ } | Select-Object -Unique -First 15) -join ', '
    $attendu = ("OK Eve. $titres." -replace '"', '').Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $psi.Arguments = "-m `"$WhisperModele`" -f `"$Wav`" -l fr -nt -np -t $threads -otxt -of `"$out`" --prompt `"$attendu`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $VoixDir
    try { $p = [Diagnostics.Process]::Start($psi) }
    catch {
        Write-Log "Dictée impossible : $_"
        Set-VoixEtat "La dictée n'a pas pu démarrer ($($_.Exception.Message))."
        Show-Bulle 'La dictée n''a pas marché.' 3000
        return
    }
    $script:Transcription = @{ Process = $p; Wav = $Wav; Out = "$out.txt"; Mode = $Mode; Debut = [Diagnostics.Stopwatch]::StartNew() }
    if (-not $script:TranscriptionTimer) {
        $script:TranscriptionTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:TranscriptionTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $script:TranscriptionTimer.Add_Tick({ Step-Transcription })
    }
    $script:TranscriptionTimer.Start()
}

function Step-Transcription {
    $t = $script:Transcription
    if (-not $t) { $script:TranscriptionTimer.Stop(); return }
    if (-not $t.Process.HasExited) {
        if ($t.Debut.Elapsed.TotalSeconds -gt 60) { try { $t.Process.Kill() } catch {} } else { return }
    }
    $script:Transcription = $null
    $script:TranscriptionTimer.Stop()
    $texte = ''
    try { if (Test-Path -LiteralPath $t.Out) { $texte = [IO.File]::ReadAllText($t.Out, [Text.Encoding]::UTF8) } } catch {}
    # Le dernier enregistrement est gardé (derniere-dictee.wav) pour comprendre une phrase mal entendue
    try { Move-Item -LiteralPath $t.Wav -Destination (Join-Path $DataDir 'derniere-dictee.wav') -Force } catch {}
    Remove-Item -LiteralPath $t.Out -ErrorAction SilentlyContinue
    Write-Log "Dictée ($([math]::Round($t.Debut.Elapsed.TotalSeconds, 1)) s) : $($texte.Trim())"
    if ($t.Mode -eq 'eveil') { Invoke-Reveil $texte } else { Invoke-Dictee $texte }
}

# Ce qui a été dit : l'assistant s'en occupe s'il est installé, sinon les règles d'Evermind
function Invoke-Dictee([string]$Texte) {
    $t = ($Texte -replace '\[[^\]]*\]|\([^)]*\)', ' ' -replace '\s+', ' ').Trim()
    $t = ($t -replace '(?i)^\W*(?:ok|okay|hey|hé)\W*(?:ève|eve|eva|èv|ev)\b\W*', '').Trim()   # « OK Eve, ... » : seulement la demande
    if ($t -match '\w' -and (Test-CerveauInstalle) -and (Invoke-Commande $t 'voix')) { return }
    Invoke-DicteeRegles $t
}

# Sans assistant : ajouté tout de suite si tout est compris, sinon Evermind s'ouvre pour corriger
function Invoke-DicteeRegles([string]$Texte) {
    $t = ($Texte -replace '\[[^\]]*\]|\([^)]*\)', ' ' -replace '\s+', ' ').Trim()
    if (-not $t -or $t -notmatch '\w') {
        Set-VoixEtat 'Je n''ai pas compris. Réessaie.'
        Show-Bulle 'Je n''ai pas compris, réessaie.' 3000
        Invoke-Parole 'Je n''ai pas compris, réessaie.'
        return
    }
    $p = Read-Phrase $t
    if (-not $p.Manque) {
        try { $r = Add-DepuisPhrase $p }
        catch { Write-Log "Ajout impossible : $_"; Invoke-Parole 'Je n''ai pas réussi à enregistrer ce rendez-vous.'; return }
        $rep = Format-Repetition $r.Repetition
        if ($r.Journee) {
            # Anniversaire ou journée entière : pas d'heure à dire
            $quand = if ($rep) { $rep } else { Format-QuandRV $r $r.Quand }
            $ecrit = "$($r.Titre), $quand"; $dit = $ecrit
        } elseif ($rep) {
            $ecrit = "$($r.Titre), $rep à $(Format-Heure $r.Quand)"
            $dit = "$($r.Titre), $rep à $((Format-QuandParle $r.Quand) -replace '^.* à ', '')"
        } else {
            $ecrit = "$($r.Titre), $(Format-Quand $r.Quand)"
            $dit = "$($r.Titre), $(Format-QuandParle $r.Quand)"
        }
        Set-VoixEtat "Tu as dit : « $t »"
        Show-FormMessage (Get-MessageNote $r) $Colors.ok
        Show-Bulle "$($Types[(Get-TypeRV $r)].Icone)  C'est noté : $ecrit" 5000
        if ($r.Lieu) { $dit += ", $($r.Lieu)" }
        if (@($r.Avec).Count) { $dit += ", avec $(@($r.Avec) -join ' et ')" }
        $conf = if ($r.Journee) { @() } else { @(Get-Conflits $r.Quand $r.Fin $r.Id) }
        if ($conf.Count) { $dit += ". Attention, tu as déjà $(Get-TitreAffiche $conf[0].RV.Titre) à ce moment-là" }
        Invoke-Parole "C'est noté : $dit."
        Update-Agenda
        return
    }
    # Il manque quelque chose : la phrase est mise dans la barre pour la compléter
    Show-MainWindow
    $ui.InPhrase.Text = $t
    $ui.InPhrase.CaretIndex = $t.Length
    [void]$ui.InPhrase.Focus()
    $dit = switch ($p.Manque) {
        'heure' { 'Je n''ai pas compris l''heure. Tu peux la corriger dans Evermind.' }
        'jour'  { 'Je n''ai pas compris le jour. Tu peux le corriger dans Evermind.' }
        'quand' { 'Je n''ai pas compris le jour ni l''heure. Tu peux corriger dans Evermind.' }
        'passe' { 'Ce moment est déjà passé.' }
        default { 'Cette date n''existe pas.' }
    }
    Set-VoixEtat "Tu as dit : « $t »"
    Show-Bulle $dit 4000
    Invoke-Parole $dit
}

# ---------------------------------------------------------------------------
# Raccourci Ctrl + Maj + Espace
# ---------------------------------------------------------------------------
$VoixHotkeyId = 0x4501
function Register-VoixHotkey {
    if ($EnTest) { return }
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $Window).EnsureHandle()
        $script:VoixHotkeyHook = [System.Windows.Interop.HwndSourceHook] {
            param([IntPtr]$hwnd, [int]$msg, [IntPtr]$wParam, [IntPtr]$lParam, [ref]$handled)
            if ($msg -eq 0x0312 -and $wParam.ToInt32() -eq $VoixHotkeyId) {
                try { Start-Ecoute 'raccourci' } catch { Write-Log "Raccourci : $_" }
                $handled.Value = $true
            }
            [IntPtr]::Zero
        }
        [System.Windows.Interop.HwndSource]::FromHwnd($h).AddHook($script:VoixHotkeyHook)
        if ([EMNative]::AddHotKey($h, $VoixHotkeyId, 0x0006, 0x20)) { $script:VoixHotkeyOk = $true }   # Ctrl (2) + Maj (4) + Espace
        else { Write-Log 'Raccourci Ctrl + Maj + Espace déjà pris par un autre programme.' }
    } catch { Write-Log "Raccourci : $_" }
}
