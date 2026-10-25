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
    matin    = 'Le matin ou le soir ? Ajoute « du matin » ou « du soir » après l''heure.'
}
$PoliceIcone = 'Segoe UI Emoji'

function Get-TitreAffiche([string]$Titre) {
    if (-not $Titre) { return 'Rendez-vous' }
    # « avec monsieur Richard » (dictée) : « avec Monsieur Richard »
    $Titre = [regex]::Replace($Titre, '\b(monsieur|madame|mademoiselle|docteur|ma[iî]tre)(?=\s+\p{Lu})', { param($m) $m.Value.Substring(0, 1).ToUpper() + $m.Value.Substring(1) })
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

# ---------------------------------------------------------------------------
# Couleurs des sortes de rendez-vous, au choix (Réglages, Thème). Une couleur choisie reste exactement la même avec
# tous les thèmes (le thème ne la traduit pas) ; « par défaut » rend celle d'Evermind, que le thème accorde.
# ---------------------------------------------------------------------------
$CouleursPalette = '#FF4D6D', '#FF9F43', '#FFC93C', '#C6F432', '#34D399', '#2DD4BF', '#38BDF8', '#3B82F6', '#818CF8', '#A855F7', '#E879F9', '#F472B6', '#C08457', '#94A3B8'
if (-not $script:CouleursDefaut) { $script:CouleursDefaut = @{}; foreach ($k in $Types.Keys) { $script:CouleursDefaut[$k] = $Types[$k].Couleur } }

function Update-CouleursSortes {
    $choix = Get-Setting 'CouleursSortes' $null
    $script:CouleursFixes = @{}
    foreach ($k in @($Types.Keys)) {
        $c = if ($choix -and $choix.$k -and [string]$choix.$k -match '^#[0-9A-Fa-f]{6}$') { ([string]$choix.$k).ToUpper() } else { $null }
        $Types[$k].Couleur = if ($c) { $c } else { $script:CouleursDefaut[$k] }
        if ($c) { $script:CouleursFixes[$c.Substring(1)] = $true }
    }
    $script:ThemeCache = @{}   # (les couleurs fixes ne passent plus par le thème)
}

function Set-CouleurSorte([string]$Type, [string]$Couleur) {
    $h = [ordered]@{}; $avant = Get-Setting 'CouleursSortes' $null
    foreach ($k in $Types.Keys) { if ($avant -and $avant.$k) { $h[$k] = [string]$avant.$k } }
    if ($Couleur) { $h[$Type] = $Couleur } else { $h.Remove($Type) }
    Set-Setting 'CouleursSortes' $h
    Update-CouleursSortes
    Write-Log "Couleur de « $($Types[$Type].Nom) » : $(if ($Couleur) { $Couleur } else { 'par défaut' })"
    # Tout ce qui montre les sortes reprend ses couleurs
    Update-CouleursReglage
    $ui.FTypes.Children.Clear(); Initialize-FTypes; if ($script:FType) { Set-FType $script:FType }
    Update-Agenda
}

Update-CouleursSortes   # (les couleurs choisies, dès le démarrage)

# Réglages, Thème : une rangée par sorte, son icône, son nom, puis les pastilles (la première : celle par défaut)
function Update-CouleursReglage {
    $ui.CouleursSortes.Children.Clear()
    foreach ($k in $Types.Keys) {
        $ligne = New-Object System.Windows.Controls.DockPanel; $ligne.Margin = '0,0,0,10'
        $ic = New-Icone $k 20; $ic.Margin = '2,0,10,0'
        [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$ligne.Children.Add($ic)
        $nom = New-Object System.Windows.Controls.TextBlock
        $nom.Text = $Types[$k].Nom; $nom.Width = 120; $nom.FontSize = 14; $nom.Foreground = Get-Brush '#F2EFFA'; $nom.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($nom, 'Left'); [void]$ligne.Children.Add($nom)
        $pastilles = New-Object System.Windows.Controls.WrapPanel
        $actuelle = $Types[$k].Couleur.ToUpper()
        foreach ($c in @($script:CouleursDefaut[$k]) + $CouleursPalette) {
            $defaut = $c -eq $script:CouleursDefaut[$k]
            $p = New-Object System.Windows.Controls.Border
            $p.Width = 20; $p.Height = 20; $p.CornerRadius = 10; $p.Margin = '0,0,5,4'; $p.Cursor = 'Hand'
            # (la couleur par défaut est montrée comme le thème la rend ; les autres telles quelles)
            $p.Background = if ($defaut) { Get-Brush $c } else { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($c)) }
            $choisie = ($defaut -and -not $script:CouleursFixes[$actuelle.Substring(1)]) -or (-not $defaut -and $c.ToUpper() -eq $actuelle)
            $p.BorderThickness = if ($choisie) { 3 } else { 1 }
            $p.BorderBrush = Get-Brush $(if ($choisie) { '#FFFFFF' } else { '#30FFFFFF' })
            $p.ToolTip = if ($defaut) { 'Couleur par défaut' } else { $c }
            $p.Tag = "$k|$(if ($defaut) { '' } else { $c })"
            $p.Add_MouseLeftButtonUp({ param($s) $x = ([string]$s.Tag).Split('|'); Set-CouleurSorte $x[0] $x[1] })
            [void]$pastilles.Children.Add($p)
        }
        [void]$ligne.Children.Add($pastilles)
        [void]$ui.CouleursSortes.Children.Add($ligne)
    }
}

# Les icônes des sortes, dessinées par Evermind (et non prises dans une police de Windows : les émojis changent d'un
# Windows à l'autre, et manquaient ou se décalaient sur certains PC). Carré de 24 : T = traits, P = parties pleines.
$IconesDessin = @{
    anniv   = @{ T = 'M4,20 H20 M5,20 V13 C5,12 6,11 7,11 H17 C18,11 19,12 19,13 V20 M5,16 C7,17.5 9,14.5 12,16 C15,17.5 17,14.5 19,16 M12,11 V8'; P = 'M12,3.2 C13.4,4.8 13.4,6.4 12,7 C10.6,6.4 10.6,4.8 12,3.2 Z' }
    sante   = @{ T = 'M9.5,4 H14.5 V9.5 H20 V14.5 H14.5 V20 H9.5 V14.5 H4 V9.5 H9.5 Z' }
    voyage  = @{ T = 'M12,3 C12.8,3 13.3,3.8 13.3,5 V9.5 L20.5,13.5 V15.5 L13.3,13.3 V18 L15.5,19.7 V21 L12,20 L8.5,21 V19.7 L10.7,18 V13.3 L3.5,15.5 V13.5 L10.7,9.5 V5 C10.7,3.8 11.2,3 12,3 Z' }
    travail = @{ T = 'M4,8 H20 C20.6,8 21,8.4 21,9 V19 C21,19.6 20.6,20 20,20 H4 C3.4,20 3,19.6 3,19 V9 C3,8.4 3.4,8 4,8 Z M9,8 V6 C9,5.4 9.4,5 10,5 H14 C14.6,5 15,5.4 15,6 V8 M3,13 H21' }
    sport   = @{ T = 'M12,3 A9,9 0 1 0 12,21 A9,9 0 1 0 12,3 Z M12,8 V3.5 M15.3,10.4 L19.8,9 M14,14.3 L16.8,18.5 M10,14.3 L7.2,18.5 M8.7,10.4 L4.2,9'; P = 'M12,8 L15.3,10.4 L14,14.3 H10 L8.7,10.4 Z' }
    jeu     = @{ T = 'M7,8 H17 C19.5,8 21,10.5 21,14 C21,16.5 20,18 18.5,18 C17.3,18 16.6,17 15.8,16 H8.2 C7.4,17 6.7,18 5.5,18 C4,18 3,16.5 3,14 C3,10.5 4.5,8 7,8 Z M8,11 V15 M6,13 H10'; P = 'M15.5,10.8 A1.2,1.2 0 1 0 15.5,13.2 A1.2,1.2 0 1 0 15.5,10.8 Z M18,12.8 A1.2,1.2 0 1 0 18,15.2 A1.2,1.2 0 1 0 18,12.8 Z' }
    sortie  = @{ T = 'M12,3 L14.4,8.9 L20.6,9.3 L15.8,13.3 L17.4,19.4 L12,16 L6.6,19.4 L8.2,13.3 L3.4,9.3 L9.6,8.9 Z' }
    rappel  = @{ T = 'M18,16 V11 C18,7.7 15.3,5 12,5 C8.7,5 6,7.7 6,11 V16 L4.5,17.5 H19.5 Z M10,20 C10.4,21 11.1,21.5 12,21.5 C12.9,21.5 13.6,21 14,20 M12,5 V3' }
    rdv     = @{ T = 'M5,5 H19 C20.1,5 21,5.9 21,7 V19 C21,20.1 20.1,21 19,21 H5 C3.9,21 3,20.1 3,19 V7 C3,5.9 3.9,5 5,5 Z M3,10 H21 M8,3 V7 M16,3 V7'; P = 'M7,13 H9 V15 H7 Z M11,13 H13 V15 H11 Z M15,13 H17 V15 H15 Z M7,17 H9 V19 H7 Z M11,17 H13 V19 H11 Z' }
    # (les détails, dans la fiche)
    lieu    = @{ T = 'M12,21 C12,21 5,14.5 5,9.5 C5,5.6 8.1,3 12,3 C15.9,3 19,5.6 19,9.5 C19,14.5 12,21 12,21 Z M12,7 A2.5,2.5 0 1 0 12,12 A2.5,2.5 0 1 0 12,7 Z' }
    avec    = @{ T = 'M9,11 A3.5,3.5 0 1 0 9,4 A3.5,3.5 0 1 0 9,11 Z M3,20 C3,16.5 5.7,14 9,14 C12.3,14 15,16.5 15,20 M16,4.3 A3.5,3.5 0 0 1 16,11 M18,14.3 C20,15 21,17 21,20' }
    coche   = @{ T = 'M4,12.5 L9.5,18 L20,6.5' }
    notes   = @{ T = 'M6,3 H15 L19,7 V21 H6 Z M15,3 V7 H19 M9,11 H16 M9,14.5 H16 M9,18 H13' }
    dossier = @{ T = 'M3,6 C3,5.4 3.4,5 4,5 H9 L11,7 H20 C20.6,7 21,7.4 21,8 V18 C21,18.6 20.6,19 20,19 H4 C3.4,19 3,18.6 3,18 Z' }
    fichier = @{ T = 'M6,3 H14 L19,8 V21 H6 Z M14,3 V8 H19' }
    lien    = @{ T = 'M10,14 C11.5,15.5 13.5,15.5 15,14 L18.5,10.5 C20,9 20,6.5 18.5,5 C17,3.5 14.5,3.5 13,5 L11.5,6.5 M14,10 C12.5,8.5 10.5,8.5 9,10 L5.5,13.5 C4,15 4,17.5 5.5,19 C7,20.5 9.5,20.5 11,19 L12.5,17.5' }
    alerte  = @{ T = 'M12,4 L21,20 H3 Z M12,10 V14'; P = 'M11,16.5 H13 V18.5 H11 Z' }
}
# Les émojis encore écrits dans le code, et leur icône dessinée
$IconesEmoji = @{ '📍' = 'lieu'; '👥' = 'avec'; '🔔' = 'rappel'; '☑' = 'coche'; '✓' = 'coche'; '📝' = 'notes'; '📁' = 'dossier'; '📄' = 'fichier'; '🔗' = 'lien'; '🎂' = 'anniv'; '⚠' = 'alerte' }

# L'icône d'une sorte, à la taille voulue (en pixels), dans sa couleur ou une autre
function New-Icone([string]$Type, [double]$Taille, [string]$Couleur = '') {
    $d = $IconesDessin[$Type]; if (-not $d) { $d = $IconesDessin['rdv'] }
    $c = if ($Couleur) { $Couleur } elseif ($Types[$Type]) { $Types[$Type].Couleur } else { $Colors.dim }
    $toile = New-Object System.Windows.Controls.Canvas
    $toile.Width = 24; $toile.Height = 24
    foreach ($k in 'T', 'P') {
        if (-not $d[$k]) { continue }
        $p = New-Object System.Windows.Shapes.Path
        $p.Data = [System.Windows.Media.Geometry]::Parse($d[$k])
        if ($k -eq 'T') { $p.StrokeThickness = 2.1; $p.StrokeLineJoin = 'Round'; $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round' }
        $p.Tag = $k
        [void]$toile.Children.Add($p)
    }
    $v = New-Object System.Windows.Controls.Viewbox
    $v.Width = $Taille; $v.Height = $Taille; $v.Child = $toile
    $v.HorizontalAlignment = 'Center'; $v.VerticalAlignment = 'Center'; $v.SnapsToDevicePixels = $true
    Set-IconeCouleur $v $c
    $v
}

function Set-IconeCouleur($Icone, [string]$Couleur) {
    $b = Get-Brush $Couleur
    foreach ($p in $Icone.Child.Children) { if ($p.Tag -eq 'T') { $p.Stroke = $b } else { $p.Fill = $b } }
}

# La même, au fil d'un texte (pastilles du calendrier, aperçu de la phrase)
function New-IconeTexte([string]$Type, [double]$Taille, [string]$Couleur = '') {
    $i = New-Icone $Type $Taille $Couleur
    $i.Margin = '0,0,4,-1'
    $c = New-Object System.Windows.Documents.InlineUIContainer $i
    $c.BaselineAlignment = 'Center'
    $c
}

function Get-MessageNote($r) {
    $rep = Format-Repetition $r.Repetition
    $nom = $Types[(Get-TypeRV $r)].Nom
    $msg = if ($rep -and $r.Journee) { "C'est noté ($nom) : $($r.Titre), $rep." }
    elseif ($rep) { "C'est noté ($nom) : $($r.Titre), $rep à $(Format-Heure $r.Quand). Le prochain : $(Format-Jour $r.Quand)." }
    else { "C'est noté ($nom) : $($r.Titre), $(Format-QuandRV $r $r.Quand)." }
    $msg + (Get-TexteFichiers $r)
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
    if (Test-AnnuleTexte $text) {
        $script:Phrase = $null
        $ui.ApercuLigne.Inlines.Add((New-Run 'Je comprends : défaire ta dernière action. Appuie sur Entrée.' '#C58CFF' 'SemiBold'))
        $ui.ApercuLigne.Visibility = 'Visible'; return
    }
    if ((Test-EstCommande $text) -and (Test-CerveauInstalle)) {
        $script:Phrase = $null
        $ui.ApercuLigne.Inlines.Add((New-Run 'Je comprends : une demande pour l''assistant. Appuie sur Entrée.' '#C58CFF' 'SemiBold'))
        $ui.ApercuLigne.Visibility = 'Visible'; return
    }
    # Des postes de travail : leur liste, avec les heures
    $hor = Get-HorairesTravail $text
    if ($hor) {
        $script:Phrase = $null
        $l = $ui.ApercuLigne.Inlines
        $l.Add((New-Run 'Je comprends :  ' $Colors.dim)); $l.Add((New-IconeTexte 'travail' 14))
        $l.Add((New-Run "$(@($hor).Count) poste$(if (@($hor).Count -gt 1) { 's' }) de travail  " $Types['travail'].Couleur 'SemiBold'))
        $l.Add((New-Run ((@($hor | ForEach-Object { "$($_.Jour) $($CreneauxNoms[$_.Creneau]) ($($_.Heures -replace ' à ', ' - '))" })) -join ',  ') $Colors.ok 'SemiBold'))
        $ui.ApercuLigne.Visibility = 'Visible'; return
    }
    $p = Read-Phrase $text
    $script:Phrase = $p
    $t = $Types[$p.Type]
    $l = $ui.ApercuLigne.Inlines
    $l.Add((New-Run 'Je comprends :  ' $Colors.dim))
    $l.Add((New-IconeTexte $p.Type 14))
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
    # Jour de la semaine et date qui ne vont pas ensemble (« lundi 3 novembre ») : on dit le jour pris
    if ($p.Remarque) { $l.Add((New-Run "`n⚠ $($p.Remarque)" '#FFB547' 'SemiBold')) }
    # Déjà quelque chose à ce moment-là ?
    if (-not $p.Manque -and -not $p.Journee) {
        $conf = @(Get-Conflits $p.Quand $p.Fin '')
        if ($conf.Count) { $l.Add((New-Run "`n⚠ Attention : tu as déjà $(@($conf | ForEach-Object { "« $(Get-TitreAffiche $_.RV.Titre) » à $(Format-Heure $_.Prochain)" }) -join ' et ') ce jour-là." '#FFB547' 'SemiBold')) }
    }
    $ui.ApercuLigne.Visibility = 'Visible'
}

# Ajoute ce que la phrase a donné (barre rapide ou voix)
# Des jours séparés (« les 3 et 10 novembre ») : un événement par jour ; le premier est retourné
function Add-DepuisPhrase($p) {
    Save-Annulation
    $premier = $null
    foreach ($c in (Get-CreationsPhrase $p)) {
        $det = Get-DetailsPhrase $p; $det.Fin = $c.Fin
        $r = Add-RendezVous (Get-TitreAffiche $p.Titre) $c.Quand $p.Repetition $p.Type $p.Journee $det
        if (-not $premier) { $premier = $r }
    }
    $premier
}

# Horaires de travail en postes (Get-HorairesTravail) : un événement par poste, « Travail (matin) » de 6 h à 14 h...
# Un poste déjà noté au même moment n'est pas recréé. Retourne ce qui a été créé (@{ RV; Quand; Creneau; Heures }).
function Add-HorairesTravail($Liste) {
    Save-Annulation
    $faits = @()
    foreach ($h in @($Liste)) {
        $p = Read-Phrase $h.Phrase
        if ($p.Manque -or -not $p.Quand) { Write-Log "Horaires : « $($h.Phrase) » pas compris ($($p.Manque))"; continue }
        if (@(Get-AgendaEntre $p.Quand $p.Quand.AddMinutes(1) | Where-Object { $_.RV.Titre -eq $h.Titre }).Count) { continue }
        $det = Get-DetailsPhrase $p; $det.Fin = $p.Fin
        $r = Add-RendezVous $h.Titre $p.Quand $p.Repetition 'travail' $false $det
        $faits += [pscustomobject]@{ RV = $r; Quand = $p.Quand; Creneau = $h.Creneau; Heures = $h.Heures }
    }
    $faits
}

# « C'est noté : 3 postes. Lundi 12 matin (6 h - 14 h), mardi 13 journée (8 h - 17 h) et mercredi 14 soir (14 h - 22 h). »
#   Dit : plus court, sans les heures
function Get-TexteHoraires($Faits) {
    $f = @($Faits)
    if (-not $f.Count) { return @{ Ecrit = 'Ces postes sont déjà dans ton agenda.'; Dit = 'Ces postes sont déjà dans ton agenda.' } }
    $quand = { param($x) if ($x.RV.Repetition) { Format-Repetition $x.RV.Repetition } else { $x.Quand.ToString('dddd d', $Fr) } }
    $ecrits = @($f | ForEach-Object { "$(& $quand $_) $($CreneauxNoms[$_.Creneau]) ($($_.Heures -replace ' à ', ' - '))" })
    $dits = @($f | ForEach-Object { "$(& $quand $_) $($CreneauxNoms[$_.Creneau])" })
    $liste = { param($l) if ($l.Count -gt 1) { "$(($l | Select-Object -SkipLast 1) -join ', ') et $($l[-1])" } else { $l[0] } }
    $n = if ($f.Count -gt 1) { "$($f.Count) postes" } else { 'un poste' }
    @{ Ecrit = "C'est noté : $n. $(Get-Majuscule (& $liste $ecrits))."; Dit = "C'est noté : $n, $(& $liste $dits)." }
}

# Réglages, Général : les heures de chaque poste (« 6 h à 14 h »), enregistrées dès qu'on quitte la case
function Update-HorairesReglage {
    $ui.HorairesTravail.Children.Clear()
    foreach ($c in $CreneauxNoms.Keys) {
        $g = New-Object System.Windows.Controls.DockPanel; $g.Margin = '0,0,0,8'
        $l = New-Object System.Windows.Controls.TextBlock
        $l.Text = Get-Majuscule $CreneauxNoms[$c]; $l.Width = 110; $l.FontSize = 14; $l.Foreground = Get-Brush '#F2EFFA'; $l.VerticalAlignment = 'Center'
        [void]$g.Children.Add($l)
        $b = New-Object System.Windows.Controls.TextBox
        $b.Style = $Window.FindResource('Champ'); $b.Width = 170; $b.HorizontalAlignment = 'Left'; $b.MaxLength = 30
        $b.Text = Get-Horaire $c; $b.Tag = $HorairesDefaut[$c]; $b.Name = "Horaire_$c"
        $b.Add_LostFocus({
            param($s)
            $cle = $s.Name -replace '^Horaire_', ''
            $v = $s.Text.Trim() -replace '^de\s+', ''
            $p = Read-Phrase "x lundi de $v" ([datetime]'2026-01-01')
            if (-not $v -or $p.Manque -or -not $p.Fin) { $s.BorderBrush = Get-Brush $Colors.bad; $s.ToolTip = 'Écris par exemple : 6 h à 14 h'; return }
            $s.BorderBrush = $null; $s.ToolTip = $null
            $h = [ordered]@{}; $avant = Get-Setting 'Horaires' $null
            foreach ($k in $CreneauxNoms.Keys) { $h[$k] = if ($avant -and $avant.$k) { [string]$avant.$k } else { $HorairesDefaut[$k] } }
            $h[$cle] = $v
            Set-Setting 'Horaires' $h
        })
        [void]$g.Children.Add($b)
        [void]$ui.HorairesTravail.Children.Add($g)
    }
}

# Les événements à créer : un seul ; un par jour séparé (« les 3 et 10 novembre », même heure) ;
# ou un par bloc de jours (« la première semaine des 3 prochains mois »). Chacun : @{ Quand; Fin }
function Get-CreationsPhrase($p) {
    $b = @($p.Blocs | Where-Object { $_ })
    if ($b.Count -gt 1) { return @($b | ForEach-Object { @{ Quand = ([datetime]$_.Debut).Date + $p.Quand.TimeOfDay; Fin = $(if ($p.Journee) { ([datetime]$_.Fin).Date } else { ([datetime]$_.Fin).Date + ([datetime]$p.Fin).TimeOfDay }) } }) }
    $j = @($p.Jours | Where-Object { $_ })
    if ($j.Count -gt 1 -and $p.Quand) { return @($j | ForEach-Object { @{ Quand = ([datetime]$_).Date + $p.Quand.TimeOfDay; Fin = $null } }) }
    @(@{ Quand = $p.Quand; Fin = $p.Fin })
}
function Get-QuandsPhrase($p) { @(Get-CreationsPhrase $p | ForEach-Object { $_.Quand }) }

function Invoke-Ajouter {
    # Une demande (« décale le dentiste à jeudi », « qu'est-ce que j'ai demain ? ») va à l'assistant
    $texte = $ui.InPhrase.Text.Trim()
    # « annule » : la dernière action est défaite (avec ou sans assistant)
    if ($texte -and (Invoke-AnnuleTexte $texte 'barre')) { return }
    if ($texte -and (Test-EstCommande $texte) -and (Test-CerveauInstalle) -and (Invoke-Commande $texte 'barre')) { return }
    # « je suis du matin lundi et mardi » : des postes de travail
    $hor = if ($texte) { Get-HorairesTravail $texte } else { $null }
    if ($hor) {
        try { $faits = @(Add-HorairesTravail $hor) } catch { Write-Log "Horaires impossibles : $_"; Show-FormMessage "Je n'ai pas réussi à enregistrer ces horaires. ($($_.Exception.Message))" $Colors.bad; return }
        $ui.InPhrase.Text = ''
        Show-FormMessage (Get-TexteHoraires $faits).Ecrit $Colors.ok
        if ($faits.Count) { Select-JourCalendrier $faits[0].Quand } else { Update-Agenda }
        return
    }
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
    $anime = $script:CalMoisAnime -ne $first -and -not $EnTest   # (tests : tout de suite, pour la capture)
    $script:CalMoisAnime = $first
    $rang = 0
    for ($i = 0; $i -lt 42; $i++) {
        $d = $start.AddDays($i)
        $choisi = $script:JourChoisi -and $d -eq $script:JourChoisi
        $cell = New-Object System.Windows.Controls.Border
        $cell.CornerRadius = 12; $cell.Margin = 3; $cell.Padding = '7,5'; $cell.BorderThickness = 1.5; $cell.Cursor = 'Hand'
        $cell.Tag = $d
        $cell.Background = Get-Brush $(if ($choisi) { '#2600E5FF' } else { '#0BFFFFFF' })
        $cell.BorderBrush = if ($choisi) { $Window.FindResource('AccentBg') } elseif ($d -eq $today) { Get-Brush '#00E5FF' } else { Get-Brush '#12FFFFFF' }
        if ($choisi) { $cell.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = [System.Windows.Media.Color]::FromRgb(0, 229, 255); BlurRadius = 18; ShadowDepth = 0; Opacity = 0.45 } }
        elseif ($d -eq $today) {
            # Aujourd'hui luit doucement, aux couleurs du thème
            $fx = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ Color = (Get-Brush '#00E5FF').Color; BlurRadius = 20; ShadowDepth = 0; Opacity = 0.15 }
            $cell.Effect = $fx
            $lu = New-Object System.Windows.Media.Animation.DoubleAnimation 0.15, 0.7, ([System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1400)))
            $lu.AutoReverse = $true; $lu.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $lu.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
            [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($lu, 20)
            if ($script:AujLueur) { $script:AnimsBoucle.Remove($script:AujLueur) }   # (la case d'avant est redessinée : sa lueur part avec elle)
            Add-AnimationBoucle $fx ([System.Windows.Media.Effects.DropShadowEffect]::OpacityProperty) $lu
            $script:AujLueur = $script:AnimsBoucle[$script:AnimsBoucle.Count - 1]
        }
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
                $ic = New-IconeTexte $type 11
                # Passé : une petite coche verte devant, et la pastille s'efface un peu
                if (Test-Valide $it.RV $it.Prochain) {
                    $ok = New-Object System.Windows.Documents.Run '✓ '; $ok.FontFamily = 'Segoe UI Symbol'; $ok.FontWeight = 'Bold'; $ok.Foreground = Get-Brush '#3DDC97'
                    $pt.Inlines.Add($ok); $pt.Foreground = Get-Brush '#A9A3BD'; $pill.Background = Get-Teinte $c 0x22
                    $pill.ToolTip = 'Passé, validé. Clique pour le voir ou le décaler.'
                }
                $pt.Inlines.Add($ic)
                $pt.Inlines.Add((New-Object System.Windows.Documents.Run $(if ($it.RV.Journee) { Get-TitreAffiche $it.RV.Titre } else { "$(Format-Heure $it.Prochain) $(Get-TitreAffiche $it.RV.Titre)" })))
                $pill.Child = $pt
                $pill.Tag = @{ Id = $it.RV.Id; Quand = $it.Prochain }; $pill.Cursor = 'Hand'
                $pill.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Show-Fiche (Get-RendezVous $s.Tag.Id) $s.Tag.Quand })
                if ($anime) {
                    $pill.Opacity = 0
                    $mv = New-Object System.Windows.Media.TranslateTransform 0, 6; $pill.RenderTransform = $mv
                    $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(420)); $t0 = [TimeSpan]::FromMilliseconds(120 + 45 * $rang++)
                    $a = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, $dur; $a.BeginTime = $t0; $pill.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
                    $a = New-Object System.Windows.Media.Animation.DoubleAnimation 6, 0, $dur; $a.BeginTime = $t0; $a.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase; $mv.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a)
                }
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
    $b.Tag = $Tag; $b.Margin = '0,0,8,8'
    $b
}

# Supprimer un rendez-vous, après « Êtes-vous sûr ? » (et « annule » permet de revenir en arrière)
function Confirm-Suppression([string]$Id) {
    $rv = Get-RendezVous $Id
    if (-not $rv) { return }
    $texte = if ($rv.Repetition) { "Il revient $(Format-Repetition $rv.Repetition) : toutes les fois seront supprimées." } else { 'Il sera enlevé de ton agenda.' }
    # (sans GetNewClosure : le bloc perdrait l'accès aux fonctions d'Evermind ; l'identifiant est gardé à part)
    $script:SuppressionId = $Id
    Show-Confirmation "Supprimer « $(Get-TitreAffiche $rv.Titre) » ?" $texte 'Supprimer' {
        $r = Get-RendezVous $script:SuppressionId
        if (-not $r) { return }
        try { Save-Annulation; Remove-RendezVous $r.Id } catch { Write-Log "Suppression impossible : $_"; Show-FormMessage (Get-TexteNonEnregistre) $Colors.bad; return }
        if ($script:FicheRV -and $script:FicheRV.Id -eq $r.Id) { Close-Fiche }
        Show-FormMessage "Supprimé : $(Get-TitreAffiche $r.Titre). (Dis « annule » pour revenir en arrière.)" $Colors.ok
        Update-Agenda
    }
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
    $fait = Test-FaitRV $r $quand

    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = 18; $row.Padding = '12,12'; $row.Margin = '0,0,0,10'; $row.BorderThickness = 1
    if ($type -eq 'anniv') {
        $bg = New-Object System.Windows.Media.LinearGradientBrush
        $bg.StartPoint = '0,0'; $bg.EndPoint = '1,1'
        $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur '#40FF2EB5')), 0))
        $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ((Get-Couleur '#22B04BFF')), 1))
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
            # (une chose qui revient : seulement cette fois-ci)
            $rond.Cursor = 'Hand'; $rond.Tag = @{ Id = $r.Id; Quand = $quand }; $rond.ToolTip = if ($fait) { 'Pas encore fait' } else { 'C''est fait' }
            if ($fait) { $rond.Child.Text = '✓'; $rond.Child.FontFamily = 'Segoe UI Symbol'; $rond.Background = Get-Teinte '#3DDC97' 0x40; $rond.BorderBrush = Get-Brush '#3DDC97'; $rond.Child.Foreground = Get-Brush '#3DDC97' }
            $rond.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Switch-FaitRV $s.Tag.Id $s.Tag.Quand })
        }
        [void]$g.Children.Add($rond)
    } else {
        $badge = New-Object System.Windows.Controls.Border
        $badge.Width = 54; $badge.Height = 62; $badge.CornerRadius = 15; $badge.Margin = '0,0,14,0'; $badge.VerticalAlignment = 'Top'
        $badge.Background = if ($today) { $Window.FindResource('AccentBg') } else { Get-Teinte $t.Couleur 0x26 }
        $badge.BorderBrush = Get-Teinte $t.Couleur 0x70; $badge.BorderThickness = 1
        $bs = New-Object System.Windows.Controls.StackPanel; $bs.VerticalAlignment = 'Center'
        $ic = New-Icone $type 14; if ($today) { Set-IconeCouleur $ic '#08060F' }
        $num = New-Texte ([string]$quand.Day) 19 $(if ($today) { '#08060F' } else { '#FFFFFF' }) 'Bold'; $num.HorizontalAlignment = 'Center'; $num.Margin = '0,-1,0,0'
        $mon = New-Texte ($quand.ToString('MMM', $Fr).TrimEnd('.')) 11 $(if ($today) { '#08060F' } else { $Colors.dim }); $mon.HorizontalAlignment = 'Center'; $mon.Margin = '0,-3,0,0'
        [void]$bs.Children.Add($ic); [void]$bs.Children.Add($num); [void]$bs.Children.Add($mon)
        $badge.Child = $bs
        [void]$g.Children.Add($badge)
    }
    # Passé : validé tout seul, une coche verte sur sa pastille (les choses à faire ont déjà la leur)
    $valide = Test-Valide $r $quand
    if ($valide -and $type -ne 'rappel') {
        $coche = New-Object System.Windows.Controls.Border
        $coche.Width = 22; $coche.Height = 22; $coche.CornerRadius = 11; $coche.Margin = '0,-5,8,0'
        $coche.HorizontalAlignment = 'Right'; $coche.VerticalAlignment = 'Top'
        $coche.Background = Get-Brush '#3DDC97'; $coche.BorderBrush = Get-Brush '#08060F'; $coche.BorderThickness = 2
        $coche.ToolTip = 'Passé, validé'
        $ct = New-Object System.Windows.Controls.TextBlock
        $ct.Text = '✓'; $ct.FontFamily = 'Segoe UI Symbol'; $ct.FontSize = 11; $ct.FontWeight = 'Bold'; $ct.Foreground = Get-Brush '#08060F'
        $ct.HorizontalAlignment = 'Center'; $ct.VerticalAlignment = 'Center'
        $coche.Child = $ct
        [void]$g.Children.Add($coche)
    }

    # Quoi (avec la sorte), quand, dans combien de temps, s'il revient, puis Modifier et Supprimer
    $txt = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($txt, 1)
    $sorte = New-Texte $t.Nom.ToUpper() 10 $t.Couleur 'Bold'; $sorte.Margin = '0,0,0,1'
    [void]$txt.Children.Add($sorte)
    $titreT = New-Texte (Get-TitreAffiche $r.Titre) 16 '#FFFFFF' 'SemiBold'
    if ($r.Important) { $titreT.Inlines.Clear(); $titreT.Inlines.Add((New-Run '★ ' '#FFD84D' 'Bold')); $titreT.Inlines.Add((New-Object System.Windows.Documents.Run (Get-TitreAffiche $r.Titre))) }
    if ($fait) { $titreT.TextDecorations = [System.Windows.TextDecorations]::Strikethrough; $titreT.Foreground = Get-Brush $Colors.dim }
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
    if ($age) { $rel.Inlines.Add((New-Run '   ' '#FF7AD0')); $rel.Inlines.Add((New-IconeTexte 'anniv' 12 '#FF7AD0')); $rel.Inlines.Add((New-Run $age '#FF7AD0')) }
    if ($valide -and $type -ne 'rappel') { $rel.Inlines.Add((New-Run '   ✓ validé' '#3DDC97' 'SemiBold')) }
    [void]$txt.Children.Add($rel)
    $resume = Get-ResumeDetails $r
    if ($resume) { $rd = New-Texte $resume 12 $Colors.dim; $rd.Margin = '0,4,0,0'; [void]$txt.Children.Add($rd) }

    $btns = New-Object System.Windows.Controls.WrapPanel   # (passe à la ligne s'il y a trop de boutons pour la largeur)
    $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,-8'
    # Validé mais pas eu lieu : on peut toujours le décaler à un autre jour
    if ($valide -and -not $r.Repetition) {
        $dec = New-PetitBouton 'Décaler' $r.Id
        $dec.ToolTip = 'Il n''a pas eu lieu ? Choisis un autre jour'
        $dec.Add_Click({ param($s) $rv = Get-RendezVous ([string]$s.Tag); if ($rv) { Open-Formulaire -RV $rv -Decaler } })
        [void]$btns.Children.Add($dec)
    }
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

# « C'est fait » / « Pas encore fait » (croix de la liste, bouton de la fiche) : pour une chose qui revient, seulement la
# fois montrée. Pas enregistré (agenda en lecture seule...) : rien n'a changé, et c'est dit.
function Switch-FaitRV([string]$Id, $Quand) {
    $rv = Get-RendezVous $Id
    if (-not $rv) { return }
    try { Save-Annulation; Set-FaitRV $rv.Id $Quand (-not (Test-FaitRV $rv $Quand)) }
    catch { Write-Log "« C'est fait » non enregistré : $_"; Show-FormMessage (Get-TexteNonEnregistre) $Colors.bad }
    Update-Agenda
}

function Get-TexteNonEnregistre {
    if ($script:AgendaPris) { 'L''agenda est en lecture seule pour l''instant : rien n''a changé. Réessaie dans quelques secondes.' }
    else { 'Je n''ai pas réussi à l''enregistrer : rien n''a changé.' }
}

# Le bandeau de l'agenda : en lecture seule (un autre programme garde le fichier ouvert : nouvel essai toutes les
# 10 secondes), ou des rendez-vous abîmés gardés de côté
function Update-AgendaBandeau {
    if (-not $ui.AgendaBandeau) { return }
    $n = @($script:AgendaIllisibles | Where-Object { $_ }).Count
    if ($script:AgendaPris) {
        $ui.AgendaBandeauTexte.Text = 'Agenda en lecture seule : un autre programme garde ton fichier de rendez-vous ouvert. Nouvel essai dans 10 s. Tes changements ne peuvent pas être enregistrés d''ici là.'
        $ui.AgendaBandeau.Visibility = 'Visible'
        Start-AgendaReessai
    } elseif ($n) {
        $ui.AgendaBandeauTexte.Text = $(if ($n -eq 1) { '1 rendez-vous de ton agenda est abîmé : je ne peux pas l''afficher, mais je le garde de côté dans le fichier, rien n''est perdu.' } else { "$n rendez-vous de ton agenda sont abîmés : je ne peux pas les afficher, mais je les garde de côté dans le fichier, rien n'est perdu." })
        $ui.AgendaBandeau.Visibility = 'Visible'
    } else { $ui.AgendaBandeau.Visibility = 'Collapsed' }
}

function Start-AgendaReessai {
    if (-not $script:AgendaReessai) {
        $script:AgendaReessai = New-Object System.Windows.Threading.DispatcherTimer
        $script:AgendaReessai.Interval = [TimeSpan]::FromSeconds(10)
        $script:AgendaReessai.Add_Tick({
            try {
                Import-Agenda
                if (-not $script:AgendaPris) { $script:AgendaReessai.Stop(); Write-Log 'Agenda relu : il peut de nouveau être enregistré'; Save-FaitAncien }
                Update-Agenda
            } catch { Write-Log "Agenda : nouvel essai impossible ($_)" }
        })
    }
    if (-not $script:AgendaReessai.IsEnabled) { $script:AgendaReessai.Start() }
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
    # (jamais « rien de prévu » quand l'agenda n'a pas pu être lu)
    if ($script:AgendaPris) { $ui.ListeVideTitre.Text = 'Agenda pas encore lu.'; $ui.ListeVideTexte.Text = 'Un autre programme garde ton fichier de rendez-vous ouvert.' + "`n" + 'Je réessaie toutes les 10 secondes.' }
    Update-AgendaBandeau
    $ui.ListeAVenir.Children.Clear()
    foreach ($it in $items) { [void]$ui.ListeAVenir.Children.Add((New-RendezVousRow $it)) }
    $n = $items.Count
    $ui.ListeVide.Visibility = if ($n) { 'Collapsed' } else { 'Visible' }
    $ui.ListeCompte.Text = switch ($n) { 0 { '' } 1 { '1 rendez-vous' } default { "$n rendez-vous" } }
    Update-Aujourdhui
}

# Aujourd'hui : l'anneau des « À faire » (cochés « C'est fait » sur ceux du jour) et la bulle de la mascotte du thème
function Update-Aujourdhui {
    $today = (Get-Date).Date
    $jour = @(Get-AgendaEntre $today $today.AddDays(1))
    $af = @($jour | Where-Object { (Get-TypeRV $_.RV) -eq 'rappel' })
    $faits = @($af | Where-Object { Test-FaitRV $_.RV $_.Prochain }).Count
    $total = $af.Count
    if ($total) {
        $ui.AFaireZone.Visibility = 'Visible'
        $ui.AFaireChiffre.Text = "$faits/$total"
        $reste = $total - $faits
        $ui.AFaireTexte.Text = if (-not $reste) { 'Tout est fait, bravo !' } elseif ($reste -eq 1) { "$faits sur $total, plus qu'une !" } else { "$faits sur $total faites" }
        # Longueur du cercle en épaisseurs de trait (diamètre 64 - trait 6)
        $L = [math]::PI * 58 / 6
        $ui.AFaireAnneau.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection (,[double[]]@($L, $L))
        $cible = $L * (1 - $faits / $total)
        if ($script:AFaireValeur -ne "$faits/$total") {
            $script:AFaireValeur = "$faits/$total"
            $a = New-Object System.Windows.Media.Animation.DoubleAnimation $L, $cible, ([System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1100)))
            $a.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase; $a.BeginTime = [TimeSpan]::FromMilliseconds(250)
            $ui.AFaireAnneau.BeginAnimation([System.Windows.Shapes.Shape]::StrokeDashOffsetProperty, $a)
        }
    } else { $ui.AFaireZone.Visibility = 'Collapsed' }
    if ($ThemePack -and $ThemePack.Mascotte) {
        $h = (Get-Date).Hour
        $bj = if ($h -ge 18 -or $h -lt 5) { 'Bonsoir' } else { 'Bonjour' }
        $rdv = @($jour | Where-Object { (Get-TypeRV $_.RV) -ne 'rappel' -and $_.Prochain -ge (Get-Date).AddMinutes(-30) -or ((Get-TypeRV $_.RV) -ne 'rappel' -and $_.RV.Journee) }).Count
        $reste = $total - $faits
        $morceaux = @()
        if ($rdv) { $morceaux += $(if ($rdv -eq 1) { '1 rendez-vous' } else { "$rdv rendez-vous" }) }
        if ($reste) { $morceaux += $(if ($reste -eq 1) { '1 chose à faire' } else { "$reste choses à faire" }) }
        $ui.MascotteTexte.Text = if ($morceaux.Count) { "$bj ! Tu as $($morceaux -join ' et ') aujourd'hui." } else { "$bj ! Rien de prévu aujourd'hui, profite bien." }
    }
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
    foreach ($k in @(@('une', 'FRepUne'), @('jour', 'FRepJour'), @('semaine', 'FRepSemaine'), @('mois', 'FRepMois'), @('an', 'FRepAn'))) {
        $ui[$k[1]].Tag = if ($k[0] -eq $Type) { 'on' } else { $null }
    }
    if (-not $script:FormOuverture -and $ui.FDernierPanel) { $ui.FDernierPanel.Visibility = if ($script:FJournee -and $script:FType -ne 'anniv' -and $Type -eq 'une') { 'Visible' } else { 'Collapsed' } }
}

function Update-FHeureInfo {
    $t = $ui.FHeure.Text
    if (-not $t.Trim()) { $ui.FHeureInfo.Text = ''; return }
    $h = Read-Heure $t
    if ($null -eq $h) { $ui.FHeureInfo.Text = 'Je ne comprends pas cette heure'; $ui.FHeureInfo.Foreground = Get-Brush $Colors.bad }
    else { $ui.FHeureInfo.Text = '= ' + (Format-Heure ([datetime]::Today + $h)); $ui.FHeureInfo.Foreground = Get-Brush $Colors.ok }
}

function Show-FMessage([string]$Text, [string]$Couleur = $Colors.bad) {
    $ui.FMessage.Text = $Text; $ui.FMessage.Foreground = Get-Brush $Couleur; $ui.FMessage.Visibility = 'Visible'
}

# -Jour : jour proposé (sinon le jour choisi, sinon aujourd'hui). -RV : rendez-vous à modifier.
function Open-Formulaire($Jour, $RV, [switch]$Copie, [switch]$Decaler) {
    $script:FormEdition = $RV
    $script:FormDecaler = [bool]$Decaler
    $titre = ''; $heure = ''; $rep = 'une'; $type = 'rdv'; $journee = $false; $script:FJusqua = $null; $script:FRepPhrase = $null
    $jourForm = if ($Jour) { ([datetime]$Jour).Date } elseif ($script:JourChoisi -and $script:JourChoisi -ge (Get-Date).Date) { $script:JourChoisi } else { (Get-Date).Date }
    if ($RV) {
        $titre = $RV.Titre; $jourForm = $RV.Quand.Date; $type = Get-TypeRV $RV; $journee = [bool]$RV.Journee
        if (-not $journee) { $heure = Format-Heure $RV.Quand }
        if ($RV.Repetition) { $rep = [string]$RV.Repetition.Type; $script:FJusqua = [string]$RV.Repetition.Jusqua }
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
        if ($p.Repetition) { $rep = [string]$p.Repetition.Type; $script:FJusqua = [string]$p.Repetition.Jusqua; $script:FRepPhrase = $p.Repetition }
    }
    $script:FRepetDepart = $rep
    $ui.FormTitre.Text = if ($Copie) { 'Copie du rendez-vous' } elseif ($Decaler) { 'Décaler le rendez-vous' } elseif ($RV) { 'Modifier le rendez-vous' } else { 'Nouveau rendez-vous' }
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
    if ($Decaler) {
        # Le calendrier s'ouvre sur le mois en cours : il ne reste qu'à choisir le nouveau jour (et l'heure si besoin)
        $script:FMois = (Get-Date).Date.AddDays(1 - (Get-Date).Day); Update-FCalendrier
        Show-FMessage 'Il n''a pas eu lieu ? Choisis le nouveau jour, et l''heure si elle change.' $Colors.accent
    }
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
    $script:FormEdition = $null; $script:FormDecaler = $false
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
        'jour'    { [ordered]@{ Type = 'jour' } }
        'semaine' { [ordered]@{ Type = 'semaine'; Jour = [int]$quand.DayOfWeek } }
        'mois'    { [ordered]@{ Type = 'mois'; Jour = $quand.Day } }
        'an'      { [ordered]@{ Type = 'an'; Jour = $quand.Day; Mois = $quand.Month } }
        default   { $null }
    }
    # Même sorte de répétition qu'avant : elle garde son rythme (« tous les 2 jours »), ses jours, son rang, sa date de fin et ses jours sautés
    if ($rep -and $script:FRepetDepart -eq $script:FRepet) {
        $avant = if ($script:FormEdition) { $script:FormEdition.Repetition } else { $script:FRepPhrase }
        if ($avant) {
            foreach ($k in 'Jours', 'Intervalle', 'Rang', 'Sauf') { if ($null -ne $avant.$k) { $rep[$k] = $avant.$k } }
            if ($avant.Rang) { $rep.Jour = $avant.Jour }
        }
        if ($script:FJusqua) { $rep.Jusqua = $script:FJusqua }
    }
    $edition = $script:FormEdition
    $limite = if ($script:FJournee) { (Get-Date).Date } else { Get-Date }
    if (-not $rep -and $quand -lt $limite -and (-not $edition -or $script:FormDecaler)) { Show-FMessage 'Ce moment est déjà passé. Choisis un autre jour ou une autre heure.'; return }
    $type = if ($script:FType) { $script:FType } else { 'rdv' }
    $lu = Read-FDetails $quand $script:FJournee
    if ($lu.Erreur) { Show-FMessage $lu.Erreur; return }
    if ($type -eq 'anniv') { $titre = Get-TitreAnniversaire $titre }
    try {
        $titre = Get-TitreAffiche $titre
        Save-Annulation
        $r = if ($edition) { Update-RendezVous $edition.Id $titre $quand $rep $type $script:FJournee $lu.Detail } else { Add-RendezVous $titre $quand $rep $type $script:FJournee $lu.Detail }
    } catch { Write-Log "Enregistrement impossible : $_"; Show-FMessage "Je n'ai pas réussi à l'enregistrer. ($($_.Exception.Message))"; return }
    # Remis à plus tard : il n'est plus validé ni fait
    if ($edition -and $edition.Fait -and $quand -ge $limite) { Set-RendezVousDetail $r.Id 'Fait' $false; $r = Get-RendezVous $r.Id }
    Close-Formulaire
    if (-not $edition) { $ui.InPhrase.Text = '' }
    $depuis = if ($r.Journee) { (Get-Date).Date } else { Get-Date }
    $prochain = Get-NextOccurrence $r.Repetition $r.Quand $depuis
    if ($prochain -eq [datetime]::MinValue) { $prochain = $r.Quand }   # sa date de fin est passée
    Show-FormMessage $(if ($edition) { "C'est modifié : $($r.Titre), $(Format-QuandRV $r $prochain)." } else { Get-MessageNote $r }) $Colors.ok
    Select-JourCalendrier $prochain
}
