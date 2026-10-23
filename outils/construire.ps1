# Construit le dossier d'Evermind prêt à partager, puis release\Evermind.zip.
# (Evermind doit être fermé : son .exe est remplacé.)
#
#   Evermind\
#     Evermind.exe                           <- à lancer (icône Evermind)
#     LISEZMOI.txt                           <- installer et utiliser
#     fichiers\Evermind.ps1, Evermind.ico, lanceur de secours (.bat)
#     fichiers\cles-publiques\*.xml          <- vérifient la signature des mises à jour (les mêmes que Mindset)
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
# Il porte le numéro de version d'Evermind.ps1, ajouté à la compilation : publier.ps1 n'a qu'un numéro à changer, et
# la signature du code (SignPath) vérifie que l'exe a bien la version de l'appli
$version = if ([IO.File]::ReadAllText((Join-Path $fich 'Evermind.ps1'), [Text.Encoding]::UTF8) -match "(?m)^\`$AppVersion = '(\d+(\.\d+){1,3})'") { $Matches[1] } else { throw 'Numéro de version introuvable dans Evermind.ps1' }
$morceaux = @($version.Split('.')); while ($morceaux.Count -lt 4) { $morceaux += '0' }
$version4 = $morceaux -join '.'
$infos = Join-Path $env:TEMP "evermind-version-$PID.cs"
[IO.File]::WriteAllText($infos, "[assembly: System.Reflection.AssemblyVersion(`"$version4`")]`n[assembly: System.Reflection.AssemblyFileVersion(`"$version4`")]`n", (New-Object Text.UTF8Encoding $true))
try {
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu "/win32icon:$(Join-Path $icones 'Evermind.ico')" "/win32manifest:$manif" /reference:System.Windows.Forms.dll "/reference:$sma" "/out:$exe" $source $infos
    if ($LASTEXITCODE) { throw "Échec de compilation de $exe" }
} finally { Remove-Item -LiteralPath $infos -Force -ErrorAction SilentlyContinue }

# Le zip, dans release\ (pas suivi par git : outils\publier.ps1 le signe et le publie dans la Release GitHub,
# où Mindset le prend pour installer et mettre à jour Evermind)
$release = Join-Path $racine 'release'
New-Item -ItemType Directory -Force -Path $release | Out-Null
$zip = Join-Path $release 'Evermind.zip'
Compress-Archive -Path $app -DestinationPath $zip -Force
# Les clés publiques de la suite doivent être dans le zip : sans elles, Evermind refuse toutes ses mises à jour (modules\maj.ps1)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($zip)
try { $cle = @($z.Entries | Where-Object { $_.FullName.Replace('\', '/') -ilike 'Evermind/fichiers/cles-publiques/*.xml' }).Count } finally { $z.Dispose() }
if (-not $cle) { throw "Le zip ne contient pas Evermind\fichiers\cles-publiques (à copier depuis Mindset\fichiers)." }
"OK : $zip"
