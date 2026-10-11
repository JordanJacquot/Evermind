# Evermind : comprendre un rendez-vous écrit (ou dit) en français de tous les jours, et l'écrire en retour.
# Règles écrites ici même : pas d'IA en ligne, rien n'est envoyé sur Internet.
# Chargé par Evermind.ps1 ; utilisable seul pour les tests (outils\tester-phrases.ps1).

if (-not $Fr) { $Fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR') }

# ---------------------------------------------------------------------------
# Vocabulaire
# ---------------------------------------------------------------------------
$MoisNoms = [ordered]@{ janvier = 1; 'février' = 2; fevrier = 2; mars = 3; avril = 4; mai = 5; juin = 6; juillet = 7
                        'août' = 8; aout = 8; septembre = 9; octobre = 10; novembre = 11; 'décembre' = 12; decembre = 12
                        # abréviations (« le 25 oct. », « 2 févr ») : après les noms entiers, qui passent en premier
                        janv = 1; 'févr' = 2; fevr = 2; 'fév' = 2; fev = 2; avr = 4; juil = 7; sept = 9; oct = 10; nov = 11; 'déc' = 12; dec = 12 }
$JoursNoms = [ordered]@{ lundi = 1; mardi = 2; mercredi = 3; jeudi = 4; vendredi = 5; samedi = 6; dimanche = 0 }

# Nombres en lettres (Whisper ou un pote peuvent écrire « trois » au lieu de « 3 »)
$Nombres = @{ une = 1; premier = 1; '1er' = 1 }
$unites = 'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf'
for ($i = 1; $i -lt 20; $i++) { $Nombres[$unites[$i]] = $i; $Nombres[$unites[$i].Replace('-', ' ')] = $i }
foreach ($dz in @(@('vingt', 20), @('trente', 30), @('quarante', 40), @('cinquante', 50))) {
    $Nombres[$dz[0]] = $dz[1]
    $Nombres["$($dz[0]) et un"] = $dz[1] + 1; $Nombres["$($dz[0])-et-un"] = $dz[1] + 1
    for ($u = 2; $u -le 9; $u++) { $Nombres["$($dz[0])-$($unites[$u])"] = $dz[1] + $u; $Nombres["$($dz[0]) $($unites[$u])"] = $dz[1] + $u }
}
$unites = $null

# Morceaux d'expressions régulières
$RxNombre = '(?:\d{1,2}|' + (($Nombres.Keys | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
$RxMois   = '(?:' + ($MoisNoms.Keys -join '|') + ')(?![\p{L}])'   # jamais au milieu d'un mot (« mai » dans « maintenant »)
$RxJour   = '(?:' + ($JoursNoms.Keys -join '|') + ')'
$RxMinMot = '(?:cinq|dix|quinze|vingt|vingt-cinq|trente|trente-cinq|quarante|quarante-cinq|cinquante|cinquante-cinq)'
$RxFrac   = '(?:et demie?|et quart|moins le quart|moins quart)'

function ConvertFrom-Nombre([string]$Text) {
    $t = ($Text.Trim().ToLowerInvariant() -replace '\s+', ' ')
    if ($t -match '^\d+$') { return [int]$t }
    if ($Nombres.ContainsKey($t)) { return [int]$Nombres[$t] }
    $null
}

# Date qui existe vraiment (pas de 31 février), sinon $null
function New-DateSure([int]$Y, [int]$M, [int]$D) {
    if ($M -lt 1 -or $M -gt 12 -or $Y -lt 1 -or $Y -gt 9998 -or $D -lt 1 -or $D -gt [datetime]::DaysInMonth($Y, $M)) { return $null }
    [datetime]::new($Y, $M, $D)
}

# Prend le premier morceau de phrase qui correspond et le retire du texte (ce qui reste fera le titre)
function Get-Morceau($State, [string]$Pattern) {
    $m = [regex]::Match($State.S, $Pattern, 'IgnoreCase')
    if ($m.Success) { $State.S = $State.S.Remove($m.Index, $m.Length).Insert($m.Index, ' ') }
    $m
}

# ---------------------------------------------------------------------------
# Semaines entières, du lundi au dimanche (et week-ends) : liste de @{ Debut; Fin }, ou $null
# ---------------------------------------------------------------------------
function Get-BlocsSemaine($st, [datetime]$today) {
    $lundiDe = { param([datetime]$d) $d.Date.AddDays(-((([int]$d.DayOfWeek) + 6) % 7)) }
    # Une semaine : du lundi au dimanche ; un week-end : samedi et dimanche
    $bloc = { param([datetime]$Debut, [bool]$WE) if ($WE) { @{ Debut = $Debut; Fin = $Debut.AddDays(1) } } else { @{ Debut = $Debut; Fin = $Debut.AddDays(6) } } }
    # La n-ième semaine d'un mois commence au n-ième lundi ; le n-ième week-end, au n-ième samedi.
    # « dernière semaine » : la dernière semaine entière du mois ; « dernier week-end » : le dernier samedi.
    $nieme = {
        param([int]$An, [int]$Mois, [int]$Rang, [bool]$WE)
        $premier = [datetime]::new($An, $Mois, 1); $der = $premier.AddMonths(1).AddDays(-1)
        $jour = if ($WE) { 6 } else { 1 }
        if ($Rang -gt 0) { return (& $bloc ($premier.AddDays((($jour - [int]$premier.DayOfWeek) + 7) % 7).AddDays(7 * ($Rang - 1))) $WE) }
        if ($WE) { return (& $bloc ($der.AddDays(-(((([int]$der.DayOfWeek) - 6) + 7) % 7))) $true) }
        $l = & $lundiDe $der; if ($l.AddDays(6) -gt $der) { $l = $l.AddDays(-7) }
        & $bloc $l $false
    }
    $rxRang = "(?<r>premi[èe]re?|1re|1er|1[eè]re|deuxi[èe]me|second|seconde|2e|troisi[èe]me|3e|quatri[èe]me|4e|derni[èe]re?)"
    $rxU = "(?<u>semaine|week-?end)"
    $rxDe = "(?:(?:de|d'|du mois de|du mois d'|en)\s*)?"
    $rang = { param($s) switch -Regex ($s.ToLower()) { '^(prem|1)' { 1 } '^(deux|sec|2)' { 2 } '^(trois|3)' { 3 } '^(quat|4)' { 4 } default { -1 } } }
    $rxN = "(?<n>\d{1,2}|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze)"
    $avant = "\b(?:pendant\s+|durant\s+|sur\s+|tout\s+|toute\s+)?(?:la|le)\s+"
    # « la première semaine des 3 prochains mois », « le premier week-end de chaque mois pendant 3 mois »
    if (($m = Get-Morceau $st "$avant$rxRang\s+$rxU\s+(?:des\s+$rxN\s+prochains\s+mois|de\s+chaque\s+mois\s+(?:pendant|durant|sur)\s+$rxN\s+mois)\b").Success) {
        $r = & $rang $m.Groups['r'].Value; $n = ConvertFrom-Nombre $m.Groups['n'].Value; $we = $m.Groups['u'].Value -match 'week'
        $blocs = @(); $mois = $today.AddDays(1 - $today.Day)
        while ($blocs.Count -lt $n -and $blocs.Count -lt 24) {
            $b = & $nieme $mois.Year $mois.Month $r $we
            if ($b.Debut -ge $today) { $blocs += $b }   # une semaine déjà commencée ne compte pas
            $mois = $mois.AddMonths(1)
        }
        return $blocs
    }
    # « la première semaine de novembre », « le dernier week-end d'octobre », « le dernier week-end octobre 2027 »,
    # « la deuxième semaine du mois prochain »
    if (($m = Get-Morceau $st "$avant$rxRang\s+$rxU\s+(?:$rxDe(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?|du\s+mois\s+(?<pro>prochain))").Success) {
        $r = & $rang $m.Groups['r'].Value; $we = $m.Groups['u'].Value -match 'week'
        if ($m.Groups['pro'].Success) { $x = $today.AddDays(1 - $today.Day).AddMonths(1); $mo = $x.Month; $y = $x.Year }
        else { $mo = $MoisNoms[$m.Groups['mo'].Value.ToLower()]; $y = if ($m.Groups['y'].Success) { [int]$m.Groups['y'].Value } else { $today.Year } }
        $b = & $nieme $y $mo $r $we
        if (-not $m.Groups['y'].Success -and -not $m.Groups['pro'].Success -and $b.Fin -lt $today) { $b = & $nieme ($y + 1) $mo $r $we }
        return @($b)
    }
    # « les deux prochains week-ends », « les 3 prochaines semaines »
    if (($m = Get-Morceau $st "\b(?:pendant\s+|durant\s+)?les\s+$rxN\s+prochain(?:e)?s\s+(?<u>semaines|week-?ends)\b").Success) {
        $n = ConvertFrom-Nombre $m.Groups['n'].Value; $we = $m.Groups['u'].Value -match 'week'
        if ($we) {
            $sam = $today.AddDays((6 - [int]$today.DayOfWeek + 7) % 7); if ($today.DayOfWeek -eq 'Sunday') { $sam = $today.AddDays(6) }
            if ($today.DayOfWeek -eq 'Saturday') { $sam = $sam.AddDays(7) }   # « les prochains » dit un samedi : à partir du suivant
            return @(for ($k = 0; $k -lt $n; $k++) { & $bloc $sam.AddDays(7 * $k) $true })
        }
        # Les semaines qui viennent, d'un seul bloc : de lundi prochain à la fin de la dernière
        $l = (& $lundiDe $today).AddDays(7)
        return @(@{ Debut = $l; Fin = $l.AddDays(7 * $n - 1) })
    }
    # « la semaine du 9 novembre », « le week-end du 24 octobre »
    if (($m = Get-Morceau $st "\b(?:pendant\s+|durant\s+|toute\s+|tout\s+)?(?:la|le)\s+$rxU\s+du\s+(?<d>$RxNombre)(?:er)?\s+(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?").Success) {
        $mo = $MoisNoms[$m.Groups['mo'].Value.ToLower()]; $d = ConvertFrom-Nombre $m.Groups['d'].Value; $we = $m.Groups['u'].Value -match 'week'
        $y = if ($m.Groups['y'].Success) { [int]$m.Groups['y'].Value } else { $today.Year }
        try { $jour = [datetime]::new($y, $mo, $d); if (-not $m.Groups['y'].Success -and $jour.AddDays(6) -lt $today) { $jour = $jour.AddYears(1) } } catch { return $null }
        $l = & $lundiDe $jour
        if ($we) { return @(& $bloc $l.AddDays(5) $true) }
        return @(& $bloc $l $false)
    }
    # « toute la semaine prochaine », « pendant la semaine prochaine », « toute cette semaine »
    if (($m = Get-Morceau $st "\b(?:toute|pendant|durant|sur)\s+(?:la\s+)?(?<q>semaine\s+prochaine|semaine\s+d'apr[èe]s|cette\s+semaine)\b").Success) {
        $l = & $lundiDe $today
        if ($m.Groups['q'].Value -notmatch 'cette') { $l = $l.AddDays(7) }
        $b = & $bloc $l $false; if ($b.Debut -lt $today) { $b.Debut = $today }
        return @($b)
    }
    # « ce week-end », « le week-end prochain » (samedi et dimanche)
    if (($m = Get-Morceau $st "\b(?:ce|le)\s+week-?end(?:\s+(?<pro>prochain))?\b(?!\s+(?:du|de|d'))").Success) {
        # Dit un dimanche, « ce week-end » c'est aujourd'hui ; « le week-end prochain », celui d'après
        if ($today.DayOfWeek -eq 'Sunday' -and -not $m.Groups['pro'].Success) { return @(@{ Debut = $today; Fin = $today }) }
        $sam = $today.AddDays((6 - [int]$today.DayOfWeek + 7) % 7)
        if ($today.DayOfWeek -eq 'Sunday') { $sam = $today.AddDays(6) }
        elseif ($today.DayOfWeek -eq 'Saturday' -and $m.Groups['pro'].Success) { $sam = $sam.AddDays(7) }   # dit un samedi : celui d'après
        return @(& $bloc $sam $true)
    }
    $null
}
# ---------------------------------------------------------------------------
# Rendez-vous qui reviennent : prochaine fois à partir d'un moment donné
# ---------------------------------------------------------------------------
#   Repetition : { Type = 'jour' } | { Type = 'semaine'; Jour = 0..6 (0 = dimanche) } | { Type = 'mois'; Jour = 1..31 }
#                | { Type = 'an'; Jour = 1..31; Mois = 1..12 }
#   Un jour qui n'existe pas dans un mois (le 31) tombe le dernier jour de ce mois.
#   Jusqua (facultatif) : dernier jour, « yyyy-MM-dd » (« tous les lundis d'octobre », « jusqu'au 15 mars »).
#   Après ce jour, il n'y a plus de prochaine fois : la date rendue est alors [datetime]::MinValue (déjà passée).
#   Sauf (facultatif) : jours enlevés de la série, « yyyy-MM-dd » (« supprime les courses du 19 octobre »).
function Get-NextOccurrence($Repetition, [datetime]$Premier, [datetime]$From) {
    if (-not $Repetition) { return $Premier }
    $c = Get-ProchaineFois $Repetition $Premier $From
    $sauf = @($Repetition.Sauf | Where-Object { $_ })
    for ($i = 0; $sauf.Count -and $i -lt 400 -and $sauf -contains $c.ToString('yyyy-MM-dd'); $i++) { $c = Get-ProchaineFois $Repetition $Premier $c.AddMinutes(1) }
    if ($Repetition.Jusqua -and $c.Date -gt [datetime]::ParseExact([string]$Repetition.Jusqua, 'yyyy-MM-dd', $null)) { return [datetime]::MinValue }
    $c
}

function Get-ProchaineFois($Repetition, [datetime]$Premier, [datetime]$From) {
    $base = if ($From -gt $Premier) { $From } else { $Premier }
    $heure = $Premier.TimeOfDay
    $n = if ($Repetition.Intervalle -and [int]$Repetition.Intervalle -gt 1) { [int]$Repetition.Intervalle } else { 1 }
    switch ([string]$Repetition.Type) {
        'jour' {
            # Tous les n jours, en comptant depuis le premier
            $c = $base.Date + $heure
            if ($c -lt $base) { $c = $c.AddDays(1) }
            $ecart = ($c.Date - $Premier.Date).Days % $n
            if ($ecart) { $c = $c.AddDays($n - $ecart) }
            return $c
        }
        'semaine' {
            # Un ou plusieurs jours de la semaine, toutes les n semaines (semaines comptées depuis celle du premier)
            $jours = @($Repetition.Jours | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
            if (-not $jours.Count) { $jours = @([int]$Repetition.Jour) }
            $lundiPremier = $Premier.Date.AddDays(-((([int]$Premier.DayOfWeek) + 6) % 7))
            for ($k = 0; $k -le 7 * $n + 7; $k++) {
                $c = $base.Date.AddDays($k) + $heure
                if ($c -lt $base -or $jours -notcontains [int]$c.DayOfWeek) { continue }
                $semaines = [math]::Floor(($c.Date - $lundiPremier).Days / 7)
                if ($semaines % $n -eq 0) { return $c }
            }
        }
        'mois' {
            # Un jour du mois (le 5), ou un rang (« le premier lundi », « le dernier vendredi »), tous les n mois
            $debutPremier = $Premier.Date.AddDays(1 - $Premier.Day)
            for ($k = 0; $k -le 24 * $n; $k++) {
                $first = $base.Date.AddDays(1 - $base.Day).AddMonths($k)
                $ecartMois = ($first.Year - $debutPremier.Year) * 12 + $first.Month - $debutPremier.Month
                if ($ecartMois % $n -ne 0) { continue }
                if ($Repetition.Rang) {
                    $wd = [int]$Repetition.Jour; $r = [int]$Repetition.Rang
                    if ($r -gt 0) {
                        $d = $first.AddDays((($wd - [int]$first.DayOfWeek) + 7) % 7).AddDays(7 * ($r - 1))
                        if ($d.Month -ne $first.Month) { continue }
                    } else {
                        $der = $first.AddMonths(1).AddDays(-1)
                        $d = $der.AddDays(-(((([int]$der.DayOfWeek) - $wd) + 7) % 7))
                    }
                    $c = $d + $heure
                } else {
                    $d = [math]::Min([int]$Repetition.Jour, [datetime]::DaysInMonth($first.Year, $first.Month))
                    $c = $first.AddDays($d - 1) + $heure
                }
                if ($c -ge $base) { return $c }
            }
        }
        'an' {
            for ($k = 0; $k -le 8 * $n; $k++) {
                $y = $base.Year + $k
                if (($y - $Premier.Year) % $n -ne 0) { continue }
                $d = [math]::Min([int]$Repetition.Jour, [datetime]::DaysInMonth($y, [int]$Repetition.Mois))
                $c = [datetime]::new($y, [int]$Repetition.Mois, $d) + $heure
                if ($c -ge $base) { return $c }
            }
        }
    }
    $Premier
}
# ---------------------------------------------------------------------------
# Lire une phrase
# ---------------------------------------------------------------------------
# Retourne : Titre, Quand (le premier rendez-vous), Repetition, et Manque :
#   ''        tout est compris
#   'heure'   le jour est compris, pas l'heure
#   'quand'   ni le jour ni l'heure
#   'passe'   ce moment est déjà passé
#   'invalide' cette date n'existe pas (31 février...)
function Read-Phrase([string]$Text, $Now) {
    if (-not $Now) { $Now = Get-Date }
    $Now = [datetime]$Now
    $today = $Now.Date
    $st = @{ S = ' ' + ($Text -replace "[’‘`´]", "'") + ' ' }
    # Ce qui est demandé à Eve en plus de l'événement ne fait pas partie de l'événement : « ... et que tu ouvres son
    # dossier au début », « ... . Et tu ouvres directement son dossier », « ... et ouvre son dossier » (sauf un autre
    # ordre de création : « ... et que tu mettes un anniversaire Jordan »)
    $st.S = $st.S -replace "(?i)(?:\s*[.;!]\s*(?:et\s+|puis\s+|ensuite\s+)?|\s*,?\s*\b(?:et|puis|ensuite)\s+)(?:(?:je veux|j'aimerais|je voudrais|il faut)\s+)?(?:que\s+|qu')?tu\s+(?>(?:m'|me\s+|lui\s+|les?\s+|l'|nous\s+)?)(?!(?:$RxOrdre|me|m|lui|les?|nous)\b)\p{L}+\b.*$", ' '
    $st.S = $st.S -replace "(?i)(?:\s*[.,;!]\s*|\s+)(?:et|puis|ensuite)\s+(?:m'|me\s+)?ouvr\w*(?:[- ]moi)?\s+(?:son|ses|sa|le|les|mon|mes|leur|leurs)\s.*$", ' '
    # « pour dans une minute », « pour demain » : le « pour » du moment
    $st.S = $st.S -replace "(?i)\bpour\s+(?=dans\s+\S+\s+(?:minutes?|heures?|jours?|semaines?|mois|ans?)\b)", ''
    # « à 17 h pile », « à 9 h précises » : l'heure suffit
    $st.S = $st.S -replace "(?i)(\d\s*(?:h|heures?)(?:\s*\d{2})?|\bmidi|\bminuit)\s+(?:pile|pr[ée]cises?|tapantes?)\b", '$1'
    # L'année, où qu'elle soit dite, va juste après le mois : « octobre, 2026 » (ponctuation de la dictée),
    # « le 27 octobre en 2027 », « le 3 mars de l'année prochaine »
    $st.S = $st.S -replace "(?i)\b($RxMois)\s*[,.;]\s*((?:19|20)\d{2})\b", '$1 $2'
    $anneeDite = $null
    if ($st.S -match "(?i)\b(?:de\s+)?l'ann[ée]e\s+prochaine\b") { $anneeDite = ([datetime]$Now).Year + 1; $st.S = $st.S -replace "(?i)\s*,?\s*\b(?:de\s+)?l'ann[ée]e\s+prochaine\b", ' ' }
    elseif ($st.S -match "(?i)(?<!$RxMois\s*)(?<!\d\s*)(?:,\s*|\b(?:en|pour)\s+)((?:19|20)\d{2})\b") {
        $y = [int]$Matches[1]; $tout = $Matches[0]
        if ($st.S -match "(?i)\b$RxMois\b(?!\s+\d{4})" -and $y -ge ([datetime]$Now).Year -and $y -le ([datetime]$Now).Year + 10) { $anneeDite = $y; $st.S = $st.S.Replace($tout, ' ') }
    }
    if ($anneeDite) { $st.S = [regex]::Replace($st.S, "(?i)\b($RxMois)\b(?!\s+\d{4})", { param($x) "$($x.Value) $anneeDite" }) }
    $date = $null; $heure = $null; $exact = $null; $rep = $null
    $periode = $null; $qualif = $null; $heureChiffres = $false; $invalide = $false
    $semaineProchaine = $false; $journee = $false

    # 0. Détails dits dans la phrase : lien, importance, rappels voulus, âge, durée, lieu donné tel quel
    #    (retirés en premier : « 2 jours avant » ou « jusqu'à 18 h » ne doivent pas devenir la date ou l'heure)
    $det = [ordered]@{ Lieu = ''; Avec = @(); Lien = ''; Important = $false; Rappels = $null; Naissance = $null; APreparer = @() }
    $finHeure = $null; $dureeMin = $null; $ageDit = $null
    if (($m = Get-Morceau $st '(?<![\w@])(?:https?://|www\.|discord\.gg/)[^\s]+').Success) { $det.Lien = $m.Value.TrimEnd('.,;') }
    if ((Get-Morceau $st "\b(?:c'est\s+|tr[èe]s\s+)?(?:important|urgent|prioritaire|[àa] ne (?:pas|surtout pas) (?:oublier|rater|louper))\b").Success) { $det.Important = $true }
    $rappels = New-Object System.Collections.ArrayList
    while (($m = Get-Morceau $st "(?:\b(?:rappelle|pr[ée]viens|avertis)[- ](?:moi|nous)\s+|\b(?:et\s+)?(?:un\s+)?rappel\s+)?\b(?<n>$RxNombre)\s+(?<u>minutes?|min|heures?|h|jours?|semaines?)\s+avant\b").Success) {
        $n = ConvertFrom-Nombre $m.Groups['n'].Value
        $mult = switch -Regex ($m.Groups['u'].Value.ToLower()) { '^m' { 1 } '^h' { 60 } '^j' { 1440 } default { 10080 } }
        [void]$rappels.Add("m$($n * $mult)")
    }
    if ((Get-Morceau $st "\b(?:(?:rappelle|pr[ée]viens)[- ]moi\s+)?la veille\b").Success) { [void]$rappels.Add('veille') }
    if ((Get-Morceau $st "\b(?:(?:rappelle|pr[ée]viens)[- ]moi\s+)?le matin m[êe]me\b").Success) { [void]$rappels.Add('matin') }
    if ((Get-Morceau $st "\b(?:(?:rappelle|pr[ée]viens)[- ]moi\s+)?(?:pile )?[àa] l'heure\b").Success) { [void]$rappels.Add('m0') }
    if ($rappels.Count) { $det.Rappels = @($rappels | Select-Object -Unique) }
    if (($m = Get-Morceau $st "\b(?:il|elle)\s+(?<v>a|aura|va avoir|f[êe]te ses)\s+(?<n>\d{1,3})\s+ans\b").Success) { $ageDit = @{ N = [int]$m.Groups['n'].Value; Futur = $m.Groups['v'].Value -ne 'a' } }
    elseif (($m = Get-Morceau $st "\bn[ée]e?\s+en\s+(?<y>(?:19|20)\d{2})\b").Success) { $det.Naissance = [int]$m.Groups['y'].Value }
    if (($m = Get-Morceau $st "\b(?:lieu|adresse)\s*:?\s+(?<l>[^,;]+)").Success) { $det.Lieu = $m.Groups['l'].Value.Trim(' .') }
    # Durée : « pendant 2 h », « pendant 1 h 30 », « pendant 45 minutes », « pendant une demi-heure »
    if (($m = Get-Morceau $st "\bpendant\s+(?:(?<n>$RxNombre)\s*(?<u>heures?|h(?![a-zà-ÿ])|minutes?|min)\b(?:\s*(?<m>\d{2})\b)?|(?<dh>une demi[- ]heure))").Success) {
        $dureeMin = if ($m.Groups['dh'].Success) { 30 }
                    elseif ($m.Groups['u'].Value -match '^h') { 60 * (ConvertFrom-Nombre $m.Groups['n'].Value) + $(if ($m.Groups['m'].Success) { [int]$m.Groups['m'].Value } else { 0 }) }
                    else { ConvertFrom-Nombre $m.Groups['n'].Value }
    }
    # Plage : « de 14 h à 16 h 30 » (le début devient l'heure), ou seulement la fin : « jusqu'à 18 h »
    $rxH = "(?<hX>$RxNombre)\s*(?:h(?![a-zà-ÿ])|heures?\b|:)(?:\s*(?<mX>\d{2})\b)?"
    if (($m = Get-Morceau $st ("\bde\s+$($rxH.Replace('hX', 'h1').Replace('mX', 'm1'))\s+(?:à|a|jusqu'à)\s+$($rxH.Replace('hX', 'h2').Replace('mX', 'm2'))")).Success) {
        $heure = [timespan]::new((ConvertFrom-Nombre $m.Groups['h1'].Value) % 24, $(if ($m.Groups['m1'].Success) { [int]$m.Groups['m1'].Value } else { 0 }), 0)
        $finHeure = [timespan]::new((ConvertFrom-Nombre $m.Groups['h2'].Value) % 24, $(if ($m.Groups['m2'].Success) { [int]$m.Groups['m2'].Value } else { 0 }), 0)
        $heureChiffres = $true
    } elseif (($m = Get-Morceau $st ("\bjusqu'?\s*(?:à|a|au)\s+(?:$($rxH.Replace('hX', 'h2').Replace('mX', 'm2'))|(?<mm>midi|minuit))")).Success) {
        $finHeure = if ($m.Groups['mm'].Success) { [timespan]::new($(if ($m.Groups['mm'].Value -match 'midi') { 12 } else { 0 }), 0, 0) }
                    else { [timespan]::new((ConvertFrom-Nombre $m.Groups['h2'].Value) % 24, $(if ($m.Groups['m2'].Success) { [int]$m.Groups['m2'].Value } else { 0 }), 0) }
    }

    # 1. Rendez-vous qui reviennent, comme dans les grands agendas :
    #    tous les jours / toutes les semaines / tous les mois / tous les ans, avec un intervalle (« toutes les deux
    #    semaines », « un lundi sur deux », « tous les 3 mois »), plusieurs jours de la semaine (« en semaine »,
    #    « le week-end », « le lundi et le jeudi ») ou un rang dans le mois (« le premier lundi du mois »)
    $rxN = "(?:\d{1,2}|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|quinze|vingt)"
    $rxWd = "(?<wdX>$RxJour)s?"
    $periodeRep = $null
    $nJours = { param($s) @([regex]::Matches($s.ToLower(), "\b$RxJour") | ForEach-Object { $JoursNoms[$_.Value] } | Select-Object -Unique) }
    if (($m = Get-Morceau $st "\b(?:le|chaque|tous les)\s+(?<r>premiers?|1er|1re|deuxi[èe]mes?|second|2e|troisi[èe]mes?|3e|quatri[èe]mes?|4e|derniers?)\s+(?<wd>$RxJour)s?\s+(?:du|de chaque|de tous les|de)\s+mois\b").Success) {
        $r = switch -Regex ($m.Groups['r'].Value.ToLower()) { '^(prem|1)' { 1 } '^(deux|sec|2)' { 2 } '^(trois|3)' { 3 } '^(quat|4)' { 4 } default { -1 } }
        $rep = [ordered]@{ Type = 'mois'; Jour = $JoursNoms[$m.Groups['wd'].Value.ToLower()]; Rang = $r }
    } elseif (($m = Get-Morceau $st "\b(?:en semaine|du lundi au vendredi|(?:tous les|chaque)\s+jours?\s+de\s+(?:la\s+)?semaine|les jours de semaine)\b").Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = 1; Jours = @(1, 2, 3, 4, 5) }
    } elseif (($m = Get-Morceau $st "\b(?:tous les week-?ends?|chaque week-?end|le week-?end)\b(?!\s+(?:prochain|du|de|d'|dernier|(?:$RxMois)))").Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = 6; Jours = @(6, 0) }
    } elseif (($m = Get-Morceau $st "\b(?:tous les|chaque|le|les)\s+$RxJour(?:s)?(?:\s*(?:,|et)\s*(?:le\s+|les\s+)?$RxJour(?:s)?)+\b").Success) {
        $js = & $nJours $m.Value
        if ($js.Count -ge 2) { $rep = [ordered]@{ Type = 'semaine'; Jour = $js[0]; Jours = $js } }
        else { $st.S = $st.S + ' ' + $m.Value }   # un seul jour finalement : on le rend à la phrase
    } elseif (($m = Get-Morceau $st "\bdu\s+(?<a>$RxJour)\s+au\s+(?<b>$RxJour)\b").Success) {
        $a = $JoursNoms[$m.Groups['a'].Value.ToLower()]; $b = $JoursNoms[$m.Groups['b'].Value.ToLower()]
        $js = @(); $k = $a; for ($n = 0; $n -lt 7; $n++) { $js += $k; if ($k -eq $b) { break }; $k = ($k + 1) % 7 }
        $rep = [ordered]@{ Type = 'semaine'; Jour = $js[0]; Jours = $js }
    } elseif (($m = Get-Morceau $st "\b(?:un|une)\s+(?<wd>$RxJour)\s+sur\s+(?<n>$rxN)\b").Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = $JoursNoms[$m.Groups['wd'].Value.ToLower()]; Intervalle = (ConvertFrom-Nombre $m.Groups['n'].Value) }
    } elseif (($m = Get-Morceau $st "\btou(?:te)?s les\s+(?<n>$rxN)\s+semaines\b").Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = $null; Intervalle = (ConvertFrom-Nombre $m.Groups['n'].Value) }
    } elseif (($m = Get-Morceau $st "\btou(?:te)?s les\s+(?<n>$rxN)\s+jours\b").Success) {
        $n = ConvertFrom-Nombre $m.Groups['n'].Value
        # « tous les 15 jours » se dit pour « toutes les deux semaines »
        $rep = if ($n -in 14, 15) { [ordered]@{ Type = 'semaine'; Jour = $null; Intervalle = 2 } } else { [ordered]@{ Type = 'jour'; Intervalle = $n } }
    } elseif (($m = Get-Morceau $st "\btou(?:te)?s les\s+(?<n>$rxN)\s+mois(?:\s+le\s+(?<d>$RxNombre)(?:er)?\b)?").Success) {
        $rep = [ordered]@{ Type = 'mois'; Jour = $(if ($m.Groups['d'].Success) { ConvertFrom-Nombre ($m.Groups['d'].Value -replace 'er$', '') } else { $null }); Intervalle = (ConvertFrom-Nombre $m.Groups['n'].Value) }
    } elseif (($m = Get-Morceau $st "\btou(?:te)?s les\s+(?<n>$rxN)\s+(?:ans|ann[ée]es)\b").Success) {
        $rep = [ordered]@{ Type = 'an'; Jour = $null; Mois = $null; Intervalle = (ConvertFrom-Nombre $m.Groups['n'].Value) }
    } elseif (($m = Get-Morceau $st "\b(?:tous les|chaque)\s+(?<wd>$RxJour)s?\b").Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = $JoursNoms[$m.Groups['wd'].Value.ToLower()] }
    } elseif (($m = Get-Morceau $st "\b(?:tous les|chaque)\s+(?<p>matins?|soirs?|apr[èe]s[- ]midis?)\b").Success) {
        $rep = [ordered]@{ Type = 'jour' }; $periodeRep = $m.Groups['p'].Value.ToLower() -replace 's$', ''
    } elseif ((Get-Morceau $st '\b(?:tous les jours|chaque jour)\b').Success) {
        $rep = [ordered]@{ Type = 'jour' }
    } elseif (($m = Get-Morceau $st "\ble\s+(?<d>$RxNombre)(?:er)?\s+(?:de\s+)?(?:chaque|tous les)\s+mois\b").Success -or
              ($m = Get-Morceau $st "(?<!semaine\s+de\s+)\b(?:tous les mois|chaque mois)(?:\s+le\s+(?<d>$RxNombre)(?:er)?\b)?").Success) {
        $rep = [ordered]@{ Type = 'mois'; Jour = $(if ($m.Groups['d'].Success) { ConvertFrom-Nombre $m.Groups['d'].Value } else { $null }) }
    } elseif ((Get-Morceau $st '\b(?:toutes les semaines|chaque semaine)\b').Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = $null }
    } elseif ((Get-Morceau $st '\b(?:tous les ans|toutes les ann[ée]es|chaque ann[ée]e)\b').Success) {
        $rep = [ordered]@{ Type = 'an'; Jour = $null; Mois = $null }
    }
    # 1 bis. Jusqu'à quand ils reviennent : « tous les lundis d'octobre (2026) », « en octobre »,
    #        « jusqu'au 31 octobre », « jusqu'à fin novembre », « jusqu'à la fin du mois », « jusqu'en décembre »
    $limDebut = $null; $limFin = $null
    [void](Get-Morceau $st "\b(?:à|a)\s+partir\s+(?=(?:du|de|d')\b)")   # « à partir du 2 novembre » : la date suit
    if ($rep) {
        $anDe = { param($mo, $y) if ($y) { [int]$y } elseif ($mo -lt $today.Month) { $today.Year + 1 } else { $today.Year } }
        $finMois = { param($mo, $y) [datetime]::new($y, $mo, [datetime]::DaysInMonth($y, $mo)) }
        # Plusieurs mois : « d'octobre et (de) novembre 2026 », « d'octobre à décembre », « en janvier, février et mars »
        $rxUnMois = "(?:fin\s+|d[ée]but\s+)?(?:d'|de\s+|en\s+)?$RxMois(?:\s+\d{4})?"
        if (($m = Get-Morceau $st "\b(?:(?:du|pour le|pendant le|tout le)\s+mois\s+)?(?:d'|de\s+|en\s+|pour\s+|pendant\s+)?(?<!\d\s)(?<!\d(?:er|re|e|ème)\s)$RxMois(?:\s+\d{4})?(?:\s*(?:,|et|à|a|au|jusqu'à|jusqu'au|jusqu'en)\s*$rxUnMois)+\b").Success) {
            # Les mois dans l'ordre, avec leur année (dite, sinon celle du mois suivant, sinon la prochaine fois)
            $morceaux = [regex]::Matches($m.Value.ToLower(), "(?<lien>,|\bet\b|\bà\b|\ba\b|\bau\b|jusqu'à|jusqu'au|jusqu'en)?\s*(?:fin\s+|d[ée]but\s+)?(?:d'|de\s+|en\s+|du\s+mois\s+(?:d'|de\s+))?(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?")
            $liste = @(foreach ($x in $morceaux) { @{ Mo = $MoisNoms[$x.Groups['mo'].Value]; Y = $(if ($x.Groups['y'].Success) { [int]$x.Groups['y'].Value } else { 0 }); Plage = $x.Groups['lien'].Value -match '^(à|a|au|jusqu)' } })
            for ($k = $liste.Count - 1; $k -ge 0; $k--) {
                if ($liste[$k].Y) { continue }
                if ($k -lt $liste.Count - 1) { $s = $liste[$k + 1]; $liste[$k].Y = if ($liste[$k].Mo -gt $s.Mo) { $s.Y - 1 } else { $s.Y } }
                else { $liste[$k].Y = if ($liste[$k].Mo -lt $today.Month) { $today.Year + 1 } else { $today.Year } }
            }
            # Les mois gardés : chacun, plus ceux entre deux mois reliés par « à » / « jusqu'à »
            $garde = New-Object System.Collections.ArrayList
            for ($k = 0; $k -lt $liste.Count; $k++) {
                $d = [datetime]::new($liste[$k].Y, $liste[$k].Mo, 1)
                if ($liste[$k].Plage -and $garde.Count) { $p = ([datetime]$garde[-1]).AddMonths(1); while ($p -lt $d -and $garde.Count -lt 36) { [void]$garde.Add($p); $p = $p.AddMonths(1) } }
                if ($garde -notcontains $d) { [void]$garde.Add($d) }
            }
            $garde = @($garde | Sort-Object)
            $limDebut = $garde[0]; $limFin = $garde[-1].AddMonths(1).AddDays(-1)
            # Un mois sauté au milieu (« octobre et décembre ») : ses jours sont enlevés de la série
            $sauf = @(for ($p = $limDebut; $p -le $limFin; $p = $p.AddDays(1)) { if ($garde -notcontains $p.AddDays(1 - $p.Day)) { $p.ToString('yyyy-MM-dd') } })
            if ($sauf.Count) { $rep.Sauf = $sauf }
        } elseif (($m = Get-Morceau $st "\bjusqu'?\s*(?:à|a|au)\s+(?:le\s+)?(?<d>$RxNombre)\s+(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?\b").Success) {
            $mo = $MoisNoms[$m.Groups['mo'].Value.ToLower()]; $y = & $anDe $mo $m.Groups['y'].Value
            $d = ConvertFrom-Nombre $m.Groups['d'].Value
            if ($d -ge 1 -and $d -le [datetime]::DaysInMonth($y, $mo)) { $limFin = [datetime]::new($y, $mo, $d) }
        } elseif (($m = Get-Morceau $st "\bjusqu'?\s*(?:à|a|au)\s+(?:la\s+)?fin\s+(?:du\s+mois\s+)?(?:(?:d'|de\s+)?(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?\b)?").Success) {
            if ($m.Groups['mo'].Success) { $mo = $MoisNoms[$m.Groups['mo'].Value.ToLower()]; $limFin = & $finMois $mo (& $anDe $mo $m.Groups['y'].Value) }
            else { $limFin = & $finMois $today.Month $today.Year }
        } elseif (($m = Get-Morceau $st "\bjusqu'en\s+(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?\b").Success) {
            $mo = $MoisNoms[$m.Groups['mo'].Value.ToLower()]; $limFin = & $finMois $mo (& $anDe $mo $m.Groups['y'].Value)
        } elseif (($m = Get-Morceau $st "\b(?:(?:du|pour le|pendant le|tout le)\s+mois\s+(?:d'|de\s+)|d'|de\s+|en\s+|pour\s+|pendant\s+)?(?<!\d\s)(?<!\d(?:er|re|e|ème)\s)(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?\b").Success) {
            $mo = $MoisNoms[$m.Groups['mo'].Value.ToLower()]; $y = & $anDe $mo $m.Groups['y'].Value
            $limDebut = [datetime]::new($y, $mo, 1); $limFin = & $finMois $mo $y
        }
        if ($limFin) { $rep.Jusqua = $limFin.ToString('yyyy-MM-dd') }
    }

    # 2. « dans 2 heures », « dans 30 minutes », « dans une demi-heure » : le moment exact
    if (($m = Get-Morceau $st "\bdans\s+(?:(?<n>$RxNombre)\s+(?<u>heures?|h|minutes?|min)\b|(?<dh>une demi[- ]heure)|(?<qh>un quart d'heure))").Success) {
        $exact = if ($m.Groups['dh'].Success) { $Now.AddMinutes(30) }
                 elseif ($m.Groups['qh'].Success) { $Now.AddMinutes(15) }
                 elseif ($m.Groups['u'].Value -match '^h') { $Now.AddHours((ConvertFrom-Nombre $m.Groups['n'].Value)) }
                 else { $Now.AddMinutes((ConvertFrom-Nombre $m.Groups['n'].Value)) }
        $exact = $exact.AddSeconds(-$exact.Second).AddMilliseconds(-$exact.Millisecond)
    }

    # 2 bis. Plusieurs jours : « du 27 au 29 octobre », « du lundi 27 au mercredi 29 », « le 27, le 28 et le 29 octobre »,
    #        « les 3 et 10 novembre », « pendant 3 jours ». Des jours qui se suivent : un seul événement (début et dernier
    #        jour) ; des jours séparés : un événement par jour (Jours).
    if (-not $rep) {
        $anDe = { param($mo, $d, $y) if ($y) { [int]$y } elseif ($mo -lt $today.Month -or ($mo -eq $today.Month -and $d -lt $today.Day)) { $today.Year + 1 } else { $today.Year } }
        $num = { param($s) ConvertFrom-Nombre ($s -replace '(?i)(er|re)$', '') }
        $jours = $null
        if (($m = Get-Morceau $st "\b(?:du|de)\s+(?:$RxJour\s+)?(?<d1>$RxNombre)(?:er)?(?:\s+(?<m1>$RxMois))?(?:\s+(?<y1>\d{4}))?\s+(?:au|à|a|jusqu'au)\s+(?:$RxJour\s+)?(?<d2>$RxNombre)(?:er)?\s+(?<m2>$RxMois)(?:\s+(?<y2>\d{4}))?\b").Success) {
            $m2 = $MoisNoms[$m.Groups['m2'].Value.ToLower()]; $d2 = & $num $m.Groups['d2'].Value
            $m1 = if ($m.Groups['m1'].Success) { $MoisNoms[$m.Groups['m1'].Value.ToLower()] } else { $m2 }; $d1 = & $num $m.Groups['d1'].Value
            $y1 = & $anDe $m1 $d1 $(if ($m.Groups['y1'].Success) { $m.Groups['y1'].Value } else { $m.Groups['y2'].Value })
            try {
                $a = [datetime]::new($y1, $m1, $d1); $b = [datetime]::new($y1, $m2, $d2)
                if ($m.Groups['y2'].Success) { $b = [datetime]::new([int]$m.Groups['y2'].Value, $m2, $d2) } elseif ($b -lt $a) { $b = $b.AddYears(1) }
                if (($b - $a).TotalDays -le 366) { $jours = @(for ($x = $a; $x -le $b; $x = $x.AddDays(1)) { $x }) }
            } catch { $invalide = $true }
        } elseif (($m = Get-Morceau $st "\b(?:les?\s+)?(?:$RxJour\s+)?$RxNombre(?:er)?(?:\s+$RxMois)?(?:\s*(?:,|et)\s*(?:(?:le|les)\s+)?(?:$RxJour\s+)?$RxNombre(?:er)?(?:\s+$RxMois)?)+\s+(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?\b").Success -or
                  ($m = Get-Morceau $st "\b(?:les?\s+)?(?:$RxJour\s+)?$RxNombre(?:er)?\s+(?<mo>$RxMois)(?:\s*(?:,|et)\s*(?:(?:le|les)\s+)?(?:$RxJour\s+)?$RxNombre(?:er)?\s+$RxMois)+(?:\s+(?<y>\d{4}))?\b").Success) {
            # Chaque jour avec son mois ; un jour sans mois prend celui du jour suivant (« le 27, 28 et 29 octobre »)
            $items = @([regex]::Matches($m.Value, "(?i)(?:$RxJour\s+)?\b(?<d>$RxNombre)(?:er)?\b(?:\s+(?<mo>$RxMois)\b)?") | ForEach-Object {
                @{ D = (& $num $_.Groups['d'].Value); Mo = $(if ($_.Groups['mo'].Success) { $MoisNoms[$_.Groups['mo'].Value.ToLower()] } else { 0 }) } } | Where-Object { $_.D -ge 1 -and $_.D -le 31 })
            for ($k = $items.Count - 1; $k -ge 0; $k--) { if (-not $items[$k].Mo) { $items[$k].Mo = if ($k -lt $items.Count - 1) { $items[$k + 1].Mo } else { $MoisNoms[$m.Groups['mo'].Value.ToLower()] } } }
            try { $jours = @($items | ForEach-Object { [datetime]::new((& $anDe $_.Mo $_.D $m.Groups['y'].Value), $_.Mo, $_.D) } | Sort-Object -Unique) } catch { $invalide = $true }
        }
        if ($jours -and $jours.Count) {
            $date = $jours[0]
            $suivis = $true; for ($k = 1; $k -lt $jours.Count; $k++) { if (($jours[$k] - $jours[$k - 1]).TotalDays -ne 1) { $suivis = $false } }
            if ($jours.Count -gt 1) { if ($suivis) { $det.FinJour = $jours[-1] } else { $det.Jours = $jours } }
        }
        if (($m = Get-Morceau $st "\b(?:sur|pendant|durant)\s+(?<n>$RxNombre)\s+jours\b").Success) { $n = ConvertFrom-Nombre $m.Groups['n'].Value; if ($n -gt 1 -and $n -le 366) { $det.NbJours = $n } }
        elseif (($m = Get-Morceau $st "\b(?:sur|pendant|durant)\s+(?<n>une|un|deux|trois|quatre|\d)\s+semaines?\b").Success) { $det.NbJours = 7 * (ConvertFrom-Nombre ($m.Groups['n'].Value -replace '^une?$', 'un')) }
        # Des semaines entières (du lundi au dimanche) : « la première semaine des 3 prochains mois », « la semaine du 9 novembre »,
        # « la dernière semaine de décembre », « toute la semaine prochaine », « ce week-end »
        if (-not $jours) {
            $blocs = @(Get-BlocsSemaine $st $today | Where-Object { $_ })
            if ($blocs.Count) {
                $date = $blocs[0].Debut
                if ($blocs.Count -gt 1) { $det.Blocs = $blocs }
                if ($blocs[0].Fin -gt $blocs[0].Debut) { $det.FinJour = $blocs[0].Fin }
            }
        }
    }

    # 3. Jours relatifs
    if (($m = Get-Morceau $st "\bdans\s+(?<n>$RxNombre)\s+(?<u>jours?|semaines?|mois|ans?)\b").Success) {
        $n = ConvertFrom-Nombre $m.Groups['n'].Value
        $date = switch -Regex ($m.Groups['u'].Value.ToLower()) { '^j' { $today.AddDays($n) } '^s' { $today.AddDays(7 * $n) } '^m' { $today.AddMonths($n) } default { $today.AddYears($n) } }
    } elseif ((Get-Morceau $st "\bapr[èe]s[- ]demain\b").Success) { $date = $today.AddDays(2) }
    elseif ((Get-Morceau $st "\baujourd'?\s?hui\b").Success) { $date = $today }
    elseif ((Get-Morceau $st '\bdemain\b').Success) { $date = $today.AddDays(1) }

    # 4. Dates : « le 27/02 », « le 27 février 2027 », « vendredi 27 février », « le 27 »
    if (-not $date) {
        if (($m = Get-Morceau $st '\b(?:le\s+)?(?<d>\d{1,2})/(?<mo>\d{1,2})(?:/(?<y>\d{2,4}))?\b').Success -or
            ($m = Get-Morceau $st "\b(?:(?:le|du|ce)\s+)?(?:(?<wdx>$RxJour)\s+)?(?<d>$RxNombre)\s+(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?\b").Success) {
            $d = ConvertFrom-Nombre $m.Groups['d'].Value
            $mo = if ($m.Groups['mo'].Value -match '^\d+$') { [int]$m.Groups['mo'].Value } else { $MoisNoms[$m.Groups['mo'].Value.ToLower()] }
            if ($m.Groups['y'].Success) {
                $y = [int]$m.Groups['y'].Value; if ($y -lt 100) { $y += 2000 }
                $date = New-DateSure $y $mo $d
            } else {
                # Sans année : la prochaine fois que cette date arrive (un 29 février attend l'année qui en a un)
                for ($k = 0; $k -le 4 -and -not $date; $k++) {
                    $c = New-DateSure ($today.Year + $k) $mo $d
                    if ($c -and $c -ge $today) { $date = $c }
                }
            }
            if (-not $date) { $invalide = $true }
        } elseif (($m = Get-Morceau $st "\b(?:(?:le|ce)\s+(?:(?<wdx>$RxJour)\s+)?|(?<wdx>$RxJour)\s+)(?<d>\d{1,2}|1er|premier)\b(?!\s*(?:h(?![a-zà-ÿ])|heures?\b|:|jours?\b|semaines?\b|mois\b|ans?\b|minutes?\b|min\b))").Success) {
            # « le 27 » : ce mois-ci, ou le mois suivant si le 27 est passé
            $d = ConvertFrom-Nombre $m.Groups['d'].Value
            for ($k = 0; $k -le 12 -and -not $date; $k++) {
                $first = $today.AddDays(1 - $today.Day).AddMonths($k)
                $c = New-DateSure $first.Year $first.Month $d
                if ($c -and $c -ge $today) { $date = $c }
            }
            if (-not $date) { $invalide = $true }
        }
    }

    # Jour de la semaine qui ne colle pas avec le numéro (« jeudi 13 » alors que le 13 est un mardi) : le jour de la semaine l'emporte
    if ($date -and $m -and $m.Groups['wdx'].Success) {
        $wdv = $JoursNoms[$m.Groups['wdx'].Value.ToLower()]
        if ([int]$date.DayOfWeek -ne $wdv) { $ecart = (($wdv - [int]$today.DayOfWeek) + 7) % 7; $date = $today.AddDays($ecart) }
    }

    # 5. Jour de la semaine : « mardi », « mardi prochain », « ce samedi », « mercredi de la semaine prochaine »
    if ((Get-Morceau $st '\b(?:de\s+)?la semaine prochaine\b').Success) { $semaineProchaine = $true }
    $wd = $null
    if (($m = Get-Morceau $st "\b(?:(?<ce>ce\s+)|le\s+)?(?<wd>$RxJour)(?:\s+(?:prochain|qui vient))?\b").Success) {
        $wd = $JoursNoms[$m.Groups['wd'].Value.ToLower()]
        if (-not $date -and -not $rep) {
            if ($semaineProchaine) {
                $lundi = $today.AddDays(7 - ((([int]$today.DayOfWeek) + 6) % 7))
                $date = $lundi.AddDays(($wd + 6) % 7)
            } else {
                $ecart = (($wd - [int]$today.DayOfWeek) + 7) % 7
                if ($ecart -eq 0 -and -not $m.Groups['ce'].Success) { $ecart = 7 }   # « mardi » dit un mardi : celui d'après
                $date = $today.AddDays($ecart)
            }
        }
    } elseif ($semaineProchaine -and -not $date) {
        $date = $today.AddDays(7 - ((([int]$today.DayOfWeek) + 6) % 7))   # lundi de la semaine prochaine
    }

    if ((Get-Morceau $st '\b(?:toute la journ[ée]e|la journ[ée]e enti[èe]re|journ[ée]e enti[èe]re)\b').Success) { $journee = $true }

    # 6. Heure : « à midi et demi », « à 15 h 30 », « 15h30 », « à 3 h de l'après-midi », « quinze heures trente »
    $rxQualif = "(?:\s+(?<q>du matin|de l'apr[èe]s[- ]midi|de l'aprem|du soir|de la nuit))?"
    if (($m = Get-Morceau $st "(?:\b(?:à|a|vers|pour)\s+)?(?<ce>\bce\s+)?(?<![-'\w])(?<mm>midi|minuit)(?:\s+(?<f>$RxFrac)|\s*(?<m>\d{2})\b)?").Success) {
        $h = if ($m.Groups['mm'].Value -match '^midi$') { 12 } else { 0 }
        $min = if ($m.Groups['m'].Success) { [int]$m.Groups['m'].Value } else { 0 }
        $heure = [timespan]::new($h, $min, 0)
        if ($m.Groups['ce'].Success -and -not $date) { $date = $today }
    } elseif (($m = Get-Morceau $st "(?:\b(?:à|a|vers|pour|de)\s+)?\b(?<h>$RxNombre)\s*(?:h(?![a-zà-ÿ])|heures?\b|:)(?:\s*(?:(?<m>\d{2})\b|(?<mw>$RxMinMot)\b))?(?:\s+(?<f>$RxFrac))?$rxQualif").Success) {
        $h = ConvertFrom-Nombre $m.Groups['h'].Value
        $min = if ($m.Groups['m'].Success) { [int]$m.Groups['m'].Value } elseif ($m.Groups['mw'].Success) { ConvertFrom-Nombre $m.Groups['mw'].Value } else { 0 }
        if ($null -ne $h -and $h -le 24 -and $min -le 59) {
            if ($h -eq 24) { $h = 0 }
            $heure = [timespan]::new($h, $min, 0)
            $heureChiffres = $true
            if ($m.Groups['q'].Success) { $qualif = $m.Groups['q'].Value.ToLower() }
        }
    }
    if ($m.Success -and $m.Groups['f'].Success -and $heure) {
        switch -Regex ($m.Groups['f'].Value.ToLower()) {
            'demi' { $heure = $heure.Add([timespan]::FromMinutes(30)) }
            'et quart' { $heure = $heure.Add([timespan]::FromMinutes(15)) }
            'moins' { $heure = $heure.Subtract([timespan]::FromMinutes(15)); if ($heure.Ticks -lt 0) { $heure = $heure.Add([timespan]::FromDays(1)) } }
        }
    }

    # 7. Moment de la journée : « ce soir », « demain matin », « cet après-midi » (heure par défaut s'il n'y en a pas)
    if (($m = Get-Morceau $st "\b(?<ce>ce\s+|cet\s+|cette\s+)?(?<p>matin|apr[èe]s[- ]midi|aprem|soir)\b").Success) {
        $periode = $m.Groups['p'].Value.ToLower()
        if ($m.Groups['ce'].Success -and -not $date) { $date = $today }
    }
    if (-not $periode -and $periodeRep) { $periode = $periodeRep }   # « tous les matins »
    $moment = if ($qualif) { $qualif } else { $periode }
    if ($heure) {
        # « 8 h » le soir ou l'après-midi veut dire 20 h ; sans précision, « à 3 h » pour un rendez-vous veut dire 15 h
        if ($moment -match 'soir|midi|aprem' -and $heure.Hours -lt 12) { $heure = $heure.Add([timespan]::FromHours(12)) }
        elseif (-not $moment -and $heureChiffres -and $heure.Hours -ge 1 -and $heure.Hours -le 6) { $heure = $heure.Add([timespan]::FromHours(12)) }
    } elseif ($moment) {
        $heure = switch -Regex ($moment) { 'matin' { [timespan]::new(9, 0, 0) } 'midi|aprem' { [timespan]::new(14, 0, 0) } default { [timespan]::new(20, 0, 0) } }
    }

    # Liste dite d'un coup : « faire les courses : lait, œufs et pain », « avec la liste lait, œufs, pain »
    $m = [regex]::Match($st.S, "(?:\s*,?\s*(?:avec\s+)?(?:la|ma|une)\s+liste\s*(?:de\s+courses\s*)?(?:suivante\s*)?:?|\s*:)\s*(?<l>[^:]+?)\s*$", 'IgnoreCase')
    if ($m.Success -and ($m.Value -match '(?i)liste' -or $m.Groups['l'].Value -match ',')) {
        $det.APreparer = @($m.Groups['l'].Value -split '\s*(?:,|;|\bet\b|\bpuis\b)\s*' | ForEach-Object { $_.Trim(' .') } | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) })
        $st.S = $st.S.Remove($m.Index)
    }

    # Titre : ce qui reste de la phrase, sans les ordres (« crée un rendez-vous ») ni les petits mots autour
    $titre = Get-TitreNettoye $st.S
    # Où : « réunion à Paris », « concert au Zénith » (un nom propre, avec sa majuscule)
    if (-not $det.Lieu) {
        $m = [regex]::Match($titre, "\s+(?:à la|à l'|à|au|aux)\s+(?<lieu>[A-ZÀ-Ý][\w'-]*(?:\s+(?:(?:de|du|des|la|le)\s+|d')?[A-ZÀ-Ý][\w'-]*)*)")
        if ($m.Success) { $det.Lieu = $m.Groups['lieu'].Value; $titre = Get-TitreNettoye ($titre.Remove($m.Index, $m.Length).Insert($m.Index, ' ')) }
    }
    # Avec qui : « déjeuner avec Paul et Léa »
    $m = [regex]::Match($titre, '^(?<avant>.*?\S)?\s*\bavec\s+(?<qui>.+)$', 'IgnoreCase')
    if ($m.Success) {
        $det.Avec = @($m.Groups['qui'].Value -split '\s*(?:,|\bet\b)\s*' | ForEach-Object { $_.Trim(' .') } | Where-Object { $_ })
        $titre = Get-TitreNettoye $m.Groups['avant'].Value
        # « rendez-vous avec Madame Dupont » : sans autre titre, le rendez-vous porte le nom des personnes
        if (-not $titre -and $det.Avec.Count) { $titre = "rendez-vous avec $($det.Avec -join ' et ')" }
    }

    # Sorte de rendez-vous, devinée d'après les mots. Un anniversaire revient chaque année et n'a pas besoin d'heure.
    $type = Get-TypeAuto $titre
    if ($type -eq 'anniv') {
        $titre = Get-TitreAnniversaire $titre
        if (-not $rep) { $rep = [ordered]@{ Type = 'an'; Jour = $null; Mois = $null } }
        # Sans heure (ou « à minuit », dit pour « le jour même ») : toute la journée
        if ((-not $heure -or $heure.Ticks -eq 0) -and -not $exact) { $journee = $true }
    }
    # Un jour sans heure (« samedi, faire les courses ») : toute la journée, pas besoin d'heure
    if (-not $heure -and -not $exact -and ($date -or $rep)) { $journee = $true }
    # Une chose à faire sans jour ni heure (« faire les courses ») : aujourd'hui, toute la journée
    if (-not $heure -and -not $exact -and -not $date -and -not $rep -and $type -eq 'rappel') { $date = $today; $journee = $true }
    if ($journee) { $heure = [timespan]::Zero; $exact = $null }
    $maintenant = if ($journee) { $today } else { $Now }

    # Résultat. Jour et Heure : ce qui a été compris, même s'il manque l'autre (pour pré-remplir le formulaire)
    $res = [ordered]@{ Titre = $titre; Quand = $null; Repetition = $null; Manque = ''; Jour = $date; Heure = $(if ($journee) { $null } else { $heure })
                       Type = $type; Journee = [bool]$journee }
    if ($invalide) { $res.Manque = 'invalide'; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
    if ($rep) {
        if (-not $heure -and $exact) { $heure = $exact.TimeOfDay }
        if ($rep.Type -eq 'an' -and -not $date) { $res.Manque = 'jour'; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
        if (-not $heure) { $res.Manque = 'heure'; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
        $ref = if ($date) { $date } elseif ($exact) { $exact.Date } else { $today }
        switch ($rep.Type) {
            'semaine' { if ($null -eq $rep.Jour) { $rep.Jour = if ($null -ne $wd) { $wd } else { [int]$ref.DayOfWeek } } }
            'mois'    { if (-not $rep.Rang -and -not $rep.Jour) { $rep.Jour = $ref.Day } }
            'an'      { $rep.Jour = $ref.Day; $rep.Mois = $ref.Month }
        }
        if ($rep.Type -eq 'mois' -and -not $rep.Rang -and ($rep.Jour -lt 1 -or $rep.Jour -gt 31)) { $res.Manque = 'invalide'; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
        $depart = if ($date -and $date -gt $today) { $date + $heure } else { $maintenant }
        if ($limDebut -and $limDebut -gt $depart) { $depart = $limDebut + $heure; if (-not $date) { $ref = $limDebut } }
        # Le premier rendez-vous est la prochaine date possible ; l'intervalle (« toutes les deux semaines ») se compte depuis lui
        $sansIntervalle = [ordered]@{}; foreach ($k in $rep.Keys) { if ($k -ne 'Intervalle') { $sansIntervalle[$k] = $rep[$k] } }
        $res.Quand = Get-NextOccurrence $sansIntervalle ($ref + $heure) $depart
        if ($res.Quand -lt $depart) { $res.Quand = Get-NextOccurrence $sansIntervalle ($depart.Date + $heure) $depart }
        $res.Repetition = $rep
        if ($res.Quand -eq [datetime]::MinValue) { $res.Quand = $null; $res.Manque = 'passe' }   # la fin demandée est déjà passée
        return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit)
    }
    if ($exact) { $res.Quand = $exact; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
    if ($date -and $heure) { $res.Quand = $date + $heure }
    elseif ($date) { $res.Manque = 'heure'; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
    elseif ($heure -and -not $journee) {
        # Juste une heure : aujourd'hui si elle n'est pas passée, sinon demain
        $res.Quand = $today + $heure
        if ($res.Quand -le $Now) { $res.Quand = $res.Quand.AddDays(1) }
    } else { $res.Manque = $(if ($journee) { 'jour' } else { 'quand' }); return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
    if ($res.Quand -lt $maintenant -or (-not $journee -and $res.Quand -eq $Now)) { $res.Manque = 'passe' }
    Complete-Phrase $res $det $finHeure $dureeMin $ageDit
}

# Ajoute au résultat les détails compris (lieu, avec qui, lien, importance, rappels, âge) et l'heure de fin
function Complete-Phrase($Res, $Det, $FinHeure, $DureeMin, $AgeDit) {
    foreach ($k in $Det.Keys) { if ($k -notin 'FinJour', 'NbJours') { $Res[$k] = $Det[$k] } }
    if (-not $Res.Contains('Blocs')) { $Res.Blocs = $null }
    $Res.Fin = $null
    $q = $Res.Quand
    # Sur plusieurs jours : la fin est le dernier jour (à l'heure de fin si elle est dite)
    $finJour = if ($Det.FinJour) { $Det.FinJour } elseif ($Det.NbJours -and $q) { $q.Date.AddDays($Det.NbJours - 1) } else { $null }
    if ($q -and $finJour -and $finJour.Date -gt $q.Date) {
        $Res.Fin = if ($Res.Journee) { $finJour.Date } elseif ($null -ne $FinHeure) { $finJour.Date + $FinHeure } else { $finJour.Date.AddHours(23).AddMinutes(59) }
        if ($AgeDit -and $q) { $Res.Naissance = $q.Year - $AgeDit.N - $(if ($AgeDit.Futur) { 0 } else { 1 }) }
        return [pscustomobject]$Res
    }
    if ($q -and -not $Res.Journee) {
        if ($DureeMin) { $Res.Fin = $q.AddMinutes($DureeMin) }
        elseif ($null -ne $FinHeure) {
            $f = $q.Date + $FinHeure
            # « de 2 h à 4 h » : le début est passé à 14 h, la fin suit (16 h) ; « de 22 h à 1 h » finit le lendemain
            while ($f -le $q -and ($f - $q).TotalHours -gt -24) { $f = $f.AddHours(12) }
            $Res.Fin = $f
        }
    }
    if ($AgeDit -and $q) { $Res.Naissance = $q.Year - $AgeDit.N - $(if ($AgeDit.Futur) { 0 } else { 1 }) }
    [pscustomobject]$Res
}

# Une heure seule, écrite comme on veut (« 15 », « 15h30 », « midi et demi », « 3 h de l'après-midi ») : TimeSpan ou $null
function Read-Heure([string]$Text) {
    $t = $Text.Trim()
    if (-not $t) { return $null }
    if ($t -match '^\d{1,2}$') { $t += ' h' }
    $p = Read-Phrase "le 1/1/2099 à $t" ([datetime]'2026-01-01')
    if ($p.Manque -or -not $p.Quand -or $p.Journee) { return $null }
    $p.Quand.TimeOfDay
}

# Ce qu'on dit autour du rendez-vous et qui n'en fait pas partie : politesse, demande, ordre
$RxPolitesse = "(?:(?:ok|okay|o\.?k\.?|hey|h[ée])[\s,]*(?:[èe]ve|eva)\b|euh+|alors|ok|okay|bon|dis|hey|evermind|s'il te pla[îi]t|s'il vous pla[îi]t|stp|svp|merci)"
$RxDemande   = "(?:je dois|il faut que je|faut que je|j'ai besoin de|je ne dois pas oublier de|n'oublie pas que je dois|est-ce que tu (?:peux|pourrais|veux bien)|est-ce que je peux|tu (?:peux|pourrais|veux bien)|peux-tu|pourrais-tu|je (?:voudrais|veux|souhaite)|j'aimerais|il faut que tu|il faut|faut)"
$RxOrdre     = "(?:cr[ée]{1,2}[rsz]?|ajoute[rsz]?|rajoute[rsz]?|met[st]?|mettes?|mettre|note[rsz]?|programme[rsz]?|planifie[rsz]?|enregistre[rsz]?|cale[rsz]?|rappelle[s]?[- ]moi|fais[- ]moi penser|pr[ée]viens[- ]moi|pense[rsz]? [àa]|n'oublie pas)"
$RxGenre     = "(?:rendez[- ]vous|rdv|[ée]v[èée]nement|event|rappel|truc)"

function Get-TitreNettoye([string]$Text) {
    $t = $Text -replace '\s+', ' '
    $t = $t -replace "\b(?:dans|sur|à|a) (?:mon|l'|le|ton|ma) ?(?:agenda|calendrier)\b", ' '
    $prev = $null
    while ($prev -ne $t) {
        $prev = $t
        $t = $t -replace '\s+([,.;:!?])', '$1' -replace '([,;:])(?:\s*[,;:])+', '$1'
        $t = $t.Trim(' ,.;:!?-'.ToCharArray())
        $t = $t -replace "^$RxPolitesse\b[\s,]*", ''
        $t = $t -replace "[\s,]*\b$RxPolitesse$", ''
        $t = $t -replace "^$RxDemande\b\s*", ''
        # « que tu me crées... », « et que tu mettes... » (on parle comme à quelqu'un)
        $t = $t -replace "^(?:et\s+)?(?:que\s+|qu')?(?:tu\s+)?(?:me\s+|m'|nous\s+)(?=$RxOrdre\b)", ''
        $t = $t -replace "^(?:et\s+)?que\s+tu\s+(?=$RxOrdre\b)", ''
        $t = $t -replace "^$RxOrdre\b(?:[- ]?(?:moi|nous|me))?\s*(?:(?:de|que)\s+|d'|qu')?", ''
        $t = $t -replace "^(?:j'ai|il y a|y a|pr[ée]vois)\b\s*(?:(?:de|que)\s+|d'|qu')?", ''
        $t = $t -replace "^(?:un |une |le |la |mon |ma |l')?(?:nouvel? |nouvelle )?$RxGenre\b\s*(?:(?:de|du|des|pour)\s+|d'|:)?", ''
        $t = $t -replace '^(?:et|puis|à|a|au|pour|vers|de|du)\s+', ''
        # « une réunion », « un café avec Paul » : l'article ne fait pas partie du nom
        $t = $t -replace '^(?:un|une)\s+(?=\S)', ''
        $t = $t -replace '\s+(?:à|a|au|le|la|de|du|pour|et|vers|ce|cet|cette)$', ''
        $t = $t -replace '\s+(?:à|a|au|le|la|de|du|pour|et|vers)\s*([,;])', '$1'
    }
    $t
}

# ---------------------------------------------------------------------------
# Sortes de rendez-vous : chacune a son icône, sa couleur et ses mots
# ---------------------------------------------------------------------------
# L'ordre compte : la première sorte dont un mot est dans le titre l'emporte.
$Types = [ordered]@{
    anniv   = @{ Nom = 'Anniversaire'; Icone = '🎂'; Couleur = '#FF2EB5'; Mots = 'anniv(?:ersaires?)?|birthday' }
    sante   = @{ Nom = 'Santé'; Icone = '💊'; Couleur = '#3DDC97'; Mots = "m[ée]decin|docteur|doc|dentiste|kin[ée](?:sith[ée]rapeute)?|ophtalmo(?:logue)?|dermato(?:logue)?|gyn[ée]co(?:logue)?|psy(?:chologue|chiatre)?|orthodontiste|ost[ée]o(?:pathe)?|infirmi[èe]re?|h[ôo]pital|clinique|radio|prise de sang|vaccin|pharmacie|labo(?:ratoire)?|analyses?|ordonnance|m[ée]dicaments?|cachets?|sant[ée]|urgences" }
    voyage  = @{ Nom = 'Voyage'; Icone = '✈'; Couleur = '#5EEAD4'; Mots = "voyage|vacances|train|avion|vol|a[ée]roport|gare|valise|h[ôo]tel|road ?trip|week-end [àa]" }
    travail = @{ Nom = 'Travail / école'; Icone = '💼'; Couleur = '#4EA8FF'; Mots = "travail|boulot|taf|r[ée]union|meeting|entretien|rendu|deadline|cours|[ée]cole|fac|lyc[ée]e|coll[èe]ge|examen|exam|partiel|devoirs?|bureau|client|formation|stage|pr[ée]sentation" }
    sport   = @{ Nom = 'Sport'; Icone = '⚽'; Couleur = '#9BE15D'; Mots = "foot(?:ball)?|sport|salle|muscu(?:lation)?|piscine|natation|course|running|footing|jogging|v[ée]lo|basket|tennis|badminton|padel|yoga|boxe|judo|karat[ée]|danse|entra[îi]nement|match|rando(?:nn[ée]e)?|escalade|ski" }
    jeu     = @{ Nom = 'Jeu'; Icone = '🎮'; Couleur = '#B04BFF'; Mots = "raid|donjon|tournoi|partie|game|games|jeux?|lan|stream|ranked|class[ée]e?s?|session|valo(?:rant)?|lol|fortnite|dofus|minecraft|warzone|apex|wow" }
    sortie  = @{ Nom = 'Sortie'; Icone = '🎉'; Couleur = '#FFB547'; Mots = "soir[ée]e|f[êe]te|resto|restaurant|cin[ée](?:ma)?|concert|ap[ée]ro|bar|bo[îi]te|mariage|bapt[êe]me|barbecue|bbq|pique-nique|repas|d[îi]ner|d[ée]jeuner|brunch|sortie|festival|spectacle|th[ée][âa]tre|expo(?:sition)?|mus[ée]e|salon" }
    rappel  = @{ Nom = 'À faire'; Icone = '🔔'; Couleur = '#FFD84D'; Mots = "appeler|t[ée]l[ée]phoner|payer|acheter|envoyer|poster|rendre|r[ée]cup[ée]rer|chercher|sortir|poubelles?|courses|penser|faire|r[ée]server|renouveler|imprimer|laver|ranger|arroser|virement|facture|loyer|imp[ôo]ts?" }
    rdv     = @{ Nom = 'Rendez-vous'; Icone = '📅'; Couleur = '#00E5FF'; Mots = $null }
}

function Get-TypeAuto([string]$Titre) {
    foreach ($k in $Types.Keys) {
        $m = $Types[$k].Mots
        if ($m -and $Titre -match "(?i)(?<![\w])(?:$m)(?![\w])") { return $k }
    }
    'rdv'
}

# Sorte d'un rendez-vous enregistré (les anciens n'en ont pas : on la devine d'après le titre)
function Get-TypeRV($RV) {
    $k = [string]$RV.Type
    if ($k -and $Types.Contains($k)) { $k } else { Get-TypeAuto $RV.Titre }
}

# « anniversaire Jordan », « anniv de Léa », « mon anniversaire » : « Anniversaire de Jordan »...
function Get-TitreAnniversaire([string]$Titre) {
    $m = [regex]::Match($Titre, "^(?:(?:mon|l'|un|une|le|ton|son)\s*)?anniv(?:ersaire)?\b\s*(?:(?:de|du|des|pour|à|a)\s+|d')?(?<nom>.*)$", 'IgnoreCase')
    if (-not $m.Success) { return $Titre }
    $nom = $m.Groups['nom'].Value.Trim()
    if (-not $nom) { return 'Anniversaire' }
    $nom = $nom.Substring(0, 1).ToUpper() + $nom.Substring(1)
    if ($nom -match '^[AEIOUYÉÈÊaeiouyéèê]') { "Anniversaire d'$nom" } else { "Anniversaire de $nom" }
}

# ---------------------------------------------------------------------------
# Écrire les dates et heures comme on les dit
# ---------------------------------------------------------------------------
function Format-Heure([datetime]$d) {
    if ($d.Hour -eq 12 -and $d.Minute -eq 0) { return 'midi' }
    if ($d.Hour -eq 0 -and $d.Minute -eq 0) { return 'minuit' }
    if ($d.Minute) { '{0} h {1:00}' -f $d.Hour, $d.Minute } else { "$($d.Hour) h" }
}

# « vendredi 27 février », « samedi 1er mars », avec l'année si ce n'est pas celle en cours
function Format-Jour([datetime]$d) {
    $t = if ($d.Day -eq 1) { $d.ToString('dddd', $Fr) + ' 1er ' + $d.ToString('MMMM', $Fr) } else { $d.ToString('dddd d MMMM', $Fr) }
    if ($d.Year -ne (Get-Date).Year) { $t += " $($d.Year)" }
    $t
}

# « vendredi 27 février à 15 h », « vendredi 27 février à midi »
function Format-Quand([datetime]$d) { "$(Format-Jour $d) à $(Format-Heure $d)" }

# « 1 h 30 », « 45 min », « 2 h »
function Format-Duree([timespan]$d) {
    $m = [int]$d.TotalMinutes
    if ($m -lt 60) { return "$m min" }
    $h = [math]::Floor($m / 60); $r = $m % 60
    if ($r) { '{0} h {1:00}' -f $h, $r } else { "$h h" }
}

# Un rappel : « veille » (la veille à 20 h), « matin » (le matin même à 8 h), « m60 » (60 minutes avant)
function Format-Rappel([string]$Code) {
    switch -Regex ($Code) {
        '^veille$' { return 'la veille à 20 h' }
        '^matin$'  { return 'le matin même à 8 h' }
        '^m0$'     { return 'à l''heure' }
        '^m(\d+)$' {
            $n = [int]$Matches[1]
            if ($n % 10080 -eq 0) { $s = $n / 10080; return "$s semaine$(if ($s -gt 1) { 's' }) avant" }
            if ($n % 1440 -eq 0) { $j = $n / 1440; return "$j jour$(if ($j -gt 1) { 's' }) avant" }
            if ($n % 60 -eq 0) { return "$($n / 60) h avant" }
            return "$n min avant"
        }
    }
    $Code
}

# « 20 h à 23 h (3 h) »
function Format-Plage([datetime]$Debut, $Fin) {
    if (-not $Fin) { return Format-Heure $Debut }
    $f = [datetime]$Fin
    "$(Format-Heure $Debut) à $(Format-Heure $f)$(if ($f.Date -ne $Debut.Date) { ' (le lendemain)' }) ($(Format-Duree ($f - $Debut)))"
}

# Même chose pour un rendez-vous : un anniversaire n'a pas d'heure, les autres « toute la journée » le disent
function Format-QuandRV($RV, [datetime]$d) {
    # Sur plusieurs jours : « du mardi 27 au jeudi 29 octobre »
    if (Test-PlusieursJours $RV) {
        $a = [datetime]$RV.Quand; $b = [datetime]$RV.Fin
        $fa = if ($a.Month -eq $b.Month -and $a.Year -eq $b.Year) { $a.ToString('dddd d', $Fr) } else { $a.ToString('dddd d MMMM', $Fr) }
        $fb = $b.ToString('dddd d MMMM', $Fr) + $(if ($b.Year -ne (Get-Date).Year) { " $($b.Year)" })
        if ($RV.Journee) { return "du $fa au $fb" }
        return "du $($a.ToString('dddd d MMMM', $Fr)) à $(Format-Heure $a) au $fb$(if ($b.TimeOfDay -lt [timespan]'23:59') { " à $(Format-Heure $b)" })"
    }
    if (-not $RV.Journee) {
        if ($RV.Fin) { $f = $d + ([datetime]$RV.Fin - [datetime]$RV.Quand); return "$(Format-Jour $d) de $(Format-Heure $d) à $(Format-Heure $f)" }
        return Format-Quand $d
    }
    if ((Get-TypeRV $RV) -eq 'anniv') { Format-Jour $d } else { "$(Format-Jour $d), toute la journée" }
}

# (une soirée de 21 h à 2 h finit le lendemain, mais ce n'est pas un événement sur plusieurs jours)
function Test-PlusieursJours($RV) { $RV -and $RV.Fin -and -not $RV.Repetition -and ([datetime]$RV.Fin).Date -gt ([datetime]$RV.Quand).Date -and ($RV.Journee -or ([datetime]$RV.Fin - [datetime]$RV.Quand).TotalHours -ge 24) }

function Format-Relatif([datetime]$d) {
    $days = ($d.Date - (Get-Date).Date).Days
    switch ($days) {
        0 { "aujourd'hui" }
        1 { 'demain' }
        2 { 'après-demain' }
        default { if ($days -lt 0) { 'passé' } elseif ($days -lt 14) { "dans $days jours" } elseif ($days -lt 60) { "dans $([math]::Floor($days / 7)) semaines" } else { "dans $([math]::Round($days / 30.4)) mois" } }
    }
}

# « tous les lundis », « tous les jours », « le 5 de chaque mois », « tous les ans le 12 mars »
function Format-Repetition($Repetition) {
    if (-not $Repetition) { return '' }
    $nomJour = { param($j) [Globalization.CultureInfo]::GetCultureInfo('fr-FR').DateTimeFormat.GetDayName([DayOfWeek][int]$j) }
    $n = if ($Repetition.Intervalle -and [int]$Repetition.Intervalle -gt 1) { [int]$Repetition.Intervalle } else { 1 }
    $jours = @($Repetition.Jours | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
    $t = switch ([string]$Repetition.Type) {
        'jour'    { if ($n -gt 1) { "tous les $n jours" } else { 'tous les jours' } }
        'semaine' {
            if ($jours.Count -gt 1) {
                $l = if (-not (Compare-Object $jours @(1, 2, 3, 4, 5))) { 'en semaine (du lundi au vendredi)' }
                     elseif (-not (Compare-Object $jours @(6, 0))) { 'le week-end' }
                     else { $noms = @($jours | ForEach-Object { & $nomJour $_ }); "le $(($noms | Select-Object -SkipLast 1) -join ', ') et le $($noms[-1])" }
                if ($n -gt 1) { "$l, une semaine sur $n" } else { $l }
            }
            elseif ($n -eq 2) { "un $(& $nomJour $Repetition.Jour) sur deux" }
            elseif ($n -gt 2) { "toutes les $n semaines le $(& $nomJour $Repetition.Jour)" }
            else { 'tous les ' + (& $nomJour $Repetition.Jour) + 's' }
        }
        'mois'    {
            $quoi = if ($Repetition.Rang) {
                $rang = switch ([int]$Repetition.Rang) { 1 { 'premier' } 2 { 'deuxième' } 3 { 'troisième' } 4 { 'quatrième' } default { 'dernier' } }
                "le $rang $(& $nomJour $Repetition.Jour)"
            } else { "le $(if ([int]$Repetition.Jour -eq 1) { '1er' } else { $Repetition.Jour })" }
            if ($n -gt 1) { "tous les $n mois, $quoi" } else { "$quoi de chaque mois" }
        }
        'an'      { "$(if ($n -gt 1) { "tous les $n ans" } else { 'tous les ans' }) le $(if ([int]$Repetition.Jour -eq 1) { '1er' } else { $Repetition.Jour }) $($Fr.DateTimeFormat.GetMonthName([int]$Repetition.Mois))" }
    }
    if ($Repetition.Jusqua) {
        $j = [datetime]::ParseExact([string]$Repetition.Jusqua, 'yyyy-MM-dd', $null)
        $jour = if ($j.Day -eq 1) { '1er' } else { $j.Day }
        $t += " jusqu'au $jour $($Fr.DateTimeFormat.GetMonthName($j.Month))$(if ($j.Year -ne (Get-Date).Year) { " $($j.Year)" })"
    }
    $sauf = @($Repetition.Sauf | Where-Object { $_ } | ForEach-Object { [datetime]::ParseExact([string]$_, 'yyyy-MM-dd', $null) } | Where-Object { $_ -ge (Get-Date).Date } | Where-Object {
        # seulement les jours où il aurait eu lieu
        $d = $_
        switch ([string]$Repetition.Type) { 'semaine' { $js = @($Repetition.Jours | Where-Object { $null -ne $_ }); if ($js.Count) { $js -contains [int]$d.DayOfWeek } else { [int]$d.DayOfWeek -eq [int]$Repetition.Jour } } 'mois' { $d.Day -eq [int]$Repetition.Jour } 'an' { $d.Day -eq [int]$Repetition.Jour -and $d.Month -eq [int]$Repetition.Mois } default { $true } }
    } | Sort-Object)
    if ($sauf.Count -eq 1) { $t += " (sauf le $($sauf[0].ToString('d MMMM', $Fr)))" }
    elseif ($sauf.Count -gt 1) { $t += " (sauf $($sauf.Count) fois)" }
    $t
}

# Une période dite avec des mots : « en octobre 2026 », « à partir de novembre », « jusqu'au 15 mars », « le 19 octobre »,
# « du 3 au 10 novembre », « cette semaine », « le mois prochain »... Retourne @{ Debut; Fin } (jours compris, l'un ou
# l'autre peut manquer : « à partir de » n'a pas de fin), ou $null si ce n'est pas compris.
function Read-Periode([string]$Texte, $Now) {
    if (-not $Now) { $Now = Get-Date }
    $today = ([datetime]$Now).Date
    $t = ($Texte -replace "[’‘`´]", "'").ToLower().Trim(' .,!?')
    $t = $t -replace "^(?:pour|pendant|sur|durant)\s+", '' -replace "^(?:(?:de|des)\s+|d')(?=la\s+semaine|ce\s+mois|cette|le\s+mois|(?:$RxMois)\b)", ''
    if (-not $t) { return $null }
    # Un jour seul, ou un mois entier (le début ou la fin du mois selon le côté)
    $jour = {
        param([string]$s, [bool]$Fin)
        $s = $s.Trim(' .,')
        if ($s -match "^(?:(?:le|la)\s+)?(?:(?<fin>fin|d[ée]but)\s+(?:de\s+|d')?)?(?:(?:du\s+)?mois\s+(?:de\s+|d'))?(?:de\s+|d'|en\s+)?(?<mo>$RxMois)(?:\s+(?<y>\d{4}))?$") {
            $mo = $MoisNoms[$Matches['mo']]
            $y = if ($Matches['y']) { [int]$Matches['y'] } elseif ($mo -lt $today.Month) { $today.Year + 1 } else { $today.Year }
            $premier = [datetime]::new($y, $mo, 1); $dernier = $premier.AddMonths(1).AddDays(-1)
            if ($Matches['fin'] -eq 'fin') { return $dernier }
            if ($Matches['fin']) { return $premier }
            return $(if ($Fin) { $dernier } else { $premier })
        }
        if ($s -match "^(?:le\s+)?mois\s+prochain$") { $p = $today.AddDays(1 - $today.Day).AddMonths(1); return $(if ($Fin) { $p.AddMonths(1).AddDays(-1) } else { $p }) }
        $p = Read-Phrase "x $s" $Now
        if ($p.Jour) { return ([datetime]$p.Jour).Date }
        if ($p.Quand) { return ([datetime]$p.Quand).Date }
        $null
    }
    if ($t -match "^(?:du|de)\s+(?<a>.+?)\s+(?:au|à|a|jusqu'au|jusqu'à)\s+(?<b>.+)$") {
        $sa = $Matches['a']; $sb = $Matches['b']
        $a = & $jour $sa $false; $b = & $jour $sb $true
        # « du 3 au 10 novembre » : le mois (et l'année) de la fin vaut aussi pour le début
        if (-not $a -and $sa -match '^\d{1,2}(?:er)?$' -and $sb -match "(?<m>$RxMois(?:\s+\d{4})?)$") { $a = & $jour "$sa $($Matches['m'])" $false }
        if ($a -and $b) { return @{ Debut = $a; Fin = $b } }
    }
    if ($t -match "^(?:à|a)\s+partir\s+(?:du\s+|de\s+|d')?(?<a>.+)$" -or $t -match "^d[èe]s\s+(?:le\s+)?(?<a>.+)$") { $a = & $jour $Matches['a'] $false; if ($a) { return @{ Debut = $a; Fin = $null } } }
    if ($t -match "^apr[èe]s\s+(?:le\s+)?(?<a>.+)$") { $a = & $jour $Matches['a'] $true; if ($a) { return @{ Debut = $a.AddDays(1); Fin = $null } } }
    if ($t -match "^jusqu'?\s*(?:au|à|a|en)\s+(?<b>.+)$") { $b = & $jour $Matches['b'] $true; if ($b) { return @{ Debut = $null; Fin = $b } } }
    if ($t -match "^avant\s+(?:le\s+)?(?<b>.+)$") { $b = & $jour $Matches['b'] $false; if ($b) { return @{ Debut = $null; Fin = $b.AddDays(-1) } } }
    if ($t -match "^(?:cette|la)\s+semaine(?:-ci)?$") { $l = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7)); return @{ Debut = $today; Fin = $l.AddDays(6) } }
    if ($t -match "^la\s+semaine\s+prochaine$") { $l = $today.AddDays(7 - (([int]$today.DayOfWeek + 6) % 7)); return @{ Debut = $l; Fin = $l.AddDays(6) } }
    if ($t -match "^ce\s+mois(?:-ci)?$") { return @{ Debut = $today; Fin = $today.AddDays(1 - $today.Day).AddMonths(1).AddDays(-1) } }
    # Un mois entier, ou un seul jour
    $a = & $jour $t $false; $b = & $jour $t $true
    if ($a -and $b) { return @{ Debut = $a; Fin = $b } }
    $null
}