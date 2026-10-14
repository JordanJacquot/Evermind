# Evermind : la suite Mindset (le portail qui installe, met à jour et lance Nevermind et Evermind).
# suite.json est lu par donnees.ps1, qui décide aussi si cette copie est gérée par Mindset ($GereParMindset).
#
#   Copie gérée    elle prend le thème de la suite au démarrage, l'écrit dans suite.json quand on en choisit un dans
#                  Evermind, et se relance quand il change (choisi dans Mindset ou dans Nevermind). Mindset la met à
#                  jour et la lance avec Windows : ni recherche de mise à jour ni démarrage avec Windows ici.
#   Copie autonome comme avant, plus un bandeau discret qui présente Mindset (tant que Mindset n'est pas installé).
# Tests : EVERMIND_SUITE (un faux suite.json, voir donnees.ps1), EVERMIND_BANDEAU_MINDSET (le bandeau de Mindset).
# Chargé par Evermind.ps1 juste après donnees.ps1, avant themes.ps1.

$MindsetPage = 'https://github.com/JordanJacquot/Mindset/releases/latest'

# Au démarrage d'une copie gérée : le thème de la suite devient celui d'Evermind (sauf un thème personnalisé, qui reste)
if ($GereParMindset -and $script:Suite.Theme) {
    $themeApp = [string](Get-Setting 'Theme' 'neon')
    if ($themeApp -notlike 'pack:*' -and $themeApp -ne $script:Suite.Theme) {
        Set-Setting 'Theme' $script:Suite.Theme
        Write-Log "Thème de la suite (Mindset) : $($script:Suite.Theme)"
    }
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
        $script:SuiteThemeAttente = if ($geree -and $s.Theme -and $s.Theme -ne $ThemeSetting -and $ThemeSetting -notlike 'pack:*') { $s.Theme } else { $null }
        if ($script:SuiteThemeAttente) { Write-Log "Thème de la suite changé : $($script:SuiteThemeAttente)" }
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

# Bandeau « Evermind fait maintenant partie de Mindset » : copie autonome, Mindset pas installé (pas de suite.json),
# et pas repoussé avec « Plus tard » ces 7 derniers jours
function Initialize-BandeauMindset {
    if ($GereParMindset -or $script:Suite.Existe) { return }
    if ($EnTest -and -not $env:EVERMIND_BANDEAU_MINDSET) { return }
    $quand = [datetime]::MinValue
    if ([datetime]::TryParse([string](Get-Setting 'MindsetPlusTard' ''), [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$quand) -and ((Get-Date) - $quand).TotalDays -lt 7) { return }
    $ui.BtnMindset.Add_Click({
        Write-Log 'Mindset : page de téléchargement ouverte'
        if (-not $EnTest) { try { Start-Process $MindsetPage } catch { Write-Log "Mindset : $_" } }
        $ui.MindsetBandeau.Visibility = 'Collapsed'
    })
    $ui.BtnMindsetPlusTard.Add_Click({ Set-Setting 'MindsetPlusTard' (Get-Date).ToString('s'); $ui.MindsetBandeau.Visibility = 'Collapsed' })
    $ui.MindsetBandeau.Visibility = 'Visible'
}

# Au démarrage (evenements.ps1)
function Initialize-Suite {
    Initialize-BandeauMindset
    if (-not $GereParMindset) { return }
    Write-Log 'Géré par Mindset : mises à jour et démarrage avec Windows par Mindset'
    $ui.DemarrageOption.Visibility = 'Collapsed'   # c'est Mindset qui lance Evermind avec Windows
    $ui.ReglagesMindset.Visibility = 'Visible'     # Réglages, Général : « les mises à jour passent par Mindset »
    $script:SuiteDate = [datetime]::MinValue
    $script:SuiteTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SuiteTimer.Interval = [TimeSpan]::FromMilliseconds(2500)
    $script:SuiteTimer.Add_Tick({ try { Update-SuiteSurveillance } catch { Write-Log "Suite Mindset : $_" } })
    $script:SuiteTimer.Start()
}
