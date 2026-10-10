# Construit le dossier d'Evermind prêt à partager, puis Evermind.zip.
#
#   Evermind\
#     Evermind.exe                           <- à lancer (icône Evermind)
#     fichiers\Evermind.ps1, Evermind.ico, lanceur de secours (.bat)
#     fichiers\modules\                      <- le code découpé par partie

$ErrorActionPreference = 'Stop'
$racine  = Split-Path $PSScriptRoot -Parent
$app     = Join-Path $racine 'Evermind'
$fich    = Join-Path $app 'fichiers'
$icones  = Join-Path $PSScriptRoot 'icones'
$csc     = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$source  = Join-Path $PSScriptRoot 'lanceur.cs'
$manif   = Join-Path $PSScriptRoot 'lanceur.manifest'

& (Join-Path $PSScriptRoot 'icone.ps1') -OutDir $icones | Out-Null
Copy-Item (Join-Path $icones 'Evermind.ico') (Join-Path $fich 'Evermind.ico') -Force

$exe = Join-Path $app 'Evermind.exe'
# Evermind.exe exécute le code lui même : il a besoin du moteur PowerShell de Windows
$sma = [psobject].Assembly.Location
& $csc /nologo /target:winexe /optimize+ /platform:anycpu "/win32icon:$(Join-Path $icones 'Evermind.ico')" "/win32manifest:$manif" /reference:System.Windows.Forms.dll "/reference:$sma" "/out:$exe" $source
if ($LASTEXITCODE) { throw "Échec de compilation de $exe" }

$zip = Join-Path $racine 'Evermind.zip'
Compress-Archive -Path $app -DestinationPath $zip -Force
"OK : $zip"
