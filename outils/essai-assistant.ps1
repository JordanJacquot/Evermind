# Evermind : essai de l'assistant (celui d'Evermind Mobile) par le même chemin que l'appli. Le pack « ia » est
# installé dans un dossier de test s'il n'y est pas encore (vrais téléchargements, empreintes vérifiées), puis
# quelques demandes passent par Invoke-Commande et Step-Demande, sur l'agenda d'exemple des tests.
#
#   .\outils\essai-assistant.ps1 [-Voix <dossier de test>] [-Phrases <phrase>, <phrase>...]
#
# Code de sortie : 0 si tout a répondu, 1 sinon.
param([string]$Voix = (Join-Path (Split-Path $PSScriptRoot -Parent) '_test\voix-assistant'),
      [string[]]$Phrases = @('Décale le dentiste à jeudi 17 h', 'Annule', 'Qu''est-ce que j''ai demain ?',
                             'euh du coup je voudrais que tu me mettes un rendez-vous chez le coiffeur vendredi à onze heures avec ma sœur Julie',
                             'Ajoute Paul au coiffeur', 'Supprime le coiffeur'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$env:EVERMIND_VOIX = $Voix
$env:EVERMIND_TEST = '1'
$env:EVERMIND_DONNEES = Join-Path $racine '_test\essai-assistant'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
$exemple = Join-Path $racine '_test\donnees-agenda\rendez-vous.json'
if (Test-Path $exemple) { Copy-Item $exemple (Join-Path $env:EVERMIND_DONNEES 'rendez-vous.json') }
$Fr = [Globalization.CultureInfo]'fr-FR'
$EnTest = $true   # rien n'est ouvert ni effacé sur le PC
foreach ($m in 'donnees', 'fichiers', 'comprendre', 'agenda', 'details', 'voix', 'cerveau') { . (Join-Path $modules "$m.ps1") }

# Sans fenêtre : ce qu'Evermind dirait ou montrerait est seulement retenu
$script:Dit = ''; $script:Montre = ''
function Invoke-Parole([string]$Texte) { $script:Dit = $Texte }
function Show-FormMessage([string]$Texte) { $script:Montre = $Texte }
function Show-Notify { }
function Show-Bulle { }
function Set-VoixEtat { }
function Show-MainWindow { }
function Update-Agenda { }
function Update-VoixInstall { }
function Invoke-DicteeRegles([string]$Texte) { $script:Montre = "(règles du PC) $Texte" }
$ui = @{ InPhrase = New-Object System.Windows.Controls.TextBox }

if (-not (Test-CerveauInstalle)) {
    Write-Host "Installation du pack « ia » dans $Voix..."
    Start-VoixInstall 'ia'
    while (-not $script:VoixDl.Fini) { Start-Sleep -Seconds 2; Write-Host ("  {0} : {1:N0} / {2:N0} Mo" -f $script:VoixDl.Etape, ($script:VoixDl.Recu / 1MB), ($script:VoixDl.Total / 1MB)) }
    if ($script:VoixDl.Erreur) { throw "installation : $($script:VoixDl.Erreur)" }
    if (-not (Test-CerveauInstalle)) { throw 'installation : des fichiers manquent encore' }
}
Import-Agenda
$rates = 0
foreach ($p in $Phrases) {
    $script:Dit = ''; $script:Montre = ''
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    if (-not (Invoke-Commande $p 'test')) { Write-Host "« $p » -> assistant absent"; $rates++; continue }
    while ($script:Demande) { Start-Sleep -Milliseconds 100; Step-Demande }
    Write-Host ("« {0} » ({1:N1} s) -> {2}" -f $p, $chrono.Elapsed.TotalSeconds, $script:Montre)
    if (-not $script:Montre) { $rates++ }
}
Write-Host "--- agenda :"
foreach ($r in $script:Agenda) { Write-Host ("  {0} | {1:yyyy-MM-dd HH:mm} | avec : {2}" -f $r.Titre, $r.Quand, ($r.Avec -join ', ')) }
Stop-Cerveau
$journal = Join-Path $env:EVERMIND_DONNEES 'assistant.log'
if (Test-Path $journal) { Write-Host "--- journal de l'assistant :"; Get-Content $journal -Encoding UTF8 | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" } }
exit $(if ($rates) { 1 } else { 0 })
