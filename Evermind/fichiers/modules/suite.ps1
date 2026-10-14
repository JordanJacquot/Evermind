# Evermind : la suite Mindset (le portail qui installe, met à jour et lance Nevermind et Evermind).
# suite.json est lu par mindset.ps1, qui décide aussi si cette copie est gérée par Mindset ($GereParMindset).
#
#   Copie gérée    elle prend le thème de la suite au démarrage, l'écrit dans suite.json quand on en choisit un dans
#                  Evermind, et se relance quand il change (choisi dans Mindset ou dans Nevermind). Mindset la met à
#                  jour et la lance avec Windows : ni recherche de mise à jour ni démarrage avec Windows ici.
#                  Le micro et le casque viennent aussi de Mindset (pris au démarrage et dès qu'ils changent, sans
#                  relance) : dans Réglages, Son et Thème, un bouton ouvre les réglages de Mindset à la place des choix.
#   Copie autonome seulement un dossier de travail (les autres sont arrêtées au lancement, mindset.ps1) : comme avant.
# Tests : EVERMIND_SUITE (un faux suite.json, voir mindset.ps1).
# Chargé par Evermind.ps1 juste après donnees.ps1, avant themes.ps1.

# Au démarrage d'une copie gérée : le thème de la suite devient celui d'Evermind (sauf un thème personnalisé, qui reste)
if ($GereParMindset -and $script:Suite.Theme) {
    $themeApp = [string](Get-Setting 'Theme' 'neon')
    if ($themeApp -notlike 'pack:*' -and $themeApp -ne $script:Suite.Theme) {
        Set-Setting 'Theme' $script:Suite.Theme
        Write-Log "Thème de la suite (Mindset) : $($script:Suite.Theme)"
    }
}

# Au démarrage d'une copie gérée : le micro et le casque de la suite remplacent ceux d'Evermind (voix.ps1 les applique)
if ($GereParMindset) {
    foreach ($k in 'Micro', 'Casque') {
        if ($null -ne $script:Suite[$k] -and $script:Suite[$k] -ne [string](Get-Setting $k '')) {
            Set-Setting $k $script:Suite[$k]
            Write-Log "$k de la suite (Mindset) : $(if ($script:Suite[$k]) { $script:Suite[$k] } else { 'celui de Windows' })"
        }
    }
}

# Micro ou casque changés dans Mindset : appliqués tout de suite, sans relancer Evermind. « OK Evermind » repart sur le
# nouveau micro, mais seulement une fois finie la dictée, la demande ou la phrase en cours ($script:EveilARelancer).
function Set-SuiteAppareils($Suite) {
    if ($null -ne $Suite.Casque -and $Suite.Casque -ne [string](Get-Setting 'Casque' '')) {
        Set-Setting 'Casque' $Suite.Casque
        [void](Set-CasqueActif)
        Write-Log "Casque de la suite (Mindset) : $(if ($Suite.Casque) { $Suite.Casque } else { 'celui de Windows' })"
    }
    if ($null -ne $Suite.Micro -and $Suite.Micro -ne [string](Get-Setting 'Micro' '')) {
        Set-Setting 'Micro' $Suite.Micro
        if (Set-MicroActif) { $script:EveilARelancer = $true }
        Write-Log "Micro de la suite (Mindset) : $(if ($Suite.Micro) { $Suite.Micro } else { 'celui de Windows' })"
    }
}

# Ouvre les réglages de Mindset sur une page (« parametres:son », « parametres:apparence ») : la page est écrite dans
# afficher-page.txt, puis Mindset est lancé (s'il tourne déjà, il se ramène et lit le fichier). Son programme est donné
# par son installation (HKLM, modifiable seulement par un administrateur), jamais par suite.json.
function Open-ReglagesMindset([string]$Page) {
    if ($Page -notin 'parametres:son', 'parametres:apparence') { return }
    $exe = $null
    try {
        $dossier = [string](Get-ItemProperty -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Mindset' -Name InstallLocation -ErrorAction Stop).InstallLocation
        if (Get-CheminNormal $dossier) { $exe = Join-Path (Get-CheminNormal $dossier) 'Mindset.exe' }
    } catch {}
    Write-Log "Réglages de Mindset demandés ($Page)"
    if ($EnTest) { return }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { Show-Notify 'Mindset introuvable' 'Ouvre Mindset pour régler le micro, le casque et le thème de toute la suite.'; return }
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'Mindset'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'afficher-page.txt'), $Page, $Utf8NoBom)
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent)
    } catch { Write-Log "Mindset : $($_.Exception.Message)" }
}

# Le thème choisi dans Evermind devient celui de toute la suite. Seuls « theme » et « modifie » changent : le reste
# (les applis de Mindset...) est gardé tel quel. Écrit à côté puis remplacé d'un coup, comme le fait Mindset.
function Write-SuiteTheme([string]$Id) {
    if (-not $GereParMindset -or $Id -notin $ThemesSuite -or -not $SuiteFile) { return }
    try {
        $j = [IO.File]::ReadAllText($SuiteFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($j -isnot [Management.Automation.PSCustomObject]) { throw 'contenu inattendu' }
        foreach ($k in 'theme', 'modifie') { if (-not $j.PSObject.Properties[$k]) { $j | Add-Member -NotePropertyName $k -NotePropertyValue $null } }
        $j.theme = $Id; $j.modifie = (Get-Date).ToString('s')
        $tmp = "$SuiteFile.tmp"
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $j -Depth 8), $Utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $SuiteFile -Force
        $script:SuiteDate = (New-Object IO.FileInfo $SuiteFile).LastWriteTimeUtc   # (notre propre écriture n'est pas un changement)
        Write-Log "Thème de la suite écrit dans suite.json : $Id"
    } catch { Write-Log "suite.json : thème non écrit ($($_.Exception.Message))" }
}

# Evermind est en train de faire quelque chose qu'une relance couperait : écoute, dictée, demande à l'assistant,
# phrase dite, « OK Evermind » entendu, alerte affichée, téléchargement, mise à jour, formulaire ouvert
function Test-RelanceGenante {
    [bool]($script:Ecoute -or $script:Transcription -or $script:Demande -or $script:Parle -or
        ($script:Eveil -and $script:Eveil.Detecte) -or ($script:VoixDl -and -not $script:VoixDl.Fini) -or
        ($script:Maj.Etat -in 'telecharge', 'pret') -or ($script:Alertes -and $script:Alertes.Count) -or
        $ui.Formulaire.Visibility -eq 'Visible' -or $ui.Confirmation.Visibility -eq 'Visible')
}

# Toutes les 2,5 secondes : suite.json a-t-il changé ? (seule sa date est lue ; le fichier n'est relu que si elle change)
function Update-SuiteSurveillance {
    $fi = New-Object IO.FileInfo $SuiteFile
    $date = if ($fi.Exists) { $fi.LastWriteTimeUtc } else { [datetime]::MinValue }
    if ($date -ne $script:SuiteDate) {
        $s = Read-Suite
        if ($s.Existe -and -not $s.Lisible) { return }   # en train d'être remplacé : relu au prochain tour
        $script:SuiteDate = $date
        # Seulement si cette copie est toujours celle de Mindset, et pas sur un thème personnalisé
        $geree = $s.Evermind -and $s.Evermind -ieq $AppRacine
        if ($geree) { Set-SuiteAppareils $s }
        $script:SuiteThemeAttente = if ($geree -and $s.Theme -and $s.Theme -ne $ThemeSetting -and $ThemeSetting -notlike 'pack:*') { $s.Theme } else { $null }
        if ($script:SuiteThemeAttente) { Write-Log "Thème de la suite changé : $($script:SuiteThemeAttente)" }
    }
    # « OK Evermind » sur le nouveau micro, une fois l'écoute, la dictée, la demande et la phrase en cours finies
    if ($script:EveilARelancer -and -not ($script:Ecoute -or $script:Transcription -or $script:Demande -or $script:Parle -or ($script:Eveil -and $script:Eveil.Detecte))) {
        $script:EveilARelancer = $false
        if (Test-EveilActif) { Stop-Eveil; Start-Eveil; try { Update-EveilReglage } catch {} }
    }
    # Le nouveau thème attend la fin de ce qui est en cours ; après la relance, il est égal à celui de la suite
    if (-not $script:SuiteThemeAttente -or (Test-RelanceGenante)) { return }
    $t = $script:SuiteThemeAttente; $script:SuiteThemeAttente = $null
    Set-Setting 'Theme' $t
    Write-Log "Thème : $t (suite Mindset), Evermind se relance"
    if ($EnTest) { return }
    $script:RelancerCache = -not $Window.IsVisible   # caché près de l'horloge : il le reste après la relance
    Restart-App
}

# Au démarrage (evenements.ps1)
function Initialize-Suite {
    if (-not $GereParMindset) { return }
    Write-Log 'Géré par Mindset : mises à jour et démarrage avec Windows par Mindset'
    $ui.DemarrageOption.Visibility = 'Collapsed'   # c'est Mindset qui lance Evermind avec Windows
    $ui.ReglagesMindset.Visibility = 'Visible'     # Réglages, Général : « les mises à jour passent par Mindset »
    # Réglages, Son et Thème : le micro, le casque et le thème se règlent dans Mindset, pour toute la suite
    $ui.SonChoix.Visibility = 'Collapsed'; $ui.SonMindset.Visibility = 'Visible'
    $ui.ThemeTexte.Visibility = 'Collapsed'; $ui.ThemeMindset.Visibility = 'Visible'
    $ui.BtnSonMindset.Add_Click({ Open-ReglagesMindset 'parametres:son' })
    $ui.BtnThemeMindset.Add_Click({ Open-ReglagesMindset 'parametres:apparence' })
    $script:SuiteDate = [datetime]::MinValue
    $script:SuiteTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SuiteTimer.Interval = [TimeSpan]::FromMilliseconds(2500)
    $script:SuiteTimer.Add_Tick({ try { Update-SuiteSurveillance } catch { Write-Log "Suite Mindset : $_" } })
    $script:SuiteTimer.Start()
}
