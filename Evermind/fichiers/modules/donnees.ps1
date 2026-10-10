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
#   { "Id": "...", "Titre": "Dentiste", "Quand": "2027-02-27T15:00", "Repetition": null, "Rappels": null, "Cree": "..." }
#   Repetition : null pour un rendez-vous unique (les rendez-vous qui reviennent arrivent avec la saisie en français)
#   Rappels    : null = les rappels par défaut des réglages
$DateFormat = 'yyyy-MM-ddTHH:mm'

function ConvertTo-RendezVous($Raw) {
    [pscustomobject]@{
        Id         = [string]$Raw.Id
        Titre      = [string]$Raw.Titre
        Quand      = [datetime]::ParseExact([string]$Raw.Quand, $DateFormat, [Globalization.CultureInfo]::InvariantCulture)
        Repetition = $Raw.Repetition
        Rappels    = $Raw.Rappels
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

function Save-Agenda {
    $list = @(foreach ($r in $script:Agenda) {
        [ordered]@{ Id = $r.Id; Titre = $r.Titre; Quand = $r.Quand.ToString($DateFormat, [Globalization.CultureInfo]::InvariantCulture)
                    Repetition = $r.Repetition; Rappels = $r.Rappels; Cree = $r.Cree }
    })
    Save-JsonFile $AgendaFile ([ordered]@{ Version = 1; RendezVous = $list })
}

function Add-RendezVous([string]$Titre, [datetime]$Quand) {
    $r = [pscustomobject]@{ Id = [guid]::NewGuid().ToString('N'); Titre = $Titre.Trim(); Quand = $Quand
                            Repetition = $null; Rappels = $null; Cree = (Get-Date -Format s) }
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

function Get-Upcoming {
    $now = Get-Date
    @($script:Agenda | Where-Object { $_.Quand -ge $now } | Sort-Object Quand)
}

# ---------------------------------------------------------------------------
# Dates et heures en français de tous les jours
# ---------------------------------------------------------------------------
function Format-Heure([datetime]$d) {
    if ($d.Minute) { '{0} h {1:00}' -f $d.Hour, $d.Minute } else { "$($d.Hour) h" }
}

# « vendredi 27 février », « samedi 1er mars », avec l'année si ce n'est pas celle en cours
function Format-Jour([datetime]$d) {
    $t = if ($d.Day -eq 1) { $d.ToString('dddd', $Fr) + ' 1er ' + $d.ToString('MMMM', $Fr) } else { $d.ToString('dddd d MMMM', $Fr) }
    if ($d.Year -ne (Get-Date).Year) { $t += " $($d.Year)" }
    $t
}

function Format-Quand([datetime]$d) { "$(Format-Jour $d) à $(Format-Heure $d)" }

function Format-Relatif([datetime]$d) {
    $days = ($d.Date - (Get-Date).Date).Days
    switch ($days) {
        0 { "aujourd'hui" }
        1 { 'demain' }
        2 { 'après-demain' }
        default { if ($days -lt 0) { 'passé' } elseif ($days -lt 14) { "dans $days jours" } elseif ($days -lt 60) { "dans $([math]::Floor($days / 7)) semaines" } else { "dans $([math]::Round($days / 30.4)) mois" } }
    }
}

# Heure écrite comme on la dit : « 15 », « 15h », « 15 h 30 », « 15:30 », « 9h05 », « midi », « minuit »
function Read-Heure([string]$Text) {
    $t = $Text.Trim().ToLowerInvariant()
    if ($t -eq 'midi') { return [timespan]::new(12, 0, 0) }
    if ($t -eq 'minuit') { return [timespan]::new(0, 0, 0) }
    if ($t -match '^(\d{1,2})\s*(?:h|:|heures?)?\s*(\d{2})?$') {
        $h = [int]$Matches[1]; $m = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
        if ($h -lt 24 -and $m -lt 60) { return [timespan]::new($h, $m, 0) }
    }
    $null
}

Import-Agenda
