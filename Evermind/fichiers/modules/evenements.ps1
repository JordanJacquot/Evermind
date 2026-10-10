# Evermind : branchement des boutons et événements de la fenêtre.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

$ui.VersionText.Text = "Evermind $AppVersion"
Update-Greeting
Update-Calendrier
Update-Liste

$ui.BtnMoisPrec.Add_Click({ Move-Mois -1 })
$ui.BtnMoisSuiv.Add_Click({ Move-Mois 1 })
$ui.BtnAjouter.Add_Click({ Invoke-Ajouter })
# Un message d'erreur sous le formulaire disparaît dès qu'on corrige
foreach ($box in $ui.InTitre, $ui.InHeure) { $box.Add_TextChanged({ if ($script:FormMsgErreur) { $ui.FormMessage.Visibility = 'Collapsed' } }) }

$ui.ChkDemarrage.IsChecked = if ($EnTest) { $true } else { Test-AutoStart }
$ui.ChkDemarrage.Add_Click({
    $on = [bool]$ui.ChkDemarrage.IsChecked
    try { Set-AutoStart $on; Write-Log "Démarrage avec Windows $(if ($on) { 'activé' } else { 'désactivé' })" }
    catch { $ui.ChkDemarrage.IsChecked = -not $on; Write-Log "Démarrage avec Windows : $_" }
})

# La croix cache Evermind près de l'horloge, « Quitter » (clic droit sur l'icône) le ferme vraiment
$Window.Add_Closing({ param($s, $e) if (-not $script:Quitting) { $e.Cancel = $true; Hide-ToTray } })
$Window.Add_Activated({ Update-Greeting; Update-Liste })   # la liste se remet à jour (« demain » devient « aujourd'hui »)
$Window.Add_Loaded({ [void]$ui.InTitre.Focus() })

# Un nouveau lancement d'Evermind demande d'afficher cette fenêtre (elle peut être cachée près de l'horloge)
if ($script:ShowSignal) {
    $script:ShowWatch = New-Object System.Windows.Threading.DispatcherTimer
    $script:ShowWatch.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:ShowWatch.Add_Tick({ if ($script:ShowSignal.WaitOne(0)) { Show-MainWindow } })
    $script:ShowWatch.Start()
}
