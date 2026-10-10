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

function Set-AutoStart([bool]$On) {
    if ($EnTest) { return }
    if ($On) { New-ItemProperty -LiteralPath $RunKey -Name $RunName -Value (Get-AutoStartCommand) -PropertyType String -Force | Out-Null }
    else { Remove-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue }
    Set-Setting 'DemarrageWindows' $On
}

# Activé au premier lancement (les rappels ne marchent que si Evermind tourne). Ensuite, le chemin est remis
# à jour à chaque lancement, au cas où le dossier d'Evermind a été déplacé.
function Initialize-AutoStart {
    if ($EnTest) { return }
    try {
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
function Show-MainWindow {
    try {
        if (-not $Window.IsVisible) { $Window.Show() }
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

function Show-Notify([string]$Title, [string]$Text) {
    if ($EnTest) { Write-Log "$Title : $Text"; return }
    try { (Get-TrayIcon).ShowBalloonTip(8000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Info) }
    catch { Write-Log "Notification impossible : $_" }
}

# La croix ne ferme pas Evermind : il reste près de l'horloge pour donner les rappels.
function Hide-ToTray {
    $Window.Hide()
    if (-not (Get-Setting 'AstuceHorloge' $false)) {
        Set-Setting 'AstuceHorloge' $true
        Show-Notify 'Evermind reste près de l''horloge' 'Il veille sur tes rendez-vous. Clique sur son icône pour le rouvrir.'
    }
}

function Exit-App {
    if ($script:Quitting) { return }
    $script:Quitting = $true
    Write-Log 'Fermeture'
    try { if ($script:ShowWatch) { $script:ShowWatch.Stop() } } catch {}
    try { if ($script:Ecoute) { $script:Ecoute.Mic.Stop(); $script:Ecoute = $null } } catch {}
    try { if ($script:VoixHotkeyOk) { [EMNative]::RemoveHotKey((New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle, $VoixHotkeyId) } } catch {}
    try { if ($script:Bulle) { $script:Bulle.Win.Close() } } catch {}
    try { if ($script:Synth) { $script:Synth.Dispose() } } catch {}
    try { Stop-Cerveau } catch {}
    try { Stop-Eveil } catch {}
    try { if ($script:LogoTimer) { $script:LogoTimer.Stop() } } catch {}
    try { if ($script:NotifyIcon) { $script:NotifyIcon.Visible = $false; $script:NotifyIcon.Dispose() } } catch {}
    try { $Window.Close() } catch {}
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}
