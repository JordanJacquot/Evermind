# Evermind : comprendre un rendez-vous écrit (ou dit) en français de tous les jours, et l'écrire en retour.
# Règles écrites ici même : pas d'IA en ligne, rien n'est envoyé sur Internet.
# Chargé par Evermind.ps1 ; utilisable seul pour les tests (outils\tester-phrases.ps1).

if (-not $Fr) { $Fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR') }

# ---------------------------------------------------------------------------
# Vocabulaire
# ---------------------------------------------------------------------------
$MoisNoms = [ordered]@{ janvier = 1; 'février' = 2; fevrier = 2; mars = 3; avril = 4; mai = 5; juin = 6; juillet = 7
                        'août' = 8; aout = 8; septembre = 9; octobre = 10; novembre = 11; 'décembre' = 12; decembre = 12 }
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
$RxMois   = '(?:' + ($MoisNoms.Keys -join '|') + ')'
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
# Rendez-vous qui reviennent : prochaine fois à partir d'un moment donné
# ---------------------------------------------------------------------------
#   Repetition : { Type = 'jour' } | { Type = 'semaine'; Jour = 0..6 (0 = dimanche) } | { Type = 'mois'; Jour = 1..31 }
#                | { Type = 'an'; Jour = 1..31; Mois = 1..12 }
#   Un jour qui n'existe pas dans un mois (le 31) tombe le dernier jour de ce mois.
function Get-NextOccurrence($Repetition, [datetime]$Premier, [datetime]$From) {
    if (-not $Repetition) { return $Premier }
    $base = if ($From -gt $Premier) { $From } else { $Premier }
    $heure = $Premier.TimeOfDay
    switch ([string]$Repetition.Type) {
        'jour' {
            $c = $base.Date + $heure
            if ($c -lt $base) { $c = $c.AddDays(1) }
            return $c
        }
        'semaine' {
            $c = $base.Date.AddDays(((([int]$Repetition.Jour) - [int]$base.DayOfWeek) + 7) % 7) + $heure
            if ($c -lt $base) { $c = $c.AddDays(7) }
            return $c
        }
        'mois' {
            for ($k = 0; $k -le 12; $k++) {
                $first = $base.Date.AddDays(1 - $base.Day).AddMonths($k)
                $d = [math]::Min([int]$Repetition.Jour, [datetime]::DaysInMonth($first.Year, $first.Month))
                $c = $first.AddDays($d - 1) + $heure
                if ($c -ge $base) { return $c }
            }
        }
        'an' {
            for ($k = 0; $k -le 8; $k++) {
                $y = $base.Year + $k
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

    # 1. Rendez-vous qui reviennent
    if (($m = Get-Morceau $st "\b(?:tous les|chaque)\s+(?<wd>$RxJour)s?\b").Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = $JoursNoms[$m.Groups['wd'].Value.ToLower()] }
    } elseif ((Get-Morceau $st '\b(?:tous les jours|chaque jour)\b').Success) {
        $rep = [ordered]@{ Type = 'jour' }
    } elseif (($m = Get-Morceau $st "\ble\s+(?<d>$RxNombre)\s+(?:de\s+)?(?:chaque|tous les)\s+mois\b").Success -or
              ($m = Get-Morceau $st "\b(?:tous les mois|chaque mois)(?:\s+le\s+(?<d>$RxNombre)\b)?").Success) {
        $rep = [ordered]@{ Type = 'mois'; Jour = $(if ($m.Groups['d'].Success) { ConvertFrom-Nombre $m.Groups['d'].Value } else { $null }) }
    } elseif ((Get-Morceau $st '\b(?:toutes les semaines|chaque semaine)\b').Success) {
        $rep = [ordered]@{ Type = 'semaine'; Jour = $null }
    } elseif ((Get-Morceau $st '\b(?:tous les ans|toutes les ann[ée]es|chaque ann[ée]e)\b').Success) {
        $rep = [ordered]@{ Type = 'an'; Jour = $null; Mois = $null }
    }

    # 2. « dans 2 heures », « dans 30 minutes », « dans une demi-heure » : le moment exact
    if (($m = Get-Morceau $st "\bdans\s+(?:(?<n>$RxNombre)\s+(?<u>heures?|h|minutes?|min)\b|(?<dh>une demi[- ]heure)|(?<qh>un quart d'heure))").Success) {
        $exact = if ($m.Groups['dh'].Success) { $Now.AddMinutes(30) }
                 elseif ($m.Groups['qh'].Success) { $Now.AddMinutes(15) }
                 elseif ($m.Groups['u'].Value -match '^h') { $Now.AddHours((ConvertFrom-Nombre $m.Groups['n'].Value)) }
                 else { $Now.AddMinutes((ConvertFrom-Nombre $m.Groups['n'].Value)) }
        $exact = $exact.AddSeconds(-$exact.Second).AddMilliseconds(-$exact.Millisecond)
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
    if (($m = Get-Morceau $st "\b(?<ce>ce\s+)?(?<wd>$RxJour)(?:\s+(?:prochain|qui vient))?\b").Success) {
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
            'mois'    { if (-not $rep.Jour) { $rep.Jour = $ref.Day } }
            'an'      { $rep.Jour = $ref.Day; $rep.Mois = $ref.Month }
        }
        if ($rep.Type -eq 'mois' -and ($rep.Jour -lt 1 -or $rep.Jour -gt 31)) { $res.Manque = 'invalide'; return (Complete-Phrase $res $det $finHeure $dureeMin $ageDit) }
        $depart = if ($date -and $date -gt $today) { $date + $heure } else { $maintenant }
        $res.Quand = Get-NextOccurrence $rep ($ref + $heure) $depart
        if ($res.Quand -lt $depart) { $res.Quand = Get-NextOccurrence $rep ($depart.Date + $heure) $depart }
        $res.Repetition = $rep
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
    foreach ($k in $Det.Keys) { $Res[$k] = $Det[$k] }
    $Res.Fin = $null
    $q = $Res.Quand
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
$RxPolitesse = "(?:euh+|alors|ok|okay|bon|dis|hey|evermind|s'il te pla[îi]t|s'il vous pla[îi]t|stp|svp|merci)"
$RxDemande   = "(?:est-ce que tu (?:peux|pourrais|veux bien)|est-ce que je peux|tu (?:peux|pourrais|veux bien)|peux-tu|pourrais-tu|je (?:voudrais|veux|souhaite)|j'aimerais|il faut que tu|il faut|faut)"
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
    if (-not $RV.Journee) {
        if ($RV.Fin) { $f = $d + ([datetime]$RV.Fin - [datetime]$RV.Quand); return "$(Format-Jour $d) de $(Format-Heure $d) à $(Format-Heure $f)" }
        return Format-Quand $d
    }
    if ((Get-TypeRV $RV) -eq 'anniv') { Format-Jour $d } else { "$(Format-Jour $d), toute la journée" }
}

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
    switch ([string]$Repetition.Type) {
        'jour'    { 'tous les jours' }
        'semaine' { 'tous les ' + [Globalization.CultureInfo]::GetCultureInfo('fr-FR').DateTimeFormat.GetDayName([DayOfWeek][int]$Repetition.Jour) + 's' }
        'mois'    { "le $(if ([int]$Repetition.Jour -eq 1) { '1er' } else { $Repetition.Jour }) de chaque mois" }
        'an'      { "tous les ans le $(if ([int]$Repetition.Jour -eq 1) { '1er' } else { $Repetition.Jour }) $($Fr.DateTimeFormat.GetMonthName([int]$Repetition.Mois))" }
    }
}