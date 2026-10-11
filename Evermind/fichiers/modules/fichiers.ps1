# Evermind : les dossiers et fichiers reliés à un rendez-vous (« réunion avec Monsieur Richard » : son dossier).
#   Chaque rendez-vous peut avoir des Fichiers (dossiers ou fichiers) : la fiche les ouvre d'un clic.
#   Evermind retrouve tout seul le dossier d'une personne dans les dossiers choisis dans les réglages
#   (par exemple « Comptabilité » : « Monsieur Richard », « Madame Dupont »...).
#   OuvrirAuDebut : à l'heure du rendez-vous, Evermind ouvre ses fichiers et le dit.
# Rien ne sort du PC : Evermind regarde seulement les noms des dossiers, jamais leur contenu.
# Chargé par Evermind.ps1, après donnees.ps1.

# Où chercher les dossiers des personnes (réglages) ; par défaut le Bureau et les Documents
function Get-DossiersRecherche {
    if ($EnTest -and $env:EVERMIND_DOSSIERS) { return @($env:EVERMIND_DOSSIERS -split ';' | Where-Object { $_ }) }
    $d = @(Get-Setting 'DossiersRecherche' $null)
    if (-not $d.Count -or ($d.Count -eq 1 -and -not $d[0])) { $d = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments')) }
    @($d | Where-Object { $_ })
}

# Un nom sans accents, sans majuscules, sans « Monsieur » ni « Madame » : les mots qui comptent
$Civilites = 'monsieur', 'madame', 'mademoiselle', 'mr', 'mme', 'mlle', 'm', 'mr.', 'dr', 'docteur', 'maitre', 'me', 'le', 'la', 'les', 'de', 'du', 'des', 'chez', 'dossier', 'client', 'societe', 'ste', 'sarl', 'sas'
function Get-MotsNom([string]$Nom) {
    $t = $Nom.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    @([regex]::Matches($t, '[a-z0-9]+') | ForEach-Object { $_.Value } | Where-Object { $_ -notin $Civilites -and $_.Length -ge 2 })
}

# Les dossiers sous les dossiers de recherche (4 niveaux au plus), gardés 2 minutes
function Get-ListeDossiers {
    if ($script:ListeDossiers -and ((Get-Date) - $script:ListeDossiersQuand).TotalSeconds -lt 120) { return $script:ListeDossiers }
    $l = New-Object System.Collections.ArrayList
    foreach ($r in (Get-DossiersRecherche)) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        try { foreach ($d in (Get-ChildItem -LiteralPath $r -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue)) { [void]$l.Add($d.FullName) } } catch {}
    }
    $script:ListeDossiers = @($l); $script:ListeDossiersQuand = Get-Date
    $script:ListeDossiers
}

# Les dossiers qui portent ce nom, les meilleurs d'abord (tous les mots du nom, puis le nom de famille seul)
function Find-Dossiers([string]$Nom) {
    $mots = @(Get-MotsNom $Nom)
    if (-not $mots.Count) { return @() }
    $res = foreach ($chemin in (Get-ListeDossiers)) {
        $md = @(Get-MotsNom (Split-Path $chemin -Leaf))
        if (-not $md.Count) { continue }
        $tous = @($mots | Where-Object { $md -contains $_ }).Count
        $score = if ($tous -eq $mots.Count -and $md.Count -eq $mots.Count) { 3 } elseif ($tous -eq $mots.Count) { 2 } elseif ($md -contains $mots[-1]) { 1 } else { 0 }
        if ($score) { [pscustomobject]@{ Chemin = $chemin; Score = $score; Profondeur = ($chemin -split '\\').Count } }
    }
    @($res | Sort-Object @{ Expression = 'Score'; Descending = $true }, Profondeur | ForEach-Object { $_.Chemin })
}

# Le dossier d'une personne, seulement s'il n'y a pas de doute (un seul dossier au meilleur score)
function Find-DossierPersonne([string]$Nom) {
    $mots = @(Get-MotsNom $Nom)
    if (-not $mots.Count) { return $null }
    $c = @(Find-Dossiers $Nom)
    if (-not $c.Count) { return $null }
    $meilleur = @($c | Where-Object { @(Get-MotsNom (Split-Path $_ -Leaf) | Where-Object { $mots -contains $_ }).Count -eq $mots.Count })
    if ($meilleur.Count -eq 1) { return $meilleur[0] }
    if (-not $meilleur.Count -and $c.Count -eq 1) { return $c[0] }
    $null
}

# Les dossiers à relier à un nouveau rendez-vous : ceux des personnes avec qui il est
# (« réunion avec Monsieur Richard »), ou d'un nom propre dans le titre (« réunion Monsieur Richard »)
function Get-DossiersAuto($Titre, $Avec) {
    $noms = @($Avec | Where-Object { $_ })
    $m = [regex]::Match([string]$Titre, '(?:(?:Monsieur|Madame|Mademoiselle|M\.|Mme|Mlle|Docteur|Dr|Ma[iî]tre|Me)\s+)?[A-ZÉÈ][\p{L}''-]+(?:\s+[A-ZÉÈ][\p{L}''-]+)*\s*$')
    if (-not $noms.Count -and $m.Success -and $m.Value -match '\s|^(?:M\.|Mme)') { $noms = @($m.Value.Trim()) }
    @($noms | ForEach-Object { Find-DossierPersonne $_ } | Where-Object { $_ } | Select-Object -Unique)
}

# « J'ai relié le dossier Monsieur Richard » (confirmation d'une création), ou rien
function Get-TexteFichiers($r) {
    $f = @($r.Fichiers)
    if (-not $f.Count) { return '' }
    $quoi = if ($f.Count -eq 1) { Get-NomFichier $f[0] } else { "$($f.Count) dossiers et fichiers" }
    " J'ai relié $quoi$(if ($r.OuvrirAuDebut) { ', je l''ouvrirai à l''heure' })."
}

# Ouvre un dossier (Explorateur) ou un fichier (son application)
function Open-Fichier([string]$Chemin) {
    if (-not (Test-Path -LiteralPath $Chemin)) { Write-Log "Fichier introuvable : $Chemin"; return $false }
    Write-Log "Ouverture : $Chemin"
    if ($EnTest) { return $true }
    try {
        if (Test-Path -LiteralPath $Chemin -PathType Container) { Start-Process explorer.exe "`"$Chemin`"" } else { Start-Process -FilePath $Chemin }
        $true
    } catch { Write-Log "Ouverture impossible : $_"; $false }
}

function Open-FichiersRV($rv) {
    $n = 0
    foreach ($f in @($rv.Fichiers)) { if (Open-Fichier $f) { $n++ } }
    $n
}

# Nom court d'un fichier ou dossier pour l'affichage et la voix (« le dossier Monsieur Richard »)
function Get-NomFichier([string]$Chemin) {
    $n = Split-Path $Chemin -Leaf
    if (Test-Path -LiteralPath $Chemin -PathType Container) { "le dossier $n" } else { "le fichier $n" }
}

# ---------------------------------------------------------------------------
# À l'heure du rendez-vous : ses fichiers s'ouvrent tout seuls (s'il le demande), une seule fois
# ---------------------------------------------------------------------------
function Invoke-OuverturesDues([datetime]$Maintenant = (Get-Date)) {
    if (-not $script:Ouverts) { $script:Ouverts = @{} }
    $faits = @()
    foreach ($it in @(Get-AgendaEntre $Maintenant.AddMinutes(-2) $Maintenant.AddSeconds(1))) {
        $rv = $it.RV
        if (-not $rv.OuvrirAuDebut -or -not @($rv.Fichiers).Count -or $rv.Journee) { continue }
        $cle = "$($rv.Id)|$($it.Prochain.ToString('s'))"
        if ($script:Ouverts.ContainsKey($cle)) { continue }
        $script:Ouverts[$cle] = $true
        $n = Open-FichiersRV $rv
        $nom = Get-TitreAffiche $rv.Titre
        $quoi = if (@($rv.Fichiers).Count -eq 1) { Get-NomFichier $rv.Fichiers[0] } else { "ses $(@($rv.Fichiers).Count) dossiers et fichiers" }
        Write-Log "C'est l'heure : $nom, $n ouvert(s)"
        Show-Notify "C'est l'heure : $nom" "J'ouvre $quoi."
        Invoke-Parole "C'est l'heure : $nom. J'ouvre $quoi."
        $faits += $rv
    }
    $faits
}

function Start-PlanificateurFichiers {
    if ($script:PlanifFichiers) { return }
    $script:PlanifFichiers = New-Object System.Windows.Threading.DispatcherTimer
    $script:PlanifFichiers.Interval = [TimeSpan]::FromSeconds(15)
    $script:PlanifFichiers.Add_Tick({ try { [void](Invoke-OuverturesDues) } catch { Write-Log "Ouverture à l'heure : $_" } })
    $script:PlanifFichiers.Start()
}

# ---------------------------------------------------------------------------
# Réglages, Général : les dossiers où chercher
# ---------------------------------------------------------------------------
function Update-DossiersReglage {
    $ui.DossiersRecherche.Children.Clear()
    foreach ($d in (Get-DossiersRecherche)) {
        $ligne = New-Object System.Windows.Controls.Border
        $ligne.Padding = '12,6'; $ligne.Margin = '0,0,0,6'; $ligne.CornerRadius = 12; $ligne.Background = Get-Brush '#0FFFFFFF'
        $dp = New-Object System.Windows.Controls.DockPanel
        $x = New-Button '✕'; $x.Tag = $d; $x.Padding = '10,3'; $x.Margin = '8,0,0,0'; $x.ToolTip = 'Ne plus chercher ici (le dossier n''est pas supprimé)'
        $x.Add_Click({ param($s) Set-DossiersRecherche @(Get-DossiersRecherche | Where-Object { $_ -ne [string]$s.Tag }) })
        [System.Windows.Controls.DockPanel]::SetDock($x, 'Right'); [void]$dp.Children.Add($x)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = "📁  $d"; $t.FontSize = 14; $t.Foreground = Get-Brush $(if (Test-Path -LiteralPath $d) { '#F2EFFA' } else { '#FFB547' }); $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'; $t.ToolTip = $d
        [void]$dp.Children.Add($t)
        $ligne.Child = $dp
        [void]$ui.DossiersRecherche.Children.Add($ligne)
    }
}

function Set-DossiersRecherche([string[]]$Liste) {
    Set-Setting 'DossiersRecherche' @($Liste | Where-Object { $_ } | Select-Object -Unique)
    $script:ListeDossiers = $null   # la recherche repart des nouveaux dossiers
    Update-DossiersReglage
}

function Add-DossierRecherche {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Choisis un dossier où chercher les dossiers des personnes (par exemple Comptabilité)'
    if ($d.ShowDialog() -eq 'OK') { Set-DossiersRecherche (@(Get-DossiersRecherche) + $d.SelectedPath) }
}
