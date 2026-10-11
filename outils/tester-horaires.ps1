# Vérifie les horaires de travail en postes : « je suis du matin lundi et mardi », « boulot lundi matin, mardi journée
# et mercredi soir », « de nuit toute la semaine prochaine »... (jours, postes, heures, rien en double).
#
#   .\outils\tester-horaires.ps1
#
# Code de sortie : 0 si tout va bien, 1 sinon.
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$Fr = [Globalization.CultureInfo]'fr-FR'
$EnTest = $true
$env:EVERMIND_DONNEES = Join-Path $racine '_test\horaires'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
foreach ($m in 'donnees', 'comprendre') { . (Join-Path $modules "$m.ps1") }

$ok = $true
function Test-Cas([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom  $Detail" -ForegroundColor Red; $script:ok = $false }
}
# Un jour fixe pour tout le test : dimanche 11 octobre 2026 à 10 h
$n = [datetime]'2026-10-11 10:00'
function Get-Postes([string]$Texte) {
    @(Get-HorairesTravail $Texte $n | ForEach-Object {
        $p = Read-Phrase $_.Phrase $n
        "$($_.Creneau) $($p.Quand.ToString('ddd dd HH:mm', $Fr)) $($p.Fin.ToString('ddd dd HH:mm', $Fr))$(if ($p.Repetition) { ' rep' })"
    })
}
$cas = @(
    , @('je suis du matin lundi', 'matin lun. 12 06:00 lun. 12 14:00')
    , @('je suis du matin lundi et mardi', 'matin lun. 12 06:00 lun. 12 14:00|matin mar. 13 06:00 mar. 13 14:00')
    , @('boulot lundi matin, mardi journée et mercredi soir', 'matin lun. 12 06:00 lun. 12 14:00|journee mar. 13 08:00 mar. 13 17:00|soir mer. 14 14:00 mer. 14 22:00')
    , @('travail lundi et mardi matin, jeudi soir', 'matin lun. 12 06:00 lun. 12 14:00|matin mar. 13 06:00 mar. 13 14:00|soir jeu. 15 14:00 jeu. 15 22:00')
    , @('je travaille de nuit toute la semaine prochaine', 'nuit lun. 12 22:00 mar. 13 06:00|nuit mar. 13 22:00 mer. 14 06:00|nuit mer. 14 22:00 jeu. 15 06:00|nuit jeu. 15 22:00 ven. 16 06:00|nuit ven. 16 22:00 sam. 17 06:00')
    , @('je suis du soir du lundi au mercredi', 'soir lun. 12 14:00 lun. 12 22:00|soir mar. 13 14:00 mar. 13 22:00|soir mer. 14 14:00 mer. 14 22:00')
    , @('travail du matin du lundi au mardi puis de nuit jeudi', 'matin lun. 12 06:00 lun. 12 14:00|matin mar. 13 06:00 mar. 13 14:00|nuit jeu. 15 22:00 ven. 16 06:00')
    , @('mets mes horaires : lundi matin, mardi soir', 'matin lun. 12 06:00 lun. 12 14:00|soir mar. 13 14:00 mar. 13 22:00')
    , @('poste du soir tous les jeudis', 'soir jeu. 15 14:00 jeu. 15 22:00 rep')
    , @('équipe du matin le 20 octobre', 'matin mar. 20 06:00 mar. 20 14:00')
    , @('je bosse l''après-midi demain', 'apresmidi lun. 12 14:00 lun. 12 22:00')
)
foreach ($c in $cas) {
    $vu = (Get-Postes $c[0]) -join '|'
    Test-Cas "« $($c[0]) »" ($vu -eq $c[1]) "`n         attendu : $($c[1])`n         obtenu  : $vu"
}
# Ce qui n'est pas un planning : lecture habituelle
foreach ($t in 'dentiste mardi matin', 'travail lundi de 6 h à 14 h', 'je fais les courses demain matin') {
    Test-Cas "pas un planning : « $t »" (-not (Get-HorairesTravail $t $n))
}
# Des heures réglées à la main
$script:Settings = @{ Horaires = @{ matin = '5 h à 13 h' } }
Test-Cas 'heures du poste réglées (5 h à 13 h)' (((Get-Postes 'je suis du matin lundi') -join '|') -eq 'matin lun. 12 05:00 lun. 12 13:00') "($((Get-Postes 'je suis du matin lundi') -join '|'))"

exit $(if ($ok) { 0 } else { 1 })
