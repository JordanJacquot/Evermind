#Requires -Version 5.1
<#
    Evermind 0.12.8
    L'agenda qui se souvient de tout pour toi : tu notes ton rendez-vous, il te le rappelle à voix haute.

    Les rendez-vous sont gardés dans %LOCALAPPDATA%\Evermind\rendez-vous.json (%LOCALAPPDATA%\Mindset\Evermind pour
    une copie installée par Mindset, voir modules\donnees.ps1). Rien n'est envoyé sur Internet.

    Evermind.ps1 -Demarrage  reste caché près de l'horloge (lancement avec Windows).
#>
param([switch]$Demarrage)   # -Demarrage : lancé avec Windows, la fenêtre ne s'ouvre pas

$AppVersion = '0.12.8'
$UpdateRepo = 'JordanJacquot/Evermind'   # dépôt GitHub des mises à jour (modules\maj.ps1)
$MainScript = $PSCommandPath
$AppExe = Join-Path (Split-Path $PSScriptRoot -Parent) 'Evermind.exe'   # le programme qui exécute ce script
$EnTest = [bool]$env:EVERMIND_TEST      # test automatique (outils\tester.ps1) : rien n'est modifié sur le PC
if ($EnTest -and $env:EVERMIND_TEST_DEMARRAGE) { $Demarrage = $true }   # (tests : lancé caché, comme avec Windows ou par Mindset)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

# ---------------------------------------------------------------------------
# Evermind s'utilise avec Mindset : une copie qui n'est pas la sienne (ni un dossier de travail) explique comment
# faire, puis s'arrête sans rien démarrer. Vérifié avant tout le reste, pour ne jamais gêner l'Evermind de Mindset.
# ---------------------------------------------------------------------------
$AppDir = $PSScriptRoot
$ModulesDir = Join-Path $AppDir 'modules'
if (Test-Path -LiteralPath (Join-Path $ModulesDir 'mindset.ps1')) {
    . (Join-Path $ModulesDir 'mindset.ps1')
    if (Test-BlocageMindset) { Show-BlocageMindset; exit }
    # Géré par Mindset et lancé à la main : il s'ouvre dans Mindset (qui le lance caché, puis l'accroche dans son onglet)
    if ($GereParMindset -and -not $Demarrage -and -not $EnTest -and (Open-DansMindset)) { exit }
}

# ---------------------------------------------------------------------------
# Une seule Evermind à la fois : un nouveau lancement ramène simplement la fenêtre
# ---------------------------------------------------------------------------
if (-not $EnTest) {
    $created = $false
    $script:InstanceMutex = New-Object System.Threading.Mutex($true, 'Local\Evermind-Instance', [ref]$created)
    $script:ShowSignal = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\Evermind-Afficher')
    if (-not $created) {
        if (-not $Demarrage) {
            # Ce lancement vient d'un clic : il autorise la fenêtre déjà ouverte à passer devant
            try {
                Add-Type -Namespace EM -Name Fg -MemberDefinition '[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);'
                [void][EM.Fg]::AllowSetForegroundWindow(-1)
            } catch {}
            [void]$script:ShowSignal.Set()
        }
        exit
    }
}

# ---------------------------------------------------------------------------
# Chargement des modules (dossier « modules » à côté de ce fichier)
# ---------------------------------------------------------------------------
$missing = @('natif.cs', 'interface.xaml', 'mindset.ps1', 'donnees.ps1', 'suite.ps1', 'fichiers.ps1', 'themes.ps1', 'comprendre.ps1', 'systeme.ps1', 'interface.ps1', 'logo.ps1', 'agenda.ps1', 'details.ps1', 'alerte.ps1', 'voix.ps1', 'maj.ps1', 'voix-kokoro.cs', 'eveil.ps1', 'cerveau.ps1', 'evenements.ps1' | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ModulesDir $_)) })
if ($missing) {
    [System.Windows.MessageBox]::Show("Des fichiers d'Evermind sont manquants :`n`n$($missing -join ', ')`n`nRéinstalle Evermind depuis Mindset.", 'Evermind', 'OK', 'Error') | Out-Null
    exit
}

# Fonctions natives (barre de titre sombre)
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $ModulesDir 'natif.cs'), [Text.Encoding]::UTF8))
# Identité propre dans la barre des tâches (icône d'Evermind au lieu de celle de PowerShell), avant toute fenêtre
$AppId = 'JordanJacquot.Evermind'
try { [EMNative]::SetAppId($AppId) } catch {}

foreach ($emModule in 'donnees', 'suite', 'fichiers', 'themes', 'comprendre', 'systeme', 'interface', 'logo', 'agenda', 'details', 'alerte', 'voix', 'maj', 'eveil', 'cerveau', 'evenements') { . (Join-Path $ModulesDir "$emModule.ps1") }

# Retire la marque « téléchargé depuis Internet » des fichiers d'Evermind, pour que Windows n'affiche plus
# d'avertissement aux lancements suivants. Pas pour une copie installée par Mindset : elle n'a pas cette marque,
# et son dossier (Program Files) n'est de toute façon pas modifiable par Evermind.
if (-not $GereParMindset) {
    try {
        $appRoot = Split-Path $PSScriptRoot -Parent
        @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Recurse -ErrorAction SilentlyContinue) +
        @(Get-ChildItem -LiteralPath $appRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Evermind\.exe|LISEZMOI\.txt)$' }) |
            Unblock-File -ErrorAction SilentlyContinue
    } catch {}
}

# ---------------------------------------------------------------------------
# Lancement
# ---------------------------------------------------------------------------
Write-Log "Démarrage Evermind $AppVersion (langue $((Get-UICulture).Name), PowerShell $($PSVersionTable.PSVersion))$(if ($Demarrage) { ', lancé avec Windows' })"
Initialize-AutoStart
if (-not $EnTest -and -not $GereParMindset) { [void](Get-TrayIcon) }   # (géré par Mindset : c'est l'icône de Mindset)
if ($env:EVERMIND_CAPTURE) { Start-Capture $env:EVERMIND_CAPTURE }
if (-not $Demarrage) { $Window.Show() }
[System.Windows.Threading.Dispatcher]::Run()

# Mise à jour : la place est libérée, puis les nouveaux fichiers remplacent les anciens et Evermind se relance
if ($script:MajLancer) {
    try { $script:InstanceMutex.ReleaseMutex(); $script:InstanceMutex.Dispose() } catch {}
    try { $script:ShowSignal.Dispose() } catch {}
    Start-MajRemplacement
    exit
}

# Relance demandée (nouveau thème) : la place est libérée, puis un nouvel Evermind démarre
# (caché près de l'horloge s'il l'était : thème de la suite changé pendant qu'on ne le regardait pas)
if ($script:Relancer) {
    try { $script:InstanceMutex.ReleaseMutex(); $script:InstanceMutex.Dispose() } catch {}
    try { $script:ShowSignal.Dispose() } catch {}
    $opt = @(if ($script:RelancerCache) { '-Demarrage' })
    if (Test-Path -LiteralPath $AppExe) { if ($opt) { Start-Process -FilePath $AppExe -ArgumentList $opt } else { Start-Process -FilePath $AppExe } }
    else { Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$MainScript`"") + $opt) }
}
