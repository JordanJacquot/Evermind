# Evermind : les détails d'un rendez-vous (fin, lieu, avec qui, lien, rappels, à préparer, notes, âge),
# leur saisie dans le formulaire et la fiche qui les montre.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# Idées de choses à préparer, selon la sorte de rendez-vous (un clic les ajoute à la liste)
$Suggestions = @{
    sante   = 'Carte Vitale', 'Ordonnance', 'Carte de mutuelle', 'Résultats d''analyses'
    voyage  = 'Billets', 'Pièce d''identité', 'Chargeur', 'Valise'
    sport   = 'Affaires de sport', 'Bouteille d''eau', 'Serviette'
    jeu     = 'Casque', 'Mettre le jeu à jour', 'Snacks'
    travail = 'Ordinateur', 'Documents', 'Badge'
    sortie  = 'Réserver', 'Cadeau', 'Argent liquide'
    anniv   = 'Cadeau', 'Carte', 'Gâteau'
    rdv     = 'Pièce d''identité', 'Documents'
    rappel  = @()
}
# Rappels proposés dans le formulaire (codes : voir Format-Rappel)
$RappelsChoix = 'm0', 'm10', 'm30', 'm60', 'matin', 'veille', 'm2880', 'm10080'

# Détails venant d'une phrase (barre rapide ou voix)
function Get-DetailsPhrase($p) {
    @{ Fin = $p.Fin; Lieu = [string]$p.Lieu; Avec = @($p.Avec); Lien = [string]$p.Lien; Rappels = $p.Rappels; Important = [bool]$p.Important; Naissance = $p.Naissance; APreparer = @($p.APreparer | Where-Object { $_ })
       Fichiers = @(Get-DossiersAuto $p.Titre $p.Avec) }   # « réunion avec Monsieur Richard » : son dossier, s'il est trouvé
}

# Lien ouvrable sans risque (seulement http et https), sinon $null
function Get-LienSur([string]$Lien) {
    $l = $Lien.Trim()
    if (-not $l) { return $null }
    if ($l -notmatch '^[a-z][a-z0-9+.-]*://') { $l = "https://$l" }
    try { $u = [uri]$l } catch { return $null }
    if ($u.IsAbsoluteUri -and $u.Scheme -in 'http', 'https') { $u.AbsoluteUri } else { $null }
}

# « Jordan aura 25 ans »
function Get-AgeTexte($RV, [datetime]$Quand) {
    if (-not $RV.Naissance) { return '' }
    $age = $Quand.Year - [int]$RV.Naissance
    if ($age -le 0 -or $age -gt 130) { return '' }
    $qui = $RV.Titre -replace "^Anniversaire (?:de |d')", ''
    if ($qui -eq 'Anniversaire') { $qui = 'Tu' }
    $verbe = if ($Quand.Date -lt (Get-Date).Date) { 'a eu' } elseif ($Quand.Date -eq (Get-Date).Date) { 'a' } else { 'aura' }
    if ($qui -eq 'Tu') { $verbe = @{ 'a eu' = 'as eu'; 'a' = 'as'; 'aura' = 'auras' }[$verbe] }
    "$qui $verbe $age ans"
}

# Petit résumé pour une ligne de la liste : « Zénith · avec Paul · 1 sur 3 prêt »
function Get-ResumeDetails($RV) {
    $parts = @()
    # (sans émojis : ils changent d'un Windows à l'autre)
    if ($RV.Lieu) { $parts += [string]$RV.Lieu }
    if (@($RV.Avec).Count) { $parts += "avec $(@($RV.Avec) -join ', ')" }
    $ap = @($RV.APreparer)
    if ($ap.Count) { $parts += "$(@($ap | Where-Object { $_.Fait }).Count)/$($ap.Count) prêt" }
    if ($RV.Lien) { $parts += 'lien' }
    if ($RV.Notes) { $parts += 'notes' }
    $parts -join '  ·  '
}

# ---------------------------------------------------------------------------
# Formulaire : les détails
# ---------------------------------------------------------------------------
# Formulaire : la liste des dossiers et fichiers (chacun avec une croix pour le retirer)
function Update-FFichiers {
    $ui.FFichiers.Children.Clear()
    foreach ($chemin in @($script:FFichiers)) {
        $ligne = New-Object System.Windows.Controls.Border
        $ligne.Padding = '10,5'; $ligne.Margin = '0,0,0,4'; $ligne.CornerRadius = 10; $ligne.Background = Get-Brush '#0FFFFFFF'
        $dp = New-Object System.Windows.Controls.DockPanel
        $x = New-Button '✕'; $x.Tag = $chemin; $x.Padding = '10,3'; $x.Margin = '8,0,0,0'; $x.ToolTip = 'Retirer (le fichier n''est pas supprimé)'
        $x.Add_Click({ param($s) $script:FFichiers = @($script:FFichiers | Where-Object { $_ -ne [string]$s.Tag }); Update-FFichiers })
        [System.Windows.Controls.DockPanel]::SetDock($x, 'Right'); [void]$dp.Children.Add($x)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = "$(if (Test-Path -LiteralPath $chemin -PathType Container) { '📁' } else { '📄' })  $(Split-Path $chemin -Leaf)"
        $t.ToolTip = $chemin; $t.FontSize = 14; $t.Foreground = Get-Brush '#F2EFFA'; $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'
        [void]$dp.Children.Add($t)
        $ligne.Child = $dp
        [void]$ui.FFichiers.Children.Add($ligne)
    }
    $ui.FOuvrirDebut.Visibility = if (@($script:FFichiers).Count) { 'Visible' } else { 'Collapsed' }
}

function Add-FFichiers([string[]]$Chemins) {
    $script:FFichiers = @(@($script:FFichiers) + @($Chemins | Where-Object { $_ }) | Select-Object -Unique)
    Update-FFichiers
}

function Initialize-FDetails {
    $ui.FAjouterDossier.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = 'Choisis le dossier à relier à ce rendez-vous'
        $r = @(Get-DossiersRecherche)[0]; if ($r -and (Test-Path -LiteralPath $r)) { $d.SelectedPath = $r }
        if ($d.ShowDialog() -eq 'OK') { Add-FFichiers @($d.SelectedPath) }
    })
    $ui.FAjouterFichier.Add_Click({
        $d = New-Object Microsoft.Win32.OpenFileDialog
        $d.Title = 'Choisis les fichiers à relier à ce rendez-vous'; $d.Multiselect = $true
        if ($d.ShowDialog($Window)) { Add-FFichiers $d.FileNames }
    })
    $ui.FTrouverDossier.Add_Click({
        $avec = @($ui.FAvec.Text -split '\s*(?:,|;|\bet\b)\s*' | Where-Object { $_.Trim() })
        $trouves = @(Get-DossiersAuto $ui.FTitre.Text $avec)
        $ui.FFichiersInfo.Visibility = 'Visible'
        if ($trouves.Count) { Add-FFichiers $trouves; $ui.FFichiersInfo.Text = "Trouvé : $(@($trouves | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')." }
        else { $ui.FFichiersInfo.Text = "Je n'ai pas trouvé de dossier à ce nom (j'ai regardé dans : $(@(Get-DossiersRecherche) -join ', ')). Écris le nom de la personne dans « Avec qui ? », ou ajoute le dossier à la main." }
    })
    $style = $Window.FindResource('Chip')
    foreach ($c in $RappelsChoix) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $style; $b.Name = "FRap_$c"; $b.Content = Get-Majuscule (Format-Rappel $c); $b.Padding = '12,6'; $b.FontSize = 13
        $b.Add_Click({
            param($s)
            $code = $s.Name -replace '^FRap_', ''
            $sel = New-Object System.Collections.ArrayList
            foreach ($x in @(Get-FRappelsActuels)) { [void]$sel.Add($x) }
            if ($sel -contains $code) { $sel.Remove($code) } else { [void]$sel.Add($code) }
            $script:FRappels = @($RappelsChoix | Where-Object { $sel -contains $_ })   # gardés dans l'ordre de la liste
            Update-FRappels
        })
        [void]$ui.FRappels.Children.Add($b)
    }
    foreach ($n in 'FDuree30', 'FDuree60', 'FDuree120') {
        $ui[$n].Add_Click({
            param($s)
            $h = Read-Heure $ui.FHeure.Text
            if ($null -eq $h) { Show-FMessage 'Mets d''abord l''heure de début.'; [void]$ui.FHeure.Focus(); return }
            $ui.FFin.Text = Format-Heure ([datetime]::Today + $h + [timespan]::FromMinutes([int]($s.Name -replace '^FDuree', '')))
        })
    }
    $ui.FFin.Add_TextChanged({ Update-FFinInfo })
    $ui.FDernier.Add_TextChanged({ Update-FDernierInfo })
    $ui.FNaissance.Add_TextChanged({ Update-FAgeInfo })
    $ui.FImportant.Add_Click({ $ui.FImportant.Tag = if ($ui.FImportant.Tag -eq 'on') { $null } else { 'on' } })
}

# Rappels choisis : ceux du rendez-vous, ou ceux par défaut de sa sorte tant qu'on n'y a pas touché
function Get-FRappelsActuels {
    if ($null -ne $script:FRappels) { return @($script:FRappels) }
    Get-RappelsDefaut $(if ($script:FType) { $script:FType } else { 'rdv' }) ([bool]$script:FJournee)
}

function Update-FRappels {
    $sel = @(Get-FRappelsActuels)
    foreach ($b in $ui.FRappels.Children) {
        $code = $b.Name -replace '^FRap_', ''
        $b.Tag = if ($sel -contains $code) { 'on' } else { $null }
        # Une journée entière (anniversaire) n'a pas d'heure : seuls la veille, le matin et les jours avant ont un sens
        $b.Visibility = if ($script:FJournee -and $code -match '^m(0|10|30|60)$') { 'Collapsed' } else { 'Visible' }
    }
}

function Update-FSuggestions {
    $ui.FSuggestions.Children.Clear()
    $type = if ($script:FType) { $script:FType } else { 'rdv' }
    foreach ($s in @($Suggestions[$type])) {
        if (-not $s) { continue }
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $Window.FindResource('Chip'); $b.Content = "+ $s"; $b.Tag = $s
        $b.Add_Click({
            param($s)
            $lignes = @($ui.FPreparer.Text -split "`r?`n" | Where-Object { $_.Trim() })
            if ($lignes -notcontains [string]$s.Tag) { $ui.FPreparer.Text = (@($lignes) + [string]$s.Tag) -join "`r`n" }
        })
        [void]$ui.FSuggestions.Children.Add($b)
    }
}

function Update-FFinInfo {
    $ui.FFinInfo.Text = ''
    $debut = Read-Heure $ui.FHeure.Text
    $fin = Read-FFin $debut
    if ($ui.FFin.Text.Trim() -and $null -eq $fin) { $ui.FFinInfo.Text = 'Je ne comprends pas cette heure'; $ui.FFinInfo.Foreground = Get-Brush $Colors.bad }
    elseif ($null -ne $fin -and $null -ne $debut) { $ui.FFinInfo.Text = "dure $(Format-Duree ($fin - $debut))"; $ui.FFinInfo.Foreground = Get-Brush $Colors.ok }
}

# Dernier jour d'un événement sur plusieurs jours (« 29 octobre », « jeudi ») : la date, ou $null si vide ou incompris
function Read-FDernier {
    $t = $ui.FDernier.Text.Trim()
    if (-not $t) { return $null }
    $p = Read-Periode $t
    if ($p -and $p.Debut -and $p.Fin -and $p.Debut -eq $p.Fin) { return $p.Debut }
    $null
}

function Update-FDernierInfo {
    $ui.FDernierInfo.Text = ''
    if (-not $ui.FDernier.Text.Trim()) { return }
    $f = Read-FDernier
    if (-not $f) { $ui.FDernierInfo.Text = 'Je ne comprends pas ce jour'; $ui.FDernierInfo.Foreground = Get-Brush $Colors.bad; return }
    $n = ($f - $script:FChoix.Date).Days + 1
    if ($n -lt 2) { $ui.FDernierInfo.Text = 'doit être après le premier jour'; $ui.FDernierInfo.Foreground = Get-Brush $Colors.bad }
    else { $ui.FDernierInfo.Text = "$n jours, jusqu'au $($f.ToString('dddd d MMMM', $Fr))"; $ui.FDernierInfo.Foreground = Get-Brush $Colors.ok }
}

# Heure de fin du formulaire, en durée depuis minuit (« de 22 h à 1 h » finit le lendemain) ; $null si vide ou incomprise
function Read-FFin($Debut) {
    $t = $ui.FFin.Text.Trim()
    if (-not $t) { return $null }
    $f = Read-Heure $t
    if ($null -eq $f) { return $null }
    if ($null -ne $Debut) { while ($f -le $Debut -and ($Debut - $f).TotalHours -lt 24) { $f = $f.Add([timespan]::FromHours(12)) } }
    $f
}

function Update-FAgeInfo {
    $ui.FAgeInfo.Text = ''
    $y = 0
    if ([int]::TryParse($ui.FNaissance.Text.Trim(), [ref]$y) -and $y -gt 1890 -and $y -le (Get-Date).Year) {
        $prochain = Get-NextOccurrence ([ordered]@{ Type = 'an'; Jour = $script:FChoix.Day; Mois = $script:FChoix.Month }) $script:FChoix (Get-Date).Date
        $ui.FAgeInfo.Text = "aura $($prochain.Year - $y) ans le $(Format-Jour $prochain)"
        $ui.FAgeInfo.Foreground = Get-Brush $Colors.ok
    }
}

# Remplit les détails du formulaire (depuis un rendez-vous, ou depuis ce que la phrase a compris)
function Set-FDetails($Source) {
    $ui.FFin.Text = if ($Source -and $Source.Fin -and $Source.Quand -and -not $Source.Journee) { Format-Heure ([datetime]$Source.Fin) } else { '' }
    $ui.FDernier.Text = if ($Source -and $Source.Journee -and $Source.Fin -and $Source.Quand -and ([datetime]$Source.Fin).Date -gt ([datetime]$Source.Quand).Date) {
        $f = [datetime]$Source.Fin; $f.ToString('d MMMM', $Fr) + $(if ($f.Year -ne (Get-Date).Year) { " $($f.Year)" })
    } else { '' }
    $ui.FLieu.Text = if ($Source) { [string]$Source.Lieu } else { '' }
    $ui.FAvec.Text = if ($Source) { @($Source.Avec) -join ', ' } else { '' }
    $ui.FLien.Text = if ($Source) { [string]$Source.Lien } else { '' }
    $ui.FPreparer.Text = if ($Source -and $Source.APreparer) { (@($Source.APreparer) | ForEach-Object { $_.Texte }) -join "`r`n" } else { '' }
    $ui.FNotes.Text = if ($Source) { [string]$Source.Notes } else { '' }
    $ui.FNaissance.Text = if ($Source -and $Source.Naissance) { [string]$Source.Naissance } else { '' }
    $ui.FImportant.Tag = if ($Source -and $Source.Important) { 'on' } else { $null }
    if ($Source -and $null -ne $Source.Rappels) { $script:FRappels = @($Source.Rappels) } else { $script:FRappels = $null }
    $script:FAvant = if ($Source -and $Source.APreparer) { @($Source.APreparer) } else { @() }   # pour garder les cases déjà cochées
    $script:FFichiers = if ($Source -and $Source.Fichiers) { @($Source.Fichiers) } else { @() }
    $ui.FOuvrirDebut.IsChecked = [bool]($Source -and $Source.OuvrirAuDebut)
    $ui.FFichiersInfo.Visibility = 'Collapsed'
    Update-FFichiers
}

# Met à jour ce qui dépend de la sorte et de « toute la journée »
function Update-FDetailsVisibles {
    $ui.FAnnivPanel.Visibility = if ($script:FType -eq 'anniv') { 'Visible' } else { 'Collapsed' }
    $ui.FFinPanel.Visibility = if ($script:FJournee) { 'Collapsed' } else { 'Visible' }
    $ui.FDernierPanel.Visibility = if ($script:FJournee -and $script:FType -ne 'anniv' -and $script:FRepet -in $null, '', 'une') { 'Visible' } else { 'Collapsed' }
    Update-FSuggestions
    Update-FRappels
    Update-FAgeInfo
}

# Lit les détails du formulaire. Retourne @{ Detail = ... } ou @{ Erreur = '...' }
function Read-FDetails([datetime]$Quand, [bool]$Journee) {
    $fin = $null
    if (-not $Journee -and $ui.FFin.Text.Trim()) {
        $f = Read-FFin $Quand.TimeOfDay
        if ($null -eq $f) { return @{ Erreur = 'Je n''ai pas compris l''heure de fin. Écris par exemple 16 h, ou efface-la.' } }
        $fin = $Quand.Date + $f
    } elseif ($Journee -and $ui.FDernierPanel.Visibility -eq 'Visible' -and $ui.FDernier.Text.Trim()) {
        $f = Read-FDernier
        if (-not $f) { return @{ Erreur = 'Je n''ai pas compris le dernier jour. Écris par exemple 29 octobre, ou efface-le.' } }
        if ($f -le $Quand.Date) { return @{ Erreur = 'Le dernier jour doit être après le premier jour.' } }
        $fin = $f
    }
    $naissance = $null
    $nt = $ui.FNaissance.Text.Trim()
    if ($script:FType -eq 'anniv' -and $nt) {
        $y = 0
        if (-not [int]::TryParse($nt, [ref]$y) -or $y -lt 1890 -or $y -gt (Get-Date).Year) { return @{ Erreur = 'L''année de naissance doit ressembler à 1998.' } }
        $naissance = $y
    }
    $lien = $ui.FLien.Text.Trim()
    if ($lien -and -not (Get-LienSur $lien)) { return @{ Erreur = 'Ce lien ne ressemble pas à une adresse web (https://...).' } }
    # Liste à préparer : une ligne = une chose ; les cases déjà cochées le restent
    $avant = @{}; foreach ($x in @($script:FAvant)) { $avant[$x.Texte] = [bool]$x.Fait }
    $prep = @(foreach ($l in ($ui.FPreparer.Text -split "`r?`n")) { $t = $l.Trim(); if ($t) { [pscustomobject]@{ Texte = $t; Fait = [bool]$avant[$t] } } })
    @{ Detail = @{
        Fin = $fin; Lieu = $ui.FLieu.Text.Trim(); Lien = $lien; Notes = $ui.FNotes.Text.Trim()
        Avec = @($ui.FAvec.Text -split '\s*(?:,|;|\bet\b)\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        APreparer = $prep; Important = ($ui.FImportant.Tag -eq 'on'); Naissance = $naissance
        Fichiers = @($script:FFichiers); OuvrirAuDebut = ([bool]$ui.FOuvrirDebut.IsChecked -and @($script:FFichiers).Count -gt 0)
        Rappels = $(if ($null -ne $script:FRappels) { , @($script:FRappels) } else { $null })
    } }
}

# ---------------------------------------------------------------------------
# Fiche d'un rendez-vous
# ---------------------------------------------------------------------------
function New-FicheSection([string]$Icone, [string]$Titre, $Contenu) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = '0,0,0,16'
    foreach ($w in '34', '*') { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = [System.Windows.GridLengthConverter]::new().ConvertFromString($w); $g.ColumnDefinitions.Add($c) }
    # L'icône dessinée (« 📍 » : le repère du lieu...), à gauche du titre
    $i = New-Icone $(if ($IconesEmoji[$Icone]) { $IconesEmoji[$Icone] } else { 'rdv' }) 18 $Colors.dim
    $i.HorizontalAlignment = 'Left'; $i.VerticalAlignment = 'Top'; $i.Margin = '0,0,0,0'
    [void]$g.Children.Add($i)
    $sp = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Titre.ToUpper(); $t.FontSize = 11; $t.FontWeight = 'Bold'; $t.Foreground = Get-Brush $Colors.dim; $t.Margin = '0,0,0,4'
    [void]$sp.Children.Add($t)
    if ($Contenu -is [string]) {
        $c = New-Object System.Windows.Controls.TextBlock
        $c.Text = $Contenu; $c.FontSize = 15; $c.Foreground = Get-Brush '#F2EFFA'; $c.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($c)
    } else { [void]$sp.Children.Add($Contenu) }
    [void]$g.Children.Add($sp)
    $g
}

# Texte suivi d'un petit bouton (« Itinéraire », « Ouvrir »)
function New-TexteBouton([string]$Texte, [string]$Bouton, [string]$Url) {
    $dp = New-Object System.Windows.Controls.DockPanel
    $b = New-Button $Bouton
    $b.Tag = $Url; $b.Margin = '12,0,0,0'; $b.VerticalAlignment = 'Top'
    $b.ToolTip = 'S''ouvre dans ton navigateur'
    $b.Add_Click({ param($s) try { Start-Process ([string]$s.Tag) } catch { Write-Log "Ouverture du lien : $_" } })
    [System.Windows.Controls.DockPanel]::SetDock($b, 'Right')
    [void]$dp.Children.Add($b)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Texte; $t.FontSize = 15; $t.Foreground = Get-Brush '#F2EFFA'; $t.TextWrapping = 'Wrap'; $t.VerticalAlignment = 'Center'
    [void]$dp.Children.Add($t)
    $dp
}

# Liste à préparer avec des cases à cocher (enregistrées tout de suite)
function New-ListeAPreparer($RV) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $i = 0
    foreach ($x in @($RV.APreparer)) {
        $ligne = New-Object System.Windows.Controls.Border
        $ligne.Padding = '8,6'; $ligne.Margin = '0,0,0,4'; $ligne.CornerRadius = 10; $ligne.Cursor = 'Hand'
        $ligne.Background = Get-Brush $(if ($x.Fait) { '#1A3DDC97' } else { '#0FFFFFFF' })
        $ligne.Tag = $i
        $dp = New-Object System.Windows.Controls.StackPanel; $dp.Orientation = 'Horizontal'
        $case = New-Object System.Windows.Controls.TextBlock
        $case.Text = if ($x.Fait) { '☑' } else { '☐' }; $case.FontFamily = 'Segoe UI Symbol'; $case.FontSize = 17; $case.Margin = '0,0,10,0'
        $case.Foreground = Get-Brush $(if ($x.Fait) { '#3DDC97' } else { '#C9C3DD' })
        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = $x.Texte; $txt.FontSize = 15; $txt.VerticalAlignment = 'Center'
        $txt.Foreground = Get-Brush $(if ($x.Fait) { $Colors.dim } else { '#F2EFFA' })
        if ($x.Fait) { $txt.TextDecorations = [System.Windows.TextDecorations]::Strikethrough }
        [void]$dp.Children.Add($case); [void]$dp.Children.Add($txt)
        $ligne.Child = $dp
        $ligne.Add_MouseLeftButtonUp({
            param($s)
            $rv = $script:FicheRV
            $liste = @($rv.APreparer | ForEach-Object { [pscustomobject]@{ Texte = $_.Texte; Fait = [bool]$_.Fait } })
            $liste[[int]$s.Tag].Fait = -not $liste[[int]$s.Tag].Fait
            Save-Annulation; Set-RendezVousDetail $rv.Id 'APreparer' $liste
            Show-Fiche $rv $script:FicheQuand
            Update-Agenda
        })
        [void]$sp.Children.Add($ligne)
        $i++
    }
    $sp
}

# Dossiers et fichiers reliés : chacun avec « Ouvrir » ; « Tout ouvrir » ; « Ouvrir au début » (à l'heure, tout s'ouvre)
function New-ListeFichiers($RV) {
    $sp = New-Object System.Windows.Controls.StackPanel
    foreach ($chemin in @($RV.Fichiers)) {
        $existe = Test-Path -LiteralPath $chemin
        $dossier = $existe -and (Test-Path -LiteralPath $chemin -PathType Container)
        $ligne = New-Object System.Windows.Controls.Border
        $ligne.Padding = '10,6'; $ligne.Margin = '0,0,0,4'; $ligne.CornerRadius = 10; $ligne.Background = Get-Brush '#0FFFFFFF'
        $dp = New-Object System.Windows.Controls.DockPanel
        $b = New-Button 'Ouvrir'; $b.Tag = $chemin; $b.Margin = '10,0,0,0'; $b.IsEnabled = $existe
        $b.Add_Click({ param($s) [void](Open-Fichier ([string]$s.Tag)) })
        [System.Windows.Controls.DockPanel]::SetDock($b, 'Right'); [void]$dp.Children.Add($b)
        $ic = New-Icone $(if ($dossier) { 'dossier' } else { 'fichier' }) 18 '#C9C3DD'; $ic.Margin = '0,0,10,0'
        [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$dp.Children.Add($ic)
        $txt = New-Object System.Windows.Controls.StackPanel; $txt.VerticalAlignment = 'Center'
        $n = New-Object System.Windows.Controls.TextBlock; $n.Text = (Split-Path $chemin -Leaf); $n.FontSize = 15; $n.Foreground = Get-Brush '#F2EFFA'; $n.TextTrimming = 'CharacterEllipsis'
        $c = New-Object System.Windows.Controls.TextBlock; $c.FontSize = 12; $c.TextTrimming = 'CharacterEllipsis'
        $c.Text = if ($existe) { Split-Path $chemin -Parent } else { "Introuvable : $chemin" }
        $c.Foreground = Get-Brush $(if ($existe) { $Colors.dim } else { '#FFB547' })
        [void]$txt.Children.Add($n); [void]$txt.Children.Add($c)
        [void]$dp.Children.Add($txt)
        $ligne.Child = $dp
        [void]$sp.Children.Add($ligne)
    }
    $bas = New-Object System.Windows.Controls.WrapPanel; $bas.Margin = '0,4,0,0'
    if (@($RV.Fichiers).Count -gt 1) {
        $tout = New-Button 'Tout ouvrir' 'BtnPrimary'; $tout.Margin = '0,0,10,0'
        $tout.Add_Click({ [void](Open-FichiersRV $script:FicheRV) })
        [void]$bas.Children.Add($tout)
    }
    # « Ouvrir au début » : un interrupteur, enregistré tout de suite
    $ch = New-Object System.Windows.Controls.CheckBox
    $ch.Style = $Window.FindResource('Switch'); $ch.IsChecked = [bool]$RV.OuvrirAuDebut; $ch.VerticalAlignment = 'Center'
    $ch.Add_Click({ param($s) Save-Annulation; Set-RendezVousDetail $script:FicheRV.Id 'OuvrirAuDebut' ([bool]$s.IsChecked); Write-Log "Ouvrir au début : $([bool]$s.IsChecked) ($($script:FicheRV.Titre))" })
    $lt = New-Object System.Windows.Controls.TextBlock
    $lt.Text = if ($RV.Journee) { 'Les ouvrir le matin même (rendez-vous sans heure)' } else { 'Les ouvrir tout seul à l''heure du rendez-vous' }
    $lt.FontSize = 14; $lt.Foreground = Get-Brush '#C9C3DD'; $lt.Margin = '10,0,0,0'; $lt.VerticalAlignment = 'Center'
    $sw = New-Object System.Windows.Controls.StackPanel; $sw.Orientation = 'Horizontal'; $sw.VerticalAlignment = 'Center'
    [void]$sw.Children.Add($ch); [void]$sw.Children.Add($lt)
    [void]$bas.Children.Add($sw)
    [void]$sp.Children.Add($bas)
    $sp
}

# Pas encore de fichiers, mais Evermind a trouvé le dossier des personnes : « Relier »
function New-SuggestionFichiers($RV, [string[]]$Trouves) {
    $sp = New-Object System.Windows.Controls.StackPanel
    foreach ($chemin in $Trouves) {
        $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '0,0,0,4'
        $b = New-Button 'Relier' 'BtnPrimary'; $b.Tag = $chemin; $b.Margin = '12,0,0,0'; $b.VerticalAlignment = 'Center'
        $b.Add_Click({ param($s) $rv = $script:FicheRV; Save-Annulation; Set-RendezVousDetail $rv.Id 'Fichiers' (@($rv.Fichiers) + [string]$s.Tag); Write-Log "Dossier relié : $($s.Tag)"; Show-Fiche $rv $script:FicheQuand })
        [System.Windows.Controls.DockPanel]::SetDock($b, 'Right'); [void]$dp.Children.Add($b)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = "J'ai trouvé $(Get-NomFichier $chemin), dans $(Split-Path $chemin -Parent). Le relier à ce rendez-vous ?"
        $t.FontSize = 15; $t.Foreground = Get-Brush '#F2EFFA'; $t.TextWrapping = 'Wrap'; $t.VerticalAlignment = 'Center'
        [void]$dp.Children.Add($t)
        [void]$sp.Children.Add($dp)
    }
    $sp
}
function Show-Fiche($RV, [datetime]$Quand) {
    if (-not $RV) { return }
    $script:FicheRV = $RV; $script:FicheQuand = $Quand
    $type = Get-TypeRV $RV
    $t = $Types[$type]
    # En-tête aux couleurs de la sorte
    $bg = New-Object System.Windows.Media.LinearGradientBrush
    $bg.StartPoint = '0,0'; $bg.EndPoint = '1,1'
    $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur ('#55' + $t.Couleur.TrimStart('#')))), 0))
    $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur '#10FFFFFF')), 1))
    $ui.FicheTete.Background = $bg
    $ui.FicheRond.Background = Get-Teinte $t.Couleur 0x30; $ui.FicheRond.BorderBrush = Get-Brush $t.Couleur
    $ui.FicheRond.Child = New-Icone $type 36
    try { $ui.FicheLueur.Color = (Get-Couleur $t.Couleur) } catch {}
    $valide = $type -ne 'rappel' -and (Test-Valide $RV $Quand)
    $ui.FicheSorte.Text = $t.Nom.ToUpper() + $(if ($RV.Important) { '   ★ IMPORTANT' } else { '' }) + $(if ($RV.Fait) { '   ✓ FAIT' } elseif ($valide) { '   ✓ VALIDÉ' } else { '' })
    $ui.FicheSorte.Foreground = Get-Brush $(if ($RV.Important) { '#FFD84D' } else { $t.Couleur })
    $ui.FicheTitre.Text = Get-TitreAffiche $RV.Titre
    $rep = Format-Repetition $RV.Repetition
    $ui.FicheQuand.Text = (Get-Majuscule (Format-QuandRV $RV $Quand)) + "   ($(Format-Relatif $Quand))" + $(if ($rep) { "`n↻ $rep" } else { '' })

    # Corps : seulement ce qui est rempli
    $c = $ui.FicheCorps.Children
    $c.Clear()
    # Passé : validé tout seul, mais s'il n'a pas eu lieu on peut encore le décaler
    if ($valide) {
        $dp = New-Object System.Windows.Controls.DockPanel
        if (-not $RV.Repetition) {
            $b = New-Button 'Décaler'
            $b.Margin = '12,0,0,0'; $b.VerticalAlignment = 'Top'; $b.ToolTip = 'Choisis un autre jour'
            $b.Add_Click({ $rv = $script:FicheRV; Close-Fiche; Open-Formulaire -RV $rv -Decaler })
            [System.Windows.Controls.DockPanel]::SetDock($b, 'Right'); [void]$dp.Children.Add($b)
        }
        $vt = New-Object System.Windows.Controls.TextBlock
        $vt.Text = if ($RV.Repetition) { 'Cette fois-ci est passée, elle est validée toute seule.' } else { 'Il est passé, je l''ai validé tout seul. S''il n''a pas eu lieu, tu peux encore le décaler.' }
        $vt.FontSize = 15; $vt.Foreground = Get-Brush '#3DDC97'; $vt.TextWrapping = 'Wrap'; $vt.VerticalAlignment = 'Center'
        [void]$dp.Children.Add($vt)
        [void]$c.Add((New-FicheSection '✓' 'Validé' $dp))
        Set-IconeCouleur $c[$c.Count - 1].Children[0] '#3DDC97'
    }
    $age = Get-AgeTexte $RV $Quand
    if ($age) { [void]$c.Add((New-FicheSection '🎂' 'Âge' $age)) }
    if ($RV.Lieu) { [void]$c.Add((New-FicheSection '📍' 'Où' (New-TexteBouton $RV.Lieu 'Itinéraire' ('https://www.google.com/maps/search/?api=1&query=' + [uri]::EscapeDataString($RV.Lieu))))) }
    if (@($RV.Avec).Count) { [void]$c.Add((New-FicheSection '👥' 'Avec' (@($RV.Avec) -join ', '))) }
    if (@($RV.Fichiers).Count) { [void]$c.Add((New-FicheSection '📁' 'Dossiers et fichiers' (New-ListeFichiers $RV))) }
    else {
        $trouves = @(Get-DossiersAuto $RV.Titre $RV.Avec)
        if ($trouves.Count) { [void]$c.Add((New-FicheSection '📁' 'Dossier trouvé' (New-SuggestionFichiers $RV $trouves))) }
    }
    $lien = Get-LienSur ([string]$RV.Lien)
    if ($lien) { [void]$c.Add((New-FicheSection '🔗' 'Lien' (New-TexteBouton $RV.Lien 'Ouvrir' $lien))) }
    $rap = @(Get-RappelsRV $RV)
    $rapTexte = if ($rap.Count) { (@($rap | ForEach-Object { Format-Rappel $_ }) -join ', ') } else { 'aucun rappel' }
    if ($null -eq $RV.Rappels) { $rapTexte += '  (réglage par défaut)' }
    [void]$c.Add((New-FicheSection '🔔' 'Je te préviens' (Get-Majuscule $rapTexte)))
    if (@($RV.APreparer).Count) {
        $nb = @($RV.APreparer | Where-Object { $_.Fait }).Count
        [void]$c.Add((New-FicheSection '☑' "À préparer ($nb sur $(@($RV.APreparer).Count))" (New-ListeAPreparer $RV)))
    }
    if ($RV.Notes) { [void]$c.Add((New-FicheSection '📝' 'Notes' $RV.Notes)) }
    if (-not $RV.Journee -and -not $RV.Fait) {
        $fin = if ($RV.Fin) { $Quand + ($RV.Fin - $RV.Quand) } else { $null }
        $conf = @(Get-Conflits $Quand $fin $RV.Id)
        if ($conf.Count) {
            [void]$c.Add((New-FicheSection '⚠' 'En même temps' ((@($conf | ForEach-Object { "$(Get-TitreAffiche $_.RV.Titre) ($(Format-Heure $_.Prochain))" }) -join ', '))))
            $c[$c.Count - 1].Children[1].Children[1].Foreground = Get-Brush '#FFB547'
        }
    }
    if (-not $RV.Lieu -and -not @($RV.Avec).Count -and -not $RV.Lien -and -not @($RV.APreparer).Count -and -not $RV.Notes -and -not $age -and -not @($RV.Fichiers).Count) {
        $vide = New-Object System.Windows.Controls.TextBlock
        $vide.Text = 'Pas encore de détails. Appuie sur « Modifier » pour ajouter un lieu, des personnes, une liste de choses à préparer ou des notes.'
        $vide.FontSize = 14; $vide.Foreground = Get-Brush $Colors.dim; $vide.TextWrapping = 'Wrap'; $vide.Margin = '34,0,0,12'
        [void]$c.Add($vide)
    }

    # Boutons : « C'est fait » pour les choses à faire
    $ui.BtnFicheFait.Visibility = if ($type -eq 'rappel') { 'Visible' } else { 'Collapsed' }
    $ui.BtnFicheFait.Content = if ($RV.Fait) { 'Pas encore fait' } else { '✓  C''est fait' }
    $ui.Fiche.Visibility = 'Visible'
}

function Close-Fiche { $ui.Fiche.Visibility = 'Collapsed'; $script:FicheRV = $null }

function Initialize-Fiche {
    $ui.BtnFicheFermer.Add_Click({ Close-Fiche })
    $ui.FicheFond.Add_MouseLeftButtonDown({ Close-Fiche })
    $ui.BtnFicheModifier.Add_Click({ $rv = $script:FicheRV; Close-Fiche; Open-Formulaire -RV $rv })
    $ui.BtnFicheDupliquer.Add_Click({ $rv = $script:FicheRV; Close-Fiche; Open-Formulaire -RV $rv -Copie })
    $ui.BtnFicheFait.Add_Click({
        $rv = $script:FicheRV
        Save-Annulation; Set-RendezVousDetail $rv.Id 'Fait' (-not $rv.Fait)
        Show-Fiche $rv $script:FicheQuand
        Update-Agenda
    })
    $ui.BtnFicheSupprimer.Add_Click({ Confirm-Suppression $script:FicheRV.Id })
}
