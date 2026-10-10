# Evermind : chargement de la fenêtre et aides pour l'interface.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# ---------------------------------------------------------------------------
# Fenêtre (décrite dans interface.xaml)
# ---------------------------------------------------------------------------
[xml]$Xaml = [IO.File]::ReadAllText((Join-Path $ModulesDir 'interface.xaml'), [Text.Encoding]::UTF8)
try { $Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $Xaml)) }
catch {
    # Sans fenêtre, Evermind resterait caché sans rien faire : on prévient et on s'arrête
    $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
    Write-Log "Fenêtre impossible à charger : $($e.Message)"
    [Console]::Error.WriteLine("Fenêtre impossible à charger : $($e.Message)")
    if (-not $EnTest) { [System.Windows.MessageBox]::Show("Evermind n'a pas pu s'ouvrir :`n`n$($e.Message)`n`nRetélécharge Evermind et remplace tout le dossier.", 'Evermind', 'OK', 'Error') | Out-Null }
    exit 1
}
$ui = @{}
foreach ($node in $Xaml.SelectNodes('//*[@*[local-name()="Name"]]')) {
    $n = $node.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1
    if ($n) { $ui[$n.Value] = $Window.FindName($n.Value) }
}

# ok : c'est noté ; bad : il manque quelque chose ; accent et accent2 : couleurs de la marque (cyan, magenta)
$Colors = @{ ok = '#7FF4FF'; bad = '#FF7A9C'; accent = '#00E5FF'; accent2 = '#FF2EB5'; dim = '#A6A1BC' }

function Get-Brush([string]$Hex) { [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex) }

# Icône de la fenêtre et logo de l'en-tête. Chargée en mémoire pour ne pas bloquer le fichier
# (il doit pouvoir être remplacé par une mise à jour).
$IconPath = Join-Path $AppDir 'Evermind.ico'
if (Test-Path -LiteralPath $IconPath) {
    try {
        $frames = [System.Windows.Media.Imaging.BitmapDecoder]::Create((New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($IconPath))), 'None', 'OnLoad').Frames
        $Window.Icon = $frames | Sort-Object PixelWidth | Where-Object { $_.PixelWidth -ge 32 } | Select-Object -First 1
    } catch { Write-Log "Icône : $_" }
}

$Window.Add_SourceInitialized({
    # Barre de titre sombre, couleur du haut du fond (#0C0920 écrit en « 0xBBGGRR »)
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle
    try { [EMNative]::SetDarkTitleBar($h, 0x20090C) } catch {}
    # Épinglée à la barre des tâches, la fenêtre se relance par Evermind.exe (ou par PowerShell s'il manque), avec son icône
    try { [EMNative]::SetWindowIdentity($h, $AppId, (Get-LaunchCommand), $IconPath, 'Evermind') }
    catch { Write-Log "Identité de la fenêtre : $_" }
})

# « Êtes-vous sûr ? » : petite fenêtre par dessus tout. $Oui est lancé seulement si on confirme.
function Show-Confirmation([string]$Titre, [string]$Texte, [string]$Bouton, [scriptblock]$Oui) {
    $ui.ConfirmationTitre.Text = $Titre
    $ui.ConfirmationTexte.Text = $Texte
    $ui.ConfirmationTexte.Visibility = if ($Texte) { 'Visible' } else { 'Collapsed' }
    $ui.BtnConfirmationOui.Content = $Bouton
    $script:ConfirmationAction = $Oui
    $ui.Confirmation.Visibility = 'Visible'
    [void]$ui.BtnConfirmationNon.Focus()   # Entrée par erreur = Annuler
}

function Close-Confirmation { $ui.Confirmation.Visibility = 'Collapsed'; $script:ConfirmationAction = $null }

# Bouton comme dans Nevermind (même style partout)
function New-Button([string]$Text, [string]$Style = 'BtnSecondary') {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $Text
    $btn.Style = $Window.FindResource($Style)
    $btn.VerticalAlignment = 'Center'
    $btn
}

# Bonjour selon l'heure
function Update-Greeting {
    $h = (Get-Date).Hour
    $hello = if ($h -ge 18 -or $h -lt 5) { 'Bonsoir' } else { 'Bonjour' }
    $ui.Greeting.Text = "$hello ! Je me souviens de tout pour toi."
}

# ---------------------------------------------------------------------------
# Capture d'écran de la fenêtre (tests automatiques)
# ---------------------------------------------------------------------------
# La fenêtre s'ouvre hors de l'écran, se dessine, est enregistrée en image, puis l'app se ferme.
function Start-Capture([string]$Path) {
    $Window.WindowStartupLocation = 'Manual'
    $Window.Left = -10000; $Window.Top = 0; $Window.ShowActivated = $false
    # Capture une fois la fenêtre dessinée et la dictée de test (s'il y en a une) terminée
    $Window.Add_ContentRendered({
        $script:CaptureTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:CaptureTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $script:CaptureTimer.Add_Tick({
            if ($script:Transcription -or $script:Demande -or $script:TestTimer -or ($script:Eveil -and $script:Eveil.Detecte) -or $script:Piper -or ($script:VoixDl -and -not $script:VoixDl.Fini)) { return }
            $script:CaptureTimer.Stop()
            try {
                $root = $Window.Content
                $w = [int]$root.ActualWidth; $h = [int]$root.ActualHeight
                $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                $bmp.Render($root)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
                $fs = [IO.File]::Create($env:EVERMIND_CAPTURE)
                try { $enc.Save($fs) } finally { $fs.Dispose() }
            } catch { Write-Log "Capture : $_"; [Console]::Error.WriteLine("Capture : $_") }
            Exit-App
        })
        $script:CaptureTimer.Start()
    })
}
