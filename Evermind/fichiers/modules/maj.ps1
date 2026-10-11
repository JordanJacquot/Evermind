# Evermind : la mise à jour en un clic.
#   Au démarrage, puis toutes les 6 heures, Evermind regarde sur GitHub la dernière version publiée (une simple lecture
#   de la page des versions : rien de personnel n'est envoyé). Si elle est plus récente, un bandeau la propose.
#   Un clic : le zip est téléchargé, son empreinte vérifiée (GitHub la donne), il est dézippé à part, puis Evermind se
#   ferme ; un petit programme remplace les fichiers et relance Evermind. Les rendez-vous et réglages ne bougent pas
#   (ils sont dans %LOCALAPPDATA%\Evermind), ni la voix ou l'assistant déjà installés.
# Tests : EVERMIND_MAJ_VERSION (version « en ligne » imaginaire) et EVERMIND_MAJ_ZIP (zip local) remplacent GitHub.
# Chargé par Evermind.ps1, après voix.ps1.

$MajDossier = Join-Path $env:TEMP 'Evermind-maj'
$script:Maj = [hashtable]::Synchronized(@{ Etat = ''; Version = ''; Url = ''; Digest = ''; Page = ''; Erreur = ''; Recu = 0L; Total = 0L; Dossier = '' })

function Test-VersionPlusRecente([string]$En, [string]$Ici) {
    try { [version]($En.TrimStart('vV')) -gt [version]($Ici.TrimStart('vV')) } catch { $false }
}

# Regarde la dernière version en arrière plan (la fenêtre ne se fige pas si Internet est lent ou absent)
function Start-MajRecherche {
    if ($script:Maj.Etat -in 'cherche', 'telecharge', 'pret') { return }
    $script:Maj.Etat = 'cherche'; $script:Maj.Erreur = ''
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($Etat, $Depot, $Version, $Zip)
        try {
            if ($Version) {   # (tests)
                $Etat.Version = $Version; $Etat.Url = $Zip; $Etat.Digest = ''; $Etat.Page = ''
            } else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $r = Invoke-RestMethod "https://api.github.com/repos/$Depot/releases/latest" -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'Evermind' }
                $a = @($r.assets | Where-Object { $_.name -eq 'Evermind.zip' })[0]
                $Etat.Version = ([string]$r.tag_name).TrimStart('vV'); $Etat.Page = [string]$r.html_url
                $Etat.Url = if ($a) { [string]$a.browser_download_url } else { '' }
                $Etat.Digest = if ($a -and $a.digest) { ([string]$a.digest -replace '^sha256:', '').ToUpper() } else { '' }
            }
            $Etat.Etat = 'vu'
        } catch { $Etat.Erreur = $_.Exception.Message; $Etat.Etat = 'erreur' }
    }).AddArgument($script:Maj).AddArgument($UpdateRepo).AddArgument($env:EVERMIND_MAJ_VERSION).AddArgument($env:EVERMIND_MAJ_ZIP)
    $script:Maj.PS = $ps; $script:Maj.Handle = $ps.BeginInvoke()
    Start-MajSuivi
}

# Le bandeau suit ce qui se passe (recherche, téléchargement, prêt)
function Start-MajSuivi {
    if (-not $script:MajTimer) {
        $script:MajTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:MajTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $script:MajTimer.Add_Tick({ Update-MajBandeau })
    }
    $script:MajTimer.Start()
}

function Update-MajBandeau {
    $m = $script:Maj
    switch ($m.Etat) {
        'cherche' { return }
        'vu' {
            $script:MajTimer.Stop()
            if ($m.Url -and (Test-VersionPlusRecente $m.Version $AppVersion) -and $m.Version -ne $script:MajPlusTard) {
                $m.Etat = 'dispo'
                Write-Log "Mise à jour disponible : $($m.Version)"
                Show-MajBandeau "Evermind $($m.Version) est disponible (tu as la $AppVersion). La mise à jour prend quelques secondes : tes rendez-vous, tes réglages et la voix restent." 'Mettre à jour' $true
            } else { $m.Etat = ''; $ui.MajBandeau.Visibility = 'Collapsed' }
        }
        'erreur' {
            $script:MajTimer.Stop()
            if ($script:MajDemandee) {
                Show-MajBandeau "La mise à jour n'a pas marché ($($m.Erreur)). Vérifie Internet et réessaie." 'Réessayer' $true
                $m.Etat = 'dispo'
            } else { Write-Log "Mise à jour : recherche impossible ($($m.Erreur))"; $m.Etat = '' }
        }
        'telecharge' {
            $pct = if ($m.Total) { [math]::Min(1.0, $m.Recu / $m.Total) } else { 0.3 }
            $ui.MajBarreFond.Visibility = 'Visible'
            Set-BarreAvance $ui.MajBarre $ui.MajBarreFond $pct
        }
        'pret' {
            $script:MajTimer.Stop()
            Install-MajPrete
        }
    }
}

function Show-MajBandeau([string]$Texte, [string]$Bouton, [bool]$PlusTard) {
    $ui.MajTexte.Text = $Texte
    $ui.BtnMaj.Content = $Bouton; $ui.BtnMaj.IsEnabled = $true
    $ui.BtnMajPlusTard.Visibility = if ($PlusTard) { 'Visible' } else { 'Collapsed' }
    $ui.MajBarreFond.Visibility = 'Collapsed'
    $ui.MajBandeau.Visibility = 'Visible'
}

# « Mettre à jour » : téléchargement, empreinte, dézippage à part (rien n'est encore remplacé)
function Start-MajTelechargement {
    $m = $script:Maj
    if ($m.Etat -in 'telecharge', 'pret') { return }
    $script:MajDemandee = $true
    $m.Etat = 'telecharge'; $m.Erreur = ''; $m.Recu = 0L; $m.Total = 0L
    $ui.MajTexte.Text = "Téléchargement d'Evermind $($m.Version)..."
    $ui.BtnMaj.IsEnabled = $false; $ui.BtnMajPlusTard.Visibility = 'Collapsed'
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($Etat, $Dossier)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $dest = Join-Path $Dossier $Etat.Version
            Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            $zip = Join-Path $Dossier "Evermind-$($Etat.Version).zip"
            if (Test-Path -LiteralPath $Etat.Url) { Copy-Item -LiteralPath $Etat.Url -Destination $zip -Force }   # (tests : zip local)
            else {
                $req = [Net.HttpWebRequest]::Create($Etat.Url); $req.UserAgent = 'Evermind'; $req.Timeout = 30000; $req.ReadWriteTimeout = 60000
                $resp = $req.GetResponse(); $Etat.Total = $resp.ContentLength
                $in = $resp.GetResponseStream(); $out = [IO.File]::Create($zip); $buf = New-Object byte[] 65536
                try { while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n); $Etat.Recu = $out.Length } }
                finally { $out.Dispose(); $in.Dispose(); $resp.Dispose() }
                if ($Etat.Total -gt 0 -and (Get-Item -LiteralPath $zip).Length -ne $Etat.Total) { throw 'le téléchargement s''est coupé' }
            }
            if ($Etat.Digest -and (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $Etat.Digest) { throw 'le fichier reçu est abîmé (empreinte différente)' }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
            $app = Join-Path $dest 'Evermind'
            if (-not (Test-Path -LiteralPath (Join-Path $app 'Evermind.exe')) -or -not (Test-Path -LiteralPath (Join-Path $app 'fichiers\Evermind.ps1'))) { throw 'le zip ne contient pas Evermind' }
            Get-ChildItem -LiteralPath $app -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
            $Etat.Dossier = $app
            $Etat.Etat = 'pret'
        } catch { $Etat.Erreur = $_.Exception.Message; $Etat.Etat = 'erreur' }
    }).AddArgument($m).AddArgument($MajDossier)
    $m.PS = $ps; $m.Handle = $ps.BeginInvoke()
    Write-Log "Mise à jour : téléchargement de $($m.Version)"
    Start-MajSuivi
}

# Tout est prêt : Evermind se ferme, le petit programme de remplacement prend le relais (voir la fin d'Evermind.ps1)
function Install-MajPrete {
    $m = $script:Maj
    $racine = Split-Path $AppDir -Parent
    $ui.MajTexte.Text = "Installation d'Evermind $($m.Version)... Evermind va se fermer et se rouvrir tout seul."
    $script:MajLancer = @{ Source = $m.Dossier; Cible = $racine; Version = $m.Version }
    try { Set-Setting 'MajInstallee' $m.Version } catch {}
    Write-Log "Mise à jour : installation de $($m.Version) dans $racine"
    if ($EnTest -and -not $env:EVERMIND_MAJ_INSTALLER) { return }
    Exit-App
}

# Appelé à la toute fin d'Evermind.ps1, une fois la fenêtre fermée : lance le remplacement des fichiers
function Start-MajRemplacement {
    $l = $script:MajLancer
    New-Item -ItemType Directory -Force -Path $MajDossier | Out-Null
    $script = Join-Path $MajDossier 'remplacer.ps1'
    $code = @'
param([int]$Attendre, [string]$Source, [string]$Cible, [string]$Journal, [switch]$PasDeRelance)
function Note([string]$t) { try { Add-Content -LiteralPath $Journal -Value "$(Get-Date -Format s) Mise à jour : $t" -Encoding UTF8 } catch {} }
# Evermind se ferme : on attend qu'il soit parti (ses fichiers ne sont plus utilisés)
try { Wait-Process -Id $Attendre -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 700
# Les nouveaux fichiers par dessus les anciens (robocopy réessaie si un fichier est encore pris)
& robocopy.exe $Source $Cible /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Note "remplacement impossible (robocopy $LASTEXITCODE)" } else { Note 'fichiers remplacés' }
if (-not $PasDeRelance) { Start-Process -FilePath (Join-Path $Cible 'Evermind.exe') }
'@
    [IO.File]::WriteAllText($script, $code, (New-Object Text.UTF8Encoding($true)))
    $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script`"", '-Attendre', $PID, '-Source', "`"$($l.Source)`"", '-Cible', "`"$($l.Cible)`"", '-Journal', "`"$LogFile`"")
    if ($env:EVERMIND_MAJ_PAS_DE_RELANCE) { $arg += '-PasDeRelance' }
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arg -WindowStyle Hidden
}

# Au démarrage : « Evermind est à jour » si on vient d'en installer une ; puis la recherche (et toutes les 6 heures)
function Initialize-Maj {
    $ui.BtnMaj.Add_Click({ if ($script:Maj.Etat -eq 'dispo') { Start-MajTelechargement } })
    $ui.BtnMajPlusTard.Add_Click({ $script:MajPlusTard = $script:Maj.Version; $script:Maj.Etat = ''; $ui.MajBandeau.Visibility = 'Collapsed' })
    $faite = [string](Get-Setting 'MajInstallee' '')
    if ($faite) {
        Set-Setting 'MajInstallee' ''
        if ($faite -eq $AppVersion) { Write-Log "Mise à jour installée : $AppVersion"; Show-Notify "Evermind est à jour" "Tu as maintenant la version $AppVersion." }
    }
    if ($EnTest -and -not $env:EVERMIND_MAJ_VERSION) { return }
    Start-MajRecherche
    $script:MajToutes = New-Object System.Windows.Threading.DispatcherTimer
    $script:MajToutes.Interval = [TimeSpan]::FromHours(6)
    $script:MajToutes.Add_Tick({ if (-not $script:Maj.Etat) { Start-MajRecherche } })
    $script:MajToutes.Start()
    # (tests : « Mettre à jour » appuyé tout seul)
    if ($env:EVERMIND_MAJ_AUTO) {
        $t = New-Object System.Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds(400)
        $t.Add_Tick({ param($s) if ($script:Maj.Etat -eq 'dispo') { $s.Stop(); Start-MajTelechargement } })
        $t.Start()
    }
}
