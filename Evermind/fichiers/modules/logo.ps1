# Evermind : le logo animé de l'en-tête, en boucle, comme l'écran de chargement de Nevermind.
# Le E blanc avec ses échos cyan et magenta « glitche » par moments, un anneau cyan vers violet tourne,
# une petite comète magenta tourne en sens inverse, un halo respire et une ligne de balayage descend.
# Les sauts s'arrêtent quand la fenêtre est cachée (Evermind près de l'horloge ne travaille pas pour rien).
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

$EveCyan = '#00E5FF'
$EveMagenta = '#FF2EB5'

function Get-ArcGeometry([double]$C, [double]$R, [double]$Start, [double]$Sweep) {
    if ($Sweep -le 0.05) { return $null }
    $a1 = $Start * [math]::PI / 180
    $a2 = ($Start + $Sweep) * [math]::PI / 180
    $p1 = [System.Windows.Point]::new($C + $R * [math]::Cos($a1), $C + $R * [math]::Sin($a1))
    $p2 = [System.Windows.Point]::new($C + $R * [math]::Cos($a2), $C + $R * [math]::Sin($a2))
    $seg = [System.Windows.Media.ArcSegment]::new($p2, [System.Windows.Size]::new($R, $R), 0.0, ($Sweep -gt 180), [System.Windows.Media.SweepDirection]::Clockwise, $true)
    $fig = New-Object System.Windows.Media.PathFigure
    $fig.StartPoint = $p1
    [void]$fig.Segments.Add($seg)
    $geo = New-Object System.Windows.Media.PathGeometry
    [void]$geo.Figures.Add($fig)
    $geo
}

function New-Glow([string]$Hex, [double]$Blur = 16, [double]$Opacity = 0.55) {
    $fx = New-Object System.Windows.Media.Effects.DropShadowEffect
    $fx.Color = (Get-Couleur $Hex)
    $fx.BlurRadius = $Blur; $fx.ShadowDepth = 0; $fx.Opacity = $Opacity
    $fx
}

function New-LinearBrush([string[]]$Hex, [double]$X1 = 0, [double]$Y1 = 0, [double]$X2 = 1, [double]$Y2 = 0) {
    $b = New-Object System.Windows.Media.LinearGradientBrush
    $b.StartPoint = [System.Windows.Point]::new($X1, $Y1); $b.EndPoint = [System.Windows.Point]::new($X2, $Y2)
    for ($i = 0; $i -lt $Hex.Count; $i++) {
        [void]$b.GradientStops.Add([System.Windows.Media.GradientStop]::new((Get-Couleur $Hex[$i]), $i / [math]::Max(1, $Hex.Count - 1)))
    }
    $b
}

function New-LogoArc([double]$C, [double]$R, [double]$Start, [double]$Sweep, $Stroke, [double]$Thick) {
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = Get-ArcGeometry $C $R $Start $Sweep
    $p.Stroke = $Stroke; $p.StrokeThickness = $Thick
    $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'
    $p
}

# Animation qui ne s'arrête jamais
function Start-LogoLoop($Target, $Property, [double]$From, [double]$To, [int]$Ms, [bool]$Reverse) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.From = $From; $a.To = $To; $a.AutoReverse = $Reverse
    $a.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($Ms))
    $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    if ($Reverse) { $e = New-Object System.Windows.Media.Animation.SineEase; $e.EasingMode = 'EaseInOut'; $a.EasingFunction = $e }
    # 30 images par seconde suffisent pour un logo qui tourne doucement : deux fois moins de calcul qu'en 60
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($a, 30)
    Add-AnimationBoucle $Target $Property $a
}

# ---------------------------------------------------------------------------
# Les animations décoratives (logo, mascotte, pied de page...) ne tournent que quand Evermind est au premier plan :
# derrière un jeu, réduit ou rangé près de l'horloge, plus rien n'est redessiné. Elles reprennent au retour.
# ---------------------------------------------------------------------------
if (-not $script:AnimsBoucle) {
    $script:AnimsBoucle = New-Object System.Collections.ArrayList
    $script:AnimsPause = -not $EnTest   # (en pause jusqu'à ce que la fenêtre passe au premier plan ; lancé avec Windows, elle reste cachée)
}
function Add-AnimationBoucle($Cible, $Propriete, $Anim) {
    [void]$script:AnimsBoucle.Add(@{ Cible = $Cible; Prop = $Propriete; Anim = $Anim })
    if (-not $script:AnimsPause) { $Cible.BeginAnimation($Propriete, $Anim) }
}
function Set-AnimationsPause([bool]$Pause) {
    if ([bool]$script:AnimsPause -eq $Pause) { return }
    $script:AnimsPause = $Pause
    foreach ($a in $script:AnimsBoucle) { try { $a.Cible.BeginAnimation($a.Prop, $(if ($Pause) { $null } else { $a.Anim })) } catch {} }
    foreach ($t in @($script:PackTimers)) { try { if ($Pause) { $t.Stop() } else { $t.Start() } } catch {} }
}

# ---------------------------------------------------------------------------
# Le E : un trait épais aux bouts arrondis (le contour et la barre du milieu), comme le N de Nevermind
# ---------------------------------------------------------------------------
function Get-EveE([double]$Size) {
    $x = $Size * 0.27; $y = $Size * 0.2; $w = $Size * 0.46; $h = $Size * 0.6
    $p = [System.Windows.Media.Geometry]::Parse("M $($x + $w),$y L $x,$y L $x,$($y + $h) L $($x + $w),$($y + $h) M $x,$($y + $h / 2) L $($x + $w * 0.82),$($y + $h / 2)")
    $pen = New-Object System.Windows.Media.Pen ([System.Windows.Media.Brushes]::Black), ($Size * 0.17)
    $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
    $wide = $p.GetWidenedPathGeometry($pen)
    $g = [System.Windows.Media.Geometry]::Combine($wide, $wide, 'Union', $null)
    $g.Freeze()
    $g
}

function New-LogoGeoPath($Geo, [string]$Hex) {
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = $Geo; $p.Fill = Get-Brush $Hex
    $p.RenderTransform = New-Object System.Windows.Media.TranslateTransform 0, 0
    $p
}

# Le E animable : { Root, Cyan, Mag, Base, Pieces (tranches), Size, Rest (décalages au repos) }
function New-EveMark([double]$Size) {
    $n = Get-EveE $Size
    $root = New-Object System.Windows.Controls.Grid
    $root.Width = $Size; $root.Height = $Size
    $cyan = New-LogoGeoPath $n $EveCyan; $cyan.Opacity = 0.92
    $mag = New-LogoGeoPath $n $EveMagenta; $mag.Opacity = 0.92
    # Le E blanc privé de ses deux tranches, et les tranches à part pour pouvoir les décaler
    $bands = @(@(0.36, 0.07), @(0.63, 0.05))
    $bandGeo = New-Object System.Windows.Media.GeometryGroup
    foreach ($b in $bands) { $bandGeo.Children.Add((New-Object System.Windows.Media.RectangleGeometry ([System.Windows.Rect]::new(-$Size, $Size * $b[0], 3 * $Size, $Size * $b[1])))) }
    $base = New-LogoGeoPath ([System.Windows.Media.Geometry]::Combine($n, $bandGeo, 'Exclude', $null)) '#FFFFFF'
    $pieces = foreach ($b in $bands) {
        $r = New-Object System.Windows.Media.RectangleGeometry ([System.Windows.Rect]::new(-$Size, $Size * $b[0], 3 * $Size, $Size * $b[1]))
        New-LogoGeoPath ([System.Windows.Media.Geometry]::Combine($n, $r, 'Intersect', $null)) '#FFFFFF'
    }
    foreach ($e in @($cyan, $mag, $base) + @($pieces)) { [void]$root.Children.Add($e) }
    $m = @{ Root = $root; Cyan = $cyan; Mag = $mag; Base = $base; Pieces = @($pieces); Size = $Size; Rest = @(-0.035, 0.035, 0.05, -0.04) }
    Set-EvePose $m $m.Rest
    $m
}

function Set-EvePose($M, [double[]]$Pose) {
    $s = $M.Size
    $M.Cyan.RenderTransform.X = $Pose[0] * $s
    $M.Mag.RenderTransform.X = $Pose[1] * $s
    $M.Pieces[0].RenderTransform.X = $Pose[2] * $s
    $M.Pieces[1].RenderTransform.X = $Pose[3] * $s
}

# Un « saut » de quelques centaines de millisecondes : décalages au hasard, puis retour au repos
function Start-EveGlitch($Mark, [int]$Ms = 300) {
    if (-not $Mark -or $Mark.Busy) { return }
    $Mark.Busy = $true
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(45)
    $t.Tag = @{ Mark = $Mark; Until = [DateTime]::Now.AddMilliseconds($Ms); Rnd = (New-Object Random) }
    $t.Add_Tick({
        param($s, $e)
        $x = $s.Tag; $r = $x.Rnd
        if ([DateTime]::Now -gt $x.Until) {
            $s.Stop()
            Set-EvePose $x.Mark $x.Mark.Rest
            $x.Mark.Base.RenderTransform.X = 0
            $x.Mark.Busy = $false
            return
        }
        $j = { param($a) ($r.NextDouble() * 2 - 1) * $a }
        Set-EvePose $x.Mark @((& $j 0.09), (& $j 0.09), (& $j 0.14), (& $j 0.14))
        $x.Mark.Base.RenderTransform.X = (& $j 0.03) * $x.Mark.Size
    })
    $t.Start()
}

# ---------------------------------------------------------------------------
# Le logo complet, dans un carré de côté $S : halo, anneaux, comète, E et balayage, tout en boucle
# ---------------------------------------------------------------------------
function Start-LogoAnime($Hote, [double]$S = 84) {
    if (-not $Hote) { return }
    $Hote.Children.Clear()
    $k = $S / 260.0          # mêmes proportions que l'écran de chargement de Nevermind (260 px)
    $C = $S / 2
    $cv = New-Object System.Windows.Controls.Canvas
    $cv.Width = $S; $cv.Height = $S

    # Halo qui respire derrière le logo
    $halo = New-Object System.Windows.Shapes.Ellipse
    $halo.Width = 220 * $k; $halo.Height = 220 * $k
    $rb = New-Object System.Windows.Media.RadialGradientBrush
    [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new((Get-Couleur '#5500E5FF'), 0))
    [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new((Get-Couleur '#22FF2EB5'), 0.6))
    [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new((Get-Couleur '#00FF2EB5'), 1))
    $halo.Fill = $rb
    $halo.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
    $hs = New-Object System.Windows.Media.ScaleTransform 1, 1
    $halo.RenderTransform = $hs
    [System.Windows.Controls.Canvas]::SetLeft($halo, 20 * $k); [System.Windows.Controls.Canvas]::SetTop($halo, 20 * $k)
    [void]$cv.Children.Add($halo)
    Start-LogoLoop $hs ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 0.85 1.1 1600 $true
    Start-LogoLoop $hs ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 0.85 1.1 1600 $true

    # Anneau de fond, et l'anneau cyan vers violet qui tourne (sur Nevermind, il se remplit avec le chargement)
    $epais = [math]::Max(2.0, 6 * $k)
    [void]$cv.Children.Add((New-LogoArc $C (112 * $k) -90 359.9 (Get-Brush '#16FFFFFF') $epais))
    $tour = New-Object System.Windows.Controls.Canvas
    $tour.Width = $S; $tour.Height = $S
    $rot = New-Object System.Windows.Media.RotateTransform 0, $C, $C
    $tour.RenderTransform = $rot
    $arc = New-LogoArc $C (112 * $k) -90 250 (New-LinearBrush @($EveCyan, '#B04BFF', $EveMagenta) 0 0 1 1) $epais
    $arc.Effect = New-Glow $EveCyan (14 * $k + 4) 0.7
    [void]$tour.Children.Add($arc)
    [void]$cv.Children.Add($tour)
    Start-LogoLoop $rot ([System.Windows.Media.RotateTransform]::AngleProperty) 0 360 3200 $false

    # Petite comète magenta qui tourne en sens inverse, plus loin
    $com = New-Object System.Windows.Controls.Canvas
    $com.Width = $S; $com.Height = $S
    $rot2 = New-Object System.Windows.Media.RotateTransform 0, $C, $C
    $com.RenderTransform = $rot2
    $col = (Get-Couleur $EveMagenta)
    $cb = New-Object System.Windows.Media.LinearGradientBrush
    $cb.StartPoint = [System.Windows.Point]::new(0, 1); $cb.EndPoint = [System.Windows.Point]::new(1, 0)
    [void]$cb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb(0, $col.R, $col.G, $col.B), 0))
    [void]$cb.GradientStops.Add([System.Windows.Media.GradientStop]::new($col, 1))
    [void]$com.Children.Add((New-LogoArc $C (124 * $k) 0 60 $cb ([math]::Max(1.2, 2 * $k))))
    [void]$cv.Children.Add($com)
    Start-LogoLoop $rot2 ([System.Windows.Media.RotateTransform]::AngleProperty) 360 0 2600 $false

    # Thème personnalisé avec son logo : l'image remplace le E (avec son anneau et ses lueurs)
    if ($ThemePack -and $ThemePack.Logo) {
        Add-PackLogo $cv $C (150 * $k)
        [void]$Hote.Children.Add($cv)
        $script:LogoTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:LogoTimer.Interval = [TimeSpan]::FromSeconds(7)
        $script:LogoTimer.Add_Tick({ param($s) $s.Interval = [TimeSpan]::FromSeconds((Get-Random -Minimum 6 -Maximum 13)); if (-not $script:AnimsPause -and $Window.IsVisible -and $Window.WindowState -ne 'Minimized') { Start-PackLogoShake } })
        $script:LogoTimer.Start()
        $Hote.Add_MouseEnter({ Start-PackLogoShake })
        return
    }

    # Le E, au centre
    $mark = New-EveMark (128 * $k)
    [System.Windows.Controls.Canvas]::SetLeft($mark.Root, $C - 64 * $k); [System.Windows.Controls.Canvas]::SetTop($mark.Root, $C - 64 * $k)
    [void]$cv.Children.Add($mark.Root)

    # Ligne de balayage qui descend en boucle (dans le cercle)
    $scanHost = New-Object System.Windows.Controls.Canvas
    $scanHost.Width = $S; $scanHost.Height = $S
    $scanHost.Clip = New-Object System.Windows.Media.EllipseGeometry ([System.Windows.Point]::new($C, $C)), (106 * $k), (106 * $k)
    $scan = New-Object System.Windows.Shapes.Rectangle
    $scan.Width = $S; $scan.Height = [math]::Max(1.5, 3 * $k)
    $scan.Fill = New-LinearBrush @('#0000E5FF', '#9900E5FF', '#0000E5FF') 0 0 1 0
    $st = New-Object System.Windows.Media.TranslateTransform 0, 0
    $scan.RenderTransform = $st
    [void]$scanHost.Children.Add($scan)
    [void]$cv.Children.Add($scanHost)
    Start-LogoLoop $st ([System.Windows.Media.TranslateTransform]::YProperty) (20 * $k) (240 * $k) 2200 $false

    [void]$Hote.Children.Add($cv)
    $script:LogoMarque = $mark

    # Petits sauts réguliers du E, comme pendant le chargement de Nevermind ; un de plus au survol
    $script:LogoTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:LogoTimer.Interval = [TimeSpan]::FromMilliseconds(1300)
    $script:LogoTimer.Add_Tick({ if (-not $script:AnimsPause -and $Window.IsVisible -and $Window.WindowState -ne 'Minimized') { Start-EveGlitch $script:LogoMarque 260 } })
    $script:LogoTimer.Start()
    $Hote.Add_MouseEnter({ Start-EveGlitch $script:LogoMarque 420 })
}

# ---------------------------------------------------------------------------
# Logo d'un thème personnalisé (image du pack) : il se secoue de temps en temps et au survol ;
# une planche animée joue un tour ; avec une lueur (LogoGlow), il lévite en brillant
# ---------------------------------------------------------------------------
function Add-PackLogo($Canvas, [double]$C, [double]$Taille) {
    $img = New-Object System.Windows.Controls.Image
    $img.Width = $Taille; $img.Height = $Taille; $img.Stretch = 'Uniform'
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
    $frames = $null; $timer = $null
    if ($ThemePack.LogoFrames -gt 1) {
        $frames = Get-SheetFrames $ThemePack.Logo $ThemePack.LogoFrames
        $img.Source = $frames[0]
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($ThemePack.LogoDelay)
        $timer.Add_Tick({
            param($s)
            if ($script:AnimsPause -or -not $Window.IsVisible -or $Window.WindowState -eq 'Minimized') { return }
            $m = $script:PackLogo
            $m.Frame++
            if ($m.Frame -ge $m.Frames.Count) { $m.Frame = 0; if (-not $ThemePack.LogoBoucle) { $s.Stop() } }
            $m.Img.Source = $m.Frames[$m.Frame]
        })
    } else {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = New-Object Uri $ThemePack.Logo; $bi.DecodePixelWidth = 256; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
        $img.Source = $bi
    }
    $rot = New-Object System.Windows.Media.RotateTransform 0
    $mv = New-Object System.Windows.Media.TranslateTransform
    $grp = New-Object System.Windows.Media.TransformGroup; $grp.Children.Add($rot); $grp.Children.Add($mv)
    $img.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.85); $img.RenderTransform = $grp
    [System.Windows.Controls.Canvas]::SetLeft($img, $C - $Taille / 2); [System.Windows.Controls.Canvas]::SetTop($img, $C - $Taille / 2)
    [void]$Canvas.Children.Add($img)
    $script:PackLogo = @{ Img = $img; Rot = $rot; Move = $mv; Frames = $frames; Frame = 0; Timer = $timer; Glow = $ThemePack.LogoGlow }
    if ($timer -and $ThemePack.LogoBoucle) { $timer.Start() }   # logo animé du thème (Pikachu...) : il bouge tout le temps
    if ($ThemePack.LogoGlow) { Start-Sautille $img 3 $ThemePack.LogoGlow }   # lévitation lumineuse permanente
}

function Start-PackLogoShake {
    $m = $script:PackLogo
    if (-not $m) { return }
    if ($m.Timer) { if (-not $m.Timer.IsEnabled) { $m.Frame = 0; $m.Timer.Start() }; return }
    if ($m.Glow) { return }
    $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($k in @(@(0, 0), @(110, -22), @(240, 18), @(360, -12), @(470, 6), @(580, 0))) {
        [void]$a.KeyFrames.Add((New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame ([double]$k[1]), ([System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($k[0])))))
    }
    $m.Rot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $a)
}

# ---------------------------------------------------------------------------
# Le logo se déplace : on le glisse où on veut dans la fenêtre (sa place est gardée, en proportion de la fenêtre,
# et reste dedans quand on la redimensionne). Molette : sa taille. Double-clic : retour à sa place et sa taille.
# Il est dessiné en 84 px, puis mis à la taille voulue (60 px par défaut).
# ---------------------------------------------------------------------------
$LogoTailleDefaut = 60
function Get-LogoTaille {
    if ($script:DansMindset) { return $LogoTailleDefaut }   # affiché dans Mindset : à sa place, taille d'origine
    $t = [double](Get-Setting 'LogoTaille' 0)
    if ($t -lt 36 -or $t -gt 140) { $LogoTailleDefaut } else { $t }
}

function Update-LogoPlace {
    $taille = Get-LogoTaille
    $ui.LogoHote.LayoutTransform = New-Object System.Windows.Media.ScaleTransform ($taille / 84.0), ($taille / 84.0)
    $W = $ui.LogoCalque.ActualWidth; $H = $ui.LogoCalque.ActualHeight
    if (-not $W -or -not $H) { return }
    $pos = if ($script:DansMindset) { $null } else { Get-Setting 'LogoPos' $null }   # (dans Mindset : toujours à sa place)
    if ($pos -and $null -ne $pos.X) {
        $ui.LogoPlace.Visibility = 'Collapsed'
        $x = [double]$pos.X * $W; $y = [double]$pos.Y * $H
    } else {
        # À sa place dans l'en-tête, centré sur la place gardée pour lui
        $ui.LogoPlace.Visibility = 'Visible'; $ui.LogoPlace.Width = $taille - 6; $ui.LogoPlace.Height = $taille - 6
        $ui.LogoPlace.UpdateLayout()
        $pt = $ui.LogoPlace.TranslatePoint([System.Windows.Point]::new(0, 0), $ui.LogoCalque)
        $x = $pt.X + $ui.LogoPlace.ActualWidth / 2 - $taille / 2; $y = $pt.Y + $ui.LogoPlace.ActualHeight / 2 - $taille / 2
    }
    [System.Windows.Controls.Canvas]::SetLeft($ui.LogoHote, [math]::Min([math]::Max(0.0, $x), [math]::Max(0.0, $W - $taille)))
    [System.Windows.Controls.Canvas]::SetTop($ui.LogoHote, [math]::Min([math]::Max(0.0, $y), [math]::Max(0.0, $H - $taille)))
}

function Initialize-LogoDeplacable {
    $l = $ui.LogoHote
    $l.Add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        if ($script:DansMindset) { return }   # affiché dans Mindset : le logo ne bouge pas
        if ($e.ClickCount -ge 2) { Set-Setting 'LogoPos' $null; Set-Setting 'LogoTaille' $LogoTailleDefaut; Update-LogoPlace; return }
        $script:LogoDrag = @{ Debut = $e.GetPosition($ui.LogoCalque); X = [System.Windows.Controls.Canvas]::GetLeft($s); Y = [System.Windows.Controls.Canvas]::GetTop($s); Bouge = $false }
        [void]$s.CaptureMouse()
    })
    $l.Add_MouseMove({
        param($s, $e)
        $d = $script:LogoDrag
        if (-not $d -or $e.LeftButton -ne 'Pressed') { return }
        $p = $e.GetPosition($ui.LogoCalque)
        $dx = $p.X - $d.Debut.X; $dy = $p.Y - $d.Debut.Y
        if (-not $d.Bouge -and [math]::Abs($dx) + [math]::Abs($dy) -lt 4) { return }
        $d.Bouge = $true
        $taille = Get-LogoTaille
        [System.Windows.Controls.Canvas]::SetLeft($s, [math]::Min([math]::Max(0.0, $d.X + $dx), [math]::Max(0.0, $ui.LogoCalque.ActualWidth - $taille)))
        [System.Windows.Controls.Canvas]::SetTop($s, [math]::Min([math]::Max(0.0, $d.Y + $dy), [math]::Max(0.0, $ui.LogoCalque.ActualHeight - $taille)))
    })
    $l.Add_MouseLeftButtonUp({
        param($s, $e)
        $d = $script:LogoDrag; $script:LogoDrag = $null
        $s.ReleaseMouseCapture()
        if (-not $d -or -not $d.Bouge) { return }
        # Sa place, en proportion de la fenêtre
        Set-Setting 'LogoPos' ([ordered]@{ X = [math]::Round([System.Windows.Controls.Canvas]::GetLeft($s) / $ui.LogoCalque.ActualWidth, 4); Y = [math]::Round([System.Windows.Controls.Canvas]::GetTop($s) / $ui.LogoCalque.ActualHeight, 4) })
        Update-LogoPlace
    })
    $l.Add_MouseWheel({
        param($s, $e)
        $e.Handled = $true
        if ($script:DansMindset) { return }
        $avant = Get-LogoTaille
        $taille = [math]::Min(140.0, [math]::Max(36.0, $avant + $(if ($e.Delta -gt 0) { 6 } else { -6 })))
        if ($taille -eq $avant) { return }
        # (déplacé : il grandit autour de son centre)
        $pos = Get-Setting 'LogoPos' $null
        if ($pos -and $null -ne $pos.X) {
            $W = $ui.LogoCalque.ActualWidth; $H = $ui.LogoCalque.ActualHeight
            Set-Setting 'LogoPos' ([ordered]@{ X = [math]::Round(([double]$pos.X * $W - ($taille - $avant) / 2) / $W, 4); Y = [math]::Round(([double]$pos.Y * $H - ($taille - $avant) / 2) / $H, 4) })
        }
        Set-Setting 'LogoTaille' $taille
        Update-LogoPlace
    })
    $Window.Add_SizeChanged({ Update-LogoPlace })
    $Window.Add_ContentRendered({ Update-LogoPlace })
    $ui.LogoCalque.Add_Loaded({ Update-LogoPlace })
}
