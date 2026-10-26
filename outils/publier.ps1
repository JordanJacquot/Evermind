# Publie une nouvelle version d'Evermind sur GitHub, avec sa signature.
# Mindset la propose ensuite (il installe et met à jour Evermind à partir du zip signé de la Release).
#
#   .\outils\publier.ps1 -Version 0.12.0 -Notes "Ce qui change dans cette version"
#
# Avant de publier, le script vérifie la syntaxe de tous les fichiers, l'absence de tirets cadratins, les clés
# publiques (la même liste que Mindset), et lance le test automatique (outils\tester.ps1). -SansTest saute le test (urgence).
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

# Le zip est construit depuis git (construire.ps1) et seul le numéro de version est commité ici : tout le reste doit
# déjà être commité, sinon la Release ne serait pas ce que contient le dépôt
Push-Location $racine
try {
    $ErrorActionPreference = 'Continue'
    $enCours = @(git status --porcelain --untracked-files=no)
} finally { Pop-Location; $ErrorActionPreference = 'Stop' }
# (une publication arrêtée en route, par exemple un mot de passe mal tapé, laisse seulement le numéro de version écrit
# dans ces deux fichiers : on les remet comme dans git, ils sont réécrits juste après)
$siens = @('Evermind/fichiers/Evermind.ps1', 'Evermind/LISEZMOI.txt')
if ($enCours.Count -and -not @($enCours | Where-Object { $_ -notmatch '^(M |MM| M) ' -or $siens -notcontains $_.Substring(3).Trim('"') }).Count) {
    git -C $racine reset -q -- $siens[0] $siens[1] 2>$null   # (préparés pour le commit par une tentative arrêtée)
    git -C $racine checkout -- $siens[0] $siens[1] 2>$null
    Write-Host 'Le numéro de version laissé par une publication arrêtée en route est remis comme dans git.'
    $enCours = @()
}
if ($enCours.Count) { throw "Des changements ne sont pas commités : commite-les d'abord.`n$($enCours -join "`n")" }

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
# Clés publiques livrées avec Evermind : exactement la liste de Mindset (mêmes fichiers, même contenu), sinon les copies
# autonomes refuseraient une version signée avec une nouvelle clé, ou accepteraient encore une clé retirée
$cles = Join-Path $app 'fichiers\cles-publiques'
$clesMindset = Join-Path (Split-Path $racine -Parent) 'Mindset\Mindset\fichiers\cles-publiques'
function Get-EmpreinteCles([string]$Dossier) { @(Get-ChildItem -LiteralPath $Dossier -File -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join ';' }
$empreinte = Get-EmpreinteCles $cles
if (-not $empreinte -or $empreinte -ne (Get-EmpreinteCles $clesMindset)) {
    $problemes += "Clés publiques : Evermind\fichiers\cles-publiques absentes ou différentes de celles de Mindset ($clesMindset)"
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
# Le numéro de version est mis dans l'index : construire.ps1 prend les fichiers de l'index (git), exactement ce qui sera
# commité. signer.ps1 s'arrête sur une erreur s'il ne peut pas signer : la publication est alors annulée avant tout envoi.
$fichiersVersion = @('Evermind/fichiers/Evermind.ps1', 'Evermind/LISEZMOI.txt')
Push-Location $racine
try { Invoke-Native git (@('add', '--') + $fichiersVersion) } finally { Pop-Location }
$construit = @(& (Join-Path $PSScriptRoot 'construire.ps1'))
$arbreZip = if ("$($construit[-1])" -match 'arbre git ([0-9a-f]{40})') { $Matches[1] } else { throw 'Publication annulée : construire.ps1 n''a pas dit de quel état de git vient le zip.' }
Remove-Item -LiteralPath "$zip.sig" -ErrorAction SilentlyContinue   # jamais l'ancienne signature d'un autre zip
& (Join-Path (Split-Path $racine -Parent) 'Mindset\outils\signer.ps1') -Fichier $zip
if (-not (Test-Path -LiteralPath "$zip.sig")) { throw 'Publication annulée : le zip n''a pas pu être signé.' }

# 3. Envoi sur GitHub et création de la version. Le zip et sa signature ne sont pas dans le dépôt (release\ est ignoré par git) :
#    ils sont seulement joints à la Release.
Push-Location $racine
try {
    # (seulement le numéro de version, déjà dans l'index : jamais un fichier qui traîne)
    Invoke-Native git (@('commit', '-m', "Evermind $Version", '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>', '--') + $fichiersVersion)
    $arbreCommit = ([string](git rev-parse 'HEAD^{tree}')).Trim()
    if ($arbreCommit -ne $arbreZip) { throw "Publication annulée : le commit ($arbreCommit) n'est pas l'état de git du zip ($arbreZip). Rien n'a été envoyé." }
    Invoke-Native git @('tag', "v$Version")
    Invoke-Native git @('push', 'origin', 'HEAD', '--tags')
    if (-not $Notes) { $Notes = "Evermind $Version" }
    Invoke-Native gh @('release', 'create', "v$Version", $zip, "$zip.sig", '--title', "Evermind $Version", '--notes', $Notes)
} finally { Pop-Location }
"Version $Version publiée."
