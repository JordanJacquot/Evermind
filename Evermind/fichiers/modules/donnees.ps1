# Evermind : journal, réglages et fichier des rendez-vous.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

# ---------------------------------------------------------------------------
# Dossier de données
# ---------------------------------------------------------------------------
$DataDir      = if ($env:EVERMIND_DONNEES) { $env:EVERMIND_DONNEES } else { Join-Path $env:LOCALAPPDATA 'Evermind' }
$AgendaFile   = Join-Path $DataDir 'rendez-vous.json'
$SettingsFile = Join-Path $DataDir 'reglages.json'
$LogFile      = Join-Path $DataDir 'journal.txt'
$Utf8NoBom    = New-Object Text.UTF8Encoding($false)
$Fr           = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

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

# Écrit un fichier JSON sans risque de le perdre : on écrit à côté, puis on remplace d'un coup
# (l'ancienne version reste dans « .bak » si quelque chose tourne mal).
function Save-JsonFile([string]$Path, $Object) {
    $json = ConvertTo-Json -InputObject $Object -Depth 8
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $json, $Utf8NoBom)
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, "$Path.bak") }
    else { [IO.File]::Move($tmp, $Path) }
}

# Lit un fichier JSON. Un fichier abîmé est mis de côté (rien n'est jamais effacé) et on repart de la sauvegarde.
function Read-JsonFile([string]$Path) {
    foreach ($p in $Path, "$Path.bak") {
        if (-not [IO.File]::Exists($p)) { continue }
        try { return ([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
        catch {
            Write-Log "Fichier illisible ($p) : $_"
            try { Copy-Item -LiteralPath $p -Destination "$p.abime-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force } catch {}
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
#   Fichiers : dossiers et fichiers reliés (chemins complets) ; OuvrirAuDebut : les ouvrir quand le rendez-vous commence
$Details = 'Fin', 'Lieu', 'Avec', 'Lien', 'Notes', 'APreparer', 'Rappels', 'Important', 'Fait', 'Naissance', 'Fichiers', 'OuvrirAuDebut'

# Une date de détail abîmée ne doit jamais faire perdre le rendez-vous : elle est simplement ignorée
function Read-DateSouple($Valeur) {
    if ($Valeur -isnot [string] -or -not $Valeur) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Valeur, $DateFormat, [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $d } else { $null }
}

function ConvertTo-RendezVous($Raw) {
    $ic = [Globalization.CultureInfo]::InvariantCulture
    [pscustomobject]@{
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
        Rappels    = if ($null -ne $Raw.Rappels) { @($Raw.Rappels | Where-Object { $_ -is [string] }) } else { $null }
        Important  = [bool]$Raw.Important
        Fait       = [bool]$Raw.Fait
        Naissance  = if ($Raw.Naissance -is [int] -or $Raw.Naissance -is [long] -or "$($Raw.Naissance)" -match '^\d{4}$') { [int]"$($Raw.Naissance)" } else { $null }
        Fichiers   = @($Raw.Fichiers | Where-Object { $_ -is [string] -and $_ })
        OuvrirAuDebut = [bool]$Raw.OuvrirAuDebut
        Cree       = [string]$Raw.Cree
    }
}

function Import-Agenda {
    $script:Agenda = New-Object System.Collections.ArrayList
    $j = Read-JsonFile $AgendaFile
    if (-not $j) { return }
    foreach ($r in @($j.RendezVous)) {
        if (-not $r) { continue }
        try { [void]$script:Agenda.Add((ConvertTo-RendezVous $r)) }
        catch { Write-Log "Rendez-vous illisible ignoré : $($r | ConvertTo-Json -Compress)" }
    }
}

# L'agenda tel qu'il est écrit dans le fichier (sert aussi à « annule », qui en garde une copie)
function Get-AgendaDonnees {
    $ic = [Globalization.CultureInfo]::InvariantCulture
    @(foreach ($r in $script:Agenda) {
        [ordered]@{ Id = $r.Id; Titre = $r.Titre; Type = $r.Type; Journee = [bool]$r.Journee
                    Quand = $r.Quand.ToString($DateFormat, $ic); Fin = $(if ($r.Fin) { $r.Fin.ToString($DateFormat, $ic) } else { $null })
                    Repetition = $r.Repetition; Lieu = $r.Lieu; Avec = @($r.Avec); Lien = $r.Lien; Notes = $r.Notes
                    APreparer = @($r.APreparer | ForEach-Object { [ordered]@{ Texte = $_.Texte; Fait = [bool]$_.Fait } })
                    Rappels = $(if ($null -ne $r.Rappels) { @($r.Rappels) } else { $null })
                    Important = [bool]$r.Important; Fait = [bool]$r.Fait; Naissance = $r.Naissance
                    Fichiers = @($r.Fichiers); OuvrirAuDebut = [bool]$r.OuvrirAuDebut; Cree = $r.Cree }
    })
}

function Save-Agenda {
    Save-JsonFile $AgendaFile ([ordered]@{ Version = 2; RendezVous = @(Get-AgendaDonnees) })
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
            'Rappels'   { $r.Rappels = if ($null -ne $v) { @($v) } else { $null } }
            default     { $r.$k = $v }
        }
    }
}

function Add-RendezVous([string]$Titre, [datetime]$Quand, $Repetition, [string]$Type = 'rdv', [bool]$Journee = $false, $Detail) {
    $r = [pscustomobject]@{ Id = [guid]::NewGuid().ToString('N'); Titre = $Titre.Trim(); Type = $Type; Journee = $Journee; Quand = $Quand; Fin = $null
                            Repetition = $Repetition; Lieu = ''; Avec = @(); Lien = ''; Notes = ''; APreparer = @(); Rappels = $null
                            Important = $false; Fait = $false; Naissance = $null; Fichiers = @(); OuvrirAuDebut = $false; Cree = (Get-Date -Format s) }
    Set-Details $r $Detail
    [void]$script:Agenda.Add($r)
    Save-Agenda
    Write-Log "Rendez-vous ajouté : $($r.Titre), $($r.Quand.ToString($DateFormat))"
    $r
}

function Remove-RendezVous([string]$Id) {
    $r = $script:Agenda | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $r) { return }
    $script:Agenda.Remove($r)
    Save-Agenda
    Write-Log "Rendez-vous supprimé : $($r.Titre), $($r.Quand.ToString($DateFormat))"
}

function Update-RendezVous([string]$Id, [string]$Titre, [datetime]$Quand, $Repetition, [string]$Type = 'rdv', [bool]$Journee = $false, $Detail) {
    $r = Get-RendezVous $Id
    if (-not $r) { throw 'ce rendez-vous n''existe plus' }
    $r.Titre = $Titre.Trim(); $r.Quand = $Quand; $r.Repetition = $Repetition; $r.Type = $Type; $r.Journee = $Journee
    Set-Details $r $Detail
    Save-Agenda
    Write-Log "Rendez-vous modifié : $($r.Titre), $($r.Quand.ToString($DateFormat))"
    $r
}

function Get-RendezVous([string]$Id) { $script:Agenda | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }

# Change un seul détail (« c'est fait », une case de la liste à préparer) et enregistre
function Set-RendezVousDetail([string]$Id, [string]$Nom, $Valeur) {
    $r = Get-RendezVous $Id
    if (-not $r) { return }
    Set-Details $r @{ $Nom = $Valeur }
    Save-Agenda
}

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
        $_.RV.Id -ne $SaufId -and -not $_.RV.Journee -and -not $_.RV.Fait -and
        $_.Prochain -lt $f -and $(if ($_.RV.Fin) { $_.Prochain + ($_.RV.Fin - $_.RV.Quand) } else { $_.Prochain.AddHours(1) }) -gt $Debut
    })
}

# Toutes les fois où des rendez-vous tombent entre deux moments (pour le calendrier du mois)
function Get-AgendaEntre([datetime]$Debut, [datetime]$Fin) {
    @(foreach ($r in $script:Agenda) {
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
    }) | Sort-Object Prochain
}

# Rendez-vous à venir, avec la prochaine fois (« Prochain ») pour ceux qui reviennent
function Get-Upcoming {
    $now = Get-Date
    @(foreach ($r in $script:Agenda) {
        $depuis = if ($r.Journee) { $now.Date } else { $now }   # un anniversaire reste « à venir » toute sa journée
        $next = Get-NextOccurrence $r.Repetition $r.Quand $depuis
        if ($next -lt $depuis -and (Test-PlusieursJours $r) -and $r.Fin -ge $depuis) { $next = $depuis.Date }   # commencé, pas encore fini
        if ($next -ge $depuis -and -not $r.Fait) { [pscustomobject]@{ RV = $r; Prochain = $next } }
    }) | Sort-Object Prochain
}

Import-Agenda
