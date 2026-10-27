# Vérifie la mise à jour en un clic d'une copie autonome d'Evermind, sans Internet ni vraie clé (une clé de test) :
#   1. la version écrite DANS le zip est contrôlée : illisible, différente de celle annoncée ou pas plus récente que
#      celle d'ici, la mise à jour est refusée (un ancien zip bien signé ne fait pas revenir une vieille version) ;
#   1b. mêmes règles que Mindset : une clé publique qui contient un élément de clé privée (même vide, préfixé ou caché
#      dans un sous-élément) ou sans Modulus est refusée ; un zip signé mais abîmé (taille ou CRC) ou avec une entrée
#      chiffrée est refusé (contre-épreuve : .NET seul les acceptait) ;
#   2. le remplacement des fichiers : l'ancien dossier est mis de côté puis remis si la copie échoue (jamais un
#      mélange des deux versions), la liste des clés est exactement la nouvelle.
# Rien ne touche au vrai Evermind : tout se passe dans _test\maj.
#
#   .\outils\tester-maj.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$test = Join-Path $racine '_test\maj'
Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $test | Out-Null
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}

# Les fonctions d'Evermind sont prises telles quelles dans maj.ps1 (sans charger toute l'appli)
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $modules 'maj.ps1'), [ref]$null, [ref]$null)
foreach ($n in 'Test-Signature', 'Test-VersionPlusRecente', 'Get-RefusVersionZip', 'Expand-ZipMaj', 'Start-MajTelechargement', 'Get-CodeRemplacement') {
    $f = $ast.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $n }, $true)
    if (-not $f) { Test-Cas "maj.ps1 : $n existe" $false; continue }
    . ([scriptblock]::Create($f.Extent.Text))
}
function Write-Log([string]$t) { }
function Start-MajSuivi { }

# Une clé de test (jamais celle de Jordan) et des zips signés avec elle
$cles = Join-Path $test 'cles'; New-Item -ItemType Directory -Force $cles | Out-Null
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 3072
[IO.File]::WriteAllText((Join-Path $cles 'test.xml'), $rsa.ToXmlString($false))
function New-ZipTest([string]$Nom, [string]$Version, [string]$Cle = 'neuve.xml') {
    $d = Join-Path $test "src-$Nom"
    New-Item -ItemType Directory -Force (Join-Path $d 'Evermind\fichiers\cles-publiques') | Out-Null
    [IO.File]::WriteAllText((Join-Path $d 'Evermind\Evermind.exe'), 'faux programme')
    [IO.File]::WriteAllText((Join-Path $d 'Evermind\Mindset.exe'), 'nouveau programme')
    [IO.File]::WriteAllText((Join-Path $d 'Evermind\LISEZMOI.txt'), 'nouveau lisezmoi')
    $ligne = if ($Version) { "`$AppVersion = '$Version'" } else { '# (pas de version)' }
    [IO.File]::WriteAllText((Join-Path $d 'Evermind\fichiers\Evermind.ps1'), "# Evermind de test`r`n$ligne`r`n", (New-Object Text.UTF8Encoding $true))
    [IO.File]::WriteAllText((Join-Path $d "Evermind\fichiers\cles-publiques\$Cle"), '<RSAKeyValue/>')
    $zip = Join-Path $test "$Nom.zip"
    [IO.Compression.ZipFile]::CreateFromDirectory($d, $zip)
    $octets = [IO.File]::ReadAllBytes($zip)
    [IO.File]::WriteAllBytes("$zip.sig", $rsa.SignData($octets, [System.Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')))
    $zip
}
function Invoke-Expand([string]$Zip, [string]$Annoncee, [string]$Ici = '0.17.0', [byte[]]$Sig = $null) {
    $dest = Join-Path $test ("x-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $dest | Out-Null
    if (-not $Sig) { $Sig = [IO.File]::ReadAllBytes("$Zip.sig") }
    Expand-ZipMaj ([IO.File]::ReadAllBytes($Zip)) $Sig $cles $dest $Annoncee $Ici
}

# ---------------------------------------------------------------------------
# 1. Version écrite dans le zip (constat 8)
# ---------------------------------------------------------------------------
$z18 = New-ZipTest 'v18' '0.18.0'
$z16 = New-ZipTest 'v16' '0.16.0' 'vieille.xml'
$z17 = New-ZipTest 'v17' '0.17.0'
$zSans = New-ZipTest 'sans' ''
$x = Invoke-Expand $z18 '0.18.0'
Test-Cas 'version plus récente, comme annoncée : acceptée' ($x.Dossier -and -not $x.Refus -and -not $x.Erreur) "($($x.Erreur))"
$x = Invoke-Expand $z16 '0.18.0'
Test-Cas 'ancien zip signé republié sous un nouveau numéro : refusé' ($x.Refus -and -not $x.Dossier -and $x.Erreur -match '0\.18\.0.*0\.16\.0') "($($x.Erreur))"
$x = Invoke-Expand $z16 '0.16.0'
Test-Cas 'version plus ancienne : refusée' ($x.Refus -and $x.Erreur -match 'pas plus récente') "($($x.Erreur))"
$x = Invoke-Expand $z17 '0.17.0'
Test-Cas 'même version : refusée' ($x.Refus -and $x.Erreur -match 'pas plus récente') "($($x.Erreur))"
$x = Invoke-Expand $zSans '0.18.0'
Test-Cas 'version illisible : refusée' ($x.Refus -and $x.Erreur -match 'illisible') "($($x.Erreur))"
$x = Invoke-Expand $z18 '0.18.0' '0.17.0' ([byte[]](1, 2, 3))
Test-Cas 'signature fausse : refusée' ($x.Refus -and $x.Erreur -match 'signature') "($($x.Erreur))"

# ---------------------------------------------------------------------------
# 1b. Clés et zips : les mêmes règles que Mindset (signature.ps1 et paquets.ps1)
# ---------------------------------------------------------------------------
$octets18 = [IO.File]::ReadAllBytes($z18); $sig18 = [IO.File]::ReadAllBytes("$z18.sig")
$publique = $rsa.ToXmlString($false)
function Test-Cle([string]$Xml) {
    $f = Join-Path $test ("cle-" + [guid]::NewGuid().ToString('N') + '.xml')
    [IO.File]::WriteAllText($f, $Xml)
    Test-Signature $octets18 $sig18 $f
}
Test-Cas 'clé publique seule : la bonne signature est acceptée' (Test-Cle $publique)
foreach ($ajout in '<D>AQAB</D>', '<P></P>', '<Q/>', '<DP>AQAB</DP>', '<DQ>AQAB</DQ>', '<InverseQ>AQAB</InverseQ>', '<x:D xmlns:x="urn:essai">AQAB</x:D>', '<Autre><InverseQ>AQAB</InverseQ></Autre>') {
    $xml = $publique.Replace('</RSAKeyValue>', "$ajout</RSAKeyValue>")
    # (contre-épreuve : .NET seul la prend pour une clé publique)
    $r = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $publiqueSelonNet = $false
    try { $r.FromXmlString($xml); $publiqueSelonNet = $r.PublicOnly } catch {} finally { $r.Dispose() }
    Test-Cas "clé avec un élément privé $ajout : refusée (.NET seul : publique $publiqueSelonNet)" (-not (Test-Cle $xml))
}
Test-Cas 'clé sans Modulus : refusée' (-not (Test-Cle ([regex]::Replace($publique, '<Modulus>.*</Modulus>', ''))))
Test-Cas 'clé sans Exponent : refusée' (-not (Test-Cle ([regex]::Replace($publique, '<Exponent>.*</Exponent>', ''))))

# Zips signés, trafiqués dans leurs en-têtes (répertoire central et en-tête local) puis signés de nouveau
function New-ZipTrafique([string]$Nom, [scriptblock]$Changer) {
    $o = [IO.File]::ReadAllBytes($z18)
    for ($i = 0; $i -le $o.Length - 46; $i++) {
        if ([BitConverter]::ToUInt32($o, $i) -ne 0x02014b50) { continue }
        $nomEntree = [Text.Encoding]::UTF8.GetString($o, $i + 46, [BitConverter]::ToUInt16($o, $i + 28)).Replace('\', '/')
        if ($nomEntree -eq 'Evermind/fichiers/Evermind.ps1') { & $Changer $o $i ([int][BitConverter]::ToUInt32($o, $i + 42)) }
    }
    $zip = Join-Path $test "$Nom.zip"
    [IO.File]::WriteAllBytes($zip, $o)
    [IO.File]::WriteAllBytes("$zip.sig", $rsa.SignData($o, [System.Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')))
    $zip
}
function Set-Taille([byte[]]$o, [int]$c, [int]$l, [uint32]$Taille) { [BitConverter]::GetBytes($Taille).CopyTo($o, $c + 24); [BitConverter]::GetBytes($Taille).CopyTo($o, $l + 22) }
$zChiffre = New-ZipTrafique 'chiffre' { param($o, $c, $l) $o[$c + 8] = $o[$c + 8] -bor 1; $o[$l + 6] = $o[$l + 6] -bor 1 }
$zLong = New-ZipTrafique 'plus-long' { param($o, $c, $l) Set-Taille $o $c $l 3 }
$zCourtCrc = New-ZipTrafique 'plus-court-crc' { param($o, $c, $l) Set-Taille $o $c $l 100000; $o[$c + 16] = $o[$c + 16] -bxor 0xFF; $o[$l + 14] = $o[$l + 14] -bxor 0xFF }
$zCourt = New-ZipTrafique 'plus-court' { param($o, $c, $l) Set-Taille $o $c $l 100000 }
$zCrc = New-ZipTrafique 'crc' { param($o, $c, $l) $o[$c + 16] = $o[$c + 16] -bxor 0xFF; $o[$l + 14] = $o[$l + 14] -bxor 0xFF }
$zDeflate = New-ZipTrafique 'deflate' { param($o, $c, $l) $debut = $l + 30 + [BitConverter]::ToUInt16($o, $l + 26) + [BitConverter]::ToUInt16($o, $l + 28); for ($k = 2; $k -lt 12; $k++) { $o[$debut + $k] = $o[$debut + $k] -bxor 0x5A } }
function Test-NetSeul([string]$Zip) {   # (contre-épreuve : ce que faisait ExtractToDirectory)
    $d = Join-Path $test ("net-" + [guid]::NewGuid().ToString('N'))
    try { [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $d); $true } catch { $false }
}
# (contre-épreuve sur les quatre premiers : .NET seul les dézippait sans rien dire)
foreach ($cas in @(@($zChiffre, 'entrée chiffrée', 'chiffré', $true), @($zLong, 'fichier plus long que la taille annoncée', 'abîmé', $true), @($zCourtCrc, 'fichier plus court que la taille annoncée et CRC faux', 'abîmé', $true), @($zCrc, 'CRC faux, bonne taille', 'abîmé', $true), @($zCourt, 'taille annoncée trop grande, CRC juste', 'abîmé', $false), @($zDeflate, 'contenu compressé abîmé', 'abîmé', $false))) {
    $netSeul = Test-NetSeul $cas[0]
    $x = Invoke-Expand $cas[0] '0.18.0'
    Test-Cas "zip signé, $($cas[1]) : refusé (.NET seul l'acceptait : $netSeul)" (($netSeul -or -not $cas[3]) -and $x.Refus -and -not $x.Dossier -and $x.Erreur -match $cas[2]) "($($x.Erreur))"
}
$zIllisible = Join-Path $test 'illisible.zip'; [IO.File]::WriteAllBytes($zIllisible, [byte[]](1..200))
[IO.File]::WriteAllBytes("$zIllisible.sig", $rsa.SignData([byte[]](1..200), [System.Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')))
$x = Invoke-Expand $zIllisible '0.18.0'
Test-Cas 'zip signé mais illisible : refusé comme abîmé' ($x.Refus -and $x.Erreur -match 'abîmé') "($($x.Erreur))"

# Le vrai téléchargement en arrière plan (Start-MajTelechargement), avec un zip local : le refus arrive bien jusque-là
$ui = @{ MajTexte = [pscustomobject]@{ Text = '' }; BtnMaj = [pscustomobject]@{ IsEnabled = $true }; BtnMajPlusTard = [pscustomobject]@{ Visibility = '' } }
$DossierTravail = $null; $GereParMindset = $false; $AppVersion = '0.17.0'
$MajDossier = Join-Path $test 'telechargements'; $ClePublique = $cles
function Invoke-Telechargement([string]$Zip, [string]$Annoncee) {
    $script:Maj = [hashtable]::Synchronized(@{ Etat = 'dispo'; Version = $Annoncee; Url = $Zip; UrlSig = "$Zip.sig"; Digest = ''; Page = ''; Erreur = ''; Refus = $false; Recu = 0L; Total = 0L; Dossier = '' })
    Start-MajTelechargement
    $limite = (Get-Date).AddSeconds(60)
    while ($script:Maj.Etat -eq 'telecharge' -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 100 }
    $script:Maj
}
$m = Invoke-Telechargement $z18 '0.18.0'
Test-Cas 'téléchargement : une version plus récente est prête' ($m.Etat -eq 'pret' -and (Test-Path -LiteralPath (Join-Path $m.Dossier 'fichiers\Evermind.ps1'))) "($($m.Etat) : $($m.Erreur))"
$m = Invoke-Telechargement $z16 '0.18.0'
Test-Cas 'téléchargement : l''ancien zip est refusé, rien ne reste' ($m.Etat -eq 'erreur' -and $m.Refus -and -not (Test-Path -LiteralPath (Join-Path $MajDossier '0.18.0'))) "($($m.Etat) : $($m.Erreur))"

# ---------------------------------------------------------------------------
# 2. Remplacement des fichiers (constat 9)
# ---------------------------------------------------------------------------
$remplacer = Join-Path $test 'remplacer.ps1'
[IO.File]::WriteAllText($remplacer, (Get-CodeRemplacement), (New-Object Text.UTF8Encoding $true))
$journal = Join-Path $test 'journal.txt'
function New-Installe([string]$Nom) {
    $c = Join-Path $test "installe-$Nom"
    New-Item -ItemType Directory -Force (Join-Path $c 'fichiers\cles-publiques') | Out-Null
    [IO.File]::WriteAllText((Join-Path $c 'Evermind.exe'), 'ancien programme')
    [IO.File]::WriteAllText((Join-Path $c 'LISEZMOI.txt'), 'ancien lisezmoi')   # (pas de Mindset.exe : une ancienne version)
    [IO.File]::WriteAllText((Join-Path $c 'fichiers\Evermind.ps1'), "`$AppVersion = '0.17.0'`r`n")
    [IO.File]::WriteAllText((Join-Path $c 'fichiers\ancien-seulement.txt'), 'ancien')
    [IO.File]::WriteAllText((Join-Path $c 'fichiers\cles-publiques\vieille.xml'), '<RSAKeyValue/>')
    $c
}
function Invoke-Remplacer([string]$Source, [string]$Cible) {
    $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$remplacer`"", '-Attendre', '999999', '-Source', "`"$Source`"", '-Cible', "`"$Cible`"", '-Journal', "`"$journal`"", '-PasDeRelance' -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(120000)) { $p.Kill() }
}
$src18 = Join-Path $test 'src-v18\Evermind'
# Tout va bien : la nouvelle version, exactement (rien de l'ancienne ne traîne), la nouvelle liste de clés
$c1 = New-Installe 'ok'
Invoke-Remplacer $src18 $c1
$v1 = [IO.File]::ReadAllText((Join-Path $c1 'fichiers\Evermind.ps1'))
Test-Cas 'remplacement : nouvelle version en place' ($v1 -match "0\.18\.0" -and -not (Test-Path -LiteralPath (Join-Path $c1 'fichiers.ancien'))) "($v1)"
Test-Cas 'remplacement : rien de l''ancienne version ne traîne' (-not (Test-Path -LiteralPath (Join-Path $c1 'fichiers\ancien-seulement.txt')))
Test-Cas 'remplacement : la liste des clés est la nouvelle' (@(Get-ChildItem -LiteralPath (Join-Path $c1 'fichiers\cles-publiques') | ForEach-Object Name) -join ',' -eq 'neuve.xml')
Test-Cas 'remplacement : les programmes et le LISEZMOI sont les nouveaux' ([IO.File]::ReadAllText((Join-Path $c1 'Evermind.exe')) -eq 'faux programme' -and [IO.File]::ReadAllText((Join-Path $c1 'Mindset.exe')) -eq 'nouveau programme' -and [IO.File]::ReadAllText((Join-Path $c1 'LISEZMOI.txt')) -eq 'nouveau lisezmoi')
Test-Cas 'remplacement : aucun dossier de côté oublié' (-not @(Get-ChildItem -LiteralPath $c1 -Directory | Where-Object { $_.Name -ne 'fichiers' }).Count) "($(@(Get-ChildItem -LiteralPath $c1 -Directory).Name -join ', '))"
# La copie échoue (un fichier de la nouvelle version reste pris) : l'ancienne version est remise telle quelle
$c2 = New-Installe 'rate'
$pris = Join-Path $src18 'fichiers\pris.txt'; [IO.File]::WriteAllText($pris, 'pris')
$verrou = [IO.File]::Open($pris, 'Open', 'Read', 'None')
try { Invoke-Remplacer $src18 $c2 } finally { $verrou.Dispose(); Remove-Item -LiteralPath $pris -Force }
$v2 = [IO.File]::ReadAllText((Join-Path $c2 'fichiers\Evermind.ps1'))
Test-Cas 'copie ratée : l''ancienne version remise, sans mélange' ($v2 -match "0\.17\.0" -and (Test-Path -LiteralPath (Join-Path $c2 'fichiers\ancien-seulement.txt')) -and (Test-Path -LiteralPath (Join-Path $c2 'fichiers\cles-publiques\vieille.xml')) -and -not (Test-Path -LiteralPath (Join-Path $c2 'fichiers\cles-publiques\neuve.xml'))) "($v2)"
Test-Cas 'copie ratée : aucun dossier de côté oublié' (-not @(Get-ChildItem -LiteralPath $c2 -Directory | Where-Object { $_.Name -ne 'fichiers' }).Count) "($(@(Get-ChildItem -LiteralPath $c2 -Directory).Name -join ', '))"
Test-Cas 'copie ratée : noté au journal' ((Test-Path -LiteralPath $journal) -and [IO.File]::ReadAllText($journal) -match 'ancienne version remise')
# Audit du 25/10, 25h : les fichiers à côté de « fichiers » sont remis aussi (jamais un nouvel Evermind.exe avec l'ancien code)
Test-Cas 'copie ratée : Evermind.exe et LISEZMOI.txt anciens, le nouveau Mindset.exe retiré' ([IO.File]::ReadAllText((Join-Path $c2 'Evermind.exe')) -eq 'ancien programme' -and [IO.File]::ReadAllText((Join-Path $c2 'LISEZMOI.txt')) -eq 'ancien lisezmoi' -and -not (Test-Path -LiteralPath (Join-Path $c2 'Mindset.exe'))) "($([IO.File]::ReadAllText((Join-Path $c2 'Evermind.exe'))) / $([IO.File]::ReadAllText((Join-Path $c2 'LISEZMOI.txt'))) / Mindset.exe $(Test-Path -LiteralPath (Join-Path $c2 'Mindset.exe')))"
# L'ancien dossier « fichiers » ne peut pas être mis de côté (un de ses fichiers est pris) : rien n'est remplacé
$c3 = New-Installe 'pris'
$verrou = [IO.File]::Open((Join-Path $c3 'fichiers\ancien-seulement.txt'), 'Open', 'Read', 'None')
try { Invoke-Remplacer $src18 $c3 } finally { $verrou.Dispose() }
$v3 = [IO.File]::ReadAllText((Join-Path $c3 'fichiers\Evermind.ps1'))
Test-Cas 'ancien dossier pris : rien n''est remplacé' ($v3 -match '0\.17\.0' -and [IO.File]::ReadAllText((Join-Path $c3 'Evermind.exe')) -eq 'ancien programme' -and [IO.File]::ReadAllText((Join-Path $c3 'LISEZMOI.txt')) -eq 'ancien lisezmoi' -and -not (Test-Path -LiteralPath (Join-Path $c3 'Mindset.exe'))) "($v3 / $([IO.File]::ReadAllText((Join-Path $c3 'Evermind.exe'))))"
Test-Cas 'ancien dossier pris : aucun dossier de côté oublié' (-not @(Get-ChildItem -LiteralPath $c3 -Directory | Where-Object { $_.Name -ne 'fichiers' }).Count) "($(@(Get-ChildItem -LiteralPath $c3 -Directory).Name -join ', '))"

$rsa.Dispose()
Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
exit $(if ($ok) { 0 } else { 1 })
