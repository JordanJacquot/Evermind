# Evermind : thèmes de couleurs (Réglages, onglet Thème), les mêmes que Nevermind.
# Toute l'app est dessinée avec la palette Néon ; un thème « traduit » chaque couleur au chargement :
# les couleurs de la marque (cyan, violet, magenta) prennent celles du thème, les gris et les fonds prennent sa teinte.
# Les couleurs d'état (vert = bien, orange, rouge, bleu) ne changent jamais.
# Chargé par Evermind.ps1 juste après donnees.ps1, avant la lecture de la fenêtre (interface.ps1).

$AppThemes = [ordered]@{
    neon = @{ Name = 'Néon'; Desc = 'Le thème d''Evermind : cyan, violet et magenta sur fond de nuit.'
        P = '#00E5FF'; S = '#B04BFF'; T = '#FF2EB5'; Map = @{}; NH = $null; NS = 1.0
        Hello = '{0} ! Je me souviens de tout pour toi.'; Font = $null; Decor = $null }
    crepuscule = @{ Name = 'Crépuscule'; Desc = 'Le style Néon recoloré : orange, rose et or, comme un coucher de soleil.'
        P = '#FF8A3D'; S = '#FF3D7F'; T = '#FFC83D'; NH = 345; NS = 0.75
        Map = @{ '0C0920' = '1A0B12'; '06050F' = '0B0508'; '0B0820' = '170910'; '08060F' = '160806' }
        Hello = '{0} ! Je me souviens de tout pour toi.'; Font = $null; Decor = $null }
    terminal = @{ Name = 'Terminal'; Desc = 'Pour les geeks : vert phosphore sur fond noir, tout en police de code.'
        P = '#33FF77'; S = '#B6FF3B'; T = '#00E0A0'; NH = 140; NS = 0.55
        Map = @{ '0C0920' = '030B06'; '06050F' = '000302'; '0B0820' = '020A05'; '08060F' = '001A08' }
        Hello = '> {0}. je me souviens de tout._'; Font = 'Cascadia Code, Consolas'; Decor = 'terminal' }
    arcade = @{ Name = 'Arcade'; Desc = 'Jaune, rouge et bleu vifs sur fond bleu nuit, comme une vieille borne.'
        P = '#FBD000'; S = '#E52521'; T = '#1E88E5'; NH = 228; NS = 0.9
        Map = @{ '0C0920' = '0B1640'; '06050F' = '050A20'; '0B0820' = '0A1338'; '08060F' = '1A1000' }
        Hello = '{0} ! Je me souviens de tout pour toi.'; Font = $null; Decor = $null }
    rubis = @{ Name = 'Rubis'; Desc = 'Rouge vif, jaune et bleu sur un gris anthracite sobre.'
        P = '#FF3B3B'; S = '#FFDE00'; T = '#3B6FFF'; NH = 0; NS = 0.15
        Map = @{ '0C0920' = '17171D'; '06050F' = '0A0A0D'; '0B0820' = '141419'; '08060F' = '1A0606' }
        Hello = '{0} ! Je me souviens de tout pour toi.'; Font = $null; Decor = $null }
}

# ---------------------------------------------------------------------------
# Thèmes personnalisés (packs) : un dossier (ou un zip à importer) hors de l'app, avec pack.json et ses images.
# Ils restent sur le PC (dossier des données d'Evermind, « packs ») et ne passent jamais par GitHub :
# on peut y mettre ses propres images, même de personnages qui ne nous appartiennent pas, pour un usage privé.
#
# pack.json (le même principe que les packs de Nevermind) :
#   Name, Desc        nom et description affichés dans Réglages, Thème
#   Base              thème de couleurs utilisé (neon, crepuscule, terminal, arcade, rubis)
#   Colors            ou des couleurs propres au pack : { P, S, T, NH, NS, Map }
#   Hello             bonjour de l'en-tête (« {0} » = Bonjour ou Bonsoir)
#   Logo              image à la place du E (PNG transparent, carré) ; LogoFrames, LogoDelay : planche animée ;
#                     LogoGlow : couleur d'une lueur, le logo lévite au lieu de se secouer
#   Mascotte          personnage animé dans l'en-tête : { File = planche PNG (images côte à côte), Frames, Delay (ms), Flip }
#   Footer            dessin animé dans la barre du bas : { File = planche PNG, Frames, Delay (ms), Height (px) }
#   TabIcons          icônes des onglets des Réglages : { son, voix, assistant, theme, general = { File, Frames, Delay, Glow } }
#   Background        image de fond, sous un voile sombre (BackgroundOpacity 0 à 1, BackgroundAlign « bas-droite »...)
#   Font, FontScope   police du pack (.ttf) : sur les titres (« titres ») ou partout (« tout ») ; FontPixel false : police lisse
# ---------------------------------------------------------------------------
$PacksDir = Join-Path $DataDir 'packs'
if ($EnTest -and $env:EVERMIND_PACKS) { $PacksDir = $env:EVERMIND_PACKS }

function Get-ThemePack([string]$Id) {
    $dir = Join-Path $PacksDir $Id
    $f = Join-Path $dir 'pack.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Log "Pack $Id illisible : $_"; return $null }
    $fichier = { param($n) if ($n -and (Test-Path -LiteralPath (Join-Path $dir ([string]$n)))) { Join-Path $dir ([string]$n) } else { $null } }
    $p = @{ Id = $Id; Dir = $dir; Name = [string]$j.Name; Desc = [string]$j.Desc; Base = [string]$j.Base; Hello = [string]$j.Hello; Font = $null; FontScope = 'titres' }
    if (-not $p.Name) { $p.Name = $Id }
    $p.Logo = & $fichier $j.Logo
    $p.LogoFrames = [math]::Max(1, [int]$j.LogoFrames); $p.LogoDelay = [math]::Max(30, [int]$j.LogoDelay); $p.LogoGlow = [string]$j.LogoGlow
    $p.Mascotte = $null
    if ($j.Mascotte -and (& $fichier $j.Mascotte.File)) { $p.Mascotte = @{ File = (& $fichier $j.Mascotte.File); Frames = [math]::Max(1, [int]$j.Mascotte.Frames); Delay = [math]::Max(40, [int]$j.Mascotte.Delay); Flip = [bool]$j.Mascotte.Flip } }
    $p.Footer = $null
    if ($j.Footer -and (& $fichier $j.Footer.File)) { $p.Footer = @{ File = (& $fichier $j.Footer.File); Frames = [math]::Max(1, [int]$j.Footer.Frames); Delay = [math]::Max(40, [int]$j.Footer.Delay); Height = [math]::Max(16, [int]$j.Footer.Height) } }
    $p.TabIcons = @{}
    if ($j.TabIcons) {
        foreach ($pr in $j.TabIcons.PSObject.Properties) {
            $v = $pr.Value
            if (& $fichier $v.File) { $p.TabIcons[$pr.Name] = @{ File = (& $fichier $v.File); Frames = [math]::Max(1, [int]$v.Frames); Delay = [math]::Max(40, [int]$v.Delay); Glow = [string]$v.Glow } }
        }
    }
    $p.Background = & $fichier $j.Background
    $p.BackgroundOpacity = if ($j.BackgroundOpacity) { [math]::Min(1.0, [math]::Max(0.05, [double]$j.BackgroundOpacity)) } else { 0.35 }
    $al = ([string]$j.BackgroundAlign).ToLowerInvariant()
    $p.BackgroundAlignX = if ($al -match 'droite') { 'Right' } elseif ($al -match 'gauche') { 'Left' } else { 'Center' }
    $p.BackgroundAlignY = if ($al -match 'bas') { 'Bottom' } elseif ($al -match 'haut') { 'Top' } else { 'Center' }
    if (& $fichier $j.Font) { $p.Font = & $fichier $j.Font; if ([string]$j.FontScope -eq 'tout') { $p.FontScope = 'tout' } }
    $p.FontPixel = if ($null -ne $j.FontPixel) { [bool]$j.FontPixel } else { $true }
    # Couleurs propres au pack : un thème « pack-<dossier> » ajouté à la liste (jamais affiché comme thème de base)
    if ($j.Colors -and $j.Colors.P -and $j.Colors.S -and $j.Colors.T) {
        $map = @{}
        if ($j.Colors.Map) { foreach ($pr in $j.Colors.Map.PSObject.Properties) { $map[$pr.Name.TrimStart('#').ToUpper()] = ([string]$pr.Value).TrimStart('#').ToUpper() } }
        $key = "pack-$Id"
        $AppThemes[$key] = @{ Name = $p.Name; Desc = $p.Desc; P = [string]$j.Colors.P; S = [string]$j.Colors.S; T = [string]$j.Colors.T
            NH = $(if ($null -ne $j.Colors.NH) { [double]$j.Colors.NH } else { $null }); NS = $(if ($j.Colors.NS) { [double]$j.Colors.NS } else { 1.0 })
            Map = $map; Hello = $AppThemes['neon'].Hello; Font = $null; Decor = $null; Pack = $true }
        $p.Base = $key
    }
    if (-not $AppThemes.Contains($p.Base)) { $p.Base = 'neon' }
    $p
}

function Get-ThemePacks {
    if (-not (Test-Path -LiteralPath $PacksDir)) { return @() }
    @(Get-ChildItem -LiteralPath $PacksDir -Directory | ForEach-Object { Get-ThemePack $_.Name } | Where-Object { $_ })
}

# Pack (zip contenant pack.json) ajouté dans le dossier des packs ; renvoie son identifiant
function Import-ThemePack([string]$Zip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = Join-Path $env:TEMP ("evermind-pack-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $tmp)
    $json = @(Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'pack.json' | Select-Object -First 1)
    if (-not $json.Count) { throw 'Ce zip ne contient pas de pack.json : ce n''est pas un thème Evermind.' }
    $src = $json[0].DirectoryName
    $id = (([IO.Path]::GetFileNameWithoutExtension($Zip) -replace '^(?i)th[eè]me-', '').Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '' -replace '[^\w\-]', '-').ToLower()
    $dest = Join-Path $PacksDir $id
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File) {
        $to = Join-Path $dest $f.FullName.Substring($src.Length + 1)
        New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $to -Force
    }
    try { [IO.Directory]::Delete($tmp, $true) } catch {}
    if (-not (Get-ThemePack $id)) { throw 'Le pack.json de ce thème est illisible.' }
    Write-Log "Thème personnalisé importé : $id"
    $id
}

# Thème choisi : un thème de base, ou « pack:<dossier> » (les tests peuvent en forcer un pour les captures)
$ThemeSetting = [string](Get-Setting 'Theme' 'neon')
if ($EnTest -and $env:EVERMIND_THEME) { $ThemeSetting = $env:EVERMIND_THEME }
$ThemePack = $null
$ThemeId = $ThemeSetting
if ($ThemeSetting -like 'pack:*') {
    $ThemePack = Get-ThemePack $ThemeSetting.Substring(5)
    $ThemeId = if ($ThemePack) { $ThemePack.Base } else { 'neon' }
}
if (-not $AppThemes.Contains($ThemeId)) { $ThemeId = 'neon' }
$Theme = $AppThemes[$ThemeId]

# Police du pack, utilisable partout comme un nom de police (« file:///dossier/#Nom, police de secours »)
$PackFont = $null
if ($ThemePack -and $ThemePack.Font) {
    try {
        $gt = New-Object System.Windows.Media.GlyphTypeface (New-Object Uri $ThemePack.Font)
        $PackFont = 'file:///' + ($ThemePack.Dir -replace '\\', '/') + '/#' + @($gt.FamilyNames.Values)[0]
    } catch { Write-Log "Police du pack illisible : $_" }
}

# Bonjour de l'en-tête (« {0} » = Bonjour ou Bonsoir)
function Get-ThemeHello { if ($ThemePack -and $ThemePack.Hello) { $ThemePack.Hello } else { $Theme.Hello } }

# Police du pack dans la fenêtre : titres (styles H1, H2) ; avec FontScope « tout », toute l'app.
# Une police pixel, bien plus large, passe en tailles « pixel exactes » (8, 12, 16 ou 24) : nette, et rien ne déborde.
function Get-PackFontSize([double]$Size) { if ($Size -lt 15) { 8 } elseif ($Size -lt 21) { 12 } elseif ($Size -lt 30) { 16 } else { 24 } }
function Convert-PackFontSizes([string]$Text) {
    $Text = [regex]::Replace($Text, '<[A-Za-z][^<>]*?FontSize="[0-9.]+"[^<>]*>', {
        param($m)
        if ($m.Value -match 'Emoji|Fluent Icons|MDL2') { return $m.Value }
        [regex]::Replace($m.Value, 'FontSize="([0-9.]+)"', { param($n) 'FontSize="' + (Get-PackFontSize ([double]::Parse($n.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture))) + '"' })
    })
    $Text = [regex]::Replace($Text, '<Setter Property="FontSize" Value="([0-9.]+)"/>', { param($m) '<Setter Property="FontSize" Value="' + (Get-PackFontSize ([double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture))) + '"/>' })
    [regex]::Replace($Text, '(<Window [^>]*?)FontSize="[0-9.]+"', '$1FontSize="8"', 1)
}
function Add-PackFontXaml([string]$Text) {
    $spec = [Security.SecurityElement]::Escape("$PackFont, Segoe UI Variable Display, Segoe UI")
    $crisp = if ($ThemePack.FontPixel) { '<Setter Property="TextOptions.TextRenderingMode" Value="Aliased"/><Setter Property="TextOptions.TextFormattingMode" Value="Display"/>' } else { '' }
    $Text = $Text.Replace('Segoe UI Variable Display, Segoe UI', $spec)
    $Text = $Text.Replace('<Style x:Key="H1" TargetType="TextBlock">', '<Style x:Key="H1" TargetType="TextBlock">' + $crisp)
    $Text = $Text.Replace('<Style x:Key="H2" TargetType="TextBlock">', '<Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontFamily" Value="' + $spec + '"/>' + $crisp)
    if ($ThemePack.FontScope -eq 'tout') {
        $Text = $Text.Replace('Segoe UI Variable Text, Segoe UI', $spec)
        if ($ThemePack.FontPixel) {
            $Text = [regex]::Replace($Text, '(<Window [^>]*?)FontFamily=', '$1TextOptions.TextRenderingMode="Aliased" TextOptions.TextFormattingMode="Display" FontFamily=', 1)
            $Text = Convert-PackFontSizes $Text
        }
    }
    $Text
}

# Attention : PowerShell ne distingue pas $R de $r, d'où des noms différents pour les valeurs 0 à 1
function ConvertTo-Hsl([int]$Red, [int]$Green, [int]$Blue) {
    $r = $Red / 255.0; $g = $Green / 255.0; $b = $Blue / 255.0
    $max = [math]::Max($r, [math]::Max($g, $b)); $min = [math]::Min($r, [math]::Min($g, $b))
    $l = ($max + $min) / 2
    if ($max -eq $min) { return @(0.0, 0.0, $l) }
    $d = $max - $min
    $s = if ($l -gt 0.5) { $d / (2 - $max - $min) } else { $d / ($max + $min) }
    $h = if ($max -eq $r) { (($g - $b) / $d) + $(if ($g -lt $b) { 6 } else { 0 }) } elseif ($max -eq $g) { (($b - $r) / $d) + 2 } else { (($r - $g) / $d) + 4 }
    @(($h * 60.0), $s, $l)
}

function ConvertFrom-Hsl([double]$H, [double]$S, [double]$L) {
    $H = (($H % 360) + 360) % 360
    $c = (1 - [math]::Abs(2 * $L - 1)) * $S
    $x = $c * (1 - [math]::Abs((($H / 60.0) % 2) - 1))
    $m = $L - $c / 2
    $rgb = switch ([int][math]::Floor($H / 60.0)) { 0 { @($c, $x, 0.0) } 1 { @($x, $c, 0.0) } 2 { @(0.0, $c, $x) } 3 { @(0.0, $x, $c) } 4 { @($x, 0.0, $c) } default { @($c, 0.0, $x) } }
    '{0:X2}{1:X2}{2:X2}' -f [int][math]::Round(255 * ($rgb[0] + $m)), [int][math]::Round(255 * ($rgb[1] + $m)), [int][math]::Round(255 * ($rgb[2] + $m))
}

# Couleur Néon (« #RRGGBB » ou « #AARRGGBB ») traduite dans un thème
$script:ThemeCache = @{}
function ConvertTo-ThemeHex([string]$Hex, [string]$Id = $ThemeId) {
    if ($Id -eq 'neon' -or -not $Hex -or $Hex[0] -ne '#' -or ($Hex.Length -ne 7 -and $Hex.Length -ne 9)) { return $Hex }
    # Une couleur choisie pour une sorte de rendez-vous (Réglages, Thème) reste telle quelle
    if ($script:CouleursFixes -and $script:CouleursFixes[$Hex.Substring($Hex.Length - 6).ToUpper()]) { return $Hex }
    $key = "$Id|$Hex"
    $hit = $script:ThemeCache[$key]
    if ($hit) { return $hit }
    $th = $AppThemes[$Id]
    $alpha = if ($Hex.Length -eq 9) { $Hex.Substring(1, 2) } else { '' }
    $rgb = $Hex.Substring($Hex.Length - 6).ToUpper()
    $out = $rgb
    if ($th.Map.ContainsKey($rgb)) { $out = $th.Map[$rgb] }
    elseif ($rgb -eq '00E5FF') { $out = $th.P.Substring(1) } elseif ($rgb -eq 'B04BFF') { $out = $th.S.Substring(1) } elseif ($rgb -eq 'FF2EB5') { $out = $th.T.Substring(1) }
    else {
        $r = [Convert]::ToInt32($rgb.Substring(0, 2), 16); $g = [Convert]::ToInt32($rgb.Substring(2, 2), 16); $b = [Convert]::ToInt32($rgb.Substring(4, 2), 16)
        $hsl = ConvertTo-Hsl $r $g $b
        $h = $hsl[0]; $s = $hsl[1]; $l = $hsl[2]
        $brand = $null
        if ($s -gt 0.5 -and $l -gt 0.2 -and $l -lt 0.92) {
            if ($h -ge 170 -and $h -lt 200) { $brand = $th.P } elseif ($h -ge 228 -and $h -lt 292) { $brand = $th.S } elseif ($h -ge 292 -and $h -lt 336) { $brand = $th.T }
        }
        if ($brand) {
            # Même clarté que la couleur d'origine (une variante claire reste claire), teinte et saturation du thème
            $bh = ConvertTo-Hsl ([Convert]::ToInt32($brand.Substring(1, 2), 16)) ([Convert]::ToInt32($brand.Substring(3, 2), 16)) ([Convert]::ToInt32($brand.Substring(5, 2), 16))
            $dl = $l - 0.5
            $out = if ([math]::Abs($dl) -lt 0.06) { $brand.Substring(1).ToUpper() } else { ConvertFrom-Hsl $bh[0] $bh[1] ([math]::Min(0.95, [math]::Max(0.05, $bh[2] + $dl))) }
        } elseif (($s -lt 0.35 -or $l -lt 0.16) -and $l -gt 0.015 -and $l -lt 0.97 -and $null -ne $th.NH) {
            # Gris et fonds : la teinte du thème, même clarté
            $out = ConvertFrom-Hsl $th.NH ([math]::Min(1.0, $s * $th.NS)) $l
        }
    }
    $res = "#$alpha$out"
    $script:ThemeCache[$key] = $res
    $res
}

# Une couleur de l'app, dans le thème choisi
function Get-Couleur([string]$Hex) { [System.Windows.Media.ColorConverter]::ConvertFromString((ConvertTo-ThemeHex $Hex)) }

# Texte de la fenêtre (interface.xaml) traduit avant d'être chargé : couleurs, et police du thème
function Convert-ThemeXaml([string]$Text, [string]$Id = $ThemeId) {
    if ($PackFont -and $Id -eq $ThemeId) { $Text = Add-PackFontXaml $Text }
    if ($Id -eq 'neon') { return $Text }
    $th = $AppThemes[$Id]
    $Text = [regex]::Replace($Text, '(?<![&\w])#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})(?![0-9A-Fa-f])', { param($m) ConvertTo-ThemeHex $m.Value $Id })
    if ($th.Font) { $Text = $Text.Replace('Segoe UI Variable Display, Segoe UI', $th.Font).Replace('Segoe UI Variable Text, Segoe UI', $th.Font) }
    $Text
}

# ---------------------------------------------------------------------------
# Décor de fond propre au thème (discret, derrière tout, ne capte jamais la souris)
# ---------------------------------------------------------------------------
function New-RawBrush([string]$Hex) { [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex) }

function New-RawGradient([string[]]$Hex, [double]$X2 = 1, [double]$Y2 = 1) {
    $b = New-Object System.Windows.Media.LinearGradientBrush
    $b.StartPoint = [System.Windows.Point]::new(0, 0); $b.EndPoint = [System.Windows.Point]::new($X2, $Y2)
    for ($i = 0; $i -lt $Hex.Count; $i++) {
        [void]$b.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString($Hex[$i]), $i / [math]::Max(1, $Hex.Count - 1)))
    }
    $b
}

function Add-ThemeDecor {
    $d = $ui.BackdropDeco
    if (-not $d) { return }
    $d.Children.Clear()
    # Fond d'écran d'un pack : l'image, puis un voile sombre qui garde le texte lisible
    if ($ThemePack -and $ThemePack.Background) {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = New-Object Uri $ThemePack.Background; $bi.DecodePixelWidth = 1920; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
        $brush = New-Object System.Windows.Media.ImageBrush $bi
        $brush.Stretch = 'UniformToFill'; $brush.AlignmentX = $ThemePack.BackgroundAlignX; $brush.AlignmentY = $ThemePack.BackgroundAlignY
        $img = New-Object System.Windows.Shapes.Rectangle
        $img.Fill = $brush; $img.Opacity = $ThemePack.BackgroundOpacity
        [void]$d.Children.Add($img)
        $veil = New-Object System.Windows.Shapes.Rectangle
        $veil.Fill = New-RawGradient @('#99000000', '#33000000', '#AA000000') 0 1
        [void]$d.Children.Add($veil)
    }
    if ($ThemePack) { Initialize-PackVisuels }
    switch ($Theme.Decor) {
        'terminal' {
            # Lignes de balayage d'un vieil écran
            $lines = New-Object System.Windows.Media.DrawingBrush
            $lines.TileMode = 'Tile'; $lines.Viewport = [System.Windows.Rect]::new(0, 0, 4, 4); $lines.ViewportUnits = 'Absolute'
            $lines.Drawing = New-Object System.Windows.Media.GeometryDrawing (New-RawBrush '#2233FF77'), $null, ([System.Windows.Media.RectangleGeometry]::new([System.Windows.Rect]::new(0, 0, 4, 1)))
            $scan = New-Object System.Windows.Shapes.Rectangle
            $scan.Fill = $lines; $scan.Opacity = 0.5
            [void]$d.Children.Add($scan)
        }
    }
}

# ---------------------------------------------------------------------------
# Visuels d'un thème personnalisé : mascotte, dessin du bas, icônes des onglets des Réglages
# ---------------------------------------------------------------------------
# Tailles pixel pour tout le texte sous $Racine (sauf les émojis et ce qui est déjà en taille pixel)
function Update-TaillesPixel($Racine) {
    $pile = New-Object System.Collections.Stack
    $pile.Push($Racine)
    while ($pile.Count) {
        $el = $pile.Pop()
        if ($el -is [System.Windows.Controls.TextBlock] -or $el -is [System.Windows.Controls.Control]) {
            $fs = $el.FontSize
            if ($fs -notin 8, 12, 16, 24 -and [string]$el.FontFamily -notmatch 'Emoji') { $el.FontSize = Get-PackFontSize $fs }
        }
        if ($el -is [System.Windows.Media.Visual] -or $el -is [System.Windows.Media.Media3D.Visual3D]) {
            $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($el)
            for ($i = 0; $i -lt $n; $i++) { $pile.Push([System.Windows.Media.VisualTreeHelper]::GetChild($el, $i)) }
        }
    }
}

# Planche PNG (images côte à côte) découpée en images prêtes à afficher
function Get-SheetFrames([string]$File, [int]$Count) {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit(); $bi.UriSource = New-Object Uri $File; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
    $fw = [int]($bi.PixelWidth / $Count)
    @(for ($i = 0; $i -lt $Count; $i++) { $c = New-Object System.Windows.Media.Imaging.CroppedBitmap $bi, ([System.Windows.Int32Rect]::new($i * $fw, 0, $fw, $bi.PixelHeight)); $c.Freeze(); $c })
}

# Une image qui défile en boucle (fenêtre visible seulement : rien ne tourne quand Evermind est caché)
function Start-Defilement($Img, $Frames, [int]$Delay) {
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds($Delay)
    $t.Tag = @{ Img = $Img; Frames = $Frames; Frame = 0 }
    $t.Add_Tick({ param($s) if ($script:AnimsPause -or -not $Window.IsVisible -or $Window.WindowState -eq 'Minimized') { return }; $x = $s.Tag; $x.Frame = ($x.Frame + 1) % $x.Frames.Count; $x.Img.Source = $x.Frames[$x.Frame] })
    if ($Frames.Count -gt 1) { $t.Start() }
    $t
}

# Saut (image fixe) : elle sautille en boucle ; lévitation lumineuse si une couleur est donnée
function Start-Sautille($Img, [double]$Haut = 6, [string]$Lueur = '') {
    $mv = New-Object System.Windows.Media.TranslateTransform
    $grp = New-Object System.Windows.Media.TransformGroup
    if ($Img.RenderTransform -is [System.Windows.Media.ScaleTransform]) { $grp.Children.Add($Img.RenderTransform) }
    $grp.Children.Add($mv)
    $Img.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5); $Img.RenderTransform = $grp
    $ease = New-Object System.Windows.Media.Animation.SineEase; $ease.EasingMode = 'EaseInOut'
    $up = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$Haut), ([System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($(if ($Lueur) { 900 } else { 320 }))))
    $up.AutoReverse = $true; $up.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever; $up.EasingFunction = $ease
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($up, 30)
    Add-AnimationBoucle $mv ([System.Windows.Media.TranslateTransform]::YProperty) $up
    if ($Lueur) {
        $fx = New-Object System.Windows.Media.Effects.DropShadowEffect
        $fx.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Lueur); $fx.ShadowDepth = 0; $fx.Opacity = 0.9; $fx.BlurRadius = 10
        $Img.Effect = $fx
    }
}

function Initialize-PackVisuels {
    $script:PackTimers = @()
    # Police pixel partout : les textes créés par le code passent aussi en tailles pixel (8, 12, 16, 24), nets et sans déborder.
    # Vérifié peu après chaque changement d'affichage (jamais plus de 3 fois par seconde).
    if ($PackFont -and $ThemePack.FontScope -eq 'tout' -and $ThemePack.FontPixel) {
        $script:PixelAFaire = $true
        $Window.Add_LayoutUpdated({ $script:PixelAFaire = $true })
        $script:PixelTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:PixelTimer.Interval = [TimeSpan]::FromMilliseconds(350)
        $script:PixelTimer.Add_Tick({ if ($script:PixelAFaire -and $Window.IsVisible) { $script:PixelAFaire = $false; Update-TaillesPixel $Window } })
        $script:PixelTimer.Start()
    }
    # Mascotte : le personnage du thème, animé dans l'en-tête
    if ($ThemePack.Mascotte) {
        $M = $ThemePack.Mascotte
        $frames = Get-SheetFrames $M.File $M.Frames
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $frames[0]; $img.Height = 72; $img.Stretch = 'Uniform'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, $(if ($frames[0].PixelHeight -le 72) { 'NearestNeighbor' } else { 'HighQuality' }))
        if ($M.Flip) { $img.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5); $img.RenderTransform = New-Object System.Windows.Media.ScaleTransform -1, 1 }
        $ui.Mascotte.Child = $img; $ui.Mascotte.Visibility = 'Visible'
        if ($frames.Count -gt 1) { $script:PackTimers += Start-Defilement $img $frames $M.Delay } else { Start-Sautille $img 8 }
    }
    # Dessin animé de la barre du bas
    if ($ThemePack.Footer) {
        $F = $ThemePack.Footer
        $frames = Get-SheetFrames $F.File $F.Frames
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $frames[0]; $img.Height = $F.Height; $img.Stretch = 'Uniform'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, $(if ($F.Height -ge $frames[0].PixelHeight) { 'NearestNeighbor' } else { 'HighQuality' }))
        $ui.FooterArt.Child = $img; $ui.FooterArt.Visibility = 'Visible'
        $script:PackTimers += Start-Defilement $img $frames $F.Delay
    }
    # Icônes des onglets des Réglages : immobiles, animées au survol de l'onglet
    foreach ($k in @($ThemePack.TabIcons.Keys)) {
        $nom = @{ son = 'Son'; voix = 'Voix'; assistant = 'Assistant'; theme = 'Theme'; general = 'General' }[$k]
        $btn = if ($nom) { $ui["Onglet$nom"] } else { $null }
        if (-not $btn) { continue }
        $def = $ThemePack.TabIcons[$k]
        $frames = Get-SheetFrames $def.File $def.Frames
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $frames[0]; $img.Height = 22; $img.Stretch = 'Uniform'; $img.Margin = [System.Windows.Thickness]::new(0, -4, 7, -4); $img.VerticalAlignment = 'Center'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
        $texte = ([string]$btn.Content) -replace '^\S+\s+', ''   # le texte de l'onglet, sans son émoji
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = $texte; $tb.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($img); [void]$sp.Children.Add($tb)
        $btn.Content = $sp
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds($def.Delay)
        $t.Tag = @{ Img = $img; Frames = $frames; Frame = 0 }
        $t.Add_Tick({ param($s) $x = $s.Tag; $x.Frame = ($x.Frame + 1) % $x.Frames.Count; $x.Img.Source = $x.Frames[$x.Frame] })
        $btn.Resources['Anim'] = $t
        $btn.Add_MouseEnter({ param($s) $a = $s.Resources['Anim']; if ($a.Tag.Frames.Count -gt 1) { $a.Start() } })
        $btn.Add_MouseLeave({ param($s) $a = $s.Resources['Anim']; $a.Stop(); $a.Tag.Frame = 0; $a.Tag.Img.Source = $a.Tag.Frames[0] })
        if ($frames.Count -le 1 -and $def.Glow) { $img.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.ColorConverter]::ConvertFromString($def.Glow); BlurRadius = 8; ShadowDepth = 0; Opacity = 0.8 } }
    }
}

# ---------------------------------------------------------------------------
# Onglet Thème : une carte par thème (aperçu à ses couleurs), puis « Appliquer et relancer »
# ---------------------------------------------------------------------------
function Update-ThemeChoix {
    $g = $ui.ThemeChoix
    $g.Children.Clear()
    if (-not $script:ThemeChoisi) { $script:ThemeChoisi = $ThemeSetting }
    # Les 5 thèmes de base, puis les thèmes personnalisés installés sur ce PC
    $choix = @(if ($GereParMindset) {
        # Copie gérée : les 5 thèmes se choisissent dans Mindset ; ici, seulement le thème de la suite (pour quitter un
        # thème personnalisé) et les thèmes personnalisés
        $k = if ($script:Suite.Theme) { $script:Suite.Theme } else { $ThemeId }
        @(@{ Cle = $k; Base = $k; Name = 'Thème de la suite'; Desc = "Celui choisi dans Mindset : $($AppThemes[$k].Name)."; Pack = $null })
    } else { @(foreach ($k in @($AppThemes.Keys | Where-Object { -not $AppThemes[$_].Pack })) { @{ Cle = $k; Base = $k; Name = $AppThemes[$k].Name; Desc = $AppThemes[$k].Desc; Pack = $null } }) })
    foreach ($pk in @(Get-ThemePacks)) { $choix += @{ Cle = "pack:$($pk.Id)"; Base = $pk.Base; Name = $pk.Name; Desc = $pk.Desc; Pack = $pk } }
    # (copie gérée sans thème personnalisé : rien à choisir ici, tout se fait dans Mindset)
    $g.Visibility = if ($GereParMindset -and $choix.Count -le 1) { 'Collapsed' } else { 'Visible' }
    if (-not @($choix | Where-Object { $_.Cle -eq $script:ThemeChoisi }).Count) { $script:ThemeChoisi = $choix[0].Cle }
    foreach ($ch in $choix) {
        $id = $ch.Base
        $th = $AppThemes[$id]
        $sel = $ch.Cle -eq $script:ThemeChoisi
        $card = New-Object System.Windows.Controls.Border
        $card.CornerRadius = [System.Windows.CornerRadius]::new(16); $card.Padding = [System.Windows.Thickness]::new(9, 9, 9, 11); $card.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
        $card.Background = Get-Brush $(if ($sel) { '#18FFFFFF' } else { '#0AFFFFFF' })
        $w = if ($sel) { 2 } else { 1 }
        $card.BorderThickness = [System.Windows.Thickness]::new($w)
        # Contour aux couleurs du thème de la carte (pas du thème actuel)
        $card.BorderBrush = if ($sel) { New-RawGradient @($th.P, $th.S) } else { Get-Brush '#1CFFFFFF' }
        if ($sel) { $card.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.ColorConverter]::ConvertFromString($th.P); BlurRadius = 18; ShadowDepth = 0; Opacity = 0.45 } }
        $card.Cursor = 'Hand'; $card.Tag = $ch.Cle
        $sp = New-Object System.Windows.Controls.StackPanel
        $pv = New-ThemePreview $id
        # Thème personnalisé : sa mascotte (ou son logo) posée sur l'aperçu
        $image = if ($ch.Pack -and $ch.Pack.Mascotte) { @($ch.Pack.Mascotte.File, $ch.Pack.Mascotte.Frames) } elseif ($ch.Pack -and $ch.Pack.Logo) { @($ch.Pack.Logo, $ch.Pack.LogoFrames) } else { $null }
        if ($image) {
            try {
                $im = New-Object System.Windows.Controls.Image
                $im.Source = (Get-SheetFrames $image[0] $image[1])[0]; $im.Height = 64; $im.HorizontalAlignment = 'Right'; $im.VerticalAlignment = 'Bottom'
                $grille = New-Object System.Windows.Controls.Grid; [void]$grille.Children.Add($pv); [void]$grille.Children.Add($im)
                $im.Margin = [System.Windows.Thickness]::new(0, 0, 6, 4)
                $pv = $grille
            } catch {}
        }
        [void]$sp.Children.Add($pv)
        $nm = New-Object System.Windows.Controls.StackPanel; $nm.Orientation = 'Horizontal'; $nm.Margin = [System.Windows.Thickness]::new(2, 9, 0, 0)
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $ch.Name; $t.FontSize = 14.5; $t.FontWeight = 'Bold'; $t.Foreground = [System.Windows.Media.Brushes]::White; $t.VerticalAlignment = 'Center'
        if ($th.Font) { $t.FontFamily = New-Object System.Windows.Media.FontFamily $th.Font }
        [void]$nm.Children.Add($t)
        if ($ch.Cle -eq $ThemeSetting -or ($ch.Cle -eq 'neon' -and -not $AppThemes.Contains($ThemeSetting) -and -not $ThemePack)) {
            $badge = New-Object System.Windows.Controls.Border
            $badge.CornerRadius = [System.Windows.CornerRadius]::new(8); $badge.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2); $badge.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
            $badge.Background = New-RawBrush ('#33' + $th.P.Substring(1)); $badge.VerticalAlignment = 'Center'
            $bt = New-Object System.Windows.Controls.TextBlock; $bt.Text = 'Actuel'; $bt.FontSize = 11; $bt.Foreground = [System.Windows.Media.Brushes]::White
            $badge.Child = $bt
            [void]$nm.Children.Add($badge)
        }
        [void]$sp.Children.Add($nm)
        $d = New-Object System.Windows.Controls.TextBlock; $d.Text = $ch.Desc; $d.FontSize = 12; $d.TextWrapping = 'Wrap'; $d.Foreground = Get-Brush '#A6A1BC'; $d.Margin = [System.Windows.Thickness]::new(2, 3, 0, 0)
        [void]$sp.Children.Add($d)
        $card.Child = $sp
        $card.Add_MouseLeftButtonUp({ param($s) $script:ThemeChoisi = [string]$s.Tag; Update-ThemeChoix })
        [void]$g.Children.Add($card)
    }
    $change = $script:ThemeChoisi -ne $ThemeSetting
    $nomChoisi = @($choix | Where-Object { $_.Cle -eq $script:ThemeChoisi })[0].Name
    $ui.BtnThemeAppliquer.Visibility = if ($change) { 'Visible' } else { 'Collapsed' }
    $ui.ThemeInfo.Text = if ($change) { "« $nomChoisi » s'applique en relançant Evermind (quelques secondes)." } elseif ($g.Visibility -ne 'Visible') { '' } else { 'Clique sur un thème pour le choisir.' }
    $ui.ThemeInfo.Parent.Visibility = if ($ui.ThemeInfo.Text) { 'Visible' } else { 'Collapsed' }
}

# « Importer un thème » : un zip choisi sur le PC, copié dans le dossier des thèmes, puis choisi
function Invoke-ImportTheme {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Choisis le thème (.zip)'; $dlg.Filter = 'Thème Evermind (*.zip)|*.zip'
    $bureau = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Thème-Evermind'
    if (Test-Path -LiteralPath $bureau) { $dlg.InitialDirectory = $bureau }
    if (-not $dlg.ShowDialog($Window)) { return }
    try {
        $id = Import-ThemePack $dlg.FileName
        $script:ThemeChoisi = "pack:$id"
        Update-ThemeChoix
        $ui.ThemeInfo.Text = "« $((Get-ThemePack $id).Name) » ajouté : clique sur « Appliquer et relancer »."
    } catch { $ui.ThemeInfo.Text = "Ce thème n'a pas pu être ajouté : $($_.Exception.Message)" }
}

function Set-AppTheme([string]$Id) {
    if ($Id -like 'pack:*') { if (-not (Get-ThemePack $Id.Substring(5))) { return } }
    elseif (-not $AppThemes.Contains($Id)) { return }
    Set-Setting 'Theme' $Id
    Write-Log "Thème : $Id"
    if ($GereParMindset) { Write-SuiteTheme $Id }   # un des 5 thèmes : toute la suite le prend (suite.ps1)
    if ($EnTest) { $ui.ThemeInfo.Text = "Thème « $Id » choisi (test : pas de relance)."; return }
    Restart-App
}

# ---------------------------------------------------------------------------
# Aperçu d'un thème (onglet Thème) : un petit Evermind à ses couleurs, sans traduction par le thème actuel
# ---------------------------------------------------------------------------
function New-ThemePreview([string]$Id) {
    $c = { param($h) ConvertTo-ThemeHex $h $Id }
    $th = $AppThemes[$Id]
    $bg = New-Object System.Windows.Controls.Border
    $bg.Height = 112; $bg.CornerRadius = [System.Windows.CornerRadius]::new(12); $bg.ClipToBounds = $true
    $bg.Background = New-RawGradient @((& $c '#0C0920'), (& $c '#06050F'))
    $cv = New-Object System.Windows.Controls.Canvas
    foreach ($blob in @(@($th.P, 10, -30), @($th.T, 170, 40))) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = 140; $e.Height = 120
        $rb = New-Object System.Windows.Media.RadialGradientBrush
        [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#55' + $blob[0].Substring(1)), 0))
        [void]$rb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#00' + $blob[0].Substring(1)), 1))
        $e.Fill = $rb
        [System.Windows.Controls.Canvas]::SetLeft($e, $blob[1]); [System.Windows.Controls.Canvas]::SetTop($e, $blob[2])
        [void]$cv.Children.Add($e)
    }
    # Le E dans son anneau, et le bouton « Nouveau rendez-vous »
    $ring = New-Object System.Windows.Shapes.Ellipse
    $ring.Width = 30; $ring.Height = 30; $ring.StrokeThickness = 3; $ring.Stroke = New-RawGradient @($th.P, $th.S, $th.T)
    $ring.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.ColorConverter]::ConvertFromString($th.P); BlurRadius = 10; ShadowDepth = 0; Opacity = 0.8 }
    [System.Windows.Controls.Canvas]::SetLeft($ring, 10); [System.Windows.Controls.Canvas]::SetTop($ring, 8)
    [void]$cv.Children.Add($ring)
    $e1 = New-Object System.Windows.Controls.TextBlock
    $e1.Text = 'E'; $e1.FontWeight = 'Black'; $e1.FontSize = 15; $e1.Foreground = [System.Windows.Media.Brushes]::White
    if ($th.Font) { $e1.FontFamily = New-Object System.Windows.Media.FontFamily $th.Font }
    [System.Windows.Controls.Canvas]::SetLeft($e1, 20); [System.Windows.Controls.Canvas]::SetTop($e1, 12)
    [void]$cv.Children.Add($e1)
    $nv = New-Object System.Windows.Controls.Border
    $nv.Width = 58; $nv.Height = 14; $nv.CornerRadius = [System.Windows.CornerRadius]::new(7); $nv.Background = New-RawGradient @($th.P, $th.S) 1 0
    [System.Windows.Controls.Canvas]::SetLeft($nv, 176); [System.Windows.Controls.Canvas]::SetTop($nv, 15)
    [void]$cv.Children.Add($nv)
    # Un petit calendrier : jours, et trois rendez-vous aux couleurs du thème
    for ($k = 0; $k -lt 14; $k++) {
        $j = New-Object System.Windows.Controls.Border
        $j.Width = 20; $j.Height = 20; $j.CornerRadius = [System.Windows.CornerRadius]::new(5)
        $j.Background = New-RawBrush (& $c '#14FFFFFF')
        if ($k -eq 4) { $j.BorderBrush = New-RawBrush $th.P; $j.BorderThickness = [System.Windows.Thickness]::new(1.5) }
        [System.Windows.Controls.Canvas]::SetLeft($j, 10 + ($k % 7) * 24); [System.Windows.Controls.Canvas]::SetTop($j, 48 + [math]::Floor($k / 7) * 26)
        [void]$cv.Children.Add($j)
    }
    foreach ($pt in @(@($th.P, 1, 0), @($th.T, 3, 0), @($th.S, 9, 1))) {
        $p = New-Object System.Windows.Controls.Border
        $p.Width = 16; $p.Height = 5; $p.CornerRadius = [System.Windows.CornerRadius]::new(3); $p.Background = New-RawBrush $pt[0]
        [System.Windows.Controls.Canvas]::SetLeft($p, 12 + ($pt[1] % 7) * 24); [System.Windows.Controls.Canvas]::SetTop($p, 60 + $pt[2] * 26)
        [void]$cv.Children.Add($p)
    }
    # Une carte « À venir »
    $todo = New-Object System.Windows.Controls.Border
    $todo.Width = 48; $todo.Height = 46; $todo.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $todo.Background = New-RawGradient @(('#33' + $th.T.Substring(1)), ('#22' + $th.S.Substring(1)))
    $todo.BorderBrush = New-RawGradient @(('#AA' + $th.T.Substring(1)), ('#AA' + $th.S.Substring(1))); $todo.BorderThickness = [System.Windows.Thickness]::new(1)
    [System.Windows.Controls.Canvas]::SetLeft($todo, 186); [System.Windows.Controls.Canvas]::SetTop($todo, 48)
    [void]$cv.Children.Add($todo)
    $bg.Child = $cv
    $bg
}
