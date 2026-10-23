# Evermind : la voix. On appuie sur Ctrl + Maj + Espace (même en jeu) ou sur le micro, on parle,
# Whisper écrit ce qu'on a dit, Evermind le comprend et répond avec une voix naturelle (Kokoro).
# Tout se passe sur le PC : rien n'est envoyé sur Internet.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# ---------------------------------------------------------------------------
# Module de voix (dictée Whisper et voix Kokoro), téléchargé une seule fois dans le dossier de données
# ---------------------------------------------------------------------------
# Versions fixées et vérifiées : si un fichier téléchargé n'a pas exactement l'empreinte attendue, il est refusé.
$VoixDir   = if ($env:EVERMIND_VOIX) { $env:EVERMIND_VOIX } else { Join-Path $DataDir 'voix' }   # à part pour les tests
$WhisperExe = Join-Path $VoixDir 'whisper-cli.exe'
$WhisperModele = Join-Path $VoixDir 'ggml-small-q5_1.bin'
$WhisperServeur = Join-Path $VoixDir 'whisper-server.exe'   # Whisper gardé chargé : une phrase est écrite en moins d'une seconde
$IaDir = Join-Path $VoixDir 'ia'
$LlamaExe = Join-Path $IaDir 'llama-server.exe'
# L'assistant : celui d'Evermind Mobile (ses règles, ses contrôles et son modèle entraîné, Evermind 0.6B), dans un petit
# programme Java (dépôt Evermind-Mobile, module assistant-pc) qui lance lui-même le modèle avec llama-server
$IaModele = Join-Path $IaDir 'evermind-0.6b-v3-q8_0.gguf'
$AssistantDir = Join-Path $IaDir 'assistant'
$JavaExe = Join-Path $AssistantDir 'jdk-21.0.12.1+1-jre\bin\java.exe'
$AssistantLib = Join-Path $AssistantDir 'v2\evermind-assistant\lib'
$IaAncienModele = Join-Path $IaDir 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf'   # (l'ancien cerveau, 2,5 Go : effacé)
$KokoroDir = Join-Path $VoixDir 'kokoro'
$KokoroModele = Join-Path $KokoroDir 'modele'
# (la voix d'Evermind, compilée ici sous le nom Mindset.exe : voir Get-CopieMindset ; elle s'appelait EvermindVoix.exe)
$KokoroExe = Join-Path $KokoroDir 'Mindset.exe'
# Les anciennes voix (Supertonic, Piper) ne servent plus : effacées pour rendre la place
$VoixAncienne = Join-Path $VoixDir 'supertonic'
if (-not $EnTest) {
    foreach ($ancien in @($VoixAncienne, (Join-Path $VoixDir 'piper'), $IaAncienModele, (Join-Path $KokoroDir 'EvermindVoix.exe')) + @(Get-ChildItem -LiteralPath $VoixDir -Filter 'fr_FR-*.onnx*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) +
            # (les anciennes versions du modèle et du programme de l'assistant)
            @(Get-ChildItem -LiteralPath $IaDir -Filter 'evermind-0.6b-*.gguf' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $IaModele } | ForEach-Object { $_.FullName }) +
            @(Get-ChildItem -LiteralPath $AssistantDir -Directory -Filter 'v*' -ErrorAction SilentlyContinue | Where-Object { $AssistantLib -notlike "$($_.FullName)\*" } | ForEach-Object { $_.FullName })) {
        if (Test-Path -LiteralPath $ancien) { try { Remove-Item -LiteralPath $ancien -Recurse -Force -ErrorAction Stop } catch {} }
    }
}

# Gestionnaire des tâches : toute la suite tient sur une seule ligne « Mindset », qui regroupe les programmes nommés
# Mindset.exe. Un programme d'aide téléchargé (whisper-server, llama-server) est donc lancé par une copie de lui-même
# nommée Mindset.exe, dans son propre dossier (ses dll sont à côté, chargées par leur nom : rien ne dépend du nom du
# programme). La copie est refaite quand l'original change (nouvelle version du module) ; l'empreinte vérifiée au
# téléchargement reste celle de l'original, qui n'est jamais modifié. Copie impossible (disque plein, ancienne copie
# encore ouverte) : l'original est lancé, comme avant. Chaque programme lancé est ensuite suivi et arrêté par son
# processus (numéro), jamais par son nom.
function Get-CopieMindset([string]$Exe) {
    try {
        $src = Get-Item -LiteralPath $Exe -ErrorAction Stop
        $copie = Join-Path $src.DirectoryName 'Mindset.exe'
        if ($src.FullName -ieq $copie) { return $Exe }
        $c = Get-Item -LiteralPath $copie -ErrorAction SilentlyContinue
        if (-not $c -or $c.Length -ne $src.Length -or $c.LastWriteTimeUtc -ne $src.LastWriteTimeUtc) {
            $tmp = "$copie.$PID.tmp"
            Copy-Item -LiteralPath $src.FullName -Destination $tmp -Force -ErrorAction Stop
            try {
                (Get-Item -LiteralPath $tmp).LastWriteTimeUtc = $src.LastWriteTimeUtc
                Move-Item -LiteralPath $tmp -Destination $copie -Force -ErrorAction Stop
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
        $copie
    } catch {
        if (Test-Path -LiteralPath $Exe) { Write-Log "$([IO.Path]::GetFileName($Exe)) lancé sous son nom (copie Mindset.exe impossible : $($_.Exception.Message))" }
        $Exe
    }
}
#   Pack : « voix » (dictée et voix Kokoro), « ia » (l'assistant qui comprend tout), « eveil » (« OK Evermind »)
#   Extraire : fichiers gardés d'un zip (tout le reste est ignoré), rangés dans le sous-dossier Vers (Plat : sans leurs dossiers)
#   Tar : dossiers et fichiers gardés d'une archive .tar.bz2 (extraits par tar.exe de Windows, sans leur premier dossier)
#   Garder : le fichier qui montre que c'est déjà installé
$VoixFichiers = @(
    @{ Pack = 'voix'; Nom = 'programme de dictée'; Url = 'https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-bin-x64.zip'
       Sha256 = '49DCC16DE826F20BD53D44F947A1AE49DFA81F86CAD67A64D80820CB192D674A'; Taille = 8194445
       Extraire = '^Release/(whisper-cli\.exe|whisper-server\.exe|whisper\.dll|ggml[^/]*\.dll)$'; Vers = ''; Garder = $WhisperServeur }
    @{ Pack = 'voix'; Nom = 'modèle de français'; Url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin'
       Sha256 = 'AE85E4A935D7A567BD102FE55AFC16BB595BDB618E11B2FC7591BC08120411BB'; Taille = 190085487; Garder = $WhisperModele }
    # La voix : Kokoro (synthèse récente, prononciation française par espeak-ng), lancée par kokoro\Mindset.exe (compilé ici) avec sherpa-onnx
    @{ Pack = 'voix'; Nom = 'moteur de la voix'; Url = 'https://api.nuget.org/v3-flatcontainer/org.k2fsa.sherpa.onnx.runtime.win-x64/1.13.8/org.k2fsa.sherpa.onnx.runtime.win-x64.1.13.8.nupkg'
       Sha256 = '2257C06893D1D90792EA3157606DE33A51122D935B6913BED5442D2FFB9E9BD7'; Taille = 8535869; Extraire = '^runtimes/win-x64/native/(onnxruntime|sherpa-onnx-c-api)\.dll$'; Vers = 'kokoro'; Plat = $true; Garder = (Join-Path $KokoroDir 'sherpa-onnx-c-api.dll') }
    @{ Pack = 'voix'; Nom = 'moteur de la voix'; Url = 'https://api.nuget.org/v3-flatcontainer/org.k2fsa.sherpa.onnx/1.13.8/org.k2fsa.sherpa.onnx.1.13.8.nupkg'
       Sha256 = 'F89F28FC6FBBC894A46C2C73B040780EC6EA7A21400D9D219DCE4D2333981D57'; Taille = 201971; Extraire = '^lib/net45/sherpa-onnx\.dll$'; Vers = 'kokoro'; Plat = $true; Garder = (Join-Path $KokoroDir 'sherpa-onnx.dll') }
    @{ Pack = 'voix'; Nom = 'modèle de la voix'; Url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2'
       Sha256 = 'C5F7E2D2CAF082BC1D20FB70334A61D99D20B484500AAD32E7CF84C128EA3298'; Taille = 349906910
       Tar = @('kokoro-multi-lang-v1_0/model.onnx', 'kokoro-multi-lang-v1_0/voices.bin', 'kokoro-multi-lang-v1_0/tokens.txt', 'kokoro-multi-lang-v1_0/espeak-ng-data', 'kokoro-multi-lang-v1_0/LICENSE')
       Vers = 'kokoro\modele'; Garder = (Join-Path $KokoroModele 'model.onnx') }
    # L'assistant : llama.cpp (version Vulkan : carte graphique NVIDIA, AMD ou Intel, sinon le processeur), le modèle
    # entraîné pour Evermind (0.6B), Java (Temurin 21, d'Adoptium) et le programme de l'assistant (le même que sur le téléphone)
    @{ Pack = 'ia'; Nom = 'moteur de l''assistant'; Url = 'https://github.com/ggml-org/llama.cpp/releases/download/b11541/llama-b11541-bin-win-vulkan-x64.zip'
       Sha256 = '37BBA511D120222F13C3D520DD875F739A530CC124E78F7CBCE0026DE0173D8A'; Taille = 33464528
       Extraire = '^(llama-server\.exe|llama-server-impl\.dll|llama\.dll|llama-common\.dll|ggml[^/]*\.dll|mtmd\.dll|libomp\.dll)$'; Vers = 'ia'; Garder = $LlamaExe }
    @{ Pack = 'ia'; Nom = 'cerveau de l''assistant'; Url = 'https://github.com/JordanJacquot/Evermind-Mobile/releases/download/assistant-v3/evermind-0.6b-v3-q8_0.gguf'
       Sha256 = 'AB12471564B38C32584081173729C5BC02F8F0EDA493C673C44D34ECE3A16068'; Taille = 639446912; Garder = $IaModele }
    @{ Pack = 'ia'; Nom = 'Java'; Url = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip'
       Sha256 = 'D35F31E712F0FCF6AC5A093EDC90204FBFF22F720BA3950BD09D331D5E621636'; Taille = 48999141
       Extraire = '^jdk-21\.0\.12\.1\+1-jre/.+[^/]$'; Vers = 'ia\assistant'; Garder = $JavaExe }
    @{ Pack = 'ia'; Nom = 'programme de l''assistant'; Url = 'https://github.com/JordanJacquot/Evermind-Mobile/releases/download/assistant-pc-v2/evermind-assistant-pc-2.zip'
       Sha256 = 'D07C0FE3737CBDA99199C767FB17D47D33D2A72A6B32D4D504C7ED59DE8E94B5'; Taille = 4249291
       Extraire = '^evermind-assistant/.+[^/]$'; Vers = 'ia\assistant\v2'; Garder = (Join-Path $AssistantLib 'assistant-pc.jar') }
)

# Voix au choix (réglages).
#   Kokoro (voix naturelles qui prononcent le français comme il faut) : la voix 1 est une vraie voix française,
#   les autres sont des voix d'autres pays à qui on fait parler français (petit accent).
#   La voix de Windows n'est pas proposée : elle sert seulement de secours, si la voix n'est pas encore installée.
$VoixListe = [ordered]@{}
$VoixListe['K30'] = @{ Nom = 'Voix 1'; Desc = 'Femme, française (conseillée)'; Moteur = 'kokoro'; Locuteur = 30 }
$VoixListe['K31'] = @{ Nom = 'Voix 2'; Desc = 'Femme, petit accent'; Moteur = 'kokoro'; Locuteur = 31 }
$VoixListe['K29'] = @{ Nom = 'Voix 3'; Desc = 'Homme, petit accent'; Moteur = 'kokoro'; Locuteur = 29 }
$VoixListe['K36'] = @{ Nom = 'Voix 4'; Desc = 'Homme, petit accent'; Moteur = 'kokoro'; Locuteur = 36 }
$VoixListe['K33'] = @{ Nom = 'Voix 5'; Desc = 'Homme grave, petit accent'; Moteur = 'kokoro'; Locuteur = 33 }
$VoixListe['windows'] = @{ Nom = 'Windows'; Desc = 'Voix de secours'; Moteur = 'windows'; Cachee = $true }

function Test-KokoroInstalle { @($VoixFichiers | Where-Object { $_.Garder -like "$KokoroDir*" -and -not (Test-Path -LiteralPath $_.Garder) }).Count -eq 0 }

function Test-VoixDispo([string]$Cle) {
    $v = $VoixListe[$Cle]
    if (-not $v) { return $false }
    switch ($v.Moteur) {
        'kokoro'     { Test-KokoroInstalle }
        default      { $true }
    }
}

# Voix choisie dans les réglages ; sinon la voix française de Kokoro ; sinon (pas encore installée) celle de Windows
function Get-VoixChoisie {
    $k = [string](Get-Setting 'Voix3' '')
    if ($k -and (Test-VoixDispo $k)) { return $k }
    if (Test-VoixDispo 'K30') { return 'K30' }
    'windows'
}

# Ce qui est dit à voix haute s'écrit parfois autrement qu'à l'écran : « 9 h » se dit « 9 heures », « rdv » se dit
# « rendez-vous »... Sans ça, la voix lit « 9 H » ou bute sur les abréviations.
function Convert-PourParler([string]$Texte) {
    $t = ' ' + $Texte + ' '
    $t = $t -replace '[«»"“”]', ' ' -replace '[★↻⚠☑📍🔗📝🎂•·|]', ' ' -replace '\p{Cs}', ''
    # Heures : « 21:30 », « 21 h 30 », « 21h30 », « 9 h », « 1 h » (une heure)
    $t = [regex]::Replace($t, '\b(\d{1,2})\s*[:hH]\s*(\d{2})\b', { param($m) "$([int]$m.Groups[1].Value) heure$(if ([int]$m.Groups[1].Value -gt 1) { 's' }) $($m.Groups[2].Value)" })
    $t = [regex]::Replace($t, '\b(\d{1,2})\s*[hH](?![a-zA-Zà-ÿ])', { param($m) "$([int]$m.Groups[1].Value) heure$(if ([int]$m.Groups[1].Value -gt 1) { 's' })" })
    $t = $t -replace '\b(\d+)\s*min\b', '$1 minutes' -replace '\b1er\b', 'premier' -replace '\b1re\b', 'première'
    $ordinaux = @{ 2 = 'deuxième'; 3 = 'troisième'; 4 = 'quatrième'; 5 = 'cinquième'; 6 = 'sixième'; 7 = 'septième'; 8 = 'huitième'; 9 = 'neuvième'; 10 = 'dixième'; 11 = 'onzième'; 12 = 'douzième' }
    $t = [regex]::Replace($t, '\b(\d+)(?:e|ème|eme)\b', { param($m) $n = [int]$m.Groups[1].Value; if ($ordinaux.ContainsKey($n)) { $ordinaux[$n] } else { "$($n)ième" } })
    $t = $t -replace '(?i)\brdv\b', 'rendez-vous' -replace '(?i)\bstp\b', 's''il te plaît' -replace '(?i)\bsvp\b', 's''il vous plaît'
    $t = $t -replace '\s*%', ' pour cent' -replace '\s*€', ' euros' -replace '\s*&\s*', ' et ' -replace '\s*°C?', ' degrés'
    ($t -replace '\s+', ' ').Trim()
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
                # Les gros fichiers (le modèle : 640 Mo) arrivent souvent en plusieurs fois : une connexion qui se coupe ne fait pas
                # d'erreur, le fichier est juste incomplet. Evermind vérifie la taille, reprend là où ça s'est arrêté
                # (même après « Réessayer » : le morceau reçu est gardé), puis vérifie l'empreinte du fichier entier.
                $tmp = Join-Path $Dossier ([IO.Path]::GetFileName($f.Url) + '.telechargement')
                $coupures = 0; $refait = $false
                $buf = New-Object byte[] 65536
                while ($true) {
                    $existant = if (Test-Path -LiteralPath $tmp) { (Get-Item -LiteralPath $tmp).Length } else { 0L }
                    if ($existant -gt $f.Taille) { Remove-Item -LiteralPath $tmp -Force; $existant = 0L }
                    if ($existant -lt $f.Taille) {
                        $resp = $null; $in = $null; $out = $null
                        try {
                            $req = [Net.HttpWebRequest]::Create($f.Url)
                            $req.UserAgent = 'Evermind'; $req.Timeout = 30000; $req.ReadWriteTimeout = 60000
                            if ($existant) { $req.AddRange([long]$existant) }
                            $resp = $req.GetResponse()
                            # Un serveur qui ne sait pas reprendre renvoie tout le fichier : on repart de zéro
                            if ($existant -and [int]$resp.StatusCode -ne 206) { $existant = 0L }
                            $in = $resp.GetResponseStream()
                            $out = New-Object IO.FileStream($tmp, $(if ($existant) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }), [IO.FileAccess]::Write)
                            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                                $out.Write($buf, 0, $n)
                                $Etat.Recu = $deja + $out.Length
                            }
                        } catch {
                            $coupures++
                            if ($coupures -ge 6) { throw "le téléchargement de « $($f.Nom) » s'est coupé plusieurs fois (connexion instable ?). Appuie sur Réessayer : il reprendra là où il s'est arrêté" }
                        } finally { if ($out) { $out.Dispose() }; if ($in) { $in.Dispose() }; if ($resp) { $resp.Dispose() } }
                        if ((Get-Item -LiteralPath $tmp -ErrorAction SilentlyContinue).Length -lt $f.Taille) {
                            if ($coupures -ge 6) { throw "le téléchargement de « $($f.Nom) » s'est coupé plusieurs fois (connexion instable ?). Appuie sur Réessayer : il reprendra là où il s'est arrêté" }
                            $coupures++; $Etat.Etape = "$($f.Nom) (connexion coupée, reprise)"; Start-Sleep -Seconds ([math]::Min(20, 3 * $coupures)); $Etat.Etape = $f.Nom
                            continue
                        }
                    }
                    # Tout est là : l'empreinte dit si c'est bien le bon fichier, intact
                    $Etat.Etape = "$($f.Nom) (vérification)"
                    $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
                    $Etat.Etape = $f.Nom
                    if ($hash -eq $f.Sha256) { break }
                    Remove-Item -LiteralPath $tmp -Force
                    if ($refait) { throw "le fichier « $($f.Nom) » arrive abîmé (empreinte différente, deux fois de suite). Un antivirus ou un proxy le modifie peut-être pendant le téléchargement" }
                    $refait = $true   # (un morceau abîmé : on le retélécharge en entier une fois)
                }
                $deja += $f.Taille
                if ($f.Tar) {
                    # Archive .tar.bz2 : tar.exe (fourni avec Windows) sort seulement les fichiers utiles
                    $Etat.Etape = "$($f.Nom) (décompression)"
                    $dest = Join-Path $Dossier ([string]$f.Vers)
                    New-Item -ItemType Directory -Force -Path $dest | Out-Null
                    $sortie = & (Join-Path $env:SystemRoot 'System32\tar.exe') -xjf $tmp -C $dest --strip-components=1 @($f.Tar) 2>&1
                    $code = $LASTEXITCODE
                    Remove-Item -LiteralPath $tmp -Force
                    if ($code -ne 0 -or -not (Test-Path -LiteralPath $f.Garder)) { throw "le fichier « $($f.Nom) » n'a pas pu être décompressé ($($sortie -join ' '))" }
                } elseif ($f.Extraire) {
                    # Seuls les fichiers utiles du zip sont gardés, à leur place
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    $zip = [IO.Compression.ZipFile]::OpenRead($tmp)
                    try {
                        foreach ($e in $zip.Entries) {
                            if ($e.FullName -notmatch $f.Extraire) { continue }
                            $rel = if ($f.Plat -or $e.FullName -like 'Release/*') { $e.Name } else { $e.FullName }
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

# ---------------------------------------------------------------------------
# Barre d'avancement vivante : elle glisse jusqu'à sa place (au lieu de sauter), un reflet lumineux la parcourt sans
# arrêt (on voit que ça travaille, même pendant la vérification), et le texte dit le pourcentage, la vitesse et le
# temps qui reste
# ---------------------------------------------------------------------------
function Set-BarreAvance($Barre, $Fond, [double]$Part) {
    $cible = [math]::Max(10.0, $Fond.ActualWidth * [math]::Min(1.0, [math]::Max(0.0, $Part)))
    if ([math]::Abs($cible - $Barre.ActualWidth) -ge 1) {
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation $cible, ([TimeSpan]::FromMilliseconds(450))
        $an.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
        $Barre.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $an)
    }
    if (-not $Barre.Child) {
        # Le reflet : une tache de lumière qui traverse la barre en boucle
        $Barre.ClipToBounds = $true
        $reflet = New-Object System.Windows.Controls.Border
        $reflet.Width = 90; $reflet.HorizontalAlignment = 'Left'
        $g = New-Object System.Windows.Media.LinearGradientBrush; $g.StartPoint = '0,0'; $g.EndPoint = '1,0'
        foreach ($s in @(@('#00FFFFFF', 0), @('#88FFFFFF', 0.5), @('#00FFFFFF', 1))) { $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($s[0])), $s[1])) }
        $reflet.Background = $g
        $tr = New-Object System.Windows.Media.TranslateTransform; $reflet.RenderTransform = $tr
        $Barre.Child = $reflet
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation -100, 900, ([TimeSpan]::FromMilliseconds(1700))
        $an.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $tr.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $an)
    }
}

# « Téléchargement : cerveau de l'assistant... 812 Mo sur 2 382 Mo (34 %) · 6,2 Mo/s · encore 4 min »
function Get-TexteAvance([string]$Debut, [long]$Recu, [long]$Total, [bool]$SansVitesse) {
    $maintenant = Get-Date
    $a = $script:Avance
    if (-not $a -or $Recu -lt $a.R) { $a = $script:Avance = @{ T = $maintenant; R = $Recu; V = 0.0 } }
    $dt = ($maintenant - $a.T).TotalSeconds
    if ($dt -ge 1) {
        $inst = ($Recu - $a.R) / $dt
        $a.V = if ($a.V) { 0.75 * $a.V + 0.25 * $inst } else { $inst }
        $a.T = $maintenant; $a.R = $Recu
    }
    $pct = if ($Total) { [math]::Floor(100 * $Recu / $Total) } else { 0 }
    $t = "$Debut...  $([math]::Round($Recu / 1MB).ToString('N0', $Fr)) Mo sur $([math]::Round($Total / 1MB).ToString('N0', $Fr)) Mo ($pct %)"
    if (-not $SansVitesse -and $a.V -gt 20KB -and $Total -gt $Recu) {
        $reste = ($Total - $Recu) / $a.V
        $duree = if ($reste -lt 60) { 'moins d''une minute' } elseif ($reste -lt 3600) { "$([math]::Ceiling($reste / 60)) min" } else { "$([math]::Floor($reste / 3600)) h $(([math]::Floor(($reste % 3600) / 60)).ToString('00'))" }
        $t += "  ·  $([math]::Round($a.V / 1MB, 1).ToString($Fr)) Mo/s  ·  encore $duree"
    }
    $t
}

# Panneau d'installation : ce qui manque (la voix d'abord, puis l'assistant), bouton, barre d'avancement
function Update-VoixInstall {
    $dl = $script:VoixDl
    $enCours = $dl -and -not $dl.Fini
    if ($dl -and $dl.Fini -and -not $dl.Annonce -and -not $dl.Erreur) {
        $dl.Annonce = $true
        if ($dl.Pack -eq 'eveil') {
            Write-Log 'Écoute « OK Evermind » installée'
            Start-Eveil
            try { Update-EveilReglage } catch {}
            Invoke-Parole 'C''est prêt. Dis OK Evermind quand tu veux me parler.'
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
        $pct = if ($dl.Total) { [math]::Min(1.0, $dl.Recu / $dl.Total) } else { 0 }
        $ui.VoixBarreFond.Visibility = 'Visible'
        Set-BarreAvance $ui.VoixBarre $ui.VoixBarreFond $pct
        $ui.VoixInstallTexte.Text = Get-TexteAvance "Téléchargement : $($dl.Etape)" $dl.Recu $dl.Total ([string]$dl.Etape -match 'vérification|décompression|reprise')
        $ui.BtnVoixInstall.IsEnabled = $false; $ui.BtnVoixInstall.Content = 'Téléchargement...'
        return
    }
    $script:Avance = $null
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
# La voix choisie dit la phrase : Kokoro (kokoro\Mindset.exe, toujours prêt une fois lancé),
# ou Windows (si la voix n'est pas encore installée). Le son est fabriqué en un instant dans un fichier, puis joué.
function Invoke-Parole([string]$Texte, [string]$Voix) {
    if ($EnTest -and -not $env:EVERMIND_TEST_PAROLE) { Write-Log "Parole : $(Convert-PourParler $Texte)"; return }
    $Texte = Convert-PourParler $Texte
    if (-not $Voix -or -not (Test-VoixDispo $Voix)) { $Voix = Get-VoixChoisie }
    $v = $VoixListe[$Voix]
    try {
        switch ($v.Moteur) {
            'kokoro'     { Start-KokoroParole $Texte $Voix; return }
        }
    } catch { Write-Log "Voix naturelle impossible : $_" }
    Invoke-ParoleWindows $Texte
}

# ---------------------------------------------------------------------------
# Kokoro : kokoro\Mindset.exe garde le modèle chargé et fabrique chaque phrase en moins d'une seconde.
# Il est compilé sur le PC à partir de voix-kokoro.cs (comme le reste du code natif d'Evermind), sous le nom
# Mindset.exe pour la ligne unique « Mindset » du Gestionnaire des tâches (voir Get-CopieMindset),
# et s'arrête après 10 minutes sans rien dire pour rendre la mémoire.
# ---------------------------------------------------------------------------
function Build-Kokoro {
    $src = Join-Path $ModulesDir 'voix-kokoro.cs'
    if ((Test-Path -LiteralPath $KokoroExe) -and (Get-Item -LiteralPath $KokoroExe).LastWriteTime -ge (Get-Item -LiteralPath $src).LastWriteTime) { return $true }
    $csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { Write-Log 'Voix Kokoro : compilateur de Windows introuvable'; return $false }
    $sortie = & $csc /nologo /target:exe /platform:x64 /optimize+ "/out:$KokoroExe" "/reference:$(Join-Path $KokoroDir 'sherpa-onnx.dll')" $src 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Log "Voix Kokoro : compilation impossible ($($sortie -join ' '))"; return $false }
    Write-Log 'Voix Kokoro compilée'
    $true
}

function Start-KokoroServeur {
    $s = $script:Kokoro
    if ($s -and -not $s.Process.HasExited) { $s.Dernier = Get-Date; return $s }
    if (-not (Build-Kokoro)) { throw 'la voix Kokoro n''a pas pu être préparée' }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $KokoroExe
    $psi.Arguments = "`"$KokoroModele`" $([math]::Max(2, [math]::Min(8, [int]([Environment]::ProcessorCount / 2))))"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $KokoroDir
    # Sortie d'erreur à part : le moteur y écrit des remarques sans importance (lues puis jetées)
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $p = [Diagnostics.Process]::Start($psi)
    $in = New-Object IO.StreamWriter($p.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
    $in.AutoFlush = $true
    try { $p.PriorityClass = 'BelowNormal' } catch {}   # (un jeu passe avant)
    $script:Kokoro = @{ Process = $p; Entree = $in; Lignes = (New-Object EMLigneur $p.StandardOutput); Remarques = (New-Object EMLigneur $p.StandardError); Pret = $false; Attente = $null; Dernier = (Get-Date) }
    Write-Log 'Voix Kokoro démarrée'
    if (-not $script:KokoroTimer) {
        $script:KokoroTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:KokoroTimer.Interval = [TimeSpan]::FromMilliseconds(50)
        $script:KokoroTimer.Add_Tick({ Step-Kokoro })
    }
    $script:KokoroTimer.Start()
    $script:Kokoro
}

function Stop-KokoroServeur {
    $s = $script:Kokoro
    $script:Kokoro = $null
    if ($s) { try { $s.Entree.Close() } catch {}; try { if (-not $s.Process.WaitForExit(1500)) { $s.Process.Kill() } } catch {} }
}

# Une phrase à dire : elle remplace celle qui attendait encore (seule la dernière compte)
function Start-KokoroParole([string]$Texte, [string]$Voix) {
    Stop-Parole
    $s = Start-KokoroServeur
    $script:ParoleNum = 1 - [int]$script:ParoleNum
    $wav = Join-Path $env:TEMP "evermind-$PID-parole$($script:ParoleNum).wav"
    $s.Attente = @{ Texte = ($Texte -replace '[\t\r\n]+', ' '); Locuteur = $VoixListe[$Voix].Locuteur; Wav = $wav; Envoye = $false; Debut = [Diagnostics.Stopwatch]::StartNew() }
    $script:Parle = $s.Attente      # « Evermind parle » : « OK Evermind » reste en pause
    Step-Kokoro
}

function Step-Kokoro {
    $s = $script:Kokoro
    if (-not $s) { $script:KokoroTimer.Stop(); return }
    while ($s.Remarques.Suivante()) {}
    while ($true) {
        $l = $s.Lignes.Suivante()
        if ($null -eq $l) { Write-Log 'Voix Kokoro arrêtée'; $script:Kokoro = $null; $script:Parle = $null; $script:KokoroTimer.Stop(); return }
        if ($l -eq '') { break }
        if ($l -eq 'PRET') { $s.Pret = $true; continue }
        $x = $l -split "`t"
        $a = $s.Attente
        if ($x[0] -eq 'ERREUR') {
            Write-Log "Voix Kokoro : $($x[1])"
            if ($a -and $a.Envoye) { $s.Attente = $null; $script:Parle = $null; Invoke-ParoleWindows $a.Texte }
            continue
        }
        if ($x[0] -eq 'OK' -and $a -and $a.Envoye -and $x[1] -eq $a.Wav) {
            $s.Attente = $null; $script:Parle = $null; $s.Dernier = Get-Date
            Invoke-Son $a.Wav $a.Debut
        }
    }
    $a = $s.Attente
    if ($s.Pret -and $a -and -not $a.Envoye) {
        $a.Envoye = $true
        try { $s.Entree.WriteLine("PARLE`t$($a.Locuteur)`t1.0`t0`t$($a.Wav)`t$($a.Texte)") }
        catch { Write-Log "Voix Kokoro : $_"; $s.Attente = $null; $script:Parle = $null; Invoke-ParoleWindows $a.Texte }
    }
    if ($a -and $a.Debut.Elapsed.TotalSeconds -gt 30) { Write-Log 'Voix Kokoro : trop lente, voix de Windows'; $s.Attente = $null; $script:Parle = $null; Invoke-ParoleWindows $a.Texte }
    # Rien à dire depuis 10 minutes : la mémoire est rendue
    if (-not $s.Attente -and ((Get-Date) - $s.Dernier).TotalMinutes -gt 10) { Stop-KokoroServeur; Write-Log 'Voix Kokoro mise en veille' }
}

# Joue un fichier son ; « OK Evermind » reste en pause le temps qu'il soit dit
function Invoke-Son([string]$Wav, $Chrono) {
    if ($EnTest) { Write-Log "Voix naturelle prête : $((Get-Item -LiteralPath $Wav).Length) octets en $([math]::Round($Chrono.Elapsed.TotalSeconds, 2)) s"; return }
    try { Invoke-SonOctets ([IO.File]::ReadAllBytes($Wav)) } catch { Write-Log "Lecture de la voix : $_" }
}

# Joue un son (.wav en mémoire) sur le casque choisi dans les réglages (sinon la sortie de Windows)
function Invoke-SonOctets([byte[]]$Octets) {
    $duree = [EMSortie]::Jouer($Octets)
    if (-not $duree) {
        # Sortie indisponible : le lecteur de Windows, sur la sortie par défaut
        $script:Lecteur = New-Object System.Media.SoundPlayer (New-Object IO.MemoryStream (, $Octets))
        $script:Lecteur.Play()
        $duree = ($Octets.Length - 44) / [math]::Max(1, [BitConverter]::ToInt32($Octets, 28))
    }
    $script:EveilReprise = (Get-Date).AddSeconds($duree + 0.8)
}


function Invoke-ParoleWindows([string]$Texte) {
    try {
        if (-not $script:Synth) {
            Add-Type -AssemblyName System.Speech
            $script:Synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $v = $script:Synth.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like 'fr*' } | Select-Object -First 1
            if ($v) { $script:Synth.SelectVoice($v.VoiceInfo.Name) }
        }
        Stop-Parole
        # Fabriquée en mémoire, puis jouée sur le casque choisi
        $ms = New-Object IO.MemoryStream
        $script:Synth.SetOutputToWaveStream($ms)
        $script:Synth.Speak($Texte)
        $script:Synth.SetOutputToNull()
        Invoke-SonOctets $ms.ToArray()
    } catch { Write-Log "Parole impossible : $_" }
}

# Coupe ce qui est en train d'être dit (une nouvelle phrase remplace l'ancienne)
function Stop-Parole {
    try { if ($script:Synth) { $script:Synth.SpeakAsyncCancelAll() } } catch {}
    try { if ($script:Lecteur) { $script:Lecteur.Stop() } } catch {}
    try { [EMSortie]::Arreter() } catch {}
    $script:Parle = $null
    if ($script:Kokoro) { $script:Kokoro.Attente = $null }
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
    $choisie = Get-VoixChoisie
    $super = Test-KokoroInstalle
    foreach ($k in $VoixListe.Keys) {
        $v = $VoixListe[$k]
        $dispo = Test-VoixDispo $k
        if ($v.Cachee) { continue }   # la voix de Windows : seulement en secours
        $on = $k -eq $choisie
        $b = New-Object System.Windows.Controls.Border
        $b.CornerRadius = 14; $b.Padding = '14,9'; $b.Margin = '0,0,0,6'; $b.BorderThickness = 1.5; $b.Tag = $k
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
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $n = New-Object System.Windows.Controls.TextBlock; $n.Text = $v.Nom; $n.FontSize = 15; $n.FontWeight = 'SemiBold'; $n.Foreground = Get-Brush '#FFFFFF'; $n.Width = 90
        $d = New-Object System.Windows.Controls.TextBlock; $d.Text = $v.Desc; $d.FontSize = 13; $d.Foreground = Get-Brush $Colors.dim; $d.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($n); [void]$sp.Children.Add($d)
        [void]$dp.Children.Add($sp)
        $b.Child = $dp
        if ($dispo) {
            $b.Add_MouseLeftButtonUp({
                param($s)
                $k = [string]$s.Tag
                Set-Setting 'Voix3' $k
                Update-VoixChoix
                Invoke-Parole "Salut ! C'est noté : dentiste, mardi 14 octobre à 15 h 30. N'oublie pas ta carte Vitale." $k
            })
        }
        [void]$ui.VoixChoix.Children.Add($b)
    }
    $ui.VoixReglageInfo.Visibility = if ($super) { 'Collapsed' } else { 'Visible' }
    $ui.VoixReglageInfo.Text = 'Les voix naturelles arrivent avec le module de voix : appuie sur « Installer la voix » (ou « Installer les voix ») sur l''écran principal.'
}

function Update-AssistantEtat {
    $ok = Test-CerveauInstalle
    $ui.BtnAssistant.Visibility = if ($ok) { 'Collapsed' } else { 'Visible' }
    $ui.AssistantEtat.Text = if ($ok) { 'Installé. Parle-lui comme à quelqu''un : « décale le dentiste à jeudi », « supprime le foot », « qu''est-ce que j''ai demain ? », « annule ». Tout se passe sur ton PC.' }
                             else { 'Une petite IA sur ton PC (700 Mo) pour tout comprendre : décaler, supprimer, ajouter des détails, répondre à tes questions. Rien ne part sur Internet.' }
}

function Open-Reglages([string]$Onglet) {
    Update-VoixChoix; Update-CroixReglage; Update-CasqueChoix; Update-MicroChoix; Update-AssistantEtat; Update-EveilReglage
    Set-OngletReglages $(if ($Onglet) { $Onglet } elseif ($script:OngletReglages) { $script:OngletReglages } else { 'Son' })
    $ui.Reglages.Visibility = 'Visible'
    Start-Vumetre
}

# Onglets des réglages : Son (casque et micro), Voix, Assistant, Général
function Set-OngletReglages([string]$Nom) {
    $script:OngletReglages = $Nom
    if ($Nom -eq 'Theme') { Update-ThemeChoix; Update-CouleursReglage }
    if ($Nom -eq 'General') { Update-DossiersReglage; Update-HorairesReglage }
    foreach ($o in 'Son', 'Voix', 'Assistant', 'Theme', 'General') {
        $ui["Onglet$o"].Tag = if ($o -eq $Nom) { 'on' } else { $null }
        $ui["Pan$o"].Visibility = if ($o -eq $Nom) { 'Visible' } else { 'Collapsed' }
    }
}
function Close-Reglages { $ui.Reglages.Visibility = 'Collapsed'; Stop-Vumetre }

# ---------------------------------------------------------------------------
# Le micro : celui de Windows, ou un autre choisi dans les réglages (casque, manette...)
# ---------------------------------------------------------------------------
# Le choix est gardé par son nom : les numéros des micros changent quand on en branche un autre
function Set-MicroActif {
    if (-not ('EMMicros' -as [type])) { return }   # outils de test qui ne chargent pas le code natif
    $nom = [string](Get-Setting 'Micro' '')
    $noms = @([EMMicros]::Noms())
    $i = if ($nom) { [array]::IndexOf($noms, $nom) } else { -1 }
    $avant = [EMMicros]::Choisi
    [EMMicros]::Choisi = if ($i -ge 0) { [uint32]$i } else { [uint32]::MaxValue }
    $avant -ne [EMMicros]::Choisi
}

# Windows coupe les noms d'appareils à 31 lettres : « … » le montre au lieu d'une parenthèse qui ne se ferme pas
function Get-NomAppareil([string]$Nom) {
    $m = [regex]::Match($Nom, '^(?<nom>.{31})(?<reste>.*)$')
    if ($m.Success -and $m.Groups['nom'].Value -match '\([^)]*$') { return $m.Groups['nom'].Value.TrimEnd() + '…)' + $m.Groups['reste'].Value }
    $Nom
}

# Le casque : comme le micro, gardé par son nom
function Set-CasqueActif {
    if (-not ('EMSortie' -as [type])) { return $false }
    $nom = [string](Get-Setting 'Casque' '')
    $noms = @([EMSortie]::Noms())
    $i = if ($nom) { [array]::IndexOf($noms, $nom) } else { -1 }
    $avant = [EMSortie]::Choisi
    [EMSortie]::Choisi = if ($i -ge 0) { [uint32]$i } else { [uint32]::MaxValue }
    $avant -ne [EMSortie]::Choisi
}

function Update-CasqueChoix {
    $ui.CasqueChoix.Children.Clear()
    $choisi = [string](Get-Setting 'Casque' '')
    $noms = @([EMSortie]::Noms())
    $liste = @(@{ Cle = ''; Nom = 'Celui de Windows'; Absent = $false }) + @($noms | ForEach-Object { @{ Cle = $_; Nom = $_; Absent = $false } })
    if ($choisi -and $noms -notcontains $choisi) { $liste += @{ Cle = $choisi; Nom = "$choisi (débranché)"; Absent = $true } }
    foreach ($c in $liste) {
        $on = $c.Cle -eq $choisi
        $b = New-Object System.Windows.Controls.Border
        $b.CornerRadius = 14; $b.Padding = '14,9'; $b.Margin = '0,0,0,6'; $b.BorderThickness = 1.5; $b.Tag = $c.Cle; $b.Cursor = 'Hand'
        $b.Background = Get-Brush $(if ($on) { '#2600E5FF' } else { '#0FFFFFFF' })
        $b.BorderBrush = if ($on) { $Window.FindResource('AccentBg') } else { Get-Brush '#1CFFFFFF' }
        $dp = New-Object System.Windows.Controls.DockPanel
        $ec = New-Object System.Windows.Controls.TextBlock
        $ec.Text = if ($on -and $c.Absent) { '✓ choisi (en attente)' } elseif ($on) { '✓ choisi' } else { '▶ choisir et écouter' }
        $ec.Foreground = Get-Brush $(if ($on) { '#7FF4FF' } else { $Colors.dim }); $ec.FontSize = 13; $ec.VerticalAlignment = 'Center'; $ec.Margin = '12,0,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($ec, 'Right')
        [void]$dp.Children.Add($ec)
        $n = New-Object System.Windows.Controls.TextBlock; $n.Text = (Get-NomAppareil $c.Nom); $n.FontSize = 14; $n.Foreground = Get-Brush '#FFFFFF'; $n.VerticalAlignment = 'Center'; $n.TextTrimming = 'CharacterEllipsis'
        [void]$dp.Children.Add($n)
        $b.Child = $dp
        $b.Add_MouseLeftButtonUp({
            param($s)
            Set-Setting 'Casque' ([string]$s.Tag)
            [void](Set-CasqueActif)
            Write-Log "Casque choisi : $(if ($s.Tag) { $s.Tag } else { 'celui de Windows' })"
            Update-CasqueChoix
            Invoke-Parole 'Salut ! Je te parle dans ce casque.'
        })
        [void]$ui.CasqueChoix.Children.Add($b)
    }
}

# Le micro choisi est débranché au lancement (casque USB pas encore prêt) : Evermind prend celui de Windows en attendant,
# et revient tout seul au micro choisi dès qu'il réapparaît (vérifié toutes les 10 secondes)
function Test-MicroRevenu {
    if (-not ('EMMicros' -as [type])) { return }
    if ($script:MicroVu -and ((Get-Date) - $script:MicroVu).TotalSeconds -lt 10) { return }
    $script:MicroVu = Get-Date
    if ([string](Get-Setting 'Casque' '') -and (Set-CasqueActif)) { Write-Log "Casque : $(if ([EMSortie]::Choisi -ne [uint32]::MaxValue) { "« $(Get-Setting 'Casque' '') » est là" } else { "« $(Get-Setting 'Casque' '') » débranché, celui de Windows en attendant" })" }
    if (-not [string](Get-Setting 'Micro' '')) { return }
    if (Set-MicroActif) {
        Write-Log "Micro : $(if ([EMMicros]::Choisi -ne [uint32]::MaxValue) { "« $(Get-Setting 'Micro' '') » est là" } else { "« $(Get-Setting 'Micro' '') » débranché, celui de Windows en attendant" })"
        if ((Test-EveilActif) -and -not $script:Ecoute) { Stop-Eveil; Start-Eveil }
    }
}

function Update-MicroChoix {
    $ui.MicroChoix.Children.Clear()
    $choisi = [string](Get-Setting 'Micro' '')
    $noms = @([EMMicros]::Noms())
    $script:MicroBarres = @{}
    $liste = @(@{ Cle = ''; Nom = 'Celui de Windows'; Index = -1 }) + @(for ($i = 0; $i -lt $noms.Count; $i++) { @{ Cle = $noms[$i]; Nom = $noms[$i]; Index = $i } })
    # Micro choisi mais débranché : il reste choisi (Evermind y reviendra), avec celui de Windows en attendant
    if ($choisi -and $noms -notcontains $choisi) { $liste += @{ Cle = $choisi; Nom = "$choisi (débranché)"; Index = -2 } }
    foreach ($m in $liste) {
        $on = $m.Cle -eq $choisi
        $b = New-Object System.Windows.Controls.Border
        $b.CornerRadius = 14; $b.Padding = '14,9'; $b.Margin = '0,0,0,6'; $b.BorderThickness = 1.5; $b.Tag = $m.Cle; $b.Cursor = 'Hand'
        $b.Background = Get-Brush $(if ($on) { '#2600E5FF' } else { '#0FFFFFFF' })
        $b.BorderBrush = if ($on) { $Window.FindResource('AccentBg') } else { Get-Brush '#1CFFFFFF' }
        $dp = New-Object System.Windows.Controls.DockPanel
        $ec = New-Object System.Windows.Controls.TextBlock
        $ec.Text = if ($on -and $m.Index -eq -2) { '✓ choisi (en attente)' } elseif ($on) { '✓ choisi' } else { 'choisir' }
        $ec.Foreground = Get-Brush $(if ($on) { '#7FF4FF' } else { $Colors.dim }); $ec.FontSize = 13; $ec.VerticalAlignment = 'Center'; $ec.Margin = '12,0,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($ec, 'Right')
        [void]$dp.Children.Add($ec)
        if ($m.Index -ge 0) {
            # Vumètre : une petite barre qui suit le son reçu par ce micro
            $fond = New-Object System.Windows.Controls.Border
            $fond.Width = 90; $fond.Height = 6; $fond.CornerRadius = 3; $fond.Background = Get-Brush '#1CFFFFFF'; $fond.VerticalAlignment = 'Center'; $fond.Margin = '12,0,0,0'
            $barre = New-Object System.Windows.Controls.Border
            $barre.Width = 0; $barre.HorizontalAlignment = 'Left'; $barre.CornerRadius = 3; $barre.Background = $Window.FindResource('AccentBg')
            $fond.Child = $barre
            [System.Windows.Controls.DockPanel]::SetDock($fond, 'Right')
            [void]$dp.Children.Add($fond)
            $script:MicroBarres[$m.Index] = $barre
        }
        $n = New-Object System.Windows.Controls.TextBlock; $n.Text = (Get-NomAppareil $m.Nom); $n.FontSize = 14; $n.Foreground = Get-Brush '#FFFFFF'; $n.VerticalAlignment = 'Center'; $n.TextTrimming = 'CharacterEllipsis'
        [void]$dp.Children.Add($n)
        $b.Child = $dp
        $b.Add_MouseLeftButtonUp({
            param($s)
            Set-Setting 'Micro' ([string]$s.Tag)
            [void](Set-MicroActif)
            Write-Log "Micro choisi : $(if ($s.Tag) { $s.Tag } else { 'celui de Windows' })"
            if (Test-EveilActif) { Stop-Eveil; Start-Eveil; try { Update-EveilReglage } catch {} }   # « OK Evermind » écoute le nouveau micro
            Update-MicroChoix
        })
        [void]$ui.MicroChoix.Children.Add($b)
    }
}

function Start-Vumetre {
    Stop-Vumetre
    if ($EnTest) { return }
    try {
        $v = New-Object EMVumetre
        $v.Start(@([EMMicros]::Noms()).Count)
        $script:Vumetre = $v
        if (-not $script:VumetreTimer) {
            $script:VumetreTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:VumetreTimer.Interval = [TimeSpan]::FromMilliseconds(80)
            $script:VumetreTimer.Add_Tick({
                $v = $script:Vumetre
                if (-not $v -or $ui.Reglages.Visibility -ne 'Visible') { Stop-Vumetre; return }
                foreach ($i in @($script:MicroBarres.Keys)) {
                    $n = if ($i -lt $v.Niveaux.Length) { $v.Niveaux[$i] } else { 0 }
                    $script:MicroBarres[$i].Width = [math]::Min(90.0, [math]::Max(0.0, 90 * [math]::Sqrt([math]::Max(0.0, $n) * 12)))
                }
            })
        }
        $script:VumetreTimer.Start()
    } catch { Write-Log "Vumètre : $_" }
}

function Stop-Vumetre {
    if ($script:VumetreTimer) { $script:VumetreTimer.Stop() }
    $v = $script:Vumetre; $script:Vumetre = $null
    if ($v) { try { $v.Stop() } catch {} }
}

[void](Set-MicroActif)
[void](Set-CasqueActif)
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
                $env = [math]::Min(1.0, [math]::Min($i, $len - $i) / 300.0)
                $w.Write([int16](5000 * $env * [math]::Sin(2 * [math]::PI * $f * $i / $rate)))
            }
        }
        $mem.Position = 0
        [void][EMSortie]::Jouer($mem.ToArray())
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
function Set-VoixEtat([string]$Texte) {
    $ui.VoixEtat.Text = $Texte; $ui.VoixEtat.Visibility = if ($Texte) { 'Visible' } else { 'Collapsed' }
    # Thème perso : son image de chargement tourne tant qu'Evermind écoute ou réfléchit
    if ($script:VoixChargeTimer) {
        $ui.VoixCharge.Visibility = if ($Texte) { 'Visible' } else { 'Collapsed' }
        if ($Texte) { $script:VoixChargeTimer.Start() } else { $script:VoixChargeTimer.Stop() }
    }
}

# -Silencieux : après un « OK Evermind » pas encore confirmé, on enregistre sans bip ni bulle (rien n'est perdu si on parle tout de suite)
function Start-Ecoute([string]$Source, [switch]$Silencieux) {
    if ($script:Ecoute) { Stop-Ecoute; return }                 # deuxième appui : on arrête d'écouter
    if ($script:Transcription -and -not $Silencieux) { return }   # Evermind réfléchit encore à la phrase d'avant
    if (-not (Test-DicteeInstallee)) {
        Show-MainWindow
        Update-VoixInstall
        Invoke-Parole 'Pour comprendre ta voix, installe d''abord la voix dans Evermind.'
        return
    }
    Test-MicroRevenu
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

# « OK Evermind » confirmé : l'écoute silencieuse devient une écoute normale
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
    # En attente de la confirmation de « OK Evermind » : on garde tout ce qui est dit (25 secondes au plus)
    if ($e.Silencieux) { if ($e.Mic.Millis -gt 25000) { Stop-EcouteSansSuite }; return }
    # « OK Evermind, supprime le foot » dit d'une traite : rien de plus après la confirmation, ce qui a été compris suffit
    if ($e.Reste -and $e.Confirme -and -not $e.Mic.HeardVoice -and $e.Confirme.ElapsedMilliseconds -gt 800) {
        $r = $e.Reste; Stop-EcouteSansSuite; Invoke-Dictee $r; return
    }
    $m = $e.Mic
    # La pastille de la bulle et le bouton micro suivent la voix
    $s = 1 + 1.2 * $m.Level
    if ($script:Bulle) { $script:Bulle.Dot.RenderTransform.ScaleX = $script:Bulle.Dot.RenderTransform.ScaleY = $s }
    $ui.MicHalo.Opacity = [math]::Min(1.0, 0.3 + 2 * $m.Level)
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
        if ($m.HeardVoice -and $m.MillisSinceVoice -gt 1000) { $fin = $true }   # une seconde de silence : fini
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
        if ($e.Reste) { Invoke-Dictee $e.Reste; return }      # la demande était déjà dans la phrase « OK Evermind, ... »
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
    # Après « OK Evermind » : le début de la phrase (entendu par l'écoute) et la suite (le micro) sont relus ensemble
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

# Whisper écrit ce qui a été dit, en arrière plan. whisper-server garde le modèle chargé : une phrase est écrite
# en une seconde environ, au lieu de deux quand whisper-cli doit tout recharger à chaque fois (gardé en secours).
# Mode 'eveil' : confirmer un « OK Evermind » dit avec une demande, sans rien montrer (un faux réveil doit rester invisible)
# Mode 'verif' : Evermind écoute déjà (bip tout de suite) ; si ce n'était pas « OK Evermind », l'écoute s'arrête sans rien dire
function Start-Transcription([string]$Wav, [string]$Mode) {
    if (-not $Mode) { Set-VoixEtat 'Je réfléchis...'; Show-Bulle 'Je réfléchis...' }
    # Les mots attendus aident Whisper : les ordres et les titres de l'agenda (« Jordan » plutôt que « Jordane »)
    $titres = @($script:Agenda | ForEach-Object { $_.Titre -replace '^Anniversaire (?:de |d'')', '' } | Where-Object { $_ } | Select-Object -Unique -First 15) -join ', '
    $attendu = "OK Evermind, supprime, décale, ajoute. $titres." -replace '"', ''
    $t = @{ Wav = $Wav; Mode = $Mode; Debut = [Diagnostics.Stopwatch]::StartNew(); Attendu = $attendu }
    $srv = $null
    try { $srv = Start-WhisperServeur } catch { Write-Log "Whisper (serveur) : $_" }
    if ($srv) { $t.Serveur = $srv }
    else {
        $out = Join-Path $env:TEMP "evermind-$PID-texte"
        Remove-Item -LiteralPath "$out.txt" -ErrorAction SilentlyContinue
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $WhisperExe
        $sans = $attendu.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''   # les accents passent mal en ligne de commande
        $psi.Arguments = "-m `"$WhisperModele`" -f `"$Wav`" -l fr -nt -np -t $(Get-FilsWhisper) -otxt -of `"$out`" --prompt `"$sans`""
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $VoixDir
        try { $t.Process = [Diagnostics.Process]::Start($psi); $t.Out = "$out.txt" }
        catch {
            Write-Log "Dictée impossible : $_"
            if (-not $Mode) { Set-VoixEtat "La dictée n'a pas pu démarrer ($($_.Exception.Message))."; Show-Bulle 'La dictée n''a pas marché.' 3000 }
            return
        }
    }
    $script:Transcription = $t
    if (-not $script:TranscriptionTimer) {
        $script:TranscriptionTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:TranscriptionTimer.Interval = [TimeSpan]::FromMilliseconds(40)
        $script:TranscriptionTimer.Add_Tick({ Step-Transcription })
    }
    $script:TranscriptionTimer.Start()
    Step-Transcription
}

function Get-FilsWhisper { [math]::Max(2, [math]::Min(12, [int]([Environment]::ProcessorCount / 2))) }

# whisper-server : lancé à la première phrase (ou quand « OK Evermind » est actif), arrêté après 10 minutes sans servir
function Start-WhisperServeur {
    $s = $script:WhisperSrv
    if ($s -and -not $s.Process.HasExited) { $s.Dernier = Get-Date; return $s }
    if (-not (Test-Path -LiteralPath $WhisperServeur)) { return $null }
    Add-Type -AssemblyName System.Net.Http
    $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Get-CopieMindset $WhisperServeur   # (nommé Mindset.exe : une seule ligne pour la suite)
    $psi.Arguments = "-m `"$WhisperModele`" --host 127.0.0.1 --port $port -l fr -nt -t $(Get-FilsWhisper)"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $VoixDir
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true   # ses messages sont lus puis jetés
    $p = [Diagnostics.Process]::Start($psi)
    try { $p.PriorityClass = 'BelowNormal' } catch {}   # (un jeu passe avant)
    $client = New-Object Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(60)
    $script:WhisperSrv = @{ Process = $p; Port = $port; Client = $client; Pret = $false; Dernier = (Get-Date)
                           Sortie = (New-Object EMLigneur $p.StandardOutput); Erreurs = (New-Object EMLigneur $p.StandardError) }
    Write-Log 'Whisper démarré'
    if (-not $script:WhisperTimer) {
        $script:WhisperTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:WhisperTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:WhisperTimer.Add_Tick({
            $s = $script:WhisperSrv
            if (-not $s) { $script:WhisperTimer.Stop(); return }
            Read-WhisperServeur $s
            if ($s.Process.HasExited) { $script:WhisperSrv = $null; Write-Log "Whisper arrêté tout seul (code $($s.Process.ExitCode))"; return }
            # Gardé prêt tant que « OK Evermind » écoute ; sinon la mémoire est rendue après 10 minutes
            if (-not $script:Transcription -and -not $script:Eveil -and ((Get-Date) - $s.Dernier).TotalMinutes -gt 10) { Stop-WhisperServeur; Write-Log 'Whisper mis en veille' }
        })
    }
    $script:WhisperTimer.Start()
    $script:WhisperSrv
}

# Lit (et oublie) ce que le serveur écrit. Il est prêt quand il écoute sur son port (le modèle est chargé).
function Read-WhisperServeur($s) {
    foreach ($lecteur in $s.Sortie, $s.Erreurs) { while ($lecteur.Suivante()) {} }
    if (-not $s.Pret) {
        $s.Pret = [bool](@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()) | Where-Object { $_.Port -eq $s.Port })
    }
}

function Stop-WhisperServeur {
    $s = $script:WhisperSrv
    $script:WhisperSrv = $null
    if ($s) { try { $s.Client.Dispose() } catch {}; try { if (-not $s.Process.HasExited) { $s.Process.Kill() } } catch {} }
}

function Step-Transcription {
    $t = $script:Transcription
    if (-not $t) { $script:TranscriptionTimer.Stop(); return }
    $texte = $null
    if ($t.Serveur) {
        $s = $t.Serveur
        Read-WhisperServeur $s
        if ($s.Process.HasExited) { $texte = '' }
        elseif (-not $t.Envoi) {
            if (-not $s.Pret) { if ($t.Debut.Elapsed.TotalSeconds -gt 20) { $texte = '' } else { return } }
            else {
                $m = New-Object Net.Http.MultipartFormDataContent
                $f = New-Object Net.Http.ByteArrayContent (, [IO.File]::ReadAllBytes($t.Wav))
                $m.Add($f, 'file', 'phrase.wav')
                $m.Add((New-Object Net.Http.StringContent 'text'), 'response_format')
                $m.Add((New-Object Net.Http.StringContent $t.Attendu), 'prompt')
                $t.Envoi = $s.Client.PostAsync("http://127.0.0.1:$($s.Port)/inference", $m)
                return
            }
        }
        elseif (-not $t.Envoi.IsCompleted) { return }
        elseif (-not $t.Lecture) {
            if ($t.Envoi.Status -ne 'RanToCompletion') { Write-Log "Whisper : $($t.Envoi.Exception.InnerException.Message)"; $texte = '' }
            else { $t.Lecture = $t.Envoi.Result.Content.ReadAsStringAsync(); return }
        }
        elseif (-not $t.Lecture.IsCompleted) { return }
        else { $texte = if ($t.Lecture.Status -eq 'RanToCompletion') { [string]$t.Lecture.Result } else { '' } }
        $s.Dernier = Get-Date
    } else {
        if (-not $t.Process.HasExited) {
            if ($t.Debut.Elapsed.TotalSeconds -gt 60) { try { $t.Process.Kill() } catch {} } else { return }
        }
        $texte = ''
        try { if (Test-Path -LiteralPath $t.Out) { $texte = [IO.File]::ReadAllText($t.Out, [Text.Encoding]::UTF8) } } catch {}
        Remove-Item -LiteralPath $t.Out -ErrorAction SilentlyContinue
    }
    $script:Transcription = $null
    $script:TranscriptionTimer.Stop()
    # Le dernier enregistrement est gardé (derniere-dictee.wav) pour comprendre une phrase mal entendue
    try { Move-Item -LiteralPath $t.Wav -Destination (Join-Path $DataDir 'derniere-dictee.wav') -Force } catch {}
    Write-Log "Dictée ($([math]::Round($t.Debut.Elapsed.TotalSeconds, 1)) s) : $($texte.Trim())"
    switch ($t.Mode) {
        'eveil' { Invoke-Reveil $texte }
        'verif' { Confirm-Reveil $texte }
        default { Invoke-Dictee $texte }
    }
}
# Ce qui a été dit : l'assistant s'en occupe s'il est installé, sinon les règles d'Evermind
function Invoke-Dictee([string]$Texte) {
    $t = ($Texte -replace '\[[^\]]*\]|\([^)]*\)', ' ' -replace '\s+', ' ').Trim()
    $t = ($t -replace "(?i)^\W*$RxReveil\b\W*", '').Trim()   # « OK Evermind, ... » : seulement la demande
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
        Show-Bulle "C'est noté : $ecrit" 5000
        if ($r.Lieu) { $dit += ", $($r.Lieu)" }
        if (@($r.Avec).Count) { $dit += ", avec $(@($r.Avec) -join ' et ')" }
        $conf = @(if (-not $r.Journee) { Get-Conflits $r.Quand $r.Fin $r.Id })   # (@ autour : un seul conflit se compte aussi)
        if ($conf.Count) { $dit += ". Attention, tu as déjà $(Get-TitreAffiche $conf[0].RV.Titre) à ce moment-là" }
        Invoke-Parole "C'est noté : $dit.$(Get-TexteFichiers $r)"
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
