# Evermind : l'agenda à l'écran. Barre rapide (une phrase, écrite ou dite), calendrier du mois,
# liste « À venir » ou du jour choisi, et formulaire pour ajouter ou modifier à la main.
# Chaque sorte de rendez-vous a son icône et sa couleur ; un anniversaire a sa propre carte.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

$Manques = @{
    heure    = 'Il me manque l''heure. Ajoute par exemple « à 15 h ».'
    jour     = 'Il me manque le jour. Ajoute par exemple « le 12 mars ».'
    quand    = 'Il me manque le jour et l''heure. Ajoute par exemple « demain à 15 h ».'
    passe    = 'Ce moment est déjà passé. Choisis un autre jour ou une autre heure.'
    invalide = 'Cette date n''existe pas. Vérifie le jour et le mois.'
}
$PoliceIcone = 'Segoe UI Emoji'

function Get-TitreAffiche([string]$Titre) {
    if (-not $Titre) { return 'Rendez-vous' }
    $Titre.Substring(0, 1).ToUpper() + $Titre.Substring(1)
}

function Get-Majuscule([string]$Texte) { if ($Texte) { $Texte.Substring(0, 1).ToUpper() + $Texte.Substring(1) } else { $Texte } }

# Couleur d'une sorte, plus ou moins transparente (Alpha de 0 à 255)
function Get-Teinte([string]$Hex, [int]$Alpha) { Get-Brush ('#{0:X2}{1}' -f $Alpha, $Hex.TrimStart('#')) }

function New-Run([string]$Texte, [string]$Couleur, [string]$Poids = 'Normal') {
    $r = New-Object System.Windows.Documents.Run $Texte
    $r.Foreground = Get-Brush $Couleur; $r.FontWeight = $Poids
    $r
}

function New-Icone([string]$Type, [double]$Taille) {
    $i = New-Object System.Windows.Controls.TextBlock
    $i.Text = $Types[$Type].Icone; $i.FontFamily = $PoliceIcone; $i.FontSize = $Taille
    $i.Foreground = Get-Brush $Types[$Type].Couleur
    $i.HorizontalAlignment = 'Center'; $i.VerticalAlignment = 'Center'
    $i
}

function Get-MessageNote($r) {
    $rep = Format-Repetition $r.Repetition
    $nom = $Types[(Get-TypeRV $r)].Nom
    if ($rep -and $r.Journee) { "C'est noté ($nom) : $($r.Titre), $rep." }
    elseif ($rep) { "C'est noté ($nom) : $($r.Titre), $rep à $(Format-Heure $r.Quand). Le prochain : $(Format-Jour $r.Quand)." }
    else { "C'est noté ($nom) : $($r.Titre), $(Format-QuandRV $r $r.Quand)." }
}

# ---------------------------------------------------------------------------
# Barre rapide : une phrase, et ce qu'Evermind en comprend pendant qu'on écrit
# ---------------------------------------------------------------------------
function Show-FormMessage([string]$Text, [string]$Color) {
    $ui.FormMessage.Text = $Text
    $ui.FormMessage.Foreground = Get-Brush $Color
    $ui.FormMessage.Visibility = 'Visible'
}

function Update-Apercu {
    $text = $ui.InPhrase.Text
    $ui.ApercuLigne.Inlines.Clear()
    if (-not $text.Trim()) { $ui.ApercuLigne.Visibility = 'Collapsed'; $script:Phrase = $null; return }
    if ((Test-EstCommande $text) -and (Test-CerveauInstalle)) {
        $script:Phrase = $null
        $ui.ApercuLigne.Inlines.Add((New-Run 'Je comprends : une demande pour l''assistant. Appuie sur Entrée.' '#C58CFF' 'SemiBold'))
        $ui.ApercuLigne.Visibility = 'Visible'; return
    }
    $p = Read-Phrase $text
    $script:Phrase = $p
    $t = $Types[$p.Type]
    $l = $ui.ApercuLigne.Inlines
    $l.Add((New-Run 'Je comprends :  ' $Colors.dim))
    $ic = New-Run "$($t.Icone) " $t.Couleur; $ic.FontFamily = $PoliceIcone; $l.Add($ic)
    $l.Add((New-Run "$($t.Nom)  " $t.Couleur 'SemiBold'))
    $l.Add((New-Run (Get-TitreAffiche $p.Titre) '#FFFFFF' 'SemiBold'))
    $l.Add((New-Run '   ' $Colors.dim))
    if ($p.Manque) { $l.Add((New-Run $Manques[$p.Manque] $Colors.bad 'SemiBold')) }
    else { $l.Add((New-Run "$(Format-QuandRV $p $p.Quand) ($(Format-Relatif $p.Quand))" $Colors.ok 'SemiBold')) }
    $rep = Format-Repetition $p.Repetition
    if ($rep) { $l.Add((New-Run "   ↻ $rep" '#C58CFF' 'SemiBold')) }
    # Détails compris dans la phrase
    $d = @()
    if ($p.Lieu) { $d += "📍 $($p.Lieu)" }
    if (@($p.Avec).Count) { $d += "avec $(@($p.Avec) -join ', ')" }
    if ($p.Rappels) { $d += "🔔 $(@($p.Rappels | ForEach-Object { Format-Rappel $_ }) -join ', ')" }
    if ($p.Lien) { $d += '🔗 lien' }
    if (@($p.APreparer).Count) { $d += "☑ $(@($p.APreparer) -join ', ')" }
    if ($p.Naissance -and $p.Quand) { $d += "🎂 aura $($p.Quand.Year - $p.Naissance) ans" }
    if ($p.Important) { $d += '★ important' }
    if ($d.Count) { $l.Add((New-Run "`n$($d -join '   ·   ')" '#C9C3DD')) }
    # Déjà quelque chose à ce moment-là ?
    if (-not $p.Manque -and -not $p.Journee) {
        $conf = @(Get-Conflits $p.Quand $p.Fin '')
        if ($conf.Count) { $l.Add((New-Run "`n⚠ Attention : tu as déjà $(@($conf | ForEach-Object { "« $(Get-TitreAffiche $_.RV.Titre) » à $(Format-Heure $_.Prochain)" }) -join ' et ') ce jour-là." '#FFB547' 'SemiBold')) }
    }
    $ui.ApercuLigne.Visibility = 'Visible'
}

# Ajoute ce que la phrase a donné (barre rapide ou voix)
function Add-DepuisPhrase($p) {
    Add-RendezVous (Get-TitreAffiche $p.Titre) $p.Quand $p.Repetition $p.Type $p.Journee (Get-DetailsPhrase $p)
}

function Invoke-Ajouter {
    # Une demande (« décale le dentiste à jeudi », « qu'est-ce que j'ai demain ? ») va à l'assistant
    $texte = $ui.InPhrase.Text.Trim()
    if ($texte -and (Test-EstCommande $texte) -and (Test-CerveauInstalle) -and (Invoke-Commande $texte 'barre')) { return }
    Update-Apercu
    $p = $script:Phrase
    if (-not $p) {
        Show-FormMessage 'Écris ou dis ton rendez-vous, par exemple : demain à 15 h dentiste. Ou appuie sur « Nouveau rendez-vous ».' $Colors.bad
        [void]$ui.InPhrase.Focus(); return
    }
    if ($p.Manque) {
        Show-FormMessage $Manques[$p.Manque] $Colors.bad
        [void]$ui.InPhrase.Focus(); return
    }
    try { $r = Add-DepuisPhrase $p }
    catch {
        Write-Log "Ajout impossible : $_"
        Show-FormMessage "Je n'ai pas réussi à enregistrer ce rendez-vous. ($($_.Exception.Message))" $Colors.bad
        return
    }
    $ui.InPhrase.Text = ''
    Show-FormMessage (Get-MessageNote $r) $Colors.ok
    [void]$ui.InPhrase.Focus()
    Update-Agenda
}

# ---------------------------------------------------------------------------
# Calendrier du mois
# ---------------------------------------------------------------------------
$script:JourChoisi = $null                                  # $null : le panneau montre « À venir »
$script:MoisAffiche = (Get-Date).Date.AddDays(1 - (Get-Date).Day)

function Update-Calendrier {
    $first = $script:MoisAffiche
    $today = (Get-Date).Date
    $ui.MoisTitre.Text = Get-Majuscule $first.ToString('MMMM yyyy', $Fr)
    $start = $first.AddDays(-((([int]$first.DayOfWeek) + 6) % 7))   # la semaine commence le lundi
    $parJour = @{}
    foreach ($it in (Get-AgendaEntre $start $start.AddDays(42))) {
        $k = $it.Prochain.Date
        if (-not $parJour.ContainsKey($k)) { $parJour[$k] = New-Object System.Collections.ArrayList }
        [void]$parJour[$k].Add($it)
    }
    $ui.CalGrille.Children.Clear()
    for ($i = 0; $i -lt 42; $i++) {
        $d = $start.AddDays($i)
        $choisi = $script:JourChoisi -and $d -eq $script:JourChoisi
        $cell = New-Object System.Windows.Controls.Border
        $cell.CornerRadius = 12; $cell.Margin = 3; $cell.Padding = '7,5'; $cell.BorderThickness = 1.5; $cell.Cursor = 'Hand'
        $cell.Tag = $d
        $cell.Background = Get-Brush $(if ($choisi) { '#2600E5FF' } else { '#0BFFFFFF' })
        $cell.BorderBrush = if ($choisi) { $Window.FindResource('AccentBg') } elseif ($d -eq $today) { Get-Brush '#00E5FF' } else { Get-Brush '#12FFFFFF' }
        if ($choisi) { $cell.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.Color]::FromRgb(0, 229, 255); BlurRadius = 18; ShadowDepth = 0; Opacity = 0.45 } }
        if ($d.Month -ne $first.Month) { $cell.Opacity = 0.38 }
        elseif ($d -lt $today) { $cell.Opacity = 0.7 }

        $sp = New-Object System.Windows.Controls.StackPanel
        $list = $parJour[$d]
        # Numéro du jour, avec un gâteau si c'est l'anniversaire de quelqu'un
        $tete = New-Object System.Windows.Controls.DockPanel
        $num = New-Object System.Windows.Controls.TextBlock
        $num.Text = [string]$d.Day; $num.FontSize = 14
        $num.FontWeight = if ($d -eq $today -or $choisi) { 'Bold' } else { 'SemiBold' }
        $num.Foreground = Get-Brush $(if ($d -eq $today) { '#00E5FF' } else { '#EEEBF7' })
        if ($list -and @($list | Where-Object { (Get-TypeRV $_.RV) -eq 'anniv' }).Count) {
            $cake = New-Icone 'anniv' 13; $cake.HorizontalAlignment = 'Right'
            [System.Windows.Controls.DockPanel]::SetDock($cake, 'Right')
            [void]$tete.Children.Add($cake)
        }
        [void]$tete.Children.Add($num)
        [void]$sp.Children.Add($tete)
        if ($list) {
            $n = 0
            foreach ($it in $list) {
                if (++$n -gt 2) { break }
                $type = Get-TypeRV $it.RV
                $c = $Types[$type].Couleur
                $pill = New-Object System.Windows.Controls.Border
                $pill.CornerRadius = 6; $pill.Padding = '4,1'; $pill.Margin = '0,3,0,0'
                $pill.Background = Get-Teinte $c 0x40
                $pill.BorderBrush = Get-Teinte $c 0x90; $pill.BorderThickness = '2,0,0,0'
                $pt = New-Object System.Windows.Controls.TextBlock
                $pt.FontSize = 11; $pt.Foreground = Get-Brush '#F2EFFA'; $pt.TextTrimming = 'CharacterEllipsis'
                $ic = New-Object System.Windows.Documents.Run "$($Types[$type].Icone) "; $ic.FontFamily = $PoliceIcone; $ic.Foreground = Get-Brush $c
                $pt.Inlines.Add($ic)
                $pt.Inlines.Add((New-Object System.Windows.Documents.Run $(if ($it.RV.Journee) { Get-TitreAffiche $it.RV.Titre } else { "$(Format-Heure $it.Prochain) $(Get-TitreAffiche $it.RV.Titre)" })))
                $pill.Child = $pt
                $pill.Tag = @{ Id = $it.RV.Id; Quand = $it.Prochain }; $pill.Cursor = 'Hand'
                $pill.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Show-Fiche (Get-RendezVous $s.Tag.Id) $s.Tag.Quand })
                [void]$sp.Children.Add($pill)
            }
            if ($list.Count -gt 2) {
                $more = New-Object System.Windows.Controls.TextBlock
                $more.Text = "+ $($list.Count - 2) autre$(if ($list.Count -gt 3) { 's' })"; $more.FontSize = 11; $more.Margin = '2,2,0,0'
                $more.Foreground = Get-Brush $Colors.dim
                [void]$sp.Children.Add($more)
            }
        }
        $cell.Child = $sp
        # Un clic : voir ce jour à droite. Double clic : ajouter un rendez-vous ce jour-là.
        $cell.Add_MouseLeftButtonDown({
            param($s, $e)
            if ($e.ClickCount -ge 2) { Open-Formulaire -Jour ([datetime]$s.Tag) } else { Select-JourCalendrier ([datetime]$s.Tag) }
        })
        $cell.Add_MouseEnter({ param($s) if (-not ($script:JourChoisi -and [datetime]$s.Tag -eq $script:JourChoisi)) { $s.Background = Get-Brush '#1AFFFFFF' } })
        $cell.Add_MouseLeave({ param($s) if (-not ($script:JourChoisi -and [datetime]$s.Tag -eq $script:JourChoisi)) { $s.Background = Get-Brush '#0BFFFFFF' } })
        [void]$ui.CalGrille.Children.Add($cell)
    }
}

function Select-JourCalendrier([datetime]$Jour) {
    $script:JourChoisi = $Jour.Date
    $script:MoisAffiche = $Jour.Date.AddDays(1 - $Jour.Day)
    Update-Agenda
}

function Move-Mois([int]$Delta) {
    $script:MoisAffiche = $script:MoisAffiche.AddMonths($Delta)
    Update-Calendrier
}

function Show-Aujourdhui {
    $script:JourChoisi = $null
    $script:MoisAffiche = (Get-Date).Date.AddDays(1 - (Get-Date).Day)
    Update-Agenda
}

# ---------------------------------------------------------------------------
# Panneau de droite : « À venir », ou les rendez-vous du jour choisi
# ---------------------------------------------------------------------------
function New-PetitBouton([string]$Texte, [string]$Tag) {
    $b = New-Button $Texte
    $b.Tag = $Tag; $b.Margin = '0,0,8,0'
    $b
}

# Supprimer un rendez-vous, après « Êtes-vous sûr ? » (et « annule » permet de revenir en arrière)
function Confirm-Suppression([string]$Id) {
    $rv = Get-RendezVous $Id
    if (-not $rv) { return }
    $texte = if ($rv.Repetition) { "Il revient $(Format-Repetition $rv.Repetition) : toutes les fois seront supprimées." } else { 'Il sera enlevé de ton agenda.' }
    Show-Confirmation "Supprimer « $(Get-TitreAffiche $rv.Titre) » ?" $texte 'Supprimer' {
        $r = Get-RendezVous $Id
        if (-not $r) { return }
        try { Save-Annulation; Remove-RendezVous $r.Id } catch { Write-Log "Suppression impossible : $_"; return }
        if ($script:FicheRV -and $script:FicheRV.Id -eq $r.Id) { Close-Fiche }
        Show-FormMessage "Supprimé : $(Get-TitreAffiche $r.Titre). (Dis « annule » pour revenir en arrière.)" $Colors.ok
        Update-Agenda
    }.GetNewClosure()
}

function New-Texte([string]$Texte, [double]$Taille, [string]$Couleur, [string]$Poids = 'Normal') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Texte; $t.FontSize = $Taille; $t.Foreground = Get-Brush $Couleur; $t.FontWeight = $Poids
    $t.TextTrimming = 'CharacterEllipsis'
    $t
}

# Une carte par rendez-vous. La forme dépend de la sorte :
#   anniversaire : carte en dégradé rose, gros gâteau, « il revient chaque année »
#   à faire      : cloche dans un rond jaune
#   les autres   : pastille du jour teintée de la couleur de la sorte, avec l'icône
function New-RendezVousRow($Item) {
    $r = $Item.RV
    $quand = $Item.Prochain
    $type = Get-TypeRV $r
    $t = $Types[$type]
    $today = $quand.Date -eq (Get-Date).Date

    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = 18; $row.Padding = '12,12'; $row.Margin = '0,0,0,10'; $row.BorderThickness = 1
    if ($type -eq 'anniv') {
        $bg = New-Object System.Windows.Media.LinearGradientBrush
        $bg.StartPoint = '0,0'; $bg.EndPoint = '1,1'
        $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#40FF2EB5')), 0))
        $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#22B04BFF')), 1))
        $row.Background = $bg; $row.BorderBrush = Get-Teinte $t.Couleur 0x90; $row.CornerRadius = 22
        if ($today) { $row.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.Color]::FromRgb(255, 46, 181); BlurRadius = 20; ShadowDepth = 0; Opacity = 0.6 } }
    } else {
        $row.Background = Get-Brush '#0FFFFFFF'; $row.BorderBrush = Get-Teinte $t.Couleur 0x38
    }

    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in 'Auto', '*') {
        $c = New-Object System.Windows.Controls.ColumnDefinition
        $c.Width = [System.Windows.GridLengthConverter]::new().ConvertFromString($w)
        $g.ColumnDefinitions.Add($c)
    }

    # Côté gauche : la forme propre à la sorte
    if ($type -eq 'anniv' -or $type -eq 'rappel') {
        $rond = New-Object System.Windows.Controls.Border
        $rond.Width = 54; $rond.Height = 54; $rond.CornerRadius = 27; $rond.Margin = '0,0,14,0'; $rond.VerticalAlignment = 'Top'
        $rond.Background = Get-Teinte $t.Couleur 0x30; $rond.BorderBrush = Get-Teinte $t.Couleur 0xC0; $rond.BorderThickness = 2
        $rond.Child = New-Icone $type 26
        if ($type -eq 'rappel') {
            $rond.Cursor = 'Hand'; $rond.Tag = $r.Id; $rond.ToolTip = if ($r.Fait) { 'Pas encore fait' } else { 'C''est fait' }
            if ($r.Fait) { $rond.Child.Text = '✓'; $rond.Child.FontFamily = 'Segoe UI Symbol'; $rond.Background = Get-Teinte '#3DDC97' 0x40; $rond.BorderBrush = Get-Brush '#3DDC97'; $rond.Child.Foreground = Get-Brush '#3DDC97' }
            $rond.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; $rv = Get-RendezVous ([string]$s.Tag); Set-RendezVousDetail $rv.Id 'Fait' (-not $rv.Fait); Update-Agenda })
        }
        [void]$g.Children.Add($rond)
    } else {
        $badge = New-Object System.Windows.Controls.Border
        $badge.Width = 54; $badge.Height = 62; $badge.CornerRadius = 15; $badge.Margin = '0,0,14,0'; $badge.VerticalAlignment = 'Top'
        $badge.Background = if ($today) { $Window.FindResource('AccentBg') } else { Get-Teinte $t.Couleur 0x26 }
        $badge.BorderBrush = Get-Teinte $t.Couleur 0x70; $badge.BorderThickness = 1
        $bs = New-Object System.Windows.Controls.StackPanel; $bs.VerticalAlignment = 'Center'
        $ic = New-Icone $type 13; if ($today) { $ic.Foreground = Get-Brush '#08060F' }
        $num = New-Texte ([string]$quand.Day) 19 $(if ($today) { '#08060F' } else { '#FFFFFF' }) 'Bold'; $num.HorizontalAlignment = 'Center'; $num.Margin = '0,-1,0,0'
        $mon = New-Texte ($quand.ToString('MMM', $Fr).TrimEnd('.')) 11 $(if ($today) { '#08060F' } else { $Colors.dim }); $mon.HorizontalAlignment = 'Center'; $mon.Margin = '0,-3,0,0'
        [void]$bs.Children.Add($ic); [void]$bs.Children.Add($num); [void]$bs.Children.Add($mon)
        $badge.Child = $bs
        [void]$g.Children.Add($badge)
    }

    # Quoi (avec la sorte), quand, dans combien de temps, s'il revient, puis Modifier et Supprimer
    $txt = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($txt, 1)
    $sorte = New-Texte $t.Nom.ToUpper() 10 $t.Couleur 'Bold'; $sorte.Margin = '0,0,0,1'
    [void]$txt.Children.Add($sorte)
    $titreT = New-Texte (Get-TitreAffiche $r.Titre) 16 '#FFFFFF' 'SemiBold'
    if ($r.Important) { $titreT.Inlines.Clear(); $titreT.Inlines.Add((New-Run '★ ' '#FFD84D' 'Bold')); $titreT.Inlines.Add((New-Object System.Windows.Documents.Run (Get-TitreAffiche $r.Titre))) }
    if ($r.Fait) { $titreT.TextDecorations = [System.Windows.TextDecorations]::Strikethrough; $titreT.Foreground = Get-Brush $Colors.dim }
    [void]$txt.Children.Add($titreT)
    $q = New-Texte (Get-Majuscule (Format-QuandRV $r $quand)) 13 '#C9C3DD'; $q.Margin = '0,2,0,0'
    [void]$txt.Children.Add($q)
    $rel = New-Object System.Windows.Controls.TextBlock
    $rel.FontSize = 13; $rel.Margin = '0,2,0,0'; $rel.TextTrimming = 'CharacterEllipsis'
    $rel.Inlines.Add((New-Run (Get-Majuscule (Format-Relatif $quand)) $(if ($type -eq 'anniv') { '#FF7AD0' } else { $Colors.accent })))
    $rep = Format-Repetition $r.Repetition
    if ($type -eq 'anniv' -and $rep -match 'ans') { $rel.Inlines.Add((New-Run '   ↻ chaque année' '#C58CFF')) }
    elseif ($rep) { $rel.Inlines.Add((New-Run "   ↻ $rep" '#C58CFF')) }
    $age = if ($type -eq 'anniv') { Get-AgeTexte $r $quand } else { '' }
    if ($age) { $rel.Inlines.Add((New-Run "   🎂 $age" '#FF7AD0')) }
    [void]$txt.Children.Add($rel)
    $resume = Get-ResumeDetails $r
    if ($resume) { $rd = New-Texte $resume 12 $Colors.dim; $rd.Margin = '0,4,0,0'; [void]$txt.Children.Add($rd) }

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,0'
    $edit = New-PetitBouton 'Modifier' $r.Id
    $edit.Add_Click({ param($s) $rv = $script:Agenda | Where-Object { $_.Id -eq [string]$s.Tag } | Select-Object -First 1; if ($rv) { Open-Formulaire -RV $rv } })
    $del = New-PetitBouton 'Supprimer' $r.Id
    $del.Add_Click({ param($s) Confirm-Suppression ([string]$s.Tag) })
    [void]$btns.Children.Add($edit); [void]$btns.Children.Add($del)
    [void]$txt.Children.Add($btns)
    [void]$g.Children.Add($txt)

    $row.Child = $g
    # Un clic sur la carte ouvre la fiche avec tous les détails
    $row.Cursor = 'Hand'; $row.Tag = @{ Id = $r.Id; Quand = $quand }
    $row.Add_MouseLeftButtonUp({ param($s) Show-Fiche (Get-RendezVous $s.Tag.Id) $s.Tag.Quand })
    $row
}

function Update-Panneau {
    $jour = $script:JourChoisi
    if ($jour) {
        $items = @(Get-AgendaEntre $jour $jour.AddDays(1))
        $ui.PanneauTitre.Text = Get-Majuscule (Format-Jour $jour)
        $ui.BtnToutVoir.Visibility = 'Visible'
        $ui.BtnAjouterJour.Visibility = if ($jour -ge (Get-Date).Date) { 'Visible' } else { 'Collapsed' }
        $ui.ListeVideTitre.Text = 'Rien ce jour-là.'
        $ui.ListeVideTexte.Text = if ($jour -ge (Get-Date).Date) { 'Appuie sur « Ajouter ce jour-là »,' + "`n" + 'ou double-clique sur le jour.' } else { '' }
    } else {
        $items = @(Get-Upcoming)
        $ui.PanneauTitre.Text = 'À venir'
        $ui.BtnToutVoir.Visibility = 'Collapsed'
        $ui.BtnAjouterJour.Visibility = 'Collapsed'
        $ui.ListeVideTitre.Text = 'Rien de prévu pour l''instant.'
        $ui.ListeVideTexte.Text = 'Dis-moi ton premier rendez-vous,' + "`n" + 'ou appuie sur « Nouveau rendez-vous ».'
    }
    $ui.ListeAVenir.Children.Clear()
    foreach ($it in $items) { [void]$ui.ListeAVenir.Children.Add((New-RendezVousRow $it)) }
    $n = $items.Count
    $ui.ListeVide.Visibility = if ($n) { 'Collapsed' } else { 'Visible' }
    $ui.ListeCompte.Text = switch ($n) { 0 { '' } 1 { '1 rendez-vous' } default { "$n rendez-vous" } }
}

function Update-Agenda { Update-Calendrier; Update-Panneau }

# ---------------------------------------------------------------------------
# Formulaire : ajouter ou modifier un rendez-vous à la main
# ---------------------------------------------------------------------------
function Update-FCalendrier {
    $first = $script:FMois
    $today = (Get-Date).Date
    $ui.FMoisTitre.Text = Get-Majuscule $first.ToString('MMMM yyyy', $Fr)
    $ui.FJours.Children.Clear()
    $start = $first.AddDays(-((([int]$first.DayOfWeek) + 6) % 7))
    $style = $Window.FindResource('Jour')
    for ($i = 0; $i -lt 42; $i++) {
        $d = $start.AddDays($i)
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $style; $b.Content = [string]$d.Day; $b.Tag = $d
        if ($d -lt $today -and $d -ne $script:FChoix) { $b.IsEnabled = $false }
        elseif ($d.Month -ne $first.Month) { $b.Foreground = Get-Brush '#5E5975' }
        if ($d -eq $script:FChoix) {
            $b.Background = $Window.FindResource('AccentBg'); $b.Foreground = Get-Brush '#08060F'; $b.FontWeight = 'Bold'
            $b.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.Color]::FromRgb(0, 229, 255); BlurRadius = 16; ShadowDepth = 0; Opacity = 0.6 }
        } elseif ($d -eq $today) { $b.BorderBrush = Get-Brush '#00E5FF' }
        $b.Add_Click({ param($s) $script:FChoix = ([datetime]$s.Tag).Date; $script:FMois = $script:FChoix.AddDays(1 - $script:FChoix.Day); Update-FCalendrier })
        [void]$ui.FJours.Children.Add($b)
    }
}

# Pilules des sortes : icône et nom, celle choisie s'allume dans sa couleur
function Initialize-FTypes {
    $style = $Window.FindResource('Chip')
    foreach ($k in $Types.Keys) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $style; $b.Name = "FType_$k"; $b.Padding = '12,7'
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $ic = New-Icone $k 14; $ic.Margin = '0,0,6,0'
        [void]$sp.Children.Add($ic)
        [void]$sp.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Types[$k].Nom; VerticalAlignment = 'Center' }))
        $b.Content = $sp
        $b.Add_Click({ param($s) $script:FTypeManuel = $true; Set-FType ($s.Name -replace '^FType_', '') })
        [void]$ui.FTypes.Children.Add($b)
    }
}

function Set-FType([string]$Type) {
    $avant = $script:FType
    $script:FType = $Type
    foreach ($b in $ui.FTypes.Children) {
        $k = $b.Name -replace '^FType_', ''
        if ($k -eq $Type) {
            $b.Background = Get-Teinte $Types[$k].Couleur 0x55; $b.BorderBrush = Get-Brush $Types[$k].Couleur; $b.FontWeight = 'SemiBold'
        } else { $b.ClearValue([System.Windows.Controls.Control]::BackgroundProperty); $b.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty); $b.FontWeight = 'Normal' }
    }
    # Un anniversaire revient chaque année, sans heure
    if ($Type -eq 'anniv' -and $avant -ne 'anniv') { Set-FRepet 'an'; Set-FJournee $true }
    if (-not $script:FormOuverture) { Update-FDetailsVisibles }
}

function Set-FJournee([bool]$On) {
    $script:FJournee = $On
    $ui.FJournee.Tag = if ($On) { 'on' } else { $null }
    $ui.FHeure.IsEnabled = -not $On
    $ui.FHeureInfo.Visibility = if ($On) { 'Collapsed' } else { 'Visible' }
    if (-not $script:FormOuverture) { Update-FDetailsVisibles }
}

function Set-FRepet([string]$Type) {
    $script:FRepet = $Type
    foreach ($k in @(@('une', 'FRepUne'), @('semaine', 'FRepSemaine'), @('mois', 'FRepMois'), @('an', 'FRepAn'))) {
        $ui[$k[1]].Tag = if ($k[0] -eq $Type) { 'on' } else { $null }
    }
}

function Update-FHeureInfo {
    $t = $ui.FHeure.Text
    if (-not $t.Trim()) { $ui.FHeureInfo.Text = ''; return }
    $h = Read-Heure $t
    if ($null -eq $h) { $ui.FHeureInfo.Text = 'Je ne comprends pas cette heure'; $ui.FHeureInfo.Foreground = Get-Brush $Colors.bad }
    else { $ui.FHeureInfo.Text = '= ' + (Format-Heure ([datetime]::Today + $h)); $ui.FHeureInfo.Foreground = Get-Brush $Colors.ok }
}

function Show-FMessage([string]$Text) {
    $ui.FMessage.Text = $Text; $ui.FMessage.Foreground = Get-Brush $Colors.bad; $ui.FMessage.Visibility = 'Visible'
}

# -Jour : jour proposé (sinon le jour choisi, sinon aujourd'hui). -RV : rendez-vous à modifier.
function Open-Formulaire($Jour, $RV, [switch]$Copie) {
    $script:FormEdition = $RV
    $titre = ''; $heure = ''; $rep = 'une'; $type = 'rdv'; $journee = $false
    $jourForm = if ($Jour) { ([datetime]$Jour).Date } elseif ($script:JourChoisi -and $script:JourChoisi -ge (Get-Date).Date) { $script:JourChoisi } else { (Get-Date).Date }
    if ($RV) {
        $titre = $RV.Titre; $jourForm = $RV.Quand.Date; $type = Get-TypeRV $RV; $journee = [bool]$RV.Journee
        if (-not $journee) { $heure = Format-Heure $RV.Quand }
        if ($RV.Repetition) { $rep = [string]$RV.Repetition.Type; if ($rep -eq 'jour') { $rep = 'une' } }
    } elseif ($ui.InPhrase.Text.Trim()) {
        # Ce qui est déjà écrit (ou dit) dans la barre pré-remplit le formulaire
        $p = Read-Phrase $ui.InPhrase.Text
        if ($p.Titre) { $titre = Get-TitreAffiche $p.Titre }
        $type = $p.Type; $journee = $p.Journee
        if ($p.Quand) { $jourForm = $p.Quand.Date; if (-not $journee) { $heure = Format-Heure $p.Quand } }
        else {
            if ($p.Jour) { $jourForm = $p.Jour }
            if ($null -ne $p.Heure) { $heure = Format-Heure ([datetime]::Today + $p.Heure) }
        }
        if ($p.Repetition -and $p.Repetition.Type -ne 'jour') { $rep = [string]$p.Repetition.Type }
    }
    $ui.FormTitre.Text = if ($Copie) { 'Copie du rendez-vous' } elseif ($RV) { 'Modifier le rendez-vous' } else { 'Nouveau rendez-vous' }
    $ui.BtnFEnregistrer.Content = if ($RV -and -not $Copie) { 'Enregistrer' } else { 'Ajouter' }
    Set-FDetails $(if ($RV) { $RV } elseif ($p -and $ui.InPhrase.Text.Trim()) { $p } else { $null })
    if ($Copie) { $script:FormEdition = $null; foreach ($x in @($script:FAvant)) { $x.Fait = $false } }
    $script:FormOuverture = $true
    $ui.FTitre.Text = $titre
    $ui.FHeure.Text = $heure
    $script:FormOuverture = $false
    $script:FTypeManuel = [bool]$RV
    $script:FType = $null
    $script:FChoix = $jourForm
    $script:FMois = $jourForm.AddDays(1 - $jourForm.Day)
    Update-FCalendrier
    Update-FHeureInfo
    Set-FRepet $rep
    Set-FType $type
    Set-FJournee $journee
    if ($rep -ne 'an' -and $type -eq 'anniv') { Set-FRepet $rep }
    Update-FDetailsVisibles
    Update-FFinInfo
    $ui.FMessage.Visibility = 'Collapsed'
    $ui.BtnAjouter.IsDefault = $false; $ui.BtnFEnregistrer.IsDefault = $true
    $ui.Formulaire.Visibility = 'Visible'
    if ($titre -and -not $heure -and -not $journee) { [void]$ui.FHeure.Focus() } else { [void]$ui.FTitre.Focus() }
}

# Pendant qu'on écrit le titre, la sorte se choisit toute seule (tant qu'on ne l'a pas choisie à la main)
function Update-FTypeAuto {
    if ($script:FormOuverture -or $script:FTypeManuel) { return }
    $k = Get-TypeAuto $ui.FTitre.Text
    if ($k -ne $script:FType) { Set-FType $k }
}

function Close-Formulaire {
    $ui.Formulaire.Visibility = 'Collapsed'
    $ui.BtnFEnregistrer.IsDefault = $false; $ui.BtnAjouter.IsDefault = $true
    $script:FormEdition = $null
}

function Save-Formulaire {
    $titre = $ui.FTitre.Text.Trim()
    if (-not $titre) { Show-FMessage 'Écris ce que c''est (par exemple : dentiste).'; [void]$ui.FTitre.Focus(); return }
    # Heure laissée vide : toute la journée
    if (-not $script:FJournee -and -not $ui.FHeure.Text.Trim()) { Set-FJournee $true }
    if ($script:FJournee) { $h = [timespan]::Zero }
    else {
        $h = Read-Heure $ui.FHeure.Text
        if ($null -eq $h) {
            Show-FMessage $(if ($ui.FHeure.Text.Trim()) { 'Je n''ai pas compris l''heure. Écris par exemple 15 h ou 15 h 30.' } else { 'À quelle heure ? Écris par exemple 15 h ou 15 h 30, ou choisis « Toute la journée ».' })
            [void]$ui.FHeure.Focus(); return
        }
    }
    $quand = $script:FChoix + $h
    $rep = switch ($script:FRepet) {
        'semaine' { [ordered]@{ Type = 'semaine'; Jour = [int]$quand.DayOfWeek } }
        'mois'    { [ordered]@{ Type = 'mois'; Jour = $quand.Day } }
        'an'      { [ordered]@{ Type = 'an'; Jour = $quand.Day; Mois = $quand.Month } }
        default   { $null }
    }
    $edition = $script:FormEdition
    $limite = if ($script:FJournee) { (Get-Date).Date } else { Get-Date }
    if (-not $rep -and $quand -lt $limite -and -not $edition) { Show-FMessage 'Ce moment est déjà passé. Choisis un autre jour ou une autre heure.'; return }
    $type = if ($script:FType) { $script:FType } else { 'rdv' }
    $lu = Read-FDetails $quand $script:FJournee
    if ($lu.Erreur) { Show-FMessage $lu.Erreur; return }
    if ($type -eq 'anniv') { $titre = Get-TitreAnniversaire $titre }
    try {
        $titre = Get-TitreAffiche $titre
        $r = if ($edition) { Update-RendezVous $edition.Id $titre $quand $rep $type $script:FJournee $lu.Detail } else { Add-RendezVous $titre $quand $rep $type $script:FJournee $lu.Detail }
    } catch { Write-Log "Enregistrement impossible : $_"; Show-FMessage "Je n'ai pas réussi à l'enregistrer. ($($_.Exception.Message))"; return }
    Close-Formulaire
    if (-not $edition) { $ui.InPhrase.Text = '' }
    $depuis = if ($r.Journee) { (Get-Date).Date } else { Get-Date }
    $prochain = Get-NextOccurrence $r.Repetition $r.Quand $depuis
    Show-FormMessage $(if ($edition) { "C'est modifié : $($r.Titre), $(Format-QuandRV $r $prochain)." } else { Get-MessageNote $r }) $Colors.ok
    Select-JourCalendrier $prochain
}
