# Evermind : saisie d'un rendez-vous (calendrier, heure) et liste « À venir ».
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# ---------------------------------------------------------------------------
# Calendrier du formulaire
# ---------------------------------------------------------------------------
$script:CalChoix = (Get-Date).Date                          # jour choisi
$script:CalMois = $script:CalChoix.AddDays(1 - $script:CalChoix.Day)   # premier jour du mois affiché

function Update-Calendrier {
    $first = $script:CalMois
    $today = (Get-Date).Date
    $ui.MoisTitre.Text = $Fr.TextInfo.ToTitleCase($first.ToString('MMMM yyyy', $Fr))
    $ui.BtnMoisPrec.IsEnabled = $first -gt $today.AddDays(1 - $today.Day)
    $ui.CalJours.Children.Clear()
    $start = $first.AddDays(-((([int]$first.DayOfWeek) + 6) % 7))   # la semaine commence le lundi
    $jourStyle = $Window.FindResource('Jour')
    for ($i = 0; $i -lt 42; $i++) {
        $d = $start.AddDays($i)
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $jourStyle
        $b.Content = [string]$d.Day
        $b.Tag = $d
        if ($d -lt $today) { $b.IsEnabled = $false }
        elseif ($d.Month -ne $first.Month) { $b.Foreground = Get-Brush '#5E5975' }
        if ($d -eq $script:CalChoix) {
            $b.Background = $Window.FindResource('AccentBg'); $b.Foreground = Get-Brush '#08060F'; $b.FontWeight = 'Bold'
            $b.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.Color]::FromRgb(0, 229, 255); BlurRadius = 16; ShadowDepth = 0; Opacity = 0.6 }
        } elseif ($d -eq $today) { $b.BorderBrush = Get-Brush '#00E5FF' }
        $b.Add_Click({ param($s) Select-Jour ([datetime]$s.Tag) })
        [void]$ui.CalJours.Children.Add($b)
    }
}

function Select-Jour([datetime]$Day) {
    $script:CalChoix = $Day.Date
    $script:CalMois = $script:CalChoix.AddDays(1 - $script:CalChoix.Day)
    Update-Calendrier
}

function Move-Mois([int]$Delta) {
    $script:CalMois = $script:CalMois.AddMonths($Delta)
    Update-Calendrier
}

# ---------------------------------------------------------------------------
# Ajout d'un rendez-vous
# ---------------------------------------------------------------------------
function Show-FormMessage([string]$Text, [string]$Color) {
    $ui.FormMessage.Text = $Text
    $ui.FormMessage.Foreground = Get-Brush $Color
    $ui.FormMessage.Visibility = 'Visible'
    $script:FormMsgErreur = $Color -eq $Colors.bad
}

function Invoke-Ajouter {
    $titre = $ui.InTitre.Text.Trim()
    if (-not $titre) {
        Show-FormMessage 'Écris d''abord ce que c''est (par exemple : dentiste).' $Colors.bad
        [void]$ui.InTitre.Focus(); return
    }
    $heure = Read-Heure $ui.InHeure.Text
    if ($null -eq $heure) {
        $msg = if ($ui.InHeure.Text.Trim()) { 'Je n''ai pas compris l''heure. Écris par exemple 15 h ou 15 h 30.' } else { 'À quelle heure ? Écris par exemple 15 h ou 15 h 30.' }
        Show-FormMessage $msg $Colors.bad
        [void]$ui.InHeure.Focus(); return
    }
    $quand = $script:CalChoix.Add($heure)
    if ($quand -lt (Get-Date)) {
        Show-FormMessage 'Cette heure est déjà passée. Choisis une heure plus tard ou un autre jour.' $Colors.bad
        [void]$ui.InHeure.Focus(); return
    }
    try { $r = Add-RendezVous $titre $quand }
    catch {
        Write-Log "Ajout impossible : $_"
        Show-FormMessage "Je n'ai pas réussi à enregistrer ce rendez-vous. ($($_.Exception.Message))" $Colors.bad
        return
    }
    Show-FormMessage "C'est noté : $($r.Titre), $(Format-Quand $r.Quand)." $Colors.ok
    $ui.InTitre.Text = ''; $ui.InHeure.Text = ''
    [void]$ui.InTitre.Focus()
    Update-Liste
}

# ---------------------------------------------------------------------------
# Liste « À venir »
# ---------------------------------------------------------------------------
function New-RendezVousRow($r) {
    $row = New-Object System.Windows.Controls.Border
    $row.Background = Get-Brush '#0FFFFFFF'; $row.BorderBrush = Get-Brush '#1CFFFFFF'; $row.BorderThickness = 1
    $row.CornerRadius = 18; $row.Padding = '14,12'; $row.Margin = '0,0,0,10'
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in 'Auto', '*', 'Auto') {
        $c = New-Object System.Windows.Controls.ColumnDefinition
        $c.Width = [System.Windows.GridLengthConverter]::new().ConvertFromString($w)
        $g.ColumnDefinitions.Add($c)
    }

    # Pastille du jour : numéro et mois, en dégradé si c'est aujourd'hui
    $today = $r.Quand.Date -eq (Get-Date).Date
    $badge = New-Object System.Windows.Controls.Border
    $badge.Width = 58; $badge.Height = 58; $badge.CornerRadius = 16; $badge.Margin = '0,0,16,0'
    $badge.Background = if ($today) { $Window.FindResource('AccentBg') } else { Get-Brush '#1AFFFFFF' }
    $bs = New-Object System.Windows.Controls.StackPanel; $bs.VerticalAlignment = 'Center'
    $num = New-Object System.Windows.Controls.TextBlock
    $num.Text = [string]$r.Quand.Day; $num.FontSize = 22; $num.FontWeight = 'Bold'; $num.HorizontalAlignment = 'Center'
    $mon = New-Object System.Windows.Controls.TextBlock
    $mon.Text = $r.Quand.ToString('MMM', $Fr).TrimEnd('.'); $mon.FontSize = 12; $mon.HorizontalAlignment = 'Center'; $mon.Margin = '0,-3,0,0'
    $fg = if ($today) { Get-Brush '#08060F' } else { Get-Brush '#FFFFFF' }
    $num.Foreground = $fg; $mon.Foreground = if ($today) { $fg } else { Get-Brush $Colors.dim }
    [void]$bs.Children.Add($num); [void]$bs.Children.Add($mon)
    $badge.Child = $bs
    [void]$g.Children.Add($badge)

    # Quoi, quand, dans combien de temps
    $txt = New-Object System.Windows.Controls.StackPanel; $txt.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($txt, 1)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = if ($r.Titre) { $r.Titre.Substring(0, 1).ToUpper() + $r.Titre.Substring(1) } else { 'Rendez-vous' }
    $t.FontSize = 17; $t.FontWeight = 'SemiBold'; $t.Foreground = Get-Brush '#FFFFFF'; $t.TextTrimming = 'CharacterEllipsis'
    $q = New-Object System.Windows.Controls.TextBlock
    $q.FontSize = 14; $q.Margin = '0,3,0,0'; $q.TextTrimming = 'CharacterEllipsis'
    $q.Inlines.Add((New-Object System.Windows.Documents.Run (Format-Quand $r.Quand) -Property @{ Foreground = Get-Brush '#C9C3DD' }))
    $q.Inlines.Add((New-Object System.Windows.Documents.Run ('   ' + (Format-Relatif $r.Quand)) -Property @{ Foreground = Get-Brush $Colors.accent }))
    [void]$txt.Children.Add($t); [void]$txt.Children.Add($q)
    [void]$g.Children.Add($txt)

    # Supprimer : un premier clic demande confirmation, le second supprime
    $del = New-Object System.Windows.Controls.Button
    $del.Style = $Window.FindResource('BtnSecondary'); $del.Content = 'Supprimer'; $del.Tag = $r.Id
    $del.VerticalAlignment = 'Center'; $del.Margin = '12,0,0,0'
    [System.Windows.Controls.Grid]::SetColumn($del, 2)
    $del.Add_Click({
        param($s)
        if ($s.Content -eq 'Supprimer') { $s.Content = 'Oui, supprimer'; $s.Style = $Window.FindResource('BtnDanger'); return }
        try { Remove-RendezVous ([string]$s.Tag) } catch { Write-Log "Suppression impossible : $_" }
        Update-Liste
    })
    $del.Add_MouseLeave({ param($s) if ($s.Content -ne 'Supprimer') { $s.Content = 'Supprimer'; $s.Style = $Window.FindResource('BtnSecondary') } })
    [void]$g.Children.Add($del)

    $row.Child = $g
    $row
}

function Update-Liste {
    $items = Get-Upcoming
    $ui.ListeAVenir.Children.Clear()
    foreach ($r in $items) { [void]$ui.ListeAVenir.Children.Add((New-RendezVousRow $r)) }
    $n = $items.Count
    $ui.ListeVide.Visibility = if ($n) { 'Collapsed' } else { 'Visible' }
    $ui.ListeCompte.Text = switch ($n) { 0 { '' } 1 { '1 rendez-vous' } default { "$n rendez-vous" } }
}
