# Vérifie les couleurs des thèmes personnalisés (packs) : elles sont collées dans le texte de la fenêtre, donc seules
# des couleurs « #RRGGBB » passent. Une couleur mal écrite, ou du texte glissé dans un pack (guillemets, balises), fait
# garder le thème de base : Evermind s'ouvre quand même, et rien d'autre ne se passe (audit du 25/10, constat 7).
# Puis le thème d'une copie gérée par Mindset : il se choisit seulement dans Mindset. Aucun choix ni import dans
# Réglages, Thème (le thème actuel, pack compris, et le bouton vers Mindset), Set-AppTheme et l'import sans effet, et
# suite.json jamais écrit. Une copie autonome garde ses choix et l'import.
# Rien ne s'affiche : la fenêtre est seulement lue (jamais montrée), avec des packs de test et un faux suite.json
# (EVERMIND_SUITE) dans _test.
#
#   .\outils\tester-themes.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$EnTest = $true
$GereParMindset = $false
$env:EVERMIND_DONNEES = Join-Path $racine '_test\themes'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
$env:EVERMIND_PACKS = Join-Path $env:EVERMIND_DONNEES 'packs'
. (Join-Path $modules 'donnees.ps1')

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}
function New-PackTest([string]$Id, $Pack) {
    $d = Join-Path $env:EVERMIND_PACKS $Id
    New-Item -ItemType Directory -Force $d | Out-Null
    [IO.File]::WriteAllText((Join-Path $d 'pack.json'), (ConvertTo-Json -InputObject $Pack -Depth 5), (New-Object Text.UTF8Encoding $false))
}
$piege = '#00E5FF"/><TextBlock xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Text="PIEGE'
New-PackTest 'bon' @{ Name = 'Bon'; Colors = @{ P = '#112233'; S = '#445566'; T = '#778899'; NH = 200; NS = 0.5; Map = @{ '0C0920' = '#101010' } } }
New-PackTest 'faute' @{ Name = 'Faute'; Base = 'rubis'; Colors = @{ P = 'red'; S = '#0F0'; T = '#778899' } }
New-PackTest 'piege' @{ Name = 'Piège'; Base = 'crepuscule'; Colors = @{ P = $piege; S = '#445566'; T = '#778899' } }
New-PackTest 'piege-map' @{ Name = 'Piège Map'; Colors = @{ P = '#112233'; S = '#445566'; T = '#778899'; Map = @{ '0C0920' = '101010"/><TextBlock Text="PIEGE' } } }
New-PackTest 'lueur' @{ Name = 'Lueur'; LogoGlow = 'n''importe quoi' }

$xamlTexte = [IO.File]::ReadAllText((Join-Path $modules 'interface.xaml'), [Text.Encoding]::UTF8)
# Comme au lancement d'Evermind : le thème choisi est lu (themes.ps1), puis la fenêtre (interface.ps1)
function Test-Lancement([string]$Theme) {
    $env:EVERMIND_THEME = $Theme
    $script:AppThemes = $null
    . (Join-Path $modules 'themes.ps1')
    $r = @{ ThemeId = $ThemeId; Fenetre = $false; Piege = $false; Erreur = ''; Pack = [bool]$ThemePack; Lueur = $(if ($ThemePack) { $ThemePack.LogoGlow }) }
    try {
        $texte = Convert-ThemeXaml $xamlTexte
        $r.Piege = $texte -match 'PIEGE'
        [xml]$x = $texte
        $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
        $r.Fenetre = [bool]$w
        $r.P = ConvertTo-ThemeHex '#00E5FF'
    } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $r.Erreur = $e.Message }
    $r
}

$r = Test-Lancement 'pack:bon'
Test-Cas 'pack aux bonnes couleurs : ses couleurs' ($r.ThemeId -eq 'pack-bon' -and $r.Fenetre -and $r.P -eq '#112233') "($($r.ThemeId) $($r.P) $($r.Erreur))"
$r = Test-Lancement 'pack:faute'
Test-Cas 'couleur mal écrite (« red », « #0F0 ») : le thème de base, la fenêtre s''ouvre' ($r.ThemeId -eq 'rubis' -and $r.Fenetre) "($($r.ThemeId) $($r.Erreur))"
$r = Test-Lancement 'pack:piege'
Test-Cas 'guillemets et balises dans une couleur : le thème de base, rien d''ajouté' ($r.ThemeId -eq 'crepuscule' -and $r.Fenetre -and -not $r.Piege) "($($r.ThemeId) piège=$($r.Piege) $($r.Erreur))"
$r = Test-Lancement 'pack:piege-map'
Test-Cas 'guillemets et balises dans Map : Néon, rien d''ajouté' ($r.ThemeId -eq 'neon' -and $r.Fenetre -and -not $r.Piege) "($($r.ThemeId) piège=$($r.Piege) $($r.Erreur))"
$r = Test-Lancement 'pack:lueur'
Test-Cas 'lueur mal écrite : aucune lueur' ($r.Pack -and $r.Lueur -eq '' -and $r.Fenetre) "($($r.Lueur) $($r.Erreur))"
Test-Cas 'pack mal écrit : noté au journal' (@([IO.File]::ReadAllLines($LogFile, [Text.Encoding]::UTF8) | Where-Object { $_ -match 'couleurs mal écrites' }).Count -ge 3)

# ---------------------------------------------------------------------------
# Le thème de toute la suite se choisit seulement dans Mindset (Paramètres, Apparence)
# ---------------------------------------------------------------------------
$env:EVERMIND_THEME = $null
$suiteTest = Join-Path $env:EVERMIND_DONNEES 'suite.json'   # (jamais le vrai suite.json)
$env:EVERMIND_SUITE = $suiteTest
$utf8 = New-Object Text.UTF8Encoding $false
# Un thème personnalisé à importer (zip avec pack.json)
$zipSrc = Join-Path $env:EVERMIND_DONNEES 'zip-source'
New-Item -ItemType Directory -Force $zipSrc | Out-Null
[IO.File]::WriteAllText((Join-Path $zipSrc 'pack.json'), (ConvertTo-Json -InputObject @{ Name = 'Importé'; Base = 'arcade' }), $utf8)
function Get-Brush([string]$Hex) { [System.Windows.Media.BrushConverter]::new().ConvertFromString((ConvertTo-ThemeHex $Hex)) }   # (comme interface.ps1)
$AppDir = $null   # (mindset.ps1 : la copie n'est pas reconnue par suite.json, on choisit $GereParMindset nous-mêmes)
$cas = @(
    @{ Nom = 'copie gérée, thème de la suite'; Gere = $true; Suite = 'rubis'; Actuel = 'Rubis'; Zip = 'theme-gere-base' },
    @{ Nom = 'copie gérée, pack installé par Mindset'; Gere = $true; Suite = 'pack:bon'; Actuel = 'Bon'; Zip = 'theme-gere-pack' },
    @{ Nom = 'copie autonome'; Gere = $false; Suite = 'rubis'; Actuel = $null; Zip = 'theme-autonome' }
)
foreach ($c in $cas) {
    $n = $c.Nom
    [IO.File]::WriteAllText($suiteTest, (ConvertTo-Json -InputObject ([ordered]@{ theme = $c.Suite; applis = [ordered]@{ evermind = 'X:\Essai\Evermind' }; modifie = '2026-10-14T16:00:00' })), $utf8)
    [IO.File]::SetLastWriteTimeUtc($suiteTest, [datetime]'2026-10-14T16:00:00Z')
    $suiteAvant = [IO.File]::ReadAllBytes($suiteTest); $dateAvant = [IO.File]::GetLastWriteTimeUtc($suiteTest)
    Set-Setting 'Theme' 'neon'
    # Comme au lancement d'Evermind : mindset.ps1, suite.ps1, themes.ps1, la fenêtre (jamais montrée), puis Initialize-Suite
    . (Join-Path $modules 'mindset.ps1')
    $GereParMindset = $c.Gere
    . (Join-Path $modules 'suite.ps1')
    $script:AppThemes = $null
    . (Join-Path $modules 'themes.ps1')
    [xml]$x = Convert-ThemeXaml $xamlTexte
    $Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    $ui = @{}
    foreach ($node in $x.SelectNodes('//*[@*[local-name()="Name"]]')) {
        $nm = $node.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1
        if ($nm) { $ui[$nm.Value] = $Window.FindName($nm.Value) }
    }
    try { Initialize-Suite } catch { Test-Cas "$n : Initialize-Suite" $false "($($_.Exception.Message))" }
    if ($script:SuiteTimer) { $script:SuiteTimer.Stop(); $script:SuiteTimer = $null }
    try { Update-ThemeChoix } catch { Test-Cas "$n : onglet Thème" $false "($($_.Exception.Message))" }
    $vu = { param($o) [bool]$o -and $o.Visibility -eq 'Visible' }
    $bas = $ui.BtnThemeAppliquer.Parent
    if ($c.Gere) {
        Test-Cas "$n : aucun choix de thème ni import visible" (-not (& $vu $ui.ThemeChoix) -and $ui.ThemeChoix.Children.Count -eq 0 -and -not (& $vu $bas) -and -not (& $vu $ui.ThemesPerso) -and -not (& $vu $ui.ThemeTexte)) "(choix=$($ui.ThemeChoix.Visibility)/$($ui.ThemeChoix.Children.Count) bas=$($bas.Visibility) import=$($ui.ThemesPerso.Visibility))"
        $textes = @($ui.ThemeMindset.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { $_.Text })
        Test-Cas "$n : le thème actuel ($($c.Actuel)) et « se choisit dans Mindset »" ((& $vu $ui.ThemeMindset) -and ($textes -contains "Thème actuel : $($c.Actuel)") -and ($textes -contains 'Le thème se choisit dans Mindset, pour toutes les applis.') -and $ui.BtnThemeMindset.Content -eq 'Ouvrir les réglages de Mindset') "($($textes -join ' | '))"
        Test-Cas "$n : thème de la suite pris au démarrage" ([string](Get-Setting 'Theme' '') -eq $c.Suite -and $(if ($c.Suite -like 'pack:*') { [bool]$ThemePack -and $ThemePack.Name -eq $c.Actuel } else { $ThemeId -eq $c.Suite })) "(réglage=$(Get-Setting 'Theme' '') ThemeId=$ThemeId)"
    } else {
        Test-Cas "$n : les 5 thèmes au choix et l'import" ((& $vu $ui.ThemeChoix) -and $ui.ThemeChoix.Children.Count -ge 5 -and (& $vu $bas) -and (& $vu $ui.ThemesPerso) -and -not (& $vu $ui.ThemeMindset)) "(choix=$($ui.ThemeChoix.Visibility)/$($ui.ThemeChoix.Children.Count) import=$($ui.ThemesPerso.Visibility) mindset=$($ui.ThemeMindset.Visibility))"
    }
    Test-Cas "$n : Couleurs des rendez-vous toujours là" ([bool]$ui.CouleursSortes -and $ui.CouleursSortes.Visibility -eq 'Visible')
    # Choisir un thème et en importer un, comme le feraient les boutons
    $avant = [string](Get-Setting 'Theme' '')
    try { Set-AppTheme 'arcade' } catch { Test-Cas "$n : Set-AppTheme" $false "($($_.Exception.Message))" }
    $apres = [string](Get-Setting 'Theme' '')
    $zip = Join-Path $env:EVERMIND_DONNEES "$($c.Zip).zip"
    Remove-Item -LiteralPath $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $zipSrc 'pack.json') -DestinationPath $zip
    $importe = $null; try { $importe = Import-ThemePack $zip } catch {}
    $dossierImporte = Join-Path $PacksDir ($c.Zip -replace '^theme-', '')
    $suiteEcrit = -not [Linq.Enumerable]::SequenceEqual([byte[]]$suiteAvant, [byte[]][IO.File]::ReadAllBytes($suiteTest)) -or [IO.File]::GetLastWriteTimeUtc($suiteTest) -ne $dateAvant
    Test-Cas "$n : suite.json jamais écrit" (-not $suiteEcrit -and -not (Get-Command Write-SuiteTheme -ErrorAction SilentlyContinue))
    if ($c.Gere) {
        Test-Cas "$n : Set-AppTheme sans effet" ($apres -eq $avant) "($avant -> $apres)"
        Test-Cas "$n : import sans effet" (-not $importe -and -not (Test-Path -LiteralPath $dossierImporte)) "(importé=$importe)"
    } else {
        Test-Cas "$n : Set-AppTheme choisit le thème" ($apres -eq 'arcade') "($avant -> $apres)"
        Test-Cas "$n : import d'un thème" ($importe -and (Test-Path -LiteralPath (Join-Path $dossierImporte 'pack.json'))) "(importé=$importe)"
    }
}

$env:EVERMIND_THEME = $null; $env:EVERMIND_PACKS = $null; $env:EVERMIND_SUITE = $null
exit $(if ($ok) { 0 } else { 1 })
