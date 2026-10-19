# Evermind : démarrage avec Windows et icône près de l'horloge.
# Chargé par Evermind.ps1, qui définit $AppDir, $ModulesDir et $MainScript.

# ---------------------------------------------------------------------------
# Démarrage avec Windows (clé « Run » de l'utilisateur, aucun droit administrateur nécessaire)
# ---------------------------------------------------------------------------
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'Evermind'

# Commande qui lance Evermind : Evermind.exe, ou PowerShell s'il manque (lancé par le .bat de secours,
# par exemple quand le « Contrôle intelligent des applications » de Windows bloque le .exe non signé)
function Get-LaunchCommand([switch]$Demarrage) {
    $opt = if ($Demarrage) { ' -Demarrage' } else { '' }
    if (Test-Path -LiteralPath $AppExe) { "`"$AppExe`"$opt" }
    else { "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$MainScript`"$opt" }
}

function Get-AutoStartCommand { Get-LaunchCommand -Demarrage }

function Test-AutoStart {
    [bool](Get-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue)
}

# L'entrée « Evermind » lance-t-elle cette copie-ci ? (Evermind.exe, ou ce script par PowerShell)
function Test-AutoStartIci {
    $cur = [string](Get-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
    if (-not $cur) { return $false }
    $chemins = @(@([regex]::Matches($cur, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) + ($cur.Trim() -replace '(?i)\s+-Demarrage$', '') | ForEach-Object { Get-CheminNormal $_ })
    ($chemins -contains (Get-CheminNormal $AppExe)) -or ($chemins -contains (Get-CheminNormal $MainScript))
}

function Set-AutoStart([bool]$On) {
    if ($EnTest -or $GereParMindset) { return }   # copie gérée : c'est Mindset qui lance Evermind avec Windows
    if ($On) { New-ItemProperty -LiteralPath $RunKey -Name $RunName -Value (Get-AutoStartCommand) -PropertyType String -Force | Out-Null }
    else { Remove-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue }
    Set-Setting 'DemarrageWindows' $On
}

# Activé au premier lancement (les rappels ne marchent que si Evermind tourne). Ensuite, le chemin est remis
# à jour à chaque lancement, au cas où le dossier d'Evermind a été déplacé.
function Initialize-AutoStart {
    if ($EnTest) { return }
    try {
        # Copie gérée par Mindset : Mindset la lance avec Windows (avec -Demarrage). Une ancienne entrée « Evermind » qui
        # lance cette copie-ci est retirée, sinon Evermind serait lancé deux fois ; celle d'une autre copie reste.
        if ($GereParMindset) {
            if (Test-AutoStartIci) { Remove-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction Stop; Write-Log 'Démarrage avec Windows : entrée d''Evermind retirée (Mindset s''en charge)' }
            return
        }
        $want = [bool](Get-Setting 'DemarrageWindows' $true)
        if ($want) {
            $cur = (Get-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
            if ($cur -ne (Get-AutoStartCommand)) { Set-AutoStart $true; Write-Log 'Démarrage avec Windows activé' }
        } elseif (Test-AutoStart) { Set-AutoStart $false }
    } catch { Write-Log "Démarrage avec Windows : $_" }
}

# ---------------------------------------------------------------------------
# Fenêtre et icône près de l'horloge
# ---------------------------------------------------------------------------
# Décrochée de Mindset, qui l'a cachée lui-même (SW_HIDE) : WPF la croit encore visible. Elle est cachée pour WPF aussi,
# pour que le prochain affichage (icône près de l'horloge) la remontre pour de bon.
function Sync-VisibiliteFenetre {
    if ($Window.IsVisible -and -not [EMNative]::EstVisible((New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle)) { $Window.Hide() }
}

function Show-MainWindow {
    # (tests : la fenêtre reste hors de l'écran et ne prend jamais le premier plan, l'utilisateur garde la main)
    if ($EnTest) { return }
    # Géré par Mindset : Evermind ne s'ouvre que dans Mindset, qui se ramène devant sur son onglet
    if ($GereParMindset -and (Open-DansMindset)) { return }
    if ($script:DansMindset) { return }   # (affiché dans Mindset : c'est Mindset qui le montre, rien ne doit l'en sortir)
    try {
        Sync-VisibiliteFenetre
        if (-not $Window.IsVisible) { $Window.ShowActivated = $true; $Window.Show() }
        if ($Window.WindowState -eq 'Minimized') { $Window.WindowState = 'Normal' }
        # Passe devant toutes les fenêtres, puis redevient une fenêtre normale
        $Window.Topmost = $true; $Window.Topmost = $false
        [void]$Window.Activate()
    } catch { Write-Log "Affichage : $_" }
}

function Get-TrayIcon {
    if (-not $script:NotifyIcon) {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ico = Join-Path $AppDir 'Evermind.ico'
        $ni.Icon = if (Test-Path -LiteralPath $ico) { New-Object System.Drawing.Icon (New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($ico))) } else { [System.Drawing.SystemIcons]::Information }
        $ni.Text = 'Evermind'
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        [void]$menu.Items.Add('Ouvrir Evermind', $null, { Show-MainWindow })
        [void]$menu.Items.Add('Quitter', $null, { Exit-App })
        $ni.ContextMenuStrip = $menu
        $ni.Add_MouseClick({ param($s, $e) if ([string]$e.Button -eq 'Left') { Show-MainWindow } })
        $ni.Add_BalloonTipClicked({ Show-MainWindow })
        $ni.Visible = $true
        $script:NotifyIcon = $ni
    }
    $script:NotifyIcon
}

# Notification : l'alerte d'Evermind (alerte.ps1), plus la bulle de Windows
function Show-Notify([string]$Title, [string]$Text) {
    if ($EnTest) { Write-Log "$Title : $Text"; return }
    Show-Alerte $Title $Text
}

# La croix ne ferme pas Evermind : il reste près de l'horloge pour donner les rappels.
function Hide-ToTray {
    $Window.Hide()
    if ($GereParMindset) { return }   # (géré par Mindset : pas d'icône à Evermind près de l'horloge)
    if (-not (Get-Setting 'AstuceHorloge' $false)) {
        Set-Setting 'AstuceHorloge' $true
        Show-Notify 'Evermind reste près de l''horloge' 'Il veille sur tes rendez-vous. Clique sur son icône pour le rouvrir.'
    }
}

# La croix : demander (par défaut), ou ce qui a été retenu (« reduire », « quitter »)
function Invoke-Croix {
    switch ([string](Get-Setting 'Croix' '')) {
        'reduire' { Hide-ToTray }
        'quitter' { [void]$Window.Dispatcher.BeginInvoke([action]{ Exit-App }) }   # pas pendant la fermeture en cours
        default {
            $ui.ChkFermerRetenir.IsChecked = $false
            $ui.Fermer.Visibility = 'Visible'
            [void]$ui.BtnFermerReduire.Focus()
        }
    }
}

function Close-Fermer { $ui.Fermer.Visibility = 'Collapsed' }

function Invoke-FermerChoix([string]$Choix) {
    if ($ui.ChkFermerRetenir.IsChecked) { Set-Setting 'Croix' $Choix; Write-Log "Croix : $Choix (retenu)" }
    Close-Fermer
    if ($Choix -eq 'quitter') { Exit-App } else { Hide-ToTray }
}

# Réglages : ce que fait la croix
function Update-CroixReglage {
    $c = [string](Get-Setting 'Croix' '')
    $ui.CroixDemander.Tag = if (-not $c) { 'on' } else { $null }
    $ui.CroixReduire.Tag = if ($c -eq 'reduire') { 'on' } else { $null }
    $ui.CroixQuitter.Tag = if ($c -eq 'quitter') { 'on' } else { $null }
}

# Relance Evermind (nouveau thème) : il se ferme, puis Evermind.ps1 le relance une fois tout arrêté
# ---------------------------------------------------------------------------
# Mode jeu : quand un programme plein écran (un jeu, une vidéo) est au premier plan, Evermind se fait tout petit.
#   Priorité basse, l'IA et la voix rendues si elles ne servent pas (l'IA garde sinon ~1 Go de la carte graphique),
#   la mémoire inutilisée rendue à Windows. « OK Evermind » et Ctrl + Maj + Espace marchent toujours (l'IA se
#   recharge en quelques secondes si on lui demande quelque chose). Vérifié toutes les 4 secondes.
# ---------------------------------------------------------------------------
function Update-ModeJeu {
    $jeuPid = [EMJeu]::PleinEcran()
    $jeu = $jeuPid -ne 0
    $moi = [Diagnostics.Process]::GetCurrentProcess()
    if ($jeu -ne [bool]$script:ModeJeu) {
        $script:ModeJeu = $jeu
        if ($jeu) {
            $nom = try { (Get-Process -Id $jeuPid -ErrorAction Stop).ProcessName } catch { '?' }
            Write-Log "Mode jeu : $nom au premier plan, Evermind se fait discret"
            try { $moi.PriorityClass = 'BelowNormal' } catch {}
            Set-AnimationsPause $true
        } else {
            Write-Log 'Mode jeu : fini'
            try { $moi.PriorityClass = 'Normal' } catch {}
        }
    }
    if (-not $jeu) { return }
    # Pendant le jeu : ce qui ne sert pas est rendu (rien n'est coupé pendant une demande ou une phrase dite)
    $occupe = $script:Demande -or $script:Transcription -or $script:Parle -or $script:Ecoute
    if (-not $occupe) {
        if ($script:Cerveau -and ((Get-Date) - $script:Cerveau.Dernier).TotalSeconds -gt 60) { Stop-Cerveau; Write-Log 'Mode jeu : assistant mis en veille' }
        if ($script:Kokoro -and ((Get-Date) - $script:Kokoro.Dernier).TotalSeconds -gt 60) { Stop-KokoroServeur; Write-Log 'Mode jeu : voix mise en veille' }
    }
    if (-not $script:MemoireRendue -or ((Get-Date) - $script:MemoireRendue).TotalMinutes -ge 2) {
        $script:MemoireRendue = Get-Date
        [GC]::Collect()
        [EMJeu]::RendreMemoire($moi.Handle)
        if ($script:WhisperSrv -and -not $script:WhisperSrv.Process.HasExited) { try { [EMJeu]::RendreMemoire($script:WhisperSrv.Process.Handle) } catch {} }
    }
}

function Start-ModeJeu {
    if ($script:ModeJeuTimer -or $EnTest) { return }
    $script:ModeJeuTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ModeJeuTimer.Interval = [TimeSpan]::FromSeconds(4)
    $script:ModeJeuTimer.Add_Tick({ try { Update-ModeJeu } catch { Write-Log "Mode jeu : $_" } })
    $script:ModeJeuTimer.Start()
}

# ---------------------------------------------------------------------------
# Affiché dans Mindset : Mindset accroche la vraie fenêtre d'Evermind dans sa zone centrale (fenêtre enfant, sans
# bordure), et peut la décrocher à tout moment. Vérifié toutes les 500 ms. Accrochée : plus de taille minimale
# (Mindset donne la place qu'il a ; plus petite que la taille minimale, toute la fenêtre est réduite d'autant, la
# mise en page reste la même) et le logo reste à sa place ; décrochée : tout revient comme avant.
# ---------------------------------------------------------------------------
$script:DansMindset = $false

function Update-DansMindset {
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle
    $dans = [EMNative]::EstEnfant($h)
    if ($dans -eq $script:DansMindset) { return }
    if (-not $script:TailleMin) { $script:TailleMin = @{ L = $Window.MinWidth; H = $Window.MinHeight } }   # (celle d'interface.xaml)
    $script:DansMindset = $dans
    if ($dans) {
        $Window.MinWidth = 0; $Window.MinHeight = 0; $script:LogoDrag = $null
        # Lancé caché (-Demarrage) : pour WPF la fenêtre n'a jamais été montrée, Mindset n'afficherait qu'un fond noir.
        # Elle est montrée sans être activée, puis remise exactement là où Mindset l'a placée.
        if (-not $Window.IsVisible) {
            $place = [EMNative]::PlaceDansParent($h)
            $Window.ShowActivated = $false; $Window.WindowStartupLocation = 'Manual'
            $Window.Show()
            [EMNative]::Placer($h, $place)
            Set-AnimationsPause $false
            Write-Log 'Affiché dans Mindset : fenêtre montrée (lancé caché)'
        }
    }
    else { $Window.MinWidth = $script:TailleMin.L; $Window.MinHeight = $script:TailleMin.H }
    Write-Log "$(if ($dans) { 'Affiché dans Mindset' } else { 'Plus affiché dans Mindset : fenêtre normale' })"
    Update-EchelleMindset
    Update-LogoPlace
}

# Dans Mindset, plus petite que la taille minimale : tout le contenu est réduit à l'échelle (rien n'est coupé ni tassé)
function Update-EchelleMindset {
    $e = 1.0
    if ($script:DansMindset -and $Window.ActualWidth -gt 0 -and $Window.ActualHeight -gt 0) {
        $e = [math]::Min(1.0, [math]::Min($Window.ActualWidth / $script:TailleMin.L, $Window.ActualHeight / $script:TailleMin.H))
    }
    $Window.Content.LayoutTransform = if ($e -lt 1.0) { New-Object System.Windows.Media.ScaleTransform $e, $e } else { $null }
}
function Start-DansMindsetSurveillance {
    if ($script:DansMindsetTimer) { return }
    $script:DansMindsetTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DansMindsetTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:DansMindsetTimer.Add_Tick({ try { Update-DansMindset } catch { Write-Log "Affichage dans Mindset : $_" } })
    $script:DansMindsetTimer.Start()
    $Window.Add_SizeChanged({ if ($script:DansMindset) { Update-EchelleMindset } })
}

# ---------------------------------------------------------------------------
# Quitter Mindset ferme aussi Evermind : Mindset écrit quitter.demande dans le dossier de données d'Evermind, attend
# 6 secondes, puis arrête Evermind s'il tourne encore. Evermind le voit (vérifié chaque seconde) et quitte comme avec
# « Quitter » : rien à confirmer, et une dictée ou une phrase en cours est coupée (on a choisi de tout quitter).
# ---------------------------------------------------------------------------
$QuitterFichier = Join-Path $DataDir 'quitter.demande'
try { if ([IO.File]::Exists($QuitterFichier)) { [IO.File]::Delete($QuitterFichier) } } catch {}   # (un vieux fichier refermerait Evermind tout de suite)

# ---------------------------------------------------------------------------
# Carte d'Evermind dans l'accueil de Mindset : les prochains rendez-vous (etat.json, dans le dossier de données), et un
# clic sur l'un d'eux dans Mindset ouvre sa fiche ici (afficher-rdv.demande : son identifiant, et la date de cette fois).
# etat.json : les 10 prochaines fois (un rendez-vous qui revient compte pour chaque fois), que du texte et des dates ;
# Mindset écarte celles qui sont passées et n'exécute jamais rien qui en vient. La demande, elle, n'est qu'un identifiant
# cherché dans l'agenda.
# ---------------------------------------------------------------------------
$EtatFichier = Join-Path $DataDir 'etat.json'
$RdvFichier = Join-Path $DataDir 'afficher-rdv.demande'
try { if ([IO.File]::Exists($RdvFichier) -and ((Get-Date) - [IO.File]::GetLastWriteTime($RdvFichier)).TotalMinutes -gt 2) { [IO.File]::Delete($RdvFichier) } } catch {}   # (une vieille demande n'ouvre rien)

function Write-EtatMindset {
    if (-not $GereParMindset) { return }
    $ic = [Globalization.CultureInfo]::InvariantCulture
    $prochains = @(Get-Upcoming | Select-Object -First 10 | ForEach-Object {
        $t = [string]$_.RV.Titre; if ($t.Length -gt 80) { $t = $t.Substring(0, 80) }
        [ordered]@{ Id = [string]$_.RV.Id; Titre = $t; Quand = $_.Prochain.ToString('s', $ic); Journee = [bool]$_.RV.Journee; Type = [string](Get-TypeRV $_.RV) }
    })
    $cle = ConvertTo-Json -InputObject $prochains -Depth 4 -Compress
    if ($cle -eq $script:EtatMindsetEcrit) { return }   # (rien de neuf : pas d'écriture)
    try { Save-JsonFile $EtatFichier ([ordered]@{ Version = 1; Maj = (Get-Date -Format s); Prochains = $prochains }); $script:EtatMindsetEcrit = $cle }
    catch { Write-Log "etat.json pour Mindset : $($_.Exception.Message)" }
}

function Show-RdvDemande([string]$Texte) {
    if ($Texte -notmatch '^([0-9a-f]{32})(\|(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d))?$') { return }
    $rv = Get-RendezVous $Matches[1]
    if (-not $rv) { return }
    $quand = $rv.Quand
    if ($Matches[3]) { try { $quand = [datetime]::ParseExact($Matches[3], 's', [Globalization.CultureInfo]::InvariantCulture) } catch {} }
    Write-Log "Fiche ouverte depuis Mindset : $($rv.Titre)"
    Show-Fiche $rv $quand
}

function Start-QuitterSurveillance {
    if ($script:QuitterTimer) { return }
    $script:QuitterTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:QuitterTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:QuitterTimer.Add_Tick({
        # Mindset demande la fiche d'un rendez-vous (clic sur sa carte)
        if ([IO.File]::Exists($RdvFichier)) {
            $t = ''; try { $t = ([IO.File]::ReadAllText($RdvFichier)).Trim(); [IO.File]::Delete($RdvFichier) } catch {}
            try { Show-RdvDemande $t } catch { Write-Log "Fiche demandée par Mindset : $_" }
        }
        # Les prochains rendez-vous pour Mindset : au démarrage, puis toutes les 10 minutes (une fois passée, une fois suivante)
        $script:EtatTicks++
        if ($script:EtatTicks % 600 -eq 1) { try { Write-EtatMindset } catch {} }
        if (-not [IO.File]::Exists($QuitterFichier)) { return }
        $script:QuitterTimer.Stop()
        try { [IO.File]::Delete($QuitterFichier) } catch {}
        Write-Log 'Fermeture demandée par Mindset'
        Exit-App
    })
    $script:QuitterTimer.Start()
}

function Restart-App {
    $script:Relancer = $true
    Exit-App
}

function Exit-App {
    if ($script:Quitting) { return }
    $script:Quitting = $true
    Write-Log 'Fermeture'
    try { if ($script:ShowWatch) { $script:ShowWatch.Stop() } } catch {}
    try { if ($script:QuitterTimer) { $script:QuitterTimer.Stop() } } catch {}
    try { if ($script:DansMindsetTimer) { $script:DansMindsetTimer.Stop() } } catch {}
    try { if ($script:Ecoute) { $script:Ecoute.Mic.Stop(); $script:Ecoute = $null } } catch {}
    try { if ($script:VoixHotkeyOk) { [EMNative]::RemoveHotKey((New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle, $VoixHotkeyId) } } catch {}
    try { if ($script:Bulle) { $script:Bulle.Win.Close() } } catch {}
    try { if ($script:Synth) { $script:Synth.Dispose() } } catch {}
    try { Stop-Cerveau } catch {}
    try { Stop-KokoroServeur } catch {}
    try { Stop-WhisperServeur } catch {}
    try { Stop-Eveil } catch {}
    try { if ($script:LogoTimer) { $script:LogoTimer.Stop() } } catch {}
    try { if ($script:NotifyIcon) { $script:NotifyIcon.Visible = $false; $script:NotifyIcon.Dispose() } } catch {}
    try { $Window.Close() } catch {}
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}
