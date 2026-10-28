# Evermind : la suite Mindset (le portail qui installe, met à jour et lance Nevermind et Evermind).
# suite.json est lu par mindset.ps1, qui décide aussi si cette copie est gérée par Mindset ($GereParMindset).
#
#   Copie gérée    le thème de toute la suite se choisit seulement dans Mindset : elle le prend au démarrage et se
#                  relance quand il change, mais ne l'écrit jamais dans suite.json (elle le lit seulement). Dans
#                  Réglages, Thème, aucun choix ni import : le thème actuel et un bouton qui ouvre les réglages de
#                  Mindset (Set-AppTheme et l'import sont sans effet, themes.ps1). Les thèmes personnalisés aussi :
#                  « pack:<id> » dans suite.json, installé par Mindset dans nos packs. Mindset la met à jour et la
#                  lance avec Windows : ni recherche de mise à jour ni démarrage avec Windows ici. Le micro et le
#                  casque viennent aussi de Mindset (pris au démarrage et dès qu'ils changent, sans relance) : dans
#                  Réglages, Son, un bouton ouvre les réglages de Mindset à la place des choix.
#   Copie autonome seulement un dossier de travail (les autres sont arrêtées au lancement, mindset.ps1) : comme avant.
# Tests : EVERMIND_SUITE (un faux suite.json, voir mindset.ps1).
# Chargé par Evermind.ps1 juste après donnees.ps1, avant themes.ps1.

# Le thème de la suite est-il utilisable ici ? Un des 5 thèmes, ou un thème personnalisé de la suite que Mindset a
# installé dans nos packs (<données>\packs\<id>\pack.json, lisible). Sinon le thème actuel reste, et c'est noté.
function Test-ThemeSuite([string]$Id) {
    if ($Id -in $ThemesSuite) { return $true }
    if ($Id -cmatch '^pack:[a-z0-9-]{1,40}$' -and (Get-ThemePack $Id.Substring(5))) { return $true }
    Write-Log "Thème de la suite $Id introuvable ou illisible dans $PacksDir : le thème actuel reste"
    $false
}

# Au démarrage d'une copie gérée (appelé par themes.ps1, avant de choisir les couleurs) : le thème de la suite,
# thèmes personnalisés compris, devient celui d'Evermind
function Sync-SuiteThemeDemarrage {
    $t = $script:Suite.Theme
    if (-not $GereParMindset -or -not $t -or $t -eq [string](Get-Setting 'Theme' 'neon') -or -not (Test-ThemeSuite $t)) { return }
    Set-Setting 'Theme' $t
    Write-Log "Thème de la suite (Mindset) : $t"
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
        $s = Read-Suite 1   # (un seul essai : la fenêtre ne doit pas attendre ; pris, il est relu au prochain tour)
        if ($s.Existe -and -not $s.Lisible) { return }   # en train d'être remplacé : relu au prochain tour
        $script:SuiteDate = $date
        # Seulement si cette copie est toujours celle de Mindset (thème personnalisé de la suite : seulement s'il est installé)
        $geree = $s.Evermind -and $s.Evermind -ieq $AppRacine
        if ($geree) { Set-SuiteAppareils $s }
        $script:SuiteThemeAttente = if ($geree -and $s.Theme -and $s.Theme -ne $ThemeSetting -and (Test-ThemeSuite $s.Theme)) { $s.Theme } else { $null }
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
    # Réglages, Son et Thème : le micro, le casque et le thème (thèmes personnalisés compris) se règlent dans Mindset.
    # Thème : aucun choix ni import ici, seulement le thème actuel et le bouton vers Mindset (Update-ThemeChoix aussi)
    $ui.SonChoix.Visibility = 'Collapsed'; $ui.SonMindset.Visibility = 'Visible'
    $ui.ThemeTexte.Visibility = 'Collapsed'; $ui.ThemeMindset.Visibility = 'Visible'; $ui.ThemesPerso.Visibility = 'Collapsed'
    $ui.ThemeChoix.Visibility = 'Collapsed'; $ui.ThemeChoixBas.Visibility = 'Collapsed'
    $ui.ThemeActuel.Text = "Thème actuel : $(Get-ThemeActuelNom)"
    $ui.BtnSonMindset.Add_Click({ Open-ReglagesMindset 'parametres:son' })
    $ui.BtnThemeMindset.Add_Click({ Open-ReglagesMindset 'parametres:apparence' })
    $script:SuiteDate = [datetime]::MinValue
    $script:SuiteTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SuiteTimer.Interval = [TimeSpan]::FromMilliseconds(2500)
    $script:SuiteTimer.Add_Tick({ try { Update-SuiteSurveillance } catch { Write-Log "Suite Mindset : $_" } })
    $script:SuiteTimer.Start()
}
