# Evermind : Mindset, le portail de la suite. Evermind s'utilise maintenant avec Mindset, qui l'installe, le met à
# jour et le lance avec Windows.
# Chargé par Evermind.ps1 tout au début, avant même de vérifier qu'aucun autre Evermind ne tourne : une copie qui
# n'est pas celle de Mindset s'arrête tout de suite (Test-BlocageMindset), sans rien démarrer ni rien déplacer, et ne
# gêne donc jamais l'Evermind de Mindset.

# ---------------------------------------------------------------------------
# %LOCALAPPDATA%\Mindset\suite.json, écrit par Mindset
#   { "theme": "neon", "applis": { "evermind": "<dossier d'Evermind.exe>", ... }, "micro": "...", "casque": "...", "modifie": "..." }
#   micro, casque : noms des appareils choisis dans Mindset pour toute la suite ("" = ceux de Windows ; absent = garder le réglage d'Evermind)
# Evermind est « géré par Mindset » si applis.evermind est le dossier de cette copie : ses données vont alors dans
# %LOCALAPPDATA%\Mindset\Evermind (donnees.ps1), il suit le thème de la suite (suite.ps1), et c'est Mindset qui le
# met à jour et le lance avec Windows.
# Sécurité : n'importe quel programme de l'utilisateur peut modifier ce fichier. On n'y accepte qu'un nom de thème
# connu, un nom d'appareil court (seulement comparé aux noms des micros et sorties), et le dossier n'y sert qu'à comparer
# avec le nôtre : rien n'y est jamais lancé ni ouvert.
# ---------------------------------------------------------------------------
$SuiteFile   = if ($EnTest) { $env:EVERMIND_SUITE } else { Join-Path $env:LOCALAPPDATA 'Mindset\suite.json' }   # (tests : un fichier à part, ou aucun)
$ThemesSuite = @('neon', 'crepuscule', 'terminal', 'arcade', 'rubis')
$MindsetPage = 'https://github.com/JordanJacquot/Mindset/releases/latest'
$MindsetExe  = Join-Path $env:ProgramFiles 'Mindset\Mindset\Mindset.exe'

# Chemin complet, sans « \ » à la fin (pour comparer deux dossiers), ou $null s'il n'est pas valable
function Get-CheminNormal([string]$Chemin) {
    if ($Chemin -notmatch '^[A-Za-z]:\\') { return $null }
    try { [IO.Path]::GetFullPath($Chemin).TrimEnd('\') } catch { $null }
}

# Ce qu'on garde de suite.json : le thème (s'il est connu, ou « pack:<id> » au nom valable), le micro et le casque ($null si absents ou pas valables),
# et le dossier d'Evermind (seulement pour comparer)
# Un fichier tenu un instant par un autre programme (antivirus, OneDrive, Mindset qui le remplace) n'est ni abîmé ni
# interdit : $Essais lectures espacées de 300 ms, puis « Pris » (on ne sait pas encore ce qu'il dit).
function Test-SuitePrise($Erreur) {
    for ($e = $Erreur; $e; $e = $e.InnerException) {
        if ($e -is [UnauthorizedAccessException]) { return $true }
        if ($e -is [IO.IOException] -and (($e.HResult -band 0xFFFF) -in 32, 33)) { return $true }   # (partage, verrou)
    }
    $false
}

function Read-Suite([int]$Essais = 10) {
    $s = @{ Existe = $false; Lisible = $false; Pris = $false; Theme = $null; Evermind = $null; Micro = $null; Casque = $null }
    if (-not $SuiteFile -or -not [IO.File]::Exists($SuiteFile)) { return $s }
    $s.Existe = $true
    $texte = $null
    for ($i = 1; $i -le $Essais; $i++) {
        try { $texte = [IO.File]::ReadAllText($SuiteFile, [Text.Encoding]::UTF8); $s.Pris = $false; break }
        catch {
            $s.Pris = Test-SuitePrise $_.Exception
            if (-not $s.Pris) { break }
            if ($i -lt $Essais) { Start-Sleep -Milliseconds 300 }
        }
    }
    if ($null -eq $texte) { return $s }
    try {
        $j = $texte | ConvertFrom-Json
        # Thème : un des 5 thèmes, ou « pack:<id> », un thème personnalisé de la suite installé par Mindset dans nos packs
        if ($j.theme -is [string] -and $j.theme -in $ThemesSuite) { $s.Theme = $j.theme.ToLowerInvariant() }
        elseif ($j.theme -is [string] -and $j.theme -cmatch '^pack:[a-z0-9-]{1,40}$') { $s.Theme = $j.theme }
        if ($j.applis -and $j.applis.evermind -is [string]) { $s.Evermind = Get-CheminNormal $j.applis.evermind }
        foreach ($k in @(@('micro', 'Micro'), @('casque', 'Casque'))) {   # (une chaîne de 64 caractères au plus, sans caractère de contrôle)
            $v = if ($j.PSObject.Properties[$k[0]]) { $j.($k[0]) } else { $null }
            if ($v -is [string] -and $v.Length -le 64 -and $v -notmatch '\p{Cc}') { $s[$k[1]] = $v }
        }
        $s.Lisible = $true
    } catch {}   # (illisible, ou en train d'être remplacé par Mindset : la copie n'est pas gérée)
    $s
}

# Le dossier de cette copie (celui d'Evermind.exe, parent de « fichiers »)
$AppRacine = if ($AppDir) { Get-CheminNormal (Split-Path $AppDir -Parent) } else { $null }
$script:Suite = Read-Suite

# Une copie installée par Mindset : dans <X>:\Mindset\Programmes ou dans Program Files\Mindset (des dossiers que seul
# un administrateur peut modifier, comme pour le choix du dossier de données dans donnees.ps1)
function Test-DossierProgrammesMindset([string]$Racine) {
    if (-not $Racine) { return $false }
    $p = Split-Path $Racine -Parent
    if (-not $p) { return $false }
    $m = Split-Path $p -Parent
    if ($m -and (Split-Path $p -Leaf) -ieq 'Programmes' -and (Split-Path $m -Leaf) -ieq 'Mindset') { return $true }
    foreach ($pf in $env:ProgramFiles, $env:ProgramW6432) { if ($pf -and $p -ieq (Join-Path $pf 'Mindset')) { return $true } }
    $false
}

# Géré par Mindset : suite.json le dit. suite.json encore pris après 3 secondes (au démarrage de Windows) : on ne
# conclut pas « copie non autorisée » ; une copie dans un dossier de programmes de Mindset est gérée.
$GereParMindset = [bool]($AppRacine -and $script:Suite.Evermind -and $script:Suite.Evermind -ieq $AppRacine)
if (-not $GereParMindset -and $script:Suite.Pris -and (Test-DossierProgrammesMindset $AppRacine)) { $GereParMindset = $true }

# ---------------------------------------------------------------------------
# Evermind s'affiche seulement dans Mindset
# ---------------------------------------------------------------------------
# Lancé à la main, ou une fenêtre à montrer (rappel cliqué, « OK Evermind ») : Mindset s'ouvre sur l'onglet d'Evermind,
# qu'il lance caché (-Demarrage) puis accroche. Son programme vient de son installation (HKLM, modifiable seulement par
# un administrateur), jamais de suite.json. $false si Mindset est introuvable (Evermind s'ouvre alors seul).
function Open-DansMindset {
    $exe = $null
    try {
        $dossier = Get-CheminNormal ([string](Get-ItemProperty -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Mindset' -Name InstallLocation -ErrorAction Stop).InstallLocation).Trim().Trim('"')
        if ($dossier) { $exe = Join-Path $dossier 'Mindset.exe' }
    } catch {}
    if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'Mindset'
        [void][IO.Directory]::CreateDirectory($dir)
        [IO.File]::WriteAllText((Join-Path $dir 'afficher-page.txt'), 'appli:evermind', (New-Object Text.UTF8Encoding($false)))
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent) -ErrorAction Stop
        $true
    } catch { $false }
}

# ---------------------------------------------------------------------------
# Copie hors de Mindset : bloquée
# ---------------------------------------------------------------------------
# Dossier de travail (code source) : un dossier .git dans son dossier ou juste au-dessus, comme D:\Projets\Evermind\Evermind.
# Il n'est jamais bloqué, mais ne se met pas à jour tout seul : la mise à jour écraserait le code source (maj.ps1).
# Pendant les tests : seulement si EVERMIND_TEST_TRAVAIL est défini (les tests tournent dans le dossier de travail).
function Test-DossierTravail {
    if ($EnTest) { return [bool]$env:EVERMIND_TEST_TRAVAIL }
    if (-not $AppRacine) { return $false }
    foreach ($d in $AppRacine, (Split-Path $AppRacine -Parent)) { if ($d -and (Test-Path -LiteralPath (Join-Path $d '.git'))) { return $true } }
    $false
}
$DossierTravail = (-not $GereParMindset) -and (Test-DossierTravail)

# Bloquée si elle n'est pas gérée par Mindset, sauf un dossier de travail. Pendant les tests : seulement si
# EVERMIND_TEST_BLOCAGE est défini.
function Test-BlocageMindset {
    if ($GereParMindset) { return $false }
    if ($EnTest) { return [bool]$env:EVERMIND_TEST_BLOCAGE }
    -not $DossierTravail
}

# La fenêtre qui l'explique, aux couleurs d'Evermind : « Ouvrir Mindset » (s'il est installé) ou « Télécharger Mindset »
# (tests : hors de l'écran, enregistrée en image dans EVERMIND_CAPTURE, puis fermée)
function Show-BlocageMindset {
    $ouvrir = Test-Path -LiteralPath $MindsetExe
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Evermind" Width="520" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#EEEBF7"/><Setter Property="FontSize" Value="14"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="10,0,0,0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Fond" CornerRadius="18" Padding="20,9" Background="#1CFFFFFF" BorderBrush="#33FFFFFF" BorderThickness="1">
            <ContentPresenter HorizontalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Fond" Property="Background" Value="#2CFFFFFF"/></Trigger></ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="BtnPrincipal" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="#0C0920"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Fond" CornerRadius="18" Padding="20,9">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#00E5FF" Offset="0"/><GradientStop Color="#B04BFF" Offset="1"/></LinearGradientBrush></Border.Background>
            <ContentPresenter HorizontalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Fond" Property="Opacity" Value="0.88"/></Trigger></ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid>
  <Border x:Name="Cadre" CornerRadius="20" Margin="16" Padding="30,26" BorderThickness="1">
    <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#0C0920" Offset="0"/><GradientStop Color="#06050F" Offset="1"/></LinearGradientBrush></Border.Background>
    <Border.BorderBrush><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#9900E5FF" Offset="0"/><GradientStop Color="#99FF2EB5" Offset="1"/></LinearGradientBrush></Border.BorderBrush>
    <Border.Effect><DropShadowEffect Color="#B04BFF" BlurRadius="24" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal">
        <Grid Width="40" Height="40" VerticalAlignment="Center">
          <Ellipse StrokeThickness="3"><Ellipse.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#00E5FF" Offset="0"/><GradientStop Color="#B04BFF" Offset="0.5"/><GradientStop Color="#FF2EB5" Offset="1"/></LinearGradientBrush></Ellipse.Stroke></Ellipse>
          <TextBlock Text="E" FontSize="19" FontWeight="Black" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock Text="Evermind" FontSize="15" Foreground="#A6A1BC" VerticalAlignment="Center" Margin="12,0,0,0"/>
      </StackPanel>
      <TextBlock Text="Evermind s'utilise maintenant avec Mindset" FontSize="21" FontWeight="Bold" Foreground="White" TextWrapping="Wrap" Margin="0,18,0,0" FontFamily="Segoe UI Variable Display, Segoe UI"/>
      <TextBlock Text="Installe Mindset, le portail de la suite : il reprend cette copie avec tes rendez-vous, tes réglages et ta voix, rien n'est perdu." FontSize="14.5" Foreground="#C9C4DD" TextWrapping="Wrap" LineHeight="21" Margin="0,10,0,0"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
        <Button x:Name="BtnFermer" Style="{StaticResource Btn}" Content="Fermer"/>
        <Button x:Name="BtnMindset" Style="{StaticResource BtnPrincipal}" Content="$(if ($ouvrir) { 'Ouvrir Mindset' } else { 'Télécharger Mindset' })" IsDefault="True"/>
      </StackPanel>
    </StackPanel>
  </Border>
  </Grid>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    $w.FindName('Cadre').Add_MouseLeftButtonDown({ try { $w.DragMove() } catch {} })
    $w.FindName('BtnFermer').Add_Click({ $w.Close() })
    $w.FindName('BtnMindset').Add_Click({
        if (-not $EnTest) {
            try { if ($ouvrir) { Start-Process -FilePath $MindsetExe } else { Start-Process $MindsetPage } } catch {}
        }
        $w.Close()
    })
    $w.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $w.Close() } })
    if ($EnTest) {
        $w.WindowStartupLocation = 'Manual'; $w.Left = -10000; $w.Top = 0; $w.ShowActivated = $false; $w.ShowInTaskbar = $false
        $w.Add_ContentRendered({
            try {
                $root = $w.Content   # (la grille entière, ombre comprise)
                $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$root.ActualWidth, [int]$root.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                $bmp.Render($root)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
                if ($env:EVERMIND_CAPTURE) { $fs = [IO.File]::Create($env:EVERMIND_CAPTURE); try { $enc.Save($fs) } finally { $fs.Dispose() } }
            } catch { [Console]::Error.WriteLine("Capture : $_") }
            $w.Close()
        })
    } else { $w.Topmost = $true; $w.Add_ContentRendered({ $w.Topmost = $false; [void]$w.Activate() }) }
    [void]$w.ShowDialog()
}
