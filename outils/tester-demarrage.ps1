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

# ---------------------------------------------------------------------------
# Audit du 25/10, constat 19 : un fichier tenu un instant au démarrage (antivirus, OneDrive) n'a pas d'effet durable
# ---------------------------------------------------------------------------
# reglages.json pris pendant le lancement : les réglages changés sont enregistrés dès qu'il est libre, avec les siens
Save-JsonFile $SettingsFile ([ordered]@{ Theme = 'neon' })                              # (la sauvegarde .bak)
Save-JsonFile $SettingsFile ([ordered]@{ Theme = 'neon'; Micro = 'Casque du salon' })   # (le fichier)
$EnTest = $true
$verrou = [IO.File]::Open($SettingsFile, 'Open', 'Read', 'None')
try {
    . (Join-Path $modules 'donnees.ps1')   # (lancement pendant que l'antivirus le tient)
    Set-Setting 'Voix' 'Denise'             # (changé pendant qu'il est encore pris)
} finally { $verrou.Dispose() }
Set-Setting 'Theme' 'rubis'                 # (changé une fois libre)
$f19 = [IO.File]::ReadAllText($SettingsFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
Test-Cas 'reglages.json pris au lancement : les changements sont enregistrés une fois libre' ($f19.Theme -eq 'rubis' -and $f19.Voix -eq 'Denise') "($($f19 | ConvertTo-Json -Compress))"
Test-Cas 'reglages.json pris au lancement : ses propres réglages sont gardés' ($f19.Micro -eq 'Casque du salon') "($($f19 | ConvertTo-Json -Compress))"

# suite.json pris au démarrage de Windows : la copie de Mindset ne se croit pas « copie non autorisée »
$suite19 = Join-Path $env:EVERMIND_DONNEES 'suite.json'
$env:EVERMIND_SUITE = $suite19
$gardeAppDir = $AppDir
function Test-SuiteLancement([string]$Dossier) {
    $script:AppDir = $Dossier
    . (Join-Path $modules 'mindset.ps1')
    @{ Gere = $GereParMindset; Lisible = $script:Suite.Lisible; Pris = $script:Suite.Pris }
}
[IO.File]::WriteAllText($suite19, '{ "theme": "neon", "applis": { "evermind": "C:\\Autre\\Evermind" } }', (New-Object Text.UTF8Encoding $false))
# (tenu 1 seconde par un autre programme, puis relâché)
$signal = Join-Path $env:EVERMIND_DONNEES 'verrou-pris.txt'; Remove-Item -LiteralPath $signal -ErrorAction SilentlyContinue
$tient = "`$f = [IO.File]::Open('$suite19', 'Open', 'Read', 'None'); [IO.File]::WriteAllText('$signal', 'ok'); Start-Sleep -Milliseconds 1000; `$f.Dispose()"
$p19 = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile', '-NonInteractive', '-Command', "& { $tient }" -WindowStyle Hidden -PassThru
for ($i = 0; $i -lt 200 -and -not (Test-Path -LiteralPath $signal); $i++) { Start-Sleep -Milliseconds 50 }
$r19 = Test-SuiteLancement 'C:\Autre\Evermind\fichiers'
if (-not $p19.WaitForExit(10000)) { $p19.Kill() }
Test-Cas 'suite.json tenu 1 s : relu, la copie est gérée par Mindset' ((Test-Path -LiteralPath $signal) -and $r19.Gere -and $r19.Lisible) "($($r19 | ConvertTo-Json -Compress))"
# Toujours pris après les essais : une copie dans un dossier de programmes de Mindset reste gérée, une autre non
$verrou = [IO.File]::Open($suite19, 'Open', 'Read', 'None')
try {
    $r19a = Test-SuiteLancement 'X:\Mindset\Programmes\Evermind\fichiers'
    $r19b = Test-SuiteLancement 'C:\Autre\Evermind\fichiers'
} finally { $verrou.Dispose() }
Test-Cas 'suite.json toujours pris : la copie de Mindset (Programmes) reste gérée' ($r19a.Gere -and $r19a.Pris) "($($r19a | ConvertTo-Json -Compress))"
Test-Cas 'suite.json toujours pris : une autre copie n''est pas gérée' (-not $r19b.Gere) "($($r19b | ConvertTo-Json -Compress))"
$AppDir = $gardeAppDir; $env:EVERMIND_SUITE = $null

exit $(if ($ok) { 0 } else { 1 })
