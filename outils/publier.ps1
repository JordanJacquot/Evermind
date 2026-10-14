# Publie une nouvelle version d'Evermind sur GitHub, avec sa signature.
# Les Evermind déjà installés la proposent ensuite (bandeau « Mettre à jour », modules\maj.ps1), et Mindset aussi.
#
#   .\outils\publier.ps1 -Version 0.12.0 -Notes "Ce qui change dans cette version"
#
# Avant de publier, le script vérifie la syntaxe de tous les fichiers, l'absence de tirets cadratins, la clé
# publique, et lance le test automatique (outils\tester.ps1). -SansTest saute le test (urgence).
# Le zip est signé avec la clé de la suite (Mindset\outils\signer.ps1) : sans signature, rien n'est publié.
# (Evermind doit être fermé : construire.ps1 remplace son .exe.)

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Notes = '',
    [switch]$SansTest
)
$ErrorActionPreference = 'Stop'
$racine = Split-Path $PSScriptRoot -Parent
$app    = Join-Path $racine 'Evermind'
$ps1    = Join-Path $app 'fichiers\Evermind.ps1'
$lisez  = Join-Path $app 'LISEZMOI.txt'
$zip    = Join-Path $racine 'release\Evermind.zip'
$utf8   = New-Object Text.UTF8Encoding($true)

if ($Version -notmatch '^\d+\.\d+(\.\d+)?$') { throw "Numéro de version invalide : $Version (exemple : 0.12.0)" }

# Un numéro déjà publié ne doit jamais être réutilisé : GitHub garde l'ancien zip en cache.
Push-Location $racine
try {
    $ErrorActionPreference = 'Continue'   # « introuvable » est la réponse attendue ici, pas une erreur
    git rev-parse -q --verify "refs/tags/v$Version" 2>$null | Out-Null
    $tagExiste = ($LASTEXITCODE -eq 0)
    gh release view "v$Version" 2>$null | Out-Null
    $releaseExiste = ($LASTEXITCODE -eq 0)
} finally { Pop-Location; $ErrorActionPreference = 'Stop' }
if ($tagExiste -or $releaseExiste) { throw "La version $Version existe déjà. Choisis un numéro plus grand (exemple : 0.11.1 ou 0.12.0)." }

# Vérifications : syntaxe, fenêtre, tirets cadratins, clé publique, puis test automatique de l'app
$problemes = @()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $app 'fichiers') -Recurse -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')) {
    $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$err)
    foreach ($e in $err) { $problemes += "Syntaxe : $($f.Name) ligne $($e.Extent.StartLineNumber) : $($e.Message)" }
}
try { [void][xml][IO.File]::ReadAllText((Join-Path $app 'fichiers\modules\interface.xaml'), [Text.Encoding]::UTF8) } catch { $problemes += "interface.xaml : $($_.Exception.Message)" }
$tirets = Get-ChildItem -LiteralPath $racine -Recurse -File -Include '*.ps1', '*.cs', '*.xaml', '*.txt', '*.md', '*.bat' |
    Where-Object { $_.FullName -notmatch '\\(\.git|_test)\\' } | Select-String -Pattern '[\u2013\u2014]'
foreach ($t in $tirets) { $problemes += "Tiret cadratin : $($t.Path) ligne $($t.LineNumber)" }
# Clé publique livrée avec Evermind : la même que celle de Mindset, sinon les copies autonomes refuseraient la mise à jour
$cle = Join-Path $app 'fichiers\cle-publique.xml'
$cleMindset = Join-Path (Split-Path $racine -Parent) 'Mindset\Mindset\fichiers\cle-publique.xml'
if (-not (Test-Path -LiteralPath $cle) -or -not (Test-Path -LiteralPath $cleMindset) -or (Get-FileHash -LiteralPath $cle).Hash -ne (Get-FileHash -LiteralPath $cleMindset).Hash) {
    $problemes += "Clé publique : Evermind\fichiers\cle-publique.xml absente ou différente de celle de Mindset ($cleMindset)"
}
if ($problemes) {
    $problemes | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw 'Publication annulée : corrige les points ci dessus.'
}
if (-not $SansTest) {
    & (Join-Path $PSScriptRoot 'tester.ps1')
    if ($LASTEXITCODE) { throw 'Publication annulée : le test automatique a échoué.' }
}

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE) { throw "Échec : $Exe $($Arguments -join ' ')" }
}

# 1. Numéro de version dans l'app (et dans l'en-tête), et dans le LISEZMOI s'il y figure
$c = [IO.File]::ReadAllText($ps1, [Text.Encoding]::UTF8)
$c = [regex]::Replace($c, "(?m)^\`$AppVersion = '[^']*'", "`$AppVersion = '$Version'")
$c = [regex]::Replace($c, '(?m)^    Evermind [\d\.]+\r?$', "    Evermind $Version`r")
[IO.File]::WriteAllText($ps1, $c, $utf8)
$l = [IO.File]::ReadAllText($lisez, [Text.Encoding]::UTF8)
$l2 = [regex]::Replace($l, '(?i)^(Evermind) [\d\.]+', "`$1 $Version")
if ($l2 -ne $l) { [IO.File]::WriteAllText($lisez, $l2, $utf8) }

# 2. Construction du .exe et du zip, puis sa signature (Mindset et Evermind refusent un zip sans signature valide).
# signer.ps1 s'arrête sur une erreur s'il ne peut pas signer : la publication est alors annulée avant tout envoi.
& (Join-Path $PSScriptRoot 'construire.ps1')
Remove-Item -LiteralPath "$zip.sig" -ErrorAction SilentlyContinue   # jamais l'ancienne signature d'un autre zip
& (Join-Path (Split-Path $racine -Parent) 'Mindset\outils\signer.ps1') -Fichier $zip
if (-not (Test-Path -LiteralPath "$zip.sig")) { throw 'Publication annulée : le zip n''a pas pu être signé.' }

# 3. Envoi sur GitHub et création de la version (le zip et sa signature)
Push-Location $racine
try {
    Invoke-Native git @('add', '-A')
    Invoke-Native git @('commit', '-m', "Evermind $Version", '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')
    Invoke-Native git @('tag', "v$Version")
    Invoke-Native git @('push', 'origin', 'HEAD', '--tags')
    if (-not $Notes) { $Notes = "Evermind $Version" }
    Invoke-Native gh @('release', 'create', "v$Version", $zip, "$zip.sig", '--title', "Evermind $Version", '--notes', $Notes)
} finally { Pop-Location }
"Version $Version publiée."
