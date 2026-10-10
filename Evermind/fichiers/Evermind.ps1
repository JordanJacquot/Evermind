#Requires -Version 5.1
<#
    Evermind 0.1.0
    L'agenda qui se souvient de tout pour toi : tu notes ton rendez-vous, il te le rappelle à voix haute.

    Les rendez-vous sont gardés dans %LOCALAPPDATA%\Evermind\rendez-vous.json. Rien n'est envoyé sur Internet.

    Evermind.ps1 -Demarrage  reste caché près de l'horloge (lancement avec Windows).
#>
param([switch]$Demarrage)   # -Demarrage : lancé avec Windows, la fenêtre ne s'ouvre pas

$AppVersion = '0.1.0'
$UpdateRepo = 'JordanJacquot/Evermind'   # dépôt GitHub où seront publiées les mises à jour
$MainScript = $PSCommandPath
$AppExe = Join-Path (Split-Path $PSScriptRoot -Parent) 'Evermind.exe'   # le programme qui exécute ce script
$EnTest = [bool]$env:EVERMIND_TEST      # test automatique (outils\tester.ps1) : rien n'est modifié sur le PC

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

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

# Retire la marque « téléchargé depuis Internet » des fichiers d'Evermind, pour que
# Windows n'affiche plus d'avertissement aux lancements suivants.
try {
    $appRoot = Split-Path $PSScriptRoot -Parent
    @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Recurse -ErrorAction SilentlyContinue) +
    @(Get-ChildItem -LiteralPath $appRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Evermind\.exe|LISEZMOI\.txt)$' }) |
        Unblock-File -ErrorAction SilentlyContinue
} catch {}

# ---------------------------------------------------------------------------
# Chargement des modules (dossier « modules » à côté de ce fichier)
# ---------------------------------------------------------------------------
$AppDir = $PSScriptRoot
$ModulesDir = Join-Path $AppDir 'modules'
$missing = @('natif.cs', 'interface.xaml', 'donnees.ps1', 'systeme.ps1', 'interface.ps1', 'agenda.ps1', 'evenements.ps1' | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ModulesDir $_)) })
if ($missing) {
    [System.Windows.MessageBox]::Show("Des fichiers d'Evermind sont manquants :`n`n$($missing -join ', ')`n`nRetélécharge Evermind et remplace tout le dossier.", 'Evermind', 'OK', 'Error') | Out-Null
    exit
}

# Fonctions natives (barre de titre sombre)
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $ModulesDir 'natif.cs'), [Text.Encoding]::UTF8))
# Identité propre dans la barre des tâches (icône d'Evermind au lieu de celle de PowerShell), avant toute fenêtre
$AppId = 'JordanJacquot.Evermind'
try { [EMNative]::SetAppId($AppId) } catch {}

foreach ($emModule in 'donnees', 'systeme', 'interface', 'agenda', 'evenements') { . (Join-Path $ModulesDir "$emModule.ps1") }

# ---------------------------------------------------------------------------
# Lancement
# ---------------------------------------------------------------------------
Write-Log "Démarrage Evermind $AppVersion (langue $((Get-UICulture).Name), PowerShell $($PSVersionTable.PSVersion))$(if ($Demarrage) { ', lancé avec Windows' })"
Initialize-AutoStart
if (-not $EnTest) { [void](Get-TrayIcon) }
if ($env:EVERMIND_CAPTURE) { Start-Capture $env:EVERMIND_CAPTURE }
if (-not $Demarrage) { $Window.Show() }
[System.Windows.Threading.Dispatcher]::Run()
