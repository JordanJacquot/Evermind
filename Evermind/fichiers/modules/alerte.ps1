# Evermind : ses propres alertes, aux couleurs d'Evermind et du thème choisi, à la place des bulles de Windows.
#   Une carte glisse en bas à droite de l'écran, au-dessus de la barre des tâches, même quand la fenêtre est
#   rangée près de l'horloge. Les alertes s'empilent, partent toutes seules (pas tant que la souris est dessus),
#   et un clic ouvre Evermind sur le rendez-vous. Un rappel, lui, est dit à voix haute et reste jusqu'à un clic.
#   « Dans 10 min » le fait revenir plus tard (retenu sur disque : même après une relance).
# Et les rappels : la veille à 20 h, le matin même à 8 h, N minutes avant (codes de Format-Rappel), une seule fois,
# rattrapés au réveil du PC ou quand il est allumé tard.
# Chargé par Evermind.ps1, après details.ps1.

$script:Alertes = New-Object System.Collections.ArrayList

# Alerte simple (micro muet, « Evermind reste près de l'horloge »...) : Show-Notify passe par ici
function Show-Alerte {
    param([string]$Titre, [string]$Texte, [string]$Etiquette = 'Evermind', [string]$Type = '', $RV = $null, $Quand = $null, [int]$Secondes = 9, [string]$Icone = '✦', [switch]$Plus)
    if ($EnTest -and -not $env:EVERMIND_CAPTURE_ALERTE) { Write-Log "Alerte : $Titre : $Texte"; return }
    try { New-AlerteFenetre $Titre $Texte $Etiquette $Type $RV $Quand $Secondes $Icone ([bool]$Plus) }
    catch {
        Write-Log "Alerte impossible : $_"
        $script:AlerteEnCapture = $false
        if (-not $GereParMindset) { try { (Get-TrayIcon).ShowBalloonTip(8000, $Titre, $Texte, [System.Windows.Forms.ToolTipIcon]::Info) } catch {} }
    }
}

function New-AlerteFenetre($Titre, $Texte, $Etiquette, $Type, $RV, $Quand, $Secondes, $Icone, $Plus) {
    $couleur = if ($Type -and $Types[$Type]) { $Types[$Type].Couleur } else { $Colors.accent }
    if ($Type -and $Types[$Type]) { $Icone = $Types[$Type].Icone }

    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'; $w.AllowsTransparency = $true; $w.Background = [System.Windows.Media.Brushes]::Transparent
    $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false; $w.ResizeMode = 'NoResize'
    $w.Width = 408; $w.SizeToContent = 'Height'; $w.WindowStartupLocation = 'Manual'
    $w.FontFamily = $Window.FontFamily
    $w.Left = -10000; $w.Top = 0

    # La carte : verre sombre, bord en dégradé et halo de la couleur du rendez-vous
    $carte = New-Object System.Windows.Controls.Border
    $carte.Margin = '14'; $carte.CornerRadius = 20; $carte.BorderThickness = 1.5; $carte.Cursor = 'Hand'
    $bord = New-Object System.Windows.Media.LinearGradientBrush; $bord.StartPoint = '0,0'; $bord.EndPoint = '1,1'
    $bord.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur $couleur)), 0))
    $bord.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur $Colors.accent2)), 1))
    $carte.BorderBrush = $bord
    $fond = New-Object System.Windows.Media.LinearGradientBrush; $fond.StartPoint = '0,0'; $fond.EndPoint = '1,1'
    # (du violet nuit vers une ombre teintée de la couleur du rendez-vous)
    $teinte = Get-Couleur $couleur
    $fond.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0xF4, 0x1B, 0x14, 0x30)), 0))
    $fond.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0xF4, [byte](0x0C + $teinte.R / 14), [byte](0x0A + $teinte.G / 14), [byte](0x16 + $teinte.B / 14))), 1))
    $carte.Background = $fond
    $carte.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = $teinte; BlurRadius = 24; ShadowDepth = 0; Opacity = 0.55 }
    $glisse = New-Object System.Windows.Media.TranslateTransform; $carte.RenderTransform = $glisse

    $tout = New-Object System.Windows.Controls.Grid
    foreach ($h in '*', 'Auto') { $r = New-Object System.Windows.Controls.RowDefinition; $r.Height = [System.Windows.GridLengthConverter]::new().ConvertFromString($h); $tout.RowDefinitions.Add($r) }

    $g = New-Object System.Windows.Controls.Grid; $g.Margin = '16,15,12,14'
    foreach ($c in 'Auto', '*', 'Auto') { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = [System.Windows.GridLengthConverter]::new().ConvertFromString($c); $g.ColumnDefinitions.Add($cd) }

    # L'icône dans un rond lumineux
    $rond = New-Object System.Windows.Controls.Border
    $rond.Width = 50; $rond.Height = 50; $rond.CornerRadius = 25; $rond.VerticalAlignment = 'Top'; $rond.BorderThickness = 2
    $rond.Background = Get-Teinte $couleur 0x30; $rond.BorderBrush = Get-Brush $couleur
    $rond.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = $teinte; BlurRadius = 16; ShadowDepth = 0; Opacity = 0.7 }
    # L'icône dessinée de la sorte (sinon un signe)
    if ($Type -and $Types[$Type]) { $ic = New-Icone $Type 24 $couleur }
    else {
        $ic = New-Object System.Windows.Controls.TextBlock
        $ic.Text = $Icone; $ic.FontSize = 23; $ic.Foreground = Get-Brush $couleur
        $ic.HorizontalAlignment = 'Center'; $ic.VerticalAlignment = 'Center'
    }
    $rond.Child = $ic
    [void]$g.Children.Add($rond)

    # Les mots
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '14,0,6,0'
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $et = New-Object System.Windows.Controls.TextBlock
    $et.Text = $Etiquette.ToUpper(); $et.FontSize = 11; $et.FontWeight = 'Bold'; $et.Foreground = Get-Brush $couleur
    [void]$sp.Children.Add($et)
    $ti = New-Object System.Windows.Controls.TextBlock
    $ti.Text = $Titre; $ti.FontSize = 17; $ti.FontWeight = 'SemiBold'; $ti.Foreground = Get-Brush '#FFFFFF'; $ti.TextWrapping = 'Wrap'; $ti.Margin = '0,2,0,0'
    [void]$sp.Children.Add($ti)
    if ($Texte) {
        $tx = New-Object System.Windows.Controls.TextBlock
        $tx.Text = $Texte; $tx.FontSize = 13.5; $tx.Foreground = Get-Brush '#C9C3DD'; $tx.TextWrapping = 'Wrap'; $tx.Margin = '0,3,0,0'
        [void]$sp.Children.Add($tx)
    }
    # Boutons : « Voir » (et « Dans 10 min » pour un rappel)
    $bs = New-Object System.Windows.Controls.StackPanel; $bs.Orientation = 'Horizontal'; $bs.Margin = '0,11,0,0'
    $voir = New-AlerteBouton 'Voir' $true $couleur
    [void]$bs.Children.Add($voir)
    if ($Plus) { $plusTard = New-AlerteBouton 'Dans 10 min' $false $couleur; $plusTard.Margin = '8,0,0,0'; [void]$bs.Children.Add($plusTard) }
    [void]$sp.Children.Add($bs)
    [void]$g.Children.Add($sp)

    # La croix
    $x = New-Object System.Windows.Controls.Border
    $x.Width = 26; $x.Height = 26; $x.CornerRadius = 13; $x.VerticalAlignment = 'Top'; $x.Background = Get-Brush '#14FFFFFF'; $x.ToolTip = 'Fermer'
    $xt = New-Object System.Windows.Controls.TextBlock; $xt.Text = '✕'; $xt.FontSize = 11; $xt.Foreground = Get-Brush '#C9C3DD'; $xt.HorizontalAlignment = 'Center'; $xt.VerticalAlignment = 'Center'
    $x.Child = $xt
    $x.Add_MouseEnter({ param($s) $s.Background = Get-Brush '#30FFFFFF' }); $x.Add_MouseLeave({ param($s) $s.Background = Get-Brush '#14FFFFFF' })
    [System.Windows.Controls.Grid]::SetColumn($x, 2)
    [void]$g.Children.Add($x)
    [void]$tout.Children.Add($g)

    # Le temps qui reste avant qu'elle parte : un fin trait lumineux qui raccourcit (aucun pour un rappel, qui reste)
    $barre = New-Object System.Windows.Controls.Border
    if ($Secondes -le 0) { $barre.Visibility = 'Collapsed' }
    $barre.Height = 3; $barre.Margin = '18,0,18,9'; $barre.CornerRadius = 2; $barre.HorizontalAlignment = 'Stretch'
    $barre.Background = $bord.Clone()
    $echelle = New-Object System.Windows.Media.ScaleTransform 1, 1; $barre.RenderTransform = $echelle
    [System.Windows.Controls.Grid]::SetRow($barre, 1)
    [void]$tout.Children.Add($barre)
    $carte.Child = $tout
    $w.Content = $carte

    $a = [pscustomobject]@{ Fenetre = $w; Carte = $carte; Glisse = $glisse; Echelle = $echelle; Reste = [double]$Secondes; Total = [double]$Secondes; Survol = $false; RV = $RV; Quand = $Quand
                            Titre = $Titre; Texte = $Texte; Etiquette = $Etiquette; Type = $Type; Icone = $Icone; Plus = $Plus; Partie = $false; Minuteur = $null }
    $w.Tag = $a; $carte.Tag = $a; $x.Tag = $a; $voir.Tag = $a; if ($Plus) { $plusTard.Tag = $a }

    $carte.Add_MouseEnter({ param($s) $s.Tag.Survol = $true })
    $carte.Add_MouseLeave({ param($s) $s.Tag.Survol = $false })
    $carte.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Open-Alerte $s.Tag })
    $x.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Close-Alerte $s.Tag })
    $voir.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Open-Alerte $s.Tag })
    if ($Plus) {
        $plusTard.Add_MouseLeftButtonUp({
            param($s, $e) $e.Handled = $true
            $al = $s.Tag; Close-Alerte $al
            Add-ReportRappel $al.RV $al.Quand (Get-Date).AddMinutes(10)
            Write-Log "Rappel remis à dans 10 min : $($al.Titre)"
        })
    }

    [void]$script:Alertes.Add($a)
    $w.Add_ContentRendered({
        param($s)
        $al = $s.Tag
        Update-PlaceAlertes
        # Arrivée : elle glisse depuis la droite en apparaissant
        $ease = New-Object System.Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation 70, 0, ([TimeSpan]::FromMilliseconds(320)); $an.EasingFunction = $ease
        $al.Glisse.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $an)
        $al.Carte.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([TimeSpan]::FromMilliseconds(260))))
        if ($EnTest -and $env:EVERMIND_CAPTURE_ALERTE) { Save-CaptureAlerte $al; return }
        if ($al.Total -le 0) { return }   # (un rappel : il reste jusqu'à un clic)
        # Le temps passe (sauf sous la souris)
        $al.Minuteur = New-Object System.Windows.Threading.DispatcherTimer
        $al.Minuteur.Interval = [TimeSpan]::FromMilliseconds(50); $al.Minuteur.Tag = $al
        $al.Minuteur.Add_Tick({
            param($s2) $b = $s2.Tag
            if ($b.Survol) { return }
            $b.Reste -= 0.05
            $b.Echelle.ScaleX = [math]::Max(0.0, $b.Reste / $b.Total)
            if ($b.Reste -le 0) { Close-Alerte $b }
        })
        $al.Minuteur.Start()
    })
    $w.Show()
}

# Bouton de l'alerte : plein (dégradé) ou discret
function New-AlerteBouton([string]$Texte, [bool]$Plein, [string]$Couleur) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = 14; $b.Padding = '14,5'; $b.Cursor = 'Hand'
    $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $Texte; $t.FontSize = 13; $t.FontWeight = 'SemiBold'
    if ($Plein) {
        $g = New-Object System.Windows.Media.LinearGradientBrush; $g.StartPoint = '0,0'; $g.EndPoint = '1,0'
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur $Couleur)), 0))
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur $Colors.accent2)), 1))
        $b.Background = $g; $t.Foreground = Get-Brush '#08060F'
    } else {
        $b.Background = Get-Brush '#18FFFFFF'; $b.BorderBrush = Get-Brush '#30FFFFFF'; $b.BorderThickness = 1; $t.Foreground = Get-Brush '#F2EFFA'
        $b.Add_MouseEnter({ param($s) $s.Background = Get-Brush '#2CFFFFFF' }); $b.Add_MouseLeave({ param($s) $s.Background = Get-Brush '#18FFFFFF' })
    }
    $b.Child = $t
    $b
}

# Les alertes s'empilent en bas à droite, la plus récente en bas
function Update-PlaceAlertes {
    $zone = [System.Windows.SystemParameters]::WorkArea
    $bas = $zone.Bottom - 4
    for ($i = $script:Alertes.Count - 1; $i -ge 0; $i--) {
        $al = $script:Alertes[$i]
        $h = $al.Fenetre.ActualHeight
        if (-not $h) { continue }
        if ($EnTest) { $al.Fenetre.Left = -10000; $al.Fenetre.Top = 0; continue }
        $al.Fenetre.Left = $zone.Right - $al.Fenetre.ActualWidth - 4
        $al.Fenetre.Top = $bas - $h
        $bas -= $h - 8
    }
}

function Close-Alerte($al) {
    if ($al.Partie) { return }
    $al.Partie = $true
    if ($al.Minuteur) { $al.Minuteur.Stop() }
    # Départ : elle glisse vers la droite en s'effaçant
    $an = New-Object System.Windows.Media.Animation.DoubleAnimation 1, 0, ([TimeSpan]::FromMilliseconds(220))
    $an.Add_Completed({
        foreach ($b in @($script:Alertes | Where-Object { $_.Partie })) { try { $b.Fenetre.Close() } catch {}; [void]$script:Alertes.Remove($b) }
        Update-PlaceAlertes
    })
    $al.Glisse.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation 0, 60, ([TimeSpan]::FromMilliseconds(220))))
    $al.Carte.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $an)
}

# Un clic : Evermind s'ouvre, sur le rendez-vous s'il y en a un
function Open-Alerte($al) {
    Close-Alerte $al
    Show-MainWindow
    if ($al.RV) {
        $rv = Get-RendezVous $al.RV.Id
        if ($rv) { Show-Fiche $rv $(if ($al.Quand) { [datetime]$al.Quand } else { $rv.Quand }) }
    }
}

# Tests : l'alerte est enregistrée en image, à côté de la capture de la fenêtre
function Save-CaptureAlerte($al) {
    $script:AlerteEnCapture = $true
    $t = New-Object System.Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds(600); $t.Tag = $al
    $t.Add_Tick({
        param($s) $s.Stop(); $b = $s.Tag
        try {
            $el = $b.Fenetre.Content
            $wd = [int]$b.Fenetre.ActualWidth; $ht = [int]$b.Fenetre.ActualHeight
            $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($wd, $ht, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
            # Un fond sombre comme un bureau, pour voir le halo
            $dv = New-Object System.Windows.Media.DrawingVisual
            $dc = $dv.RenderOpen(); $dc.DrawRectangle((Get-Brush '#FF101018'), $null, (New-Object System.Windows.Rect 0, 0, $wd, $ht)); $dc.Close()
            $bmp.Render($dv); $bmp.Render($el)
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
            $fs = [IO.File]::Create($env:EVERMIND_CAPTURE_ALERTE)
            try { $enc.Save($fs) } finally { $fs.Dispose() }
        } catch { Write-Log "Capture de l'alerte : $_"; [Console]::Error.WriteLine("Capture de l'alerte : $_") }
        $script:AlerteEnCapture = $false
    })
    $t.Start()
}

# ---------------------------------------------------------------------------
# Les rappels : « la veille à 20 h », « le matin même à 8 h », « 1 h avant »...
# ---------------------------------------------------------------------------
function Get-MomentRappel([string]$Code, [datetime]$Quand) {
    switch -Regex ($Code) {
        '^veille$' { return $Quand.Date.AddDays(-1).AddHours(20) }
        '^matin$'  { return $Quand.Date.AddHours(8) }
        '^m(\d+)$' { return $Quand.AddMinutes(-[int]$Matches[1]) }
    }
    $null
}

# « dans 1 h », « dans 25 min », « demain », « c'est l'heure »
function Get-TexteDans([datetime]$Quand, [datetime]$Maintenant, [bool]$Journee) {
    $jours = [int]($Quand.Date - $Maintenant.Date).TotalDays
    if ($Journee) { return $(switch ($jours) { 0 { "aujourd'hui" } 1 { 'demain' } default { "dans $jours jours" } }) }
    $min = ($Quand - $Maintenant).TotalMinutes
    if ($min -le 1) { return "c'est l'heure" }
    if ($min -lt 59.5) { return "dans $([math]::Round($min)) min" }
    if ($jours -eq 0 -and $min -lt 360) {
        $h = [math]::Floor(($min + 2) / 60); $m = [math]::Round($min - $h * 60)
        return "dans $h h$(if ($m -ge 5) { ' ' + ([int]$m).ToString('00') })"
    }
    switch ($jours) { 0 { "aujourd'hui" } 1 { 'demain' } default { "dans $jours jours" } }
}

# Ce qui est déjà donné, retenu sur disque (pas de doublon après une relance) : les rappels faits, les « Dans 10 min »
# en attente, et le dernier passage (pour rattraper ce qui tombe pendant la veille du PC ou quand il est éteint).
$RappelsFile = Join-Path $DataDir 'rappels.json'
$script:RappelsFaits = @{}; $script:ReportsRappels = New-Object System.Collections.ArrayList; $script:DernierPassage = $null
$script:RappelsEnregistres = [datetime]::MinValue
$jr = Read-JsonFile $RappelsFile
if ($jr) {
    foreach ($c in @($jr.Faits)) { if ($c) { $script:RappelsFaits[[string]$c] = $true } }
    foreach ($r in @($jr.Reports)) { try { if ($r) { [void]$script:ReportsRappels.Add([pscustomobject]@{ Id = [string]$r.Id; Quand = [datetime]::Parse($r.Quand); Revient = [datetime]::Parse($r.Revient) }) } } catch {} }
    try { if ($jr.DernierPassage) { $script:DernierPassage = [datetime]::Parse($jr.DernierPassage) } } catch {}
}

function Save-Rappels([datetime]$Maintenant = (Get-Date)) {
    # (on oublie ce qui a plus de 3 jours)
    foreach ($c in @($script:RappelsFaits.Keys)) {
        $q = [datetime]::MinValue
        if (-not [datetime]::TryParse(($c -split '\|')[1], [ref]$q) -or $q -lt $Maintenant.AddDays(-3)) { $script:RappelsFaits.Remove($c) }
    }
    $script:RappelsEnregistres = $Maintenant
    $d = [ordered]@{ DernierPassage = $(if ($script:DernierPassage) { $script:DernierPassage.ToString('s') }); Faits = @($script:RappelsFaits.Keys)
                     Reports = @(foreach ($r in $script:ReportsRappels) { [ordered]@{ Id = $r.Id; Quand = $r.Quand.ToString('s'); Revient = $r.Revient.ToString('s') } }) }
    try { Save-JsonFile $RappelsFile $d } catch { Write-Log "Rappels non enregistrés : $_" }
}

# « Dans 10 min » : le rappel revient plus tard (le planificateur le redonne, même après une relance)
function Add-ReportRappel($RV, $Quand, [datetime]$Revient) {
    if (-not $RV) { return }
    $q = if ($Quand) { [datetime]$Quand } else { $RV.Quand }
    [void]$script:ReportsRappels.Add([pscustomobject]@{ Id = [string]$RV.Id; Quand = $q; Revient = $Revient })
    Save-Rappels
}

# Un rappel donné en retard a-t-il encore un sens ? Oui si le rendez-vous est encore à venir (ou commence à peine),
# ou si c'est une chose à faire pas encore cochée.
function Test-RappelUtile($rv, [datetime]$Quand, [datetime]$Maintenant) {
    if ($rv.Fait) { return $false }
    if ((Get-TypeRV $rv) -eq 'rappel') { return $true }
    if ($rv.Journee) { return $Quand.Date -ge $Maintenant.Date }
    $Quand -ge $Maintenant.AddMinutes(-2)
}

# Les rappels à donner maintenant, chacun une seule fois. Ceux tombés pendant que le PC dormait ou était éteint
# (depuis le dernier passage, 2 jours au plus) sont rattrapés s'ils ont encore un sens. Plusieurs rappels du même
# rendez-vous en même temps : un seul. Les rappels sont dits à voix haute, en une seule fois.
function Invoke-RappelsDus([datetime]$Maintenant = (Get-Date)) {
    $bas = $Maintenant.AddMinutes(-2)
    if ($script:DernierPassage -and $script:DernierPassage -lt $bas) { $bas = $script:DernierPassage }
    if ($bas -lt $Maintenant.AddDays(-2)) { $bas = $Maintenant.AddDays(-2) }
    $change = $false
    $parRV = [ordered]@{}
    foreach ($it in @(Get-AgendaEntre $bas.Date $Maintenant.AddDays(8))) {
        $rv = $it.RV
        if ($rv.Fait) { continue }
        # Sur plusieurs jours : rappels pour le premier jour seulement
        if (-not $rv.Repetition -and (Test-PlusieursJours $rv) -and $it.Prochain.Date -ne $rv.Quand.Date) { continue }
        $utile = Test-RappelUtile $rv $it.Prochain $Maintenant
        $dus = @(foreach ($code in @(Get-RappelsRV $rv)) {
            $m = Get-MomentRappel $code $it.Prochain
            if ($null -eq $m -or $m -gt $Maintenant -or $m -lt $bas) { continue }
            if ($m -lt $Maintenant.AddMinutes(-2) -and -not $utile) { continue }   # (en retard, et plus de sens)
            if (-not $rv.Journee -and $m -gt $it.Prochain) { continue }   # (« le matin même » d'un rendez-vous à 7 h)
            $cle = "$($rv.Id)|$($it.Prochain.ToString('s'))|$code"
            if ($script:RappelsFaits.ContainsKey($cle)) { continue }
            $script:RappelsFaits[$cle] = $true; $change = $true
            [pscustomobject]@{ Code = $code; Moment = $m }
        })
        if (-not $dus.Count) { continue }
        # (une chose à faire qui revient, manquée plusieurs fois : seulement la dernière fois)
        $parRV[[string]$rv.Id] = [pscustomobject]@{ RV = $rv; Quand = $it.Prochain; Code = ($dus | Sort-Object Moment -Descending | Select-Object -First 1).Code }
    }
    $faits = @($parRV.Values)
    # Les « Dans 10 min » arrivés à leur heure
    foreach ($r in @($script:ReportsRappels)) {
        if ($r.Revient -gt $Maintenant) { continue }
        $script:ReportsRappels.Remove($r); $change = $true
        $rv = Get-RendezVous $r.Id
        if (-not $rv -or $rv.Fait -or $parRV.Contains([string]$r.Id)) { continue }
        if ($r.Revient -lt $Maintenant.AddMinutes(-2) -and -not (Test-RappelUtile $rv $r.Quand $Maintenant)) { continue }
        $faits += [pscustomobject]@{ RV = $rv; Quand = $r.Quand; Code = 'report' }
    }
    $paroles = @(foreach ($f in $faits) { Show-AlerteRappel $f.RV $f.Quand $Maintenant })
    # (pendant un jeu : la carte seulement, pas de voix par-dessus le jeu)
    if ($paroles.Count -and -not $script:ModeJeu) { try { Invoke-Parole ($paroles -join ' ') } catch { Write-Log "Rappel non dit : $_" } }
    # Le dernier passage, retenu sur disque dès qu'un rappel est donné, et sinon toutes les 5 minutes
    $script:DernierPassage = $Maintenant
    if ($change -or [math]::Abs(($Maintenant - $script:RappelsEnregistres).TotalMinutes) -ge 5) { Save-Rappels $Maintenant }
    $faits
}

# Court : le nom et l'heure, c'est tout (le reste est dans la fiche, « Voir »)
#   « 15 h » aujourd'hui, « Mercredi 14 octobre, 15 h » un autre jour, « Toute la journée »
function Get-HeureAlerte($rv, [datetime]$Quand, [datetime]$Maintenant) {
    $jour = if ($Quand.Date -eq $Maintenant.Date) { '' } else { Get-Majuscule $Quand.ToString('dddd d MMMM', $Fr) }
    if ($rv.Journee) { return $(if ($jour) { $jour } else { 'Toute la journée' }) }
    $h = Format-Heure $Quand
    if ($jour) { "$jour, $h" } else { $h }
}

# Un rappel reste affiché jusqu'à un clic (0 seconde : il ne part pas tout seul). Rend la phrase à dire.
function Show-AlerteRappel($rv, [datetime]$Quand, [datetime]$Maintenant) {
    $nom = Get-TitreAffiche $rv.Titre
    # Déjà passé (une chose à faire manquée pendant que le PC dormait) : « Rappel manqué »
    $passe = if ($rv.Journee) { $Quand.Date -lt $Maintenant.Date } else { $Quand -lt $Maintenant.AddMinutes(-2) }
    if ($passe) {
        $heure = Get-HeureAlerte $rv $Quand $Maintenant
        Write-Log "Rappel manqué : $nom ($heure)"
        Show-Alerte $nom $heure 'Rappel manqué' (Get-TypeRV $rv) $rv $Quand 0 -Plus
        $moment = if ($Quand.Date -eq $Maintenant.Date) { 'à ' + (Format-Heure $Quand) } elseif ($Quand.Date -eq $Maintenant.Date.AddDays(-1)) { 'hier' } else { $Quand.ToString('dddd d MMMM', $Fr) }
        return "Rappel manqué : $nom, c'était $moment."
    }
    $dans = Get-TexteDans $Quand $Maintenant ([bool]$rv.Journee)
    Write-Log "Rappel : $nom ($dans)"
    Show-Alerte $nom (Get-HeureAlerte $rv $Quand $Maintenant) "Rappel  ·  $dans" (Get-TypeRV $rv) $rv $Quand 0 -Plus
    "Rappel : $nom, $dans."
}

function Start-PlanificateurRappels {
    if ($script:PlanifRappels) { return }
    $script:PlanifRappels = New-Object System.Windows.Threading.DispatcherTimer
    $script:PlanifRappels.Interval = [TimeSpan]::FromSeconds(20)
    $script:PlanifRappels.Add_Tick({ try { [void](Invoke-RappelsDus) } catch { Write-Log "Rappels : $_" } })
    $script:PlanifRappels.Start()
}
