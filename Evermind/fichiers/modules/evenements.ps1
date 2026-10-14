# Evermind : branchement des boutons et événements de la fenêtre.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

$ui.VersionText.Text = "Evermind $AppVersion"
Update-Greeting
Start-LogoAnime $ui.LogoHote 84
# (tests : une place et une taille données d'avance, « 0.45;0.5;90 »)
if ($env:EVERMIND_LOGO) { $v = $env:EVERMIND_LOGO -split ';'; Set-Setting 'LogoPos' ([ordered]@{ X = [double]$v[0]; Y = [double]$v[1] }); Set-Setting 'LogoTaille' ([double]$v[2]) }
Initialize-LogoDeplacable   # on le glisse où on veut, molette : sa taille
Update-Agenda

# Barre rapide
$ui.BtnAjouter.Add_Click({ Invoke-Ajouter })
$ui.InPhrase.Add_TextChanged({
    Update-Apercu
    if ($ui.InPhrase.Text) { $ui.FormMessage.Visibility = 'Collapsed' }
})

# Voix
$ui.BtnMicro.Add_Click({ Start-Ecoute 'bouton' })
$ui.BtnVoixInstall.Add_Click({ Start-VoixInstall })
$ui.BtnVoixPlusTard.Add_Click({ Set-Setting 'AssistantPlusTard' $true; Update-VoixInstall })
$ui.BtnAssistant.Add_Click({ Set-Setting 'AssistantPlusTard' $false; Close-Reglages; Start-VoixInstall 'ia' })
Register-VoixHotkey
Update-RaccourciTexte
Start-Eveil   # « OK Evermind », si activé dans les réglages
$ui.ChkEveil.Add_Click({ Set-EveilReglage ([bool]$ui.ChkEveil.IsChecked) })
if (Test-DicteeInstallee) { Set-VoixEtat 'Appuie sur le micro ou sur Ctrl + Maj + Espace (même en jeu), puis parle. Je m''arrête tout seul quand tu te tais.' }
Update-VoixInstall

# Réglages (choix de la voix)
$ui.BtnReglages.Add_Click({ Open-Reglages })
foreach ($o in 'Son', 'Voix', 'Assistant', 'Theme', 'General') { $ui["Onglet$o"].Tag = $null; $ui["Onglet$o"].Add_Click({ param($s) Set-OngletReglages ($s.Name -replace '^Onglet', '') }) }
$ui.BtnReglagesFermer.Add_Click({ Close-Reglages })
$ui.ReglagesFond.Add_MouseLeftButtonDown({ Close-Reglages })

# Calendrier et panneau
$ui.BtnMoisPrec.Add_Click({ Move-Mois -1 })
$ui.BtnMoisSuiv.Add_Click({ Move-Mois 1 })
$ui.BtnAujourdhui.Add_Click({ Show-Aujourdhui })
$ui.BtnToutVoir.Add_Click({ $script:JourChoisi = $null; Update-Agenda })
$ui.BtnAjouterJour.Add_Click({ Open-Formulaire -Jour $script:JourChoisi })
$ui.BtnNouveau.Add_Click({ Open-Formulaire })

# Formulaire
$ui.FMoisPrec.Add_Click({ $script:FMois = $script:FMois.AddMonths(-1); Update-FCalendrier })
$ui.FMoisSuiv.Add_Click({ $script:FMois = $script:FMois.AddMonths(1); Update-FCalendrier })
$ui.FRepUne.Add_Click({ Set-FRepet 'une' })
$ui.FRepSemaine.Add_Click({ Set-FRepet 'semaine' })
$ui.FRepMois.Add_Click({ Set-FRepet 'mois' })
$ui.FRepAn.Add_Click({ Set-FRepet 'an' })
$ui.FHeure.Add_TextChanged({ Update-FHeureInfo })
Initialize-FTypes
Initialize-FDetails
Initialize-Fiche
$ui.BtnConfirmationNon.Add_Click({ Close-Confirmation })
$ui.ConfirmationFond.Add_MouseLeftButtonDown({ Close-Confirmation })
$ui.BtnConfirmationOui.Add_Click({ $a = $script:ConfirmationAction; Close-Confirmation; if ($a) { & $a } })
$ui.FTitre.Add_TextChanged({ Update-FTypeAuto })
$ui.FJournee.Add_Click({ Set-FJournee (-not $script:FJournee) })
$ui.BtnFAnnuler.Add_Click({ Close-Formulaire })
$ui.FormFond.Add_MouseLeftButtonDown({ Close-Formulaire })
$ui.BtnFEnregistrer.Add_Click({ Save-Formulaire })
$Window.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -ne 'Escape') { return }
    if ($ui.Fermer.Visibility -eq 'Visible') { Close-Fermer; $e.Handled = $true }
    elseif ($ui.Confirmation.Visibility -eq 'Visible') { Close-Confirmation; $e.Handled = $true }
    elseif ($ui.Formulaire.Visibility -eq 'Visible') { Close-Formulaire; $e.Handled = $true }
    elseif ($ui.Reglages.Visibility -eq 'Visible') { Close-Reglages; $e.Handled = $true }
    elseif ($ui.Fiche.Visibility -eq 'Visible') { Close-Fiche; $e.Handled = $true } })

$ui.ChkDemarrage.IsChecked = if ($EnTest) { $true } else { Test-AutoStart }
$ui.ChkDemarrage.Add_Click({
    $on = [bool]$ui.ChkDemarrage.IsChecked
    try { Set-AutoStart $on; Write-Log "Démarrage avec Windows $(if ($on) { 'activé' } else { 'désactivé' })" }
    catch { $ui.ChkDemarrage.IsChecked = -not $on; Write-Log "Démarrage avec Windows : $_" }
})

# La croix cache Evermind près de l'horloge, « Quitter » (clic droit sur l'icône) le ferme vraiment
$Window.Add_Closing({ param($s, $e) if (-not $script:Quitting) { $e.Cancel = $true; Invoke-Croix } })
$ui.BtnFermerReduire.Add_Click({ Invoke-FermerChoix 'reduire' })
$ui.BtnFermerQuitter.Add_Click({ Invoke-FermerChoix 'quitter' })
$ui.BtnFermerAnnuler.Add_Click({ Close-Fermer })
$ui.FermerFond.Add_MouseLeftButtonDown({ Close-Fermer })
$ui.BtnThemeAppliquer.Add_Click({ Set-AppTheme $script:ThemeChoisi })
$ui.BtnThemeImporter.Add_Click({ Invoke-ImportTheme })
$ui.BtnDossierRechercheAjouter.Add_Click({ Add-DossierRecherche })
$ui.BtnThemeDossier.Add_Click({ New-Item -ItemType Directory -Force -Path $PacksDir | Out-Null; Start-Process explorer.exe $PacksDir })
Add-ThemeDecor
if (-not $EnTest) { Start-PlanificateurFichiers }   # dossiers ouverts tout seuls à l'heure des rendez-vous
if (-not $EnTest) { Start-PlanificateurRappels }    # rappels : la veille, le matin même, 1 h avant...
Initialize-Maj                                      # nouvelle version d'Evermind : bandeau « Mettre à jour »
Initialize-Suite                                    # copie gérée par Mindset : thème de la suite suivi
Start-ModeJeu                                       # un jeu plein écran au premier plan : Evermind se fait discret
# Les animations ne tournent que quand Evermind est au premier plan (et jamais en mode jeu)
if (-not $EnTest) {
    $Window.Add_Activated({ if (-not $script:ModeJeu) { Set-AnimationsPause $false } })
    $Window.Add_Deactivated({ Set-AnimationsPause $true })
    $Window.Add_StateChanged({ if ($Window.WindowState -eq 'Minimized') { Set-AnimationsPause $true } })
    $Window.Add_IsVisibleChanged({ if (-not $Window.IsVisible) { Set-AnimationsPause $true } })
}
$ui.CroixDemander.Add_Click({ Set-Setting 'Croix' ''; Update-CroixReglage })
$ui.CroixReduire.Add_Click({ Set-Setting 'Croix' 'reduire'; Update-CroixReglage })
$ui.CroixQuitter.Add_Click({ Set-Setting 'Croix' 'quitter'; Update-CroixReglage })
$Window.Add_Activated({ Update-Greeting; Update-Agenda; Update-Apercu })   # « demain » devient « aujourd'hui »
$Window.Add_Loaded({ [void]$ui.InPhrase.Focus() })

Start-QuitterSurveillance   # quitter Mindset ferme aussi Evermind (quitter.demande, systeme.ps1)

# Un nouveau lancement d'Evermind demande d'afficher cette fenêtre (elle peut être cachée près de l'horloge)
if ($script:ShowSignal) {
    $script:ShowWatch = New-Object System.Windows.Threading.DispatcherTimer
    $script:ShowWatch.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:ShowWatch.Add_Tick({ if ($script:ShowSignal.WaitOne(0)) { Show-MainWindow } })
    $script:ShowWatch.Start()
}

# Tests automatiques : phrase tapée d'avance, ajout, formulaire ouvert, dictée d'un fichier son
if ($env:EVERMIND_PHRASE) { $ui.InPhrase.Text = $env:EVERMIND_PHRASE; if ($env:EVERMIND_AJOUTER) { Invoke-Ajouter } }
if ($env:EVERMIND_FORMULAIRE) { Open-Formulaire }
if ($env:EVERMIND_REGLAGES) { Open-Reglages $(if ($env:EVERMIND_REGLAGES -ne '1') { $env:EVERMIND_REGLAGES }) }
if ($env:EVERMIND_CONFIRMATION) { Confirm-Suppression (@($script:Agenda | Where-Object { $_.Titre -like $env:EVERMIND_CONFIRMATION })[0]).Id; if ($env:EVERMIND_CONFIRMATION_OUI) { $ui.BtnConfirmationOui.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent))) } }
# Couleurs des sortes choisies d'avance (« sport=#FF4D6D;sante=#3B82F6 »), et la partie des réglages qui les montre
if ($env:EVERMIND_COULEURS) { foreach ($x in $env:EVERMIND_COULEURS -split ';') { $kv = $x -split '='; if ($kv.Count -eq 2) { Set-CouleurSorte $kv[0] $kv[1] } } }
if ($env:EVERMIND_VOIR) { $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Loaded, [Action]{ $ui[$env:EVERMIND_VOIR].BringIntoView() }) | Out-Null }
# L'alerte d'Evermind, avec un rappel d'exemple (le dentiste, celui des tests)
if ($env:EVERMIND_CAPTURE_ALERTE) {
    $script:AlerteEnCapture = $true   # (la capture de la fenêtre attend celle de l'alerte)
    $rvA = @($script:Agenda | Where-Object { $_.Titre -like $env:EVERMIND_ALERTE_RV })[0]
    if ($rvA) { Show-AlerteRappel $rvA ($rvA.Quand) ($rvA.Quand.AddHours(-1)) } else { Show-Alerte 'Evermind n''entend rien' 'Aucun son ne vient du micro (coupé ?). Choisis le bon micro dans les réglages.' }
}
# Un téléchargement imaginaire en cours (l'assistant, 2,3 Go) : la barre vivante, la vitesse, le temps qui reste
if ($env:EVERMIND_TEST_TELECHARGEMENT) {
    $script:VoixDl = [hashtable]::Synchronized(@{ Recu = 812MB; Total = 2382MB; Etape = 'cerveau de l''assistant'; Erreur = ''; Fini = $false; Pack = 'ia'; Test = $true })
    $script:TestAttente = $true; $script:TestPas = 0
    $tt = New-Object System.Windows.Threading.DispatcherTimer; $tt.Interval = [TimeSpan]::FromMilliseconds(250)
    $tt.Add_Tick({ param($s) $script:VoixDl.Recu += 1.6MB; Update-VoixInstall; if (++$script:TestPas -ge 14) { $s.Stop(); $script:TestAttente = $false } })
    $tt.Start()
}if ($env:EVERMIND_JOUR) { Select-JourCalendrier ([datetime]$env:EVERMIND_JOUR) }
if ($env:EVERMIND_FICHE) {
    $it = @(@(Get-Upcoming) + @(Get-AgendaEntre (Get-Date).Date.AddDays(-30) (Get-Date)) | Where-Object { $_.RV.Titre -like $env:EVERMIND_FICHE })[0]
    if ($it) { Show-Fiche $it.RV $it.Prochain }
    # « Supprimer » dans la fiche, puis « Supprimer » dans la confirmation
    if ($it -and $env:EVERMIND_FICHE_SUPPRIMER) {
        $clic = New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent)
        $ui.BtnFicheSupprimer.RaiseEvent($clic); $ui.BtnConfirmationOui.RaiseEvent($clic)
    }
}
if ($env:EVERMIND_FORMULAIRE_RV) { Open-Formulaire -RV (@($script:Agenda | Where-Object { $_.Titre -like $env:EVERMIND_FORMULAIRE_RV })[0]) -Decaler:([bool]$env:EVERMIND_DECALER) }
if ($env:EVERMIND_TEST_PAROLE) { Invoke-Parole 'Salut ! C''est noté : anniversaire de Jordan, le 12 mars.' $env:EVERMIND_TEST_PAROLE }
if ($env:EVERMIND_DICTEE_WAV) { Start-Transcription $env:EVERMIND_DICTEE_WAV }
# Plusieurs phrases séparées par « || » : une conversation, chaque phrase après la réponse à la précédente
if ($env:EVERMIND_COMMANDE) {
    $script:TestPhrases = New-Object System.Collections.Queue
    foreach ($x in ($env:EVERMIND_COMMANDE -split '\|\|')) { if ($x.Trim()) { $script:TestPhrases.Enqueue($x.Trim()) } }
    $script:TestTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:TestTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:TestTimer.Add_Tick({
        if ($script:Demande) { return }
        if (-not $script:TestPhrases.Count) { $script:TestTimer.Stop(); $script:TestTimer = $null; return }
        if (-not (Invoke-Commande $script:TestPhrases.Dequeue() 'test')) { Write-Log 'Assistant absent'; $script:TestPhrases.Clear() }
    })
    $script:TestTimer.Start()
}
if ($env:EVERMIND_INSTALLER) { Start-VoixInstall }
if ($env:EVERMIND_FERMER) { Invoke-Croix }
# Mindset qui quitte : quitter.demande écrit après le démarrage, Evermind doit se fermer tout seul (sans capture)
if ($env:EVERMIND_TEST_QUITTER) {
    $script:TestAttente = $true
    $tq = New-Object System.Windows.Threading.DispatcherTimer; $tq.Interval = [TimeSpan]::FromMilliseconds(1500)
    $tq.Add_Tick({ param($s) $s.Stop(); [IO.File]::WriteAllText($QuitterFichier, '1234') })
    $tq.Start()
}
