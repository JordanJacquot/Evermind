# Construit le dossier d'Evermind prêt à partager, puis release\Evermind.zip.
# (Evermind doit être fermé : ses .exe sont remplacés.)
#
#   Evermind\
#     Evermind.exe                           <- à lancer (icône Evermind) : le relais, qui lance Mindset.exe
#     Mindset.exe                            <- le programme Evermind (nommé comme ceux de toute la suite : une seule
#                                               ligne « Mindset » dans le Gestionnaire des tâches)
#     LISEZMOI.txt                           <- installer et utiliser
#     fichiers\Evermind.ps1, Evermind.ico, lanceur de secours (.bat)
#     fichiers\cles-publiques\*.xml          <- vérifient la signature des mises à jour (les mêmes que Mindset)
#     fichiers\modules\                      <- le code découpé par partie
#
# Le zip vient de git, jamais du dossier tel qu'il est sur le disque : seulement les fichiers suivis, tels qu'ils sont
# dans l'index (ce qui va être commité : publier.ps1 y ajoute le numéro de version), plus les deux programmes construits
# ici. Un fichier ignoré ou oublié dans le dossier (un essai, un thème perso) ne part jamais dans la Release.
#
#   .\outils\construire.ps1                  release\Evermind.zip
#   .\outils\construire.ps1 -Zip <fichier>   (tests : un autre fichier)

param([string]$Zip = (Join-Path (Split-Path $PSScriptRoot -Parent) 'release\Evermind.zip'))
$ErrorActionPreference = 'Stop'
$racine  = Split-Path $PSScriptRoot -Parent
$app     = Join-Path $racine 'Evermind'
$fich    = Join-Path $app 'fichiers'
$icones  = Join-Path $PSScriptRoot 'icones'
$csc     = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$source  = Join-Path $PSScriptRoot 'lanceur.cs'
$relais  = Join-Path $PSScriptRoot 'relais.cs'
$manif   = Join-Path $PSScriptRoot 'lanceur.manifest'

& (Join-Path $PSScriptRoot 'icone.ps1') -OutDir $icones | Out-Null
Copy-Item (Join-Path $icones 'Evermind.ico') (Join-Path $fich 'Evermind.ico') -Force

$exe = Join-Path $app 'Mindset.exe'
$exeRelais = Join-Path $app 'Evermind.exe'
# Mindset.exe exécute le code lui même : il a besoin du moteur PowerShell de Windows
$sma = [psobject].Assembly.Location
# Les deux portent le numéro de version d'Evermind.ps1, ajouté à la compilation : publier.ps1 n'a qu'un numéro à changer, et
# la signature du code (SignPath) vérifie que l'exe a bien la version de l'appli
# (l'arbre de l'index : exactement les fichiers qui seront commités, et rien d'autre)
function Invoke-Git([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $sortie = & git -C $racine -c core.quotepath=off @Arguments
    if ($LASTEXITCODE) { throw "Échec : git $($Arguments -join ' ')" }
    $sortie
}
$arbre = ([string](Invoke-Git @('write-tree'))).Trim()
$ps1Git = (Invoke-Git @('show', "$($arbre):Evermind/fichiers/Evermind.ps1")) -join "`n"
$version = if ($ps1Git -match "(?m)^\`$AppVersion = '(\d+(\.\d+){1,3})'") { $Matches[1] } else { throw 'Numéro de version introuvable dans Evermind.ps1' }
$morceaux = @($version.Split('.')); while ($morceaux.Count -lt 4) { $morceaux += '0' }
$version4 = $morceaux -join '.'
$infos = Join-Path $env:TEMP "evermind-version-$PID.cs"
[IO.File]::WriteAllText($infos, "[assembly: System.Reflection.AssemblyVersion(`"$version4`")]`n[assembly: System.Reflection.AssemblyFileVersion(`"$version4`")]`n", (New-Object Text.UTF8Encoding $true))
try {
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu "/win32icon:$(Join-Path $icones 'Evermind.ico')" "/win32manifest:$manif" /reference:System.Windows.Forms.dll "/reference:$sma" "/out:$exe" $source $infos
    if ($LASTEXITCODE) { throw "Échec de compilation de $exe" }
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu "/win32icon:$(Join-Path $icones 'Evermind.ico')" "/win32manifest:$manif" /reference:System.Windows.Forms.dll "/out:$exeRelais" $relais $infos
    if ($LASTEXITCODE) { throw "Échec de compilation de $exeRelais" }
} finally { Remove-Item -LiteralPath $infos -Force -ErrorAction SilentlyContinue }

# Le zip, dans release\ (pas suivi par git : outils\publier.ps1 le signe et le publie dans la Release GitHub,
# où Mindset le prend pour installer et mettre à jour Evermind) : le dossier Evermind de l'index (git archive), puis les
# deux programmes
New-Item -ItemType Directory -Force -Path (Split-Path $Zip -Parent) | Out-Null
Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
Invoke-Git @('archive', '--format=zip', '-o', $Zip, $arbre, 'Evermind') | Out-Null
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::Open($Zip, 'Update')
try {
    foreach ($e in 'Mindset.exe', 'Evermind.exe') { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, (Join-Path $app $e), "Evermind/$e", 'Optimal') }
} finally { $z.Dispose() }

# Vérification : dans le zip, exactement les fichiers suivis par git sous Evermind\, et les deux programmes
$suivis = @(Invoke-Git @('ls-tree', '-r', '--name-only', $arbre, '--', 'Evermind') | Where-Object { $_ })
$z = [IO.Compression.ZipFile]::OpenRead($Zip)
try { $noms = @($z.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName.Replace('\', '/') }) } finally { $z.Dispose() }
$attendus = @($suivis) + 'Evermind/Mindset.exe', 'Evermind/Evermind.exe'
$diff = @(Compare-Object ($attendus | Sort-Object) ($noms | Sort-Object))
if ($diff.Count) { throw "Le zip n'a pas exactement les fichiers suivis par git : $(@($diff | ForEach-Object { $_.InputObject }) -join ', ')" }
# Les clés publiques de la suite doivent être dans le zip : sans elles, Evermind refuse toutes ses mises à jour (modules\maj.ps1)
$cle = @($noms | Where-Object { $_ -ilike 'Evermind/fichiers/cles-publiques/*.xml' }).Count
if (-not $cle) { throw "Le zip ne contient pas Evermind\fichiers\cles-publiques (à copier depuis Mindset\fichiers)." }
"OK : $Zip (arbre git $arbre)"
