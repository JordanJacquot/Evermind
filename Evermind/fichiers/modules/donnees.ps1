# Evermind : journal, réglages et fichier des rendez-vous.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# (Copie gérée par Mindset ou non : $GereParMindset, décidé par mindset.ps1, chargé avant tout le reste.)

# ---------------------------------------------------------------------------
# Dossier de données : %LOCALAPPDATA%\Evermind, ou celui de Mindset pour une copie gérée par Mindset
# ---------------------------------------------------------------------------
# Tout ce qu'Evermind garde (rendez-vous, réglages, journal, voix, assistant, packs...) est dans ce dossier, choisi
# ici une seule fois. Son programme (Mindset.exe) y écrit aussi son journal (il le trouve dans EVERMIND_JOURNAL, voir plus bas).
# Dossier de données d'une copie gérée, déduit de l'emplacement du programme (jamais d'un fichier modifiable) :
#   <X>:\Mindset\Programmes\Evermind   ->  <X>:\Mindset\Donnees\Evermind   (Mindset installé sur un autre disque)
#   sinon (C:\Program Files\Mindset\Evermind...)  ->  %LOCALAPPDATA%\Mindset\Evermind
function Get-DonneesMindset([string]$Racine) {
    $p = if ($Racine) { Split-Path $Racine -Parent } else { $null }
    $m = if ($p) { Split-Path $p -Parent } else { $null }
    if ($m -and (Split-Path $p -Leaf) -ieq 'Programmes' -and (Split-Path $m -Leaf) -ieq 'Mindset') { return [IO.Path]::Combine($m, 'Donnees', 'Evermind') }   # (Join-Path refuse un disque absent)
    Join-Path $env:LOCALAPPDATA 'Mindset\Evermind'
}
$DataDirAncien  = Join-Path $env:LOCALAPPDATA 'Evermind'
$DataDirMindset = Get-DonneesMindset $AppRacine
$DataDirNote    = $null   # ce qui s'est passé, écrit au journal dès qu'il est prêt
if ($env:EVERMIND_DONNEES) { $DataDir = $env:EVERMIND_DONNEES }
elseif (-not $GereParMindset) { $DataDir = $DataDirAncien }
else {
    $DataDir = $DataDirMindset
    # Premier lancement géré par Mindset : l'ancien dossier est renommé (même disque : immédiat, même pour des Go
    # de modèles). Un fichier ouvert (par exemple la voix utilisée par Eve) l'empêche : on garde l'ancien pour cette
    # fois, et on réessaie au prochain lancement. Sur un autre disque, rien n'est copié ici : c'est Mindset qui copie
    # les données avant de lancer Evermind ; en attendant, l'ancien dossier est gardé.
    if (-not [IO.Directory]::Exists($DataDirMindset) -and [IO.Directory]::Exists($DataDirAncien)) {
        if ($EnTest -and $env:LOCALAPPDATA -ieq [Environment]::GetFolderPath('LocalApplicationData')) {
            $DataDir = $DataDirAncien; $DataDirNote = 'Données : pas de déplacement pendant un test'   # (seulement dans un faux %LOCALAPPDATA%)
        } elseif ([IO.Path]::GetPathRoot($DataDirAncien) -ine [IO.Path]::GetPathRoot($DataDirMindset)) {
            $DataDir = $DataDirAncien
            $DataDirNote = "Données : $DataDirMindset est sur un autre disque, rien n'est copié ici (Mindset s'en charge), $DataDirAncien gardé cette fois"
        } else {
            try {
                New-Item -ItemType Directory -Force -Path (Split-Path $DataDirMindset -Parent) | Out-Null
                [IO.Directory]::Move($DataDirAncien, $DataDirMindset)   # (Move-Item) un simple renommage, jamais une copie à moitié faite
                $DataDirNote = "Données déplacées de $DataDirAncien vers $DataDirMindset (Evermind est géré par Mindset)"
            } catch {
                $DataDir = $DataDirAncien
                $DataDirNote = "Données : déplacement vers $DataDirMindset impossible pour l'instant ($($_.Exception.Message)), $DataDirAncien gardé cette fois"
            }
        }
    }
}
$AgendaFile   = Join-Path $DataDir 'rendez-vous.json'
$SettingsFile = Join-Path $DataDir 'reglages.json'
$LogFile      = Join-Path $DataDir 'journal.txt'
$Utf8NoBom    = New-Object Text.UTF8Encoding($false)
$Fr           = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$env:EVERMIND_JOURNAL = $LogFile   # Mindset.exe (outils\lanceur.cs) y écrit les erreurs qu'il voit passer

# Journal gardé petit : au delà de 1 Mo, on ne garde que les 3000 dernières lignes
try {
    $logInfo = New-Object IO.FileInfo $LogFile
    if ($logInfo.Exists -and $logInfo.Length -gt 1MB) {
        $logLines = [IO.File]::ReadAllLines($LogFile, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllLines($LogFile, [string[]]($logLines | Select-Object -Last 3000), $Utf8NoBom)
        $logLines = $null
    }
} catch {}

function Write-Log([string]$Message) {
    try { [IO.File]::AppendAllText($LogFile, "$(Get-Date -Format s) $Message`r`n", $Utf8NoBom) } catch {}
}
if ($DataDirNote) { Write-Log $DataDirNote }

# Écrit un fichier JSON sans risque de le perdre : on écrit à côté, puis on remplace d'un coup
# (l'ancienne version reste dans « .bak » si quelque chose tourne mal).
# Un fichier qu'un autre programme gardait ouvert à la lecture ($script:FichiersPris) n'est jamais écrit : on en a
# peut-être seulement la sauvegarde en mémoire, et l'écrire ferait perdre la dernière version.
$script:FichiersPris = @{}
function Save-JsonFile([string]$Path, $Object) {
    if ($script:FichiersPris[$Path]) { throw "$(Split-Path $Path -Leaf) est en lecture seule pour l'instant (un autre programme le garde ouvert)" }
    $json = ConvertTo-Json -InputObject $Object -Depth 8
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $json, $Utf8NoBom)
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, "$Path.bak") }
    else { [IO.File]::Move($tmp, $Path) }
}

# Lit un fichier JSON. Un fichier abîmé est mis de côté (rien n'est jamais effacé) et on repart de la sauvegarde.
# Un fichier vide (coupé net par une panne) compte comme abîmé : sinon on repartirait de rien, et la sauvegarde
# suivante écraserait la bonne copie « .bak ».
# Un fichier qu'un autre programme garde ouvert (antivirus, copie en cours...) n'est pas abîmé : 3 essais à 200 ms,
# puis il est noté « pris » ($script:FichiersPris) : on lit sa sauvegarde pour montrer quelque chose, mais rien n'est
# enregistré tant qu'il n'a pas été relu (sinon la bonne version, poussée vers « .bak », serait écrasée).
function Test-ErreurFichierPris($Erreur) {
    for ($e = $Erreur; $e; $e = $e.InnerException) {
        if ($e -is [IO.IOException] -and (($e.HResult -band 0xFFFF) -in 32, 33)) { return $true }   # (partage, verrou)
    }
    $false
}

function Read-JsonFile([string]$Path) {
    $script:FichiersPris.Remove($Path)
    foreach ($p in $Path, "$Path.bak") {
        if (-not [IO.File]::Exists($p)) { continue }
        $texte = $null; $pris = $false
        for ($essai = 1; $essai -le 3; $essai++) {
            try { $texte = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8); $pris = $false; break }
            catch {
                $pris = Test-ErreurFichierPris $_.Exception
                if (-not $pris) { break }
                if ($essai -lt 3) { Start-Sleep -Milliseconds 200 }
            }
        }
        if ($pris) {
            Write-Log "Fichier pris par un autre programme, en lecture seule pour l'instant : $p"
            if ($p -eq $Path) { $script:FichiersPris[$Path] = $true }
            continue
        }
        try {
            if ($null -eq $texte) { $texte = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }   # (autre erreur : vue ici, comme abîmé)
            $j = $texte | ConvertFrom-Json
            if ($null -eq $j) { throw 'fichier vide' }
            if ($p -ne $Path) { Write-Log "Fichier repris de sa sauvegarde : $p" }
            return $j
        }
        catch {
            Write-Log "Fichier illisible ($p) : $_"
            $copie = "$p.abime-$(Get-Date -Format yyyyMMdd-HHmmss)"
            try { Copy-Item -LiteralPath $p -Destination $copie -Force; Write-Log "Fichier abîmé mis de côté : $copie" } catch { Write-Log "Fichier abîmé non copié ($p) : $_" }
        }
    }
    $null
}

# ---------------------------------------------------------------------------
# Réglages
# ---------------------------------------------------------------------------
$script:Settings = @{}
$j = Read-JsonFile $SettingsFile
if ($j) { foreach ($p in $j.PSObject.Properties) { $script:Settings[$p.Name] = $p.Value } }

function Get-Setting([string]$Name, $Default) {
    if ($script:Settings.ContainsKey($Name)) { $script:Settings[$Name] } else { $Default }
}

function Set-Setting([string]$Name, $Value) {
    $script:Settings[$Name] = $Value
    try { Save-JsonFile $SettingsFile $script:Settings } catch { Write-Log "Réglages non enregistrés : $_" }
}

# ---------------------------------------------------------------------------
# Rendez-vous
# ---------------------------------------------------------------------------
# Dans le fichier, chaque rendez-vous ressemble à :
#   { "Id": "...", "Titre": "Dentiste", "Type": "sante", "Quand": "2027-02-27T15:00", "Journee": false, "Repetition": null, "Rappels": null, "Cree": "..." }
#   Type       : sorte de rendez-vous (anniv, sante, jeu... voir $Types dans comprendre.ps1)
#   Journee    : toute la journée (un anniversaire) ; « Quand » est alors le jour à 0 h
#   Repetition : null pour un rendez-vous unique, sinon par exemple { "Type": "semaine", "Jour": 1 } (voir comprendre.ps1)
#                « Quand » est alors la première fois
#   Rappels    : null = les rappels par défaut des réglages
$DateFormat = 'yyyy-MM-ddTHH:mm'

# Détails d'un rendez-vous, en plus du quoi et du quand
#   Fin        : heure de fin ("2027-02-27T16:00") ou null
#   Lieu, Lien, Notes : texte ; Avec : liste de noms ; APreparer : liste de { Texte, Fait }
#   Important, Fait (« À faire » terminé) : oui ou non ; Naissance : année de naissance (anniversaire)
#   FaitPour : pour une chose à faire qui revient, les fois faites (« yyyy-MM-dd » : aucune répétition ne revient plus
#              d'une fois par jour) ; Fait reste alors à non. Cocher « les poubelles » ce mardi ne coupe pas les mardis suivants.
#   Fichiers : dossiers et fichiers reliés (chemins complets) ; OuvrirAuDebut : les ouvrir quand le rendez-vous commence
$Details = 'Fin', 'Lieu', 'Avec', 'Lien', 'Notes', 'APreparer', 'Rappels', 'Important', 'Fait', 'FaitPour', 'Naissance', 'Fichiers', 'OuvrirAuDebut'

# Une date de détail abîmée ne doit jamais faire perdre le rendez-vous : elle est simplement ignorée
function Read-DateSouple($Valeur) {
    if ($Valeur -isnot [string] -or -not $Valeur) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Valeur, $DateFormat, [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $d } else { $null }
}

# Une répétition lue dans le fichier est contrôlée : abîmée (sorte inconnue, jour ou mois hors des bornes, date de fin
# illisible), elle couperait les rappels et la liste de tout l'agenda. Rend la raison, ou rien si elle est bonne.
function Get-ErreurRepetition($Rep) {
    if ($null -eq $Rep) { return $null }
    $n = { param($v, [int]$Min, [int]$Max) $x = 0; $null -eq $v -or ([int]::TryParse([string]$v, [ref]$x) -and $x -ge $Min -and $x -le $Max) }
    $type = [string]$Rep.Type
    if ($type -notin 'jour', 'semaine', 'mois', 'an') { return "sorte de répétition inconnue ($type)" }
    if (-not (& $n $Rep.Intervalle 0 1000)) { return "intervalle illisible ($($Rep.Intervalle))" }
    $d = [datetime]::MinValue
    if ($Rep.Jusqua -and -not [datetime]::TryParseExact([string]$Rep.Jusqua, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return "date de fin illisible ($($Rep.Jusqua))" }
    switch ($type) {
        'semaine' {
            if (-not (& $n $Rep.Jour 0 6)) { return "jour de la semaine illisible ($($Rep.Jour))" }
            foreach ($j in @($Rep.Jours | Where-Object { $null -ne $_ })) { if (-not (& $n $j 0 6)) { return "jour de la semaine illisible ($j)" } }
        }
        'mois' {
            if ($Rep.Rang) {
                if (-not (& $n $Rep.Rang -1 5) -or [int]$Rep.Rang -eq 0) { return "rang illisible ($($Rep.Rang))" }
                if ($null -eq $Rep.Jour -or -not (& $n $Rep.Jour 0 6)) { return "jour de la semaine illisible ($($Rep.Jour))" }
            } elseif ($null -eq $Rep.Jour -or -not (& $n $Rep.Jour 1 31)) { return "jour du mois illisible ($($Rep.Jour))" }
        }
        'an' {
            if ($null -eq $Rep.Jour -or -not (& $n $Rep.Jour 1 31)) { return "jour illisible ($($Rep.Jour))" }
            if ($null -eq $Rep.Mois -or -not (& $n $Rep.Mois 1 12)) { return "mois illisible ($($Rep.Mois))" }
        }
    }
    $null
}

function ConvertTo-RendezVous($Raw) {
    $ic = [Globalization.CultureInfo]::InvariantCulture
    $erreur = Get-ErreurRepetition $Raw.Repetition
    if ($erreur) { throw "répétition abîmée : $erreur" }
    $r = [pscustomobject]@{
        Id         = [string]$Raw.Id
        Titre      = [string]$Raw.Titre
        Type       = [string]$Raw.Type
        Journee    = [bool]$Raw.Journee
        Quand      = [datetime]::ParseExact([string]$Raw.Quand, $DateFormat, $ic)
        Fin        = Read-DateSouple $Raw.Fin
        Repetition = $Raw.Repetition
        Lieu       = if ($Raw.Lieu -is [string]) { $Raw.Lieu } else { '' }
        Avec       = @($Raw.Avec | Where-Object { $_ -is [string] -and $_ })
        Lien       = if ($Raw.Lien -is [string]) { $Raw.Lien } else { '' }
        Notes      = if ($Raw.Notes -is [string]) { $Raw.Notes } else { '' }
        APreparer  = @(foreach ($x in @($Raw.APreparer)) { if ($x -and $x.Texte) { [pscustomobject]@{ Texte = [string]$x.Texte; Fait = [bool]$x.Fait } } })
        Rappels    = if ($null -ne $Raw.Rappels) { , @($Raw.Rappels | Where-Object { $_ -is [string] }) } else { $null }   # (« , » : « aucun rappel » reste une liste vide)
        Important  = [bool]$Raw.Important
        Fait       = [bool]$Raw.Fait
        FaitPour   = @(Get-FaitPourPropre $Raw.FaitPour)
        Naissance  = if ($Raw.Naissance -is [int] -or $Raw.Naissance -is [long] -or "$($Raw.Naissance)" -match '^\d{4}$') { [int]"$($Raw.Naissance)" } else { $null }
        Fichiers   = @($Raw.Fichiers | Where-Object { $_ -is [string] -and $_ })
        OuvrirAuDebut = [bool]$Raw.OuvrirAuDebut
        Cree       = [string]$Raw.Cree
    }
    Update-FaitAncien $r
    $r
}

function Get-FaitPourPropre($Liste) { @($Liste | Where-Object { $_ -is [string] -and $_ -match '^\d{4}-\d{2}-\d{2}$' } | Select-Object -Unique) }

# Avant FaitPour, « c'est fait » sur une chose qui revient la rendait muette pour toujours (Fait = oui) : elle devient
# « faite pour sa dernière fois passée » (ou sa première, si elle n'a pas encore commencé). Il faut comprendre.ps1
# (Get-NextOccurrence), chargé après ce fichier : au démarrage, Evermind.ps1 refait ce passage une fois tout chargé.
function Update-FaitAncien($r) {
    if (-not $r.Fait -or -not $r.Repetition -or -not (Get-Command Get-NextOccurrence -ErrorAction SilentlyContinue)) { return }
    $fois = @(Get-FoisAvant $r (Get-Date) 0)
    $q = if ($fois.Count) { $fois[-1] } else { Get-NextOccurrence $r.Repetition $r.Quand $r.Quand }
    if ($q -eq [datetime]::MinValue) { $q = $r.Quand }
    $r.FaitPour = @(@($r.FaitPour) + (Get-CleFait $q) | Select-Object -Unique)
    $r.Fait = $false
    Write-Log "« C'est fait » d'une chose qui revient, gardé pour la fois du $(Get-CleFait $q) seulement : $($r.Titre)"
}

# Un rendez-vous illisible (date abîmée, répétition abîmée...) n'est jamais perdu : il n'est pas affiché, mais il reste
# tel quel dans le fichier à chaque sauvegarde ($script:AgendaIllisibles), pour pouvoir le réparer plus tard ; la
# fenêtre dit qu'il y en a (agenda.ps1).
# Fichier pris par un autre programme ($script:AgendaPris) : on montre sa sauvegarde, en lecture seule, et la fenêtre
# réessaie toutes les 10 secondes (agenda.ps1) ; rien n'est enregistré d'ici là.
function Import-Agenda {
    $script:Agenda = New-Object System.Collections.ArrayList
    $script:AgendaIllisibles = New-Object System.Collections.ArrayList
    $j = Read-JsonFile $AgendaFile
    $script:AgendaPris = [bool]$script:FichiersPris[$AgendaFile]
    if (-not $j) { return }
    foreach ($r in @($j.RendezVous)) {
        if (-not $r) { continue }
        try { [void]$script:Agenda.Add((ConvertTo-RendezVous $r)) }
        catch {
            [void]$script:AgendaIllisibles.Add($r)
            Write-Log "Rendez-vous illisible, gardé tel quel dans le fichier : $($r | ConvertTo-Json -Compress -Depth 8)"
        }
    }
}

# L'agenda tel qu'il est écrit dans le fichier (sert aussi à « annule », qui en garde une copie)
function Get-AgendaDonnees { @(foreach ($r in $script:Agenda) { ConvertTo-DonneesRV $r }) }

# Un rendez-vous tel qu'il est écrit dans le fichier
function ConvertTo-DonneesRV($r) {
    $ic = [Globalization.CultureInfo]::InvariantCulture
    [ordered]@{ Id = $r.Id; Titre = $r.Titre; Type = $r.Type; Journee = [bool]$r.Journee
                Quand = $r.Quand.ToString($DateFormat, $ic); Fin = $(if ($r.Fin) { $r.Fin.ToString($DateFormat, $ic) } else { $null })
                Repetition = $r.Repetition; Lieu = $r.Lieu; Avec = @($r.Avec); Lien = $r.Lien; Notes = $r.Notes
                APreparer = @($r.APreparer | ForEach-Object { [ordered]@{ Texte = $_.Texte; Fait = [bool]$_.Fait } })
                Rappels = $(if ($null -ne $r.Rappels) { , @($r.Rappels) } else { $null })
                Important = [bool]$r.Important; Fait = [bool]$r.Fait; FaitPour = @($r.FaitPour); Naissance = $r.Naissance
                Fichiers = @($r.Fichiers); OuvrirAuDebut = [bool]$r.OuvrirAuDebut; Cree = $r.Cree }
}

function Save-Agenda {
    Save-JsonFile $AgendaFile ([ordered]@{ Version = 2; RendezVous = @(@(Get-AgendaDonnees) + @($script:AgendaIllisibles | Where-Object { $_ })) })
    if (Get-Command Write-EtatMindset -ErrorAction SilentlyContinue) { try { Write-EtatMindset } catch {} }   # (carte de Mindset, systeme.ps1)
}

# « annule » : une copie de l'agenda est gardée avant chaque changement, d'où qu'il vienne (formulaire, suppression,
# case « c'est fait », barre, voix, assistant). « annule » remet la dernière (les 20 dernières sont gardées).
function Save-Annulation {
    if (-not $script:Annulations) { $script:Annulations = New-Object System.Collections.ArrayList }
    $json = ConvertTo-Json -InputObject @(Get-AgendaDonnees) -Depth 8 -Compress
    # (la même copie deux fois de suite ne servirait à rien : « annule » semblerait ne rien faire)
    if ($script:Annulations.Count -and $script:Annulations[$script:Annulations.Count - 1] -eq $json) { return }
    [void]$script:Annulations.Add($json)
    while ($script:Annulations.Count -gt 20) { $script:Annulations.RemoveAt(0) }
}

function Restore-Annulation {
    if (-not $script:Annulations -or -not $script:Annulations.Count) { return $false }
    $json = $script:Annulations[$script:Annulations.Count - 1]
    # La copie est relue entièrement avant de remplacer l'agenda : en cas de problème, rien n'est perdu
    try {
        $liste = ConvertFrom-Json $json      # (sans @() : PowerShell 5.1 rendrait la liste comme un seul élément)
        $nouveau = New-Object System.Collections.ArrayList
        foreach ($x in $liste) { if ($x) { [void]$nouveau.Add((ConvertTo-RendezVous $x)) } }
    } catch { Write-Log "Annulation impossible : $_"; return $false }
    $ancien = $script:Agenda
    $script:Agenda = $nouveau
    try { Save-Agenda } catch { $script:Agenda = $ancien; Write-Log "Annulation non enregistrée : $_"; return $false }
    $script:Annulations.RemoveAt($script:Annulations.Count - 1)
    Write-Log 'Dernière action annulée'
    $true
}

# $Detail : table avec les détails à mettre (Fin, Lieu, Avec...) ; ceux qui manquent restent vides
function Set-Details($r, $Detail) {
    if (-not $Detail) { return }
    foreach ($k in $Details) {
        if (-not $Detail.Contains($k)) { continue }
        $v = $Detail[$k]
        switch ($k) {
            'Avec'      { $r.Avec = @($v | Where-Object { $_ }) }
            'Fichiers'  { $r.Fichiers = @($v | Where-Object { $_ } | Select-Object -Unique) }
            'APreparer' { $r.APreparer = @($v | Where-Object { $_ } | ForEach-Object { if ($_ -is [string]) { [pscustomobject]@{ Texte = $_; Fait = $false } } else { [pscustomobject]@{ Texte = [string]$_.Texte; Fait = [bool]$_.Fait } } }) }
            'Rappels'   { if ($null -ne $v) { $r.Rappels = @($v) } else { $r.Rappels = $null } }   # (une liste vide = aucun rappel)
            'FaitPour'  { $r.FaitPour = @(Get-FaitPourPropre $v) }
            default     { $r.$k = $v }
        }
    }
}

function Add-RendezVous([string]$Titre, [datetime]$Quand, $Repetition, [string]$Type = 'rdv', [bool]$Journee = $false, $Detail) {
    $r = [pscustomobject]@{ Id = [guid]::NewGuid().ToString('N'); Titre = $Titre.Trim(); Type = $Type; Journee = $Journee; Quand = $Quand; Fin = $null
                            Repetition = $Repetition; Lieu = ''; Avec = @(); Lien = ''; Notes = ''; APreparer = @(); Rappels = $null
                            Important = $false; Fait = $false; FaitPour = @(); Naissance = $null; Fichiers = @(); OuvrirAuDebut = $false; Cree = (Get-Date -Format s) }
    Set-Details $r $Detail
    [void]$script:Agenda.Add($r)
    try { Save-Agenda } catch { $script:Agenda.Remove($r); throw }   # pas enregistré : rien n'a changé
    Write-Log "Rendez-vous ajouté : $($r.Titre), $($r.Quand.ToString($DateFormat))"
    $r
}

function Remove-RendezVous([string]$Id) {
    $r = $script:Agenda | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $r) { return }
    $i = $script:Agenda.IndexOf($r)
    $script:Agenda.Remove($r)
    try { Save-Agenda } catch { $script:Agenda.Insert($i, $r); throw }   # pas enregistré : rien n'a changé
    Write-Log "Rendez-vous supprimé : $($r.Titre), $($r.Quand.ToString($DateFormat))"
}

function Update-RendezVous([string]$Id, [string]$Titre, [datetime]$Quand, $Repetition, [string]$Type = 'rdv', [bool]$Journee = $false, $Detail) {
    $r = Get-RendezVous $Id
    if (-not $r) { throw 'ce rendez-vous n''existe plus' }
    $avant = $r.PSObject.Copy()
    $r.Titre = $Titre.Trim(); $r.Quand = $Quand; $r.Repetition = $Repetition; $r.Type = $Type; $r.Journee = $Journee
    Set-Details $r $Detail
    try { Save-Agenda } catch { Restore-RVCopie $r $avant; throw }
    Write-Log "Rendez-vous modifié : $($r.Titre), $($r.Quand.ToString($DateFormat))"
    $r
}

function Get-RendezVous([string]$Id) { $script:Agenda | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }

# Change un seul détail (« c'est fait », une case de la liste à préparer) et enregistre
function Set-RendezVousDetail([string]$Id, [string]$Nom, $Valeur) {
    $r = Get-RendezVous $Id
    if (-not $r) { return }
    $avant = $r.PSObject.Copy()
    Set-Details $r @{ $Nom = $Valeur }
    try { Save-Agenda } catch { Restore-RVCopie $r $avant; throw }
}

# Pas enregistré : le rendez-vous reprend toutes ses valeurs d'avant (le même objet : la fiche ouverte le suit)
function Restore-RVCopie($r, $Avant) { foreach ($p in $Avant.PSObject.Properties) { $r.($p.Name) = $p.Value } }

# Rappels par défaut d'une sorte de rendez-vous (codes : « veille » à 20 h, « matin » à 8 h, « m60 » = 60 minutes avant)
function Get-RappelsDefaut([string]$Type, [bool]$Journee) {
    if ($Journee -and $Type -eq 'rappel') { return @('matin') }   # une chose à faire dans la journée : le matin même
    if ($Journee -or $Type -eq 'anniv') { return @('veille', 'matin') }
    if ($Type -eq 'rappel') { return @('m0') }
    @('veille', 'matin', 'm60')
}

function Get-RappelsRV($r) { if ($null -ne $r.Rappels) { @($r.Rappels) } else { Get-RappelsDefaut (Get-TypeRV $r) $r.Journee } }

# Autres rendez-vous au même moment (une heure par défaut quand il n'y a pas d'heure de fin)
function Get-Conflits([datetime]$Debut, $Fin, [string]$SaufId) {
    $f = if ($Fin) { [datetime]$Fin } else { $Debut.AddHours(1) }
    @(Get-AgendaEntre $Debut.Date $Debut.Date.AddDays(1) | Where-Object {
        $_.RV.Id -ne $SaufId -and -not $_.RV.Journee -and -not (Test-FaitRV $_.RV $_.Prochain) -and
        $_.Prochain -lt $f -and $(if ($_.RV.Fin) { $_.Prochain + ($_.RV.Fin - $_.RV.Quand) } else { $_.Prochain.AddHours(1) }) -gt $Debut
    })
}

# Un rendez-vous passé est validé tout seul (✓) : fini (son heure de fin, ou son heure s'il n'a pas de fin), ou la journée
# terminée. Les choses « à faire » restent à cocher à la main (Fait). Validé ne bloque rien : il peut toujours être décalé.
function Test-Valide($r, [datetime]$Quand) {
    if ((Get-TypeRV $r) -eq 'rappel') { return (Test-FaitRV $r $Quand) }
    $now = Get-Date
    if ($r.Journee -or (Test-PlusieursJours $r)) {
        $fin = if ($r.Fin -and -not $r.Repetition) { ([datetime]$r.Fin).Date } else { $Quand.Date }
        return $fin -lt $now.Date
    }
    # Avec une heure de fin : validé une fois fini ; sans : dès que son heure est passée
    $fin = if ($r.Fin) { $Quand + ([datetime]$r.Fin - $r.Quand) } else { $Quand }
    $fin -le $now
}

# Un rendez-vous qui fait une erreur (répétition abîmée passée au travers...) est sauté, sans couper les autres ;
# noté une seule fois au journal
function Write-LogRVErreur($r, $Erreur) {
    if (-not $script:RVEnErreur) { $script:RVEnErreur = @{} }
    $id = [string]$r.Id
    if ($script:RVEnErreur.ContainsKey($id)) { return }
    $script:RVEnErreur[$id] = $true
    Write-Log "Rendez-vous sauté (erreur) : $($r.Titre) ($id) : $Erreur"
}

# Toutes les fois où des rendez-vous tombent entre deux moments (pour le calendrier du mois)
function Get-AgendaEntre([datetime]$Debut, [datetime]$Fin) {
    @(foreach ($r in $script:Agenda) {
        try {
            if (-not $r.Repetition) {
                if (Test-PlusieursJours $r) {
                    # Sur plusieurs jours : il apparaît chaque jour (le premier à son heure, les suivants dès minuit)
                    for ($j = $r.Quand.Date; $j -le $r.Fin.Date; $j = $j.AddDays(1)) {
                        $q = if ($j -eq $r.Quand.Date) { $r.Quand } else { $j }
                        if ($q -ge $Debut -and $q -lt $Fin) { [pscustomobject]@{ RV = $r; Prochain = $q } }
                    }
                    continue
                }
                if ($r.Quand -ge $Debut -and $r.Quand -lt $Fin) { [pscustomobject]@{ RV = $r; Prochain = $r.Quand } }
                continue
            }
            $from = $Debut
            for ($i = 0; $i -lt 400; $i++) {
                $q = Get-NextOccurrence $r.Repetition $r.Quand $from
                if ($q -ge $Fin -or $q -lt $from) { break }
                [pscustomobject]@{ RV = $r; Prochain = $q }
                $from = $q.AddMinutes(1)
            }
        } catch { Write-LogRVErreur $r $_ }
    }) | Sort-Object Prochain
}

# Rendez-vous à venir, avec la prochaine fois (« Prochain ») pour ceux qui reviennent. Une chose à faire qui revient
# montre sa prochaine fois pas encore faite.
function Get-Upcoming {
    $now = Get-Date
    @(foreach ($r in $script:Agenda) {
        try {
            $depuis = if ($r.Journee) { $now.Date } else { $now }   # un anniversaire reste « à venir » toute sa journée
            $next = Get-NextOccurrence $r.Repetition $r.Quand $depuis
            if ($next -lt $depuis -and (Test-PlusieursJours $r) -and $r.Fin -ge $depuis) { $next = $depuis.Date }   # commencé, pas encore fini
            for ($i = 0; $r.Repetition -and $i -lt 60 -and $next -ge $depuis -and (Test-FaitRV $r $next); $i++) { $next = Get-NextOccurrence $r.Repetition $r.Quand $next.Date.AddDays(1) }
            if ($next -ge $depuis -and -not (Test-FaitRV $r $next)) { [pscustomobject]@{ RV = $r; Prochain = $next } }
        } catch { Write-LogRVErreur $r $_ }
    }) | Sort-Object Prochain
}

# ---------------------------------------------------------------------------
# « C'est fait » : pour un rendez-vous unique, Fait ; pour une chose qui revient, chaque fois à part (FaitPour)
# ---------------------------------------------------------------------------
function Get-CleFait([datetime]$Quand) { $Quand.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }

function Test-FaitRV($r, $Quand) {
    if (-not $r.Repetition) { return [bool]$r.Fait }
    if ($null -eq $Quand) { return $false }
    @($r.FaitPour) -contains (Get-CleFait ([datetime]$Quand))
}

# Les fois d'un rendez-vous qui revient, de $Jours jours avant $Jusqu jusqu'à $Jusqu compris (0 : assez loin pour
# trouver la dernière fois, selon son rythme)
function Get-FoisAvant($r, [datetime]$Jusqu, [int]$Jours) {
    if (-not $r.Repetition) { return @(if ($r.Quand -le $Jusqu) { $r.Quand }) }
    if ($Jours -le 0) {
        $n = if ($r.Repetition.Intervalle -and [int]$r.Repetition.Intervalle -gt 1) { [int]$r.Repetition.Intervalle } else { 1 }
        $Jours = switch ([string]$r.Repetition.Type) { 'jour' { $n + 1 } 'semaine' { 7 * $n + 7 } 'mois' { 31 * $n + 31 } default { 366 * $n + 366 } }
    }
    $from = $Jusqu.Date.AddDays(-$Jours)
    @(for ($i = 0; $i -lt 400; $i++) {
        $q = Get-NextOccurrence $r.Repetition $r.Quand $from
        if ($q -gt $Jusqu -or $q -lt $from) { break }
        $q
        $from = $q.AddMinutes(1)
    })
}

# « C'est fait » dit sans date : la fois en cours (celle d'aujourd'hui) ou la dernière en retard, jamais une fois à
# venir. Rend la date de cette fois, ou rien si la chose n'a pas encore commencé.
function Get-FoisAFaire($r, [datetime]$Maintenant = (Get-Date)) {
    $fois = @(Get-FoisAvant $r $Maintenant.Date.AddDays(1).AddMinutes(-1) 60)
    if (-not $fois.Count) { return $null }
    $reste = @($fois | Where-Object { -not (Test-FaitRV $r $_) })
    if ($reste.Count) { $reste[-1] } else { $fois[-1] }
}

# Coche ou décoche une fois (ou le rendez-vous unique). Les fois cochées de plus de 90 jours sont oubliées.
function Set-FaitRV([string]$Id, $Quand, [bool]$Valeur) {
    $r = Get-RendezVous $Id
    if (-not $r) { return }
    if (-not $r.Repetition) { Set-RendezVousDetail $Id 'Fait' $Valeur; return }
    $cle = Get-CleFait ([datetime]$Quand)
    $limite = Get-CleFait ((Get-Date).Date.AddDays(-90))
    $liste = @(@($r.FaitPour) | Where-Object { $_ -ne $cle -and $_ -ge $limite })
    if ($Valeur) { $liste += $cle }
    Set-RendezVousDetail $Id 'FaitPour' $liste
}

Import-Agenda
