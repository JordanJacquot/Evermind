# Vérifie les couleurs des thèmes personnalisés (packs) : elles sont collées dans le texte de la fenêtre, donc seules
# des couleurs « #RRGGBB » passent. Une couleur mal écrite, ou du texte glissé dans un pack (guillemets, balises), fait
# garder le thème de base : Evermind s'ouvre quand même, et rien d'autre ne se passe (audit du 25/10, constat 7).
# Rien ne s'affiche : la fenêtre est seulement lue (jamais montrée), avec des packs de test dans _test.
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

$env:EVERMIND_THEME = $null; $env:EVERMIND_PACKS = $null
exit $(if ($ok) { 0 } else { 1 })
