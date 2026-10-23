# Vérifie ce que devient le réglage « Démarrage avec Windows » d'Evermind quand Mindset le gère. Mindset le lit
# (« DemarrageWindows » dans reglages.json, le dossier de données d'Evermind) pour savoir s'il doit lancer Evermind
# avec Windows : Evermind doit le garder tel quel, et seulement retirer son ancienne entrée « Evermind » (clé Run) qui
# lance cette copie-ci. Le registre n'est jamais touché : la clé Run est imitée.
#
#   .\outils\tester-demarrage.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$EnTest = $true   # (pendant le chargement : rien n'est lu ni déplacé hors de _test)
$AppDir = Join-Path $racine 'Evermind\fichiers'
$MainScript = Join-Path $AppDir 'Evermind.ps1'
$AppRelais = Join-Path $racine 'Evermind\Evermind.exe'
$AppExe = Join-Path $racine 'Evermind\Mindset.exe'
$env:EVERMIND_SUITE = $null
$env:EVERMIND_DONNEES = Join-Path $racine '_test\demarrage'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
foreach ($m in 'mindset', 'donnees', 'systeme') { . (Join-Path $modules "$m.ps1") }

# La clé Run imitée (ces fonctions passent avant les vraies commandes), et un chemin qui n'existe pas par sécurité
$RunKey = 'HKCU:\Software\Evermind-test-inexistant\Run'
$script:Run = @{}
function Get-ItemProperty { param([string]$LiteralPath, [string]$Name, $ErrorAction) if ($script:Run.ContainsKey($Name)) { [pscustomobject]@{ $Name = $script:Run[$Name] } } }
function Remove-ItemProperty { param([string]$LiteralPath, [string]$Name, $ErrorAction) [void]$script:Run.Remove($Name) }
function New-ItemProperty { param([string]$LiteralPath, [string]$Name, $Value, $PropertyType, [switch]$Force) $script:Run[$Name] = $Value }
$EnTest = $false; $GereParMindset = $true   # Evermind géré par Mindset, comme chez l'utilisateur

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}
# Ce que Mindset lit : le fichier lui-même
function Get-ReglageFichier { $j = [IO.File]::ReadAllText($SettingsFile, [Text.Encoding]::UTF8) | ConvertFrom-Json; $j.DemarrageWindows }

# Avant Mindset : démarrage avec Windows actif, l'entrée lance cette copie (le relais d'une ancienne entrée)
Set-Setting 'DemarrageWindows' $true
$script:Run['Evermind'] = "`"$AppRelais`" -Demarrage"
Initialize-AutoStart
Test-Cas 'actif : l''entrée de cette copie est retirée (Mindset lance Evermind)' (-not $script:Run.ContainsKey('Evermind'))
Test-Cas 'actif : « DemarrageWindows » reste à oui dans reglages.json' ((Get-ReglageFichier) -eq $true) "($(Get-ReglageFichier))"
# La case cachée (Set-AutoStart) et un deuxième lancement ne changent rien
Set-AutoStart $false
Initialize-AutoStart
Test-Cas 'actif : toujours oui après un deuxième lancement' ((Get-ReglageFichier) -eq $true -and -not $script:Run.Count) "($(Get-ReglageFichier))"

# Avant Mindset : démarrage avec Windows coupé par l'utilisateur
Set-Setting 'DemarrageWindows' $false
Initialize-AutoStart
Test-Cas 'coupé : « DemarrageWindows » reste à non' ((Get-ReglageFichier) -eq $false) "($(Get-ReglageFichier))"
Test-Cas 'coupé : aucune entrée ajoutée' (-not $script:Run.Count)

# L'entrée « Evermind » d'une autre copie reste (ce n'est pas la nôtre), le réglage aussi
Set-Setting 'DemarrageWindows' $true
$script:Run['Evermind'] = '"C:\Autre\Evermind\Mindset.exe" -Demarrage'
Initialize-AutoStart
Test-Cas 'autre copie : son entrée reste, le réglage aussi' ($script:Run['Evermind'] -eq '"C:\Autre\Evermind\Mindset.exe" -Demarrage' -and (Get-ReglageFichier) -eq $true)

exit $(if ($ok) { 0 } else { 1 })
