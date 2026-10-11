# Evermind : grand catalogue des façons de demander un rendez-vous en français.
# Au lieu d'ajouter une phrase à la fois quand une erreur arrive, ce catalogue combine systématiquement :
#   les jours (« demain », « mardi prochain », « le 1er décembre », « dans 2 semaines »...), les heures (« 15 h 30 »,
#   « 3 h de l'après-midi », « midi et demi », « 10 h et quart »...), l'ordre des mots, les débuts de phrase
#   (« ajoute », « rappelle-moi de », « j'ai »...) et les défauts de la dictée (virgules, « euh », majuscules).
# Chaque phrase est fabriquée à partir de morceaux dont on connaît le sens : la bonne réponse est donc connue.
# S'y ajoutent les répétitions, les événements sur plusieurs jours et les détails (lieu, avec qui, durée...).
# Le « maintenant » est fixé au samedi 10 octobre 2026 à 18 h 30.
#
#   .\outils\catalogue-phrases.ps1            résumé par famille, et quelques exemples de ce qui ne va pas
#   .\outils\catalogue-phrases.ps1 -Tout      toutes les erreurs
#
# Code de sortie : 0 si tout est compris, 1 sinon.
param([switch]$Tout, [int]$Exemples = 4)

$racine = Split-Path $PSScriptRoot -Parent
$Fr = [Globalization.CultureInfo]'fr-FR'
. (Join-Path $racine 'Evermind\fichiers\modules\comprendre.ps1')
$now = [datetime]'2026-10-10 18:30'
$hasard = New-Object Random 2026   # toujours le même tirage : les résultats ne changent pas d'une fois à l'autre

# ---------------------------------------------------------------------------
# 1. Jours, heures, titres, débuts de phrase : toutes les combinaisons
# ---------------------------------------------------------------------------
# Jour dit, jour attendu ; Soir : seulement avec une heure après 18 h 30 (aujourd'hui) ; Periode : accepte « matin », « soir »...
$jours = @(
    @{ D = "aujourd'hui"; J = '2026-10-10'; Soir = $true; Periode = $true }
    @{ D = 'ce soir'; J = '2026-10-10'; Soir = $true; SansHeure = '20:00' }
    @{ D = 'demain'; J = '2026-10-11'; Periode = $true }
    @{ D = 'après-demain'; J = '2026-10-12'; Periode = $true }
    @{ D = 'apres demain'; J = '2026-10-12' }
    @{ D = 'lundi'; J = '2026-10-12'; Periode = $true }
    @{ D = 'mardi'; J = '2026-10-13'; Periode = $true }
    @{ D = 'mercredi'; J = '2026-10-14'; Periode = $true }
    @{ D = 'jeudi'; J = '2026-10-15'; Periode = $true }
    @{ D = 'vendredi'; J = '2026-10-16'; Periode = $true }
    @{ D = 'dimanche'; J = '2026-10-11'; Periode = $true }
    @{ D = 'lundi prochain'; J = '2026-10-12' }
    @{ D = 'mardi prochain'; J = '2026-10-13' }
    @{ D = 'samedi prochain'; J = '2026-10-17' }
    @{ D = 'mercredi de la semaine prochaine'; J = '2026-10-14' }
    @{ D = 'le 15'; J = '2026-10-15' }
    @{ D = 'le 5'; J = '2026-11-05' }
    @{ D = 'le 15 novembre'; J = '2026-11-15' }
    @{ D = 'le 15/11'; J = '2026-11-15' }
    @{ D = 'le 15/11/2026'; J = '2026-11-15' }
    @{ D = 'le 1er décembre'; J = '2026-12-01' }
    @{ D = 'le premier décembre'; J = '2026-12-01' }
    @{ D = 'le 3 janvier'; J = '2027-01-03' }
    @{ D = 'le 3 mars 2027'; J = '2027-03-03' }
    @{ D = 'le 3 mars, 2027'; J = '2027-03-03' }
    @{ D = 'le 12 octobre 2027'; J = '2027-10-12' }
    @{ D = 'jeudi 22 octobre'; J = '2026-10-22' }
    @{ D = 'le jeudi 22 octobre'; J = '2026-10-22' }
    @{ D = 'le vingt-cinq octobre'; J = '2026-10-25' }
    @{ D = 'le 25 oct'; J = '2026-10-25' }
    @{ D = 'le 25 oct.'; J = '2026-10-25' }
    @{ D = 'le 2 févr'; J = '2027-02-02' }
    @{ D = 'dans 3 jours'; J = '2026-10-13' }
    @{ D = 'dans trois jours'; J = '2026-10-13' }
    @{ D = 'dans une semaine'; J = '2026-10-17' }
    @{ D = 'dans 2 semaines'; J = '2026-10-24' }
    @{ D = 'dans un mois'; J = '2026-11-10' }
    @{ D = 'dans 15 jours'; J = '2026-10-25' }
)
# Heure dite, heure attendue (Apres : seulement si elle est après 18 h 30, pour aujourd'hui)
$heures = @(
    @{ H = 'à 15 h'; A = '15:00' }
    @{ H = 'à 15h'; A = '15:00' }
    @{ H = 'à 15h30'; A = '15:30' }
    @{ H = 'à 15 h 30'; A = '15:30' }
    @{ H = 'à 15:30'; A = '15:30' }
    @{ H = 'à 15 heures'; A = '15:00' }
    @{ H = 'à 15 heures 30'; A = '15:30' }
    @{ H = 'à quinze heures trente'; A = '15:30' }
    @{ H = 'à 3 h de l''après-midi'; A = '15:00' }
    @{ H = 'à 9 h du matin'; A = '09:00' }
    @{ H = 'à 8 h du soir'; A = '20:00'; Apres = $true }
    @{ H = 'à midi'; A = '12:00' }
    @{ H = 'à midi et demi'; A = '12:30' }
    @{ H = 'à 14 h 45'; A = '14:45' }
    @{ H = 'vers 17 h'; A = '17:00' }
    @{ H = 'à 17 h pile'; A = '17:00' }
    @{ H = 'à 9h15'; A = '09:15' }
    @{ H = 'à 21 h'; A = '21:00'; Apres = $true }
    @{ H = 'à 21h30'; A = '21:30'; Apres = $true }
    @{ H = 'à 10 heures et quart'; A = '10:15' }
    @{ H = 'à 10 h et quart'; A = '10:15' }
    @{ H = 'à 10 h moins le quart'; A = '09:45' }
    @{ H = 'à 18 h et demie'; A = '18:30' }
    @{ H = 'à 7 h et demie du matin'; A = '07:30' }
    @{ H = 'à 20 h'; A = '20:00'; Apres = $true }
    @{ H = ''; A = 'journée'; Apres = $true }
)
$periodes = @(@{ P = 'matin'; A = '09:00' }, @{ P = 'après-midi'; A = '14:00' }, @{ P = 'soir'; A = '20:00'; Apres = $true })
# Titre dit, titre attendu (Verbe : peut suivre « rappelle-moi de », « il faut que je »)
$titres = @(
    @{ T = 'dentiste'; A = 'dentiste' }
    @{ T = 'foot'; A = 'foot' }
    @{ T = 'réunion de projet'; A = 'réunion de projet' }
    @{ T = 'coiffeur'; A = 'coiffeur' }
    @{ T = 'garage'; A = 'garage' }
    @{ T = 'resto avec Léa'; A = 'resto' }
    @{ T = 'appeler maman'; A = 'appeler maman'; Verbe = $true }
    @{ T = 'sortir les poubelles'; A = 'sortir les poubelles'; Verbe = $true }
    @{ T = 'payer le loyer'; A = 'payer le loyer'; Verbe = $true }
    @{ T = 'faire les courses'; A = 'faire les courses'; Verbe = $true }
    @{ T = 'cinéma'; A = 'cinéma' }
    @{ T = 'entretien d''embauche'; A = 'entretien d''embauche' }
    @{ T = 'kiné'; A = 'kiné' }
    @{ T = 'match de basket'; A = 'match de basket' }
)
# Début de phrase ; Verbe : demande un titre qui est une action (« rappelle-moi de payer le loyer »)
$debuts = @(
    @{ P = '' }, @{ P = 'ajoute ' }, @{ P = 'ajoute-moi ' }, @{ P = 'crée-moi ' }, @{ P = 'crée un rendez-vous ' }, @{ P = 'mets-moi ' }
    @{ P = 'note ' }, @{ P = 'programme ' }, @{ P = 'peux-tu ajouter ' }, @{ P = 'est-ce que tu peux me mettre ' }
    @{ P = 'j''aimerais que tu ajoutes ' }, @{ P = 'OK Eve, ' }, @{ P = 'euh, ' }, @{ P = 'n''oublie pas ' }
    @{ P = 'rappelle-moi de '; Verbe = $true }, @{ P = 'il faut '; Verbe = $true }, @{ P = 'je dois '; Verbe = $true }
    @{ P = 'pense à '; Verbe = $true }
)

$cas = New-Object System.Collections.ArrayList
function Add-Cas([string]$Famille, [string]$Phrase, [string]$Quand, [string]$Titre, [string]$Rep = '', [string]$Fin = '', $Morceaux) {
    [void]$cas.Add(@{ Famille = $Famille; Phrase = $Phrase; Quand = $Quand; Titre = $Titre; Rep = $Rep; Fin = $Fin; Morceaux = $Morceaux })
}
function Get-Au($Liste) { $Liste[$hasard.Next($Liste.Count)] }

foreach ($j in $jours) {
    foreach ($h in $heures) {
        if ($j.Soir -and -not $h.Apres) { continue }
        if ($j.SansHeure -and -not $h.H) { $attendu = "$($j.J) $($j.SansHeure)" }
        elseif (-not $h.H) { $attendu = "$($j.J) journée" }
        else { $attendu = "$($j.J) $($h.A)" }
        if ($j.SansHeure -and $h.H -and -not $h.Apres) { continue }
        # Trois ordres : « titre jour heure », « jour heure titre », « jour, titre, heure »
        for ($o = 0; $o -lt 3; $o++) {
            $d = Get-Au @($debuts | Where-Object { $o -eq 0 -or -not $_.Verbe })
            $t = Get-Au @($titres | Where-Object { -not $d.Verbe -or $_.Verbe })
            $phrase = switch ($o) {
                0 { "$($d.P)$($t.T) $($j.D) $($h.H)" }
                1 { "$($d.P)$($j.D) $($h.H) $($t.T)" }
                2 { "$($d.P)$($j.D), $($t.T)$(if ($h.H) { ", $($h.H)" })" }
            }
            # Défauts de la dictée : majuscule au début, point à la fin
            if ($hasard.Next(3) -eq 0) { $phrase = $phrase.Substring(0, 1).ToUpper() + $phrase.Substring(1) }
            if ($hasard.Next(3) -eq 0) { $phrase = $phrase.TrimEnd() + '.' }
            Add-Cas 'jour et heure' (($phrase -replace '\s+', ' ').Trim()) $attendu $t.A '' '' @("jour « $($j.D) »", "heure « $($h.H) »", "début « $($d.P.Trim()) »", "titre « $($t.T) »", "ordre $o")
        }
    }
    if ($j.Periode) {
        foreach ($p in $periodes) {
            if ($j.Soir -and -not $p.Apres) { continue }
            $t = Get-Au $titres
            Add-Cas 'moment de la journée' "$($t.T) $($j.D) $($p.P)" "$($j.J) $($p.A)" $t.A
        }
    }
}

# ---------------------------------------------------------------------------
# 2. Répétitions (rep : Type/Jour/Mois/Jusqua ; Intervalle et Jours notés à part)
# ---------------------------------------------------------------------------
$repetitions = @(
    , @('tous les lundis à 20 h raid', '2026-10-12 20:00', 'raid', 'semaine/1')
    , @('chaque mardi à 18 h sport', '2026-10-13 18:00', 'sport', 'semaine/2')
    , @('le mercredi à 14 h piscine toutes les semaines', '2026-10-14 14:00', 'piscine', 'semaine/3')
    , @('tous les jours à 8 h médicaments', '2026-10-11 08:00', 'médicaments', 'jour')
    , @('chaque jour à 22 h méditation', '2026-10-10 22:00', 'méditation', 'jour')
    , @('tous les matins à 7 h footing', '2026-10-11 07:00', 'footing', 'jour')
    , @('tous les soirs à 21 h appeler maman', '2026-10-10 21:00', 'appeler maman', 'jour')
    , @('le 5 de chaque mois payer le loyer', '2026-11-05 journée', 'payer le loyer', 'mois/5')
    , @('tous les mois le 28 à 10 h facture', '2026-10-28 10:00', 'facture', 'mois/28')
    , @('tous les ans le 3 mars anniversaire de mariage', '2027-03-03 journée', 'Anniversaire de mariage', 'an/3/3')
    , @('anniversaire de Tom le 14 juillet', '2027-07-14 journée', 'Anniversaire de Tom', 'an/14/7')
    , @('toutes les deux semaines le jeudi à 19 h badminton', '2026-10-15 19:00', 'badminton', 'semaine/4/x2')
    , @('tous les deux semaines le jeudi à 19 h badminton', '2026-10-15 19:00', 'badminton', 'semaine/4/x2')
    , @('toutes les trois mois le 28 à 10 h facture', '2026-10-28 10:00', 'facture', 'mois/28/x3')
    , @('un lundi sur deux à 18 h guitare', '2026-10-12 18:00', 'guitare', 'semaine/1/x2')
    , @('tous les 15 jours le samedi à 10 h marché', '2026-10-17 10:00', 'marché', 'semaine/6/x2')
    , @('en semaine à 7 h réveil', '2026-10-12 07:00', 'réveil', 'semaine/1,2,3,4,5')
    , @('du lundi au vendredi à 9 h stand-up', '2026-10-12 09:00', 'stand-up', 'semaine/1,2,3,4,5')
    , @('tous les jours de la semaine à 12 h déjeuner', '2026-10-12 12:00', 'déjeuner', 'semaine/1,2,3,4,5')
    , @('le week-end à 10 h grasse matinée', '2026-10-11 10:00', 'grasse matinée', 'semaine/6,0')
    , @('tous les week-ends à 9 h vélo', '2026-10-11 09:00', 'vélo', 'semaine/6,0')
    , @('le lundi et le jeudi à 18 h salle de sport', '2026-10-12 18:00', 'salle de sport', 'semaine/1,4')
    , @('tous les mardis et vendredis à 20 h raid', '2026-10-13 20:00', 'raid', 'semaine/2,5')
    , @('le premier lundi du mois à 19 h réunion', '2026-11-02 19:00', 'réunion', 'mois/1lundi')
    , @('chaque premier lundi du mois à 19 h réunion', '2026-11-02 19:00', 'réunion', 'mois/1lundi')
    , @('le dernier vendredi du mois à 18 h afterwork', '2026-10-30 18:00', 'afterwork', 'mois/-1vendredi')
    , @('le deuxième mardi de chaque mois à 20 h club', '2026-10-13 20:00', 'club', 'mois/2mardi')
    , @('tous les trois mois le 1er à 10 h bilan', '2026-11-01 10:00', 'bilan', 'mois/1/x3')
    , @('tous les deux jours à 8 h arroser les plantes', '2026-10-11 08:00', 'arroser les plantes', 'jour/x2')
    , @("tous les lundis d'octobre courses", '2026-10-12 journée', 'courses', 'semaine/1/2026-10-31')
    , @("tous les lundis jusqu'au 30 novembre courses", '2026-10-12 journée', 'courses', 'semaine/1/2026-11-30')
    , @("tous les mardis à partir du 3 novembre à 18 h yoga", '2026-11-03 18:00', 'yoga', 'semaine/2')
    , @("tous les jeudis à 18 h jusqu'à fin novembre piscine", '2026-10-15 18:00', 'piscine', 'semaine/4/2026-11-30')
)
foreach ($r in $repetitions) { Add-Cas 'répétition' $r[0] $r[1] $r[2] $r[3] }

# ---------------------------------------------------------------------------
# 3. Plusieurs jours, et détails
# ---------------------------------------------------------------------------
$multi = @(
    , @('ElleFest du 27 au 29 octobre', '2026-10-27 journée', 'ElleFest', '2026-10-29')
    , @('festival le 27, le 28 et le 29 octobre', '2026-10-27 journée', 'festival', '2026-10-29')
    , @('salon les 5, 6 et 7 novembre', '2026-11-05 journée', 'salon', '2026-11-07')
    , @('vacances du 20 décembre au 3 janvier', '2026-12-20 journée', 'vacances', '2027-01-03')
    , @('séminaire du lundi 2 au mercredi 4 novembre', '2026-11-02 journée', 'séminaire', '2026-11-04')
    , @('congrès pendant 3 jours à partir du 5 novembre', '2026-11-05 journée', 'congrès', '2026-11-07')
    , @('week-end à Lyon du 24 au 25 octobre', '2026-10-24 journée', 'week-end', '2026-10-25')   # « à Lyon » devient le lieu
    , @('formation du 9 au 13 novembre de 9 h à 17 h', '2026-11-09 09:00', 'formation', '2026-11-13 17:00')
    , @('ski du 6 au 13 février 2027', '2027-02-06 journée', 'ski', '2027-02-13')
    # Semaines entières (du lundi au dimanche) et week-ends
    , @('Séminaire la première semaine des trois prochains mois', '2026-11-02 journée', 'Séminaire', '2026-11-08')
    , @('séminaire durant la première semaine des 3 prochains mois', '2026-11-02 journée', 'séminaire', '2026-11-08')
    , @('séminaire la première semaine de chaque mois pendant 2 mois', '2026-11-02 journée', 'séminaire', '2026-11-08')
    , @('séminaire la semaine du 9 novembre', '2026-11-09 journée', 'séminaire', '2026-11-15')
    , @('formation la dernière semaine de novembre', '2026-11-23 journée', 'formation', '2026-11-29')
    , @('stage la première semaine de décembre', '2026-12-07 journée', 'stage', '2026-12-13')
    , @('stage la deuxième semaine du mois prochain', '2026-11-09 journée', 'stage', '2026-11-15')
    , @('vacances toute la semaine prochaine', '2026-10-12 journée', 'vacances', '2026-10-18')
    , @('camping ce week-end', '2026-10-10 journée', 'camping', '2026-10-11')
    , @('camping le week-end prochain', '2026-10-17 journée', 'camping', '2026-10-18')
    , @('conférence pendant une semaine à partir du 2 novembre', '2026-11-02 journée', 'conférence', '2026-11-08')
    , @('salon pendant deux semaines à partir du 2 novembre', '2026-11-02 journée', 'salon', '2026-11-15')
    , @('séminaire le dernier week-end octobre', '2026-10-31 journée', 'séminaire', '2026-11-01')
    , @("séminaire le dernier week-end d'octobre", '2026-10-31 journée', 'séminaire', '2026-11-01')
    , @('camping le premier week-end de novembre', '2026-11-07 journée', 'camping', '2026-11-08')
    , @('mariage le week-end du 24 octobre', '2026-10-24 journée', 'mariage', '2026-10-25')
    , @('rando les deux prochains week-ends', '2026-10-17 journée', 'rando', '2026-10-18')
    , @('stage la première semaine novembre', '2026-11-02 journée', 'stage', '2026-11-08')
    , @('yoga le premier week-end des 3 prochains mois', '2026-11-07 journée', 'yoga', '2026-11-08')
    , @('stage les 3 prochaines semaines', '2026-10-12 journée', 'stage', '2026-11-01')
)
foreach ($r in $multi) { Add-Cas 'plusieurs jours' $r[0] $r[1] $r[2] '' $r[3] }
$details = @(
    , @('crée une réunion avec Madame Dupont mardi à 15 h et que tu ouvres son dossier au début', '2026-10-13 15:00', 'réunion', '', '')
    , @('crée une réunion mardi à 15 h pour M. Richard. Et tu ouvres directement son dossier.', '2026-10-13 15:00', 'réunion pour M. Richard', '', '')
    , @('mets un café avec Paul mardi à 15 h et ouvre mes fichiers', '2026-10-13 15:00', 'café', '', '')
    , @('réunion mardi à 15 h, puis tu me lis le compte rendu', '2026-10-13 15:00', 'réunion', '', '')
    , @('dentiste mardi à 15 h pendant 1 h','2026-10-13 15:00', 'dentiste', '', '2026-10-13 16:00')
    , @('réunion lundi de 14 h à 16 h', '2026-10-12 14:00', 'réunion', '', '2026-10-12 16:00')
    , @('réunion lundi de 14h à 15h30', '2026-10-12 14:00', 'réunion', '', '2026-10-12 15:30')
    , @("soirée samedi prochain à 21 h jusqu'à 2 h", '2026-10-17 21:00', 'soirée', '', '2026-10-18 02:00')
    , @('dentiste mardi à 15 h, lieu : 12 rue des Lilas', '2026-10-13 15:00', 'dentiste', '', '')
    , @('resto avec Léa et Tom vendredi à 20 h', '2026-10-16 20:00', 'resto', '', '')
    , @('rendez-vous chez le médecin demain à 10 h', '2026-10-11 10:00', 'chez le médecin', '', '')
    , @("dentiste mardi à 15 h, c'est important", '2026-10-13 15:00', 'dentiste', '', '')
    , @('dentiste mardi à 15 h, rappelle-moi la veille', '2026-10-13 15:00', 'dentiste', '', '')
    , @('dentiste mardi à 15 h, préviens-moi 30 minutes avant', '2026-10-13 15:00', 'dentiste', '', '')
    , @('courses samedi prochain avec la liste : lait, œufs, pain', '2026-10-17 journée', 'courses', '', '')
    , @('dans 2 heures appeler le plombier', '2026-10-10 20:30', 'appeler le plombier', '', '')
    , @('dans 30 minutes sortir le gâteau', '2026-10-10 19:00', 'sortir le gâteau', '', '')
    , @('dans une demi-heure appeler Tom', '2026-10-10 19:00', 'appeler Tom', '', '')
)
foreach ($r in $details) { Add-Cas 'détails' $r[0] $r[1] $r[2] $r[3] $r[4] }

# ---------------------------------------------------------------------------
# Vérification
# ---------------------------------------------------------------------------
function Get-RepTexte($Rep) {
    if (-not $Rep) { return '' }
    $parts = @([string]$Rep.Type)
    $jrs = @($Rep.Jours | Where-Object { $null -ne $_ })
    if ($jrs.Count) { $parts += ($jrs -join ',') }
    elseif ($Rep.Rang) { $parts += "$($Rep.Rang)$(([Globalization.CultureInfo]'fr-FR').DateTimeFormat.GetDayName([DayOfWeek][int]$Rep.Jour))" }
    elseif ($null -ne $Rep.Jour -and "$($Rep.Jour)" -ne '') { $parts += [string]$Rep.Jour }
    if ($Rep.Mois) { $parts += [string]$Rep.Mois }
    if ($Rep.Intervalle -and [int]$Rep.Intervalle -gt 1) { $parts += "x$($Rep.Intervalle)" }
    if ($Rep.Jusqua) { $parts += [string]$Rep.Jusqua }
    $parts -join '/'
}
$sansAccents = { param($s) ([string]$s).ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '' -replace '[^a-z0-9 ]', ' ' -replace '\s+', ' ' }
$parFamille = [ordered]@{}
$erreurs = New-Object System.Collections.ArrayList
foreach ($c in $cas) {
    $p = Read-Phrase $c.Phrase $now
    $quand = if ($p.Manque) { "($($p.Manque))" } elseif ($p.Journee) { $p.Quand.ToString('yyyy-MM-dd') + ' journée' } else { $p.Quand.ToString('yyyy-MM-dd HH:mm') }
    $rep = Get-RepTexte $p.Repetition
    $fin = if ($c.Fin -and $p.Fin) { ([datetime]$p.Fin).ToString($(if ($c.Fin.Length -gt 10) { 'yyyy-MM-dd HH:mm' } else { 'yyyy-MM-dd' })) } elseif ($c.Fin) { '(aucune)' } else { '' }
    $bonTitre = (& $sansAccents $p.Titre).Trim() -eq (& $sansAccents $c.Titre).Trim()
    $bon = $quand -eq $c.Quand -and $bonTitre -and $rep -eq $c.Rep -and $fin -eq $c.Fin
    if (-not $parFamille.Contains($c.Famille)) { $parFamille[$c.Famille] = @{ Total = 0; Bon = 0 } }
    $parFamille[$c.Famille].Total++
    if ($bon) { $parFamille[$c.Famille].Bon++ }
    else { [void]$erreurs.Add(@{ Morceaux = $c.Morceaux; Famille = $c.Famille; Phrase = $c.Phrase; Attendu = "$($c.Quand) | $($c.Titre) | $($c.Rep) | $($c.Fin)"; Obtenu = "$quand | $($p.Titre) | $rep | $fin" }) }
}

$total = 0; $bons = 0
foreach ($f in $parFamille.Keys) {
    $x = $parFamille[$f]; $total += $x.Total; $bons += $x.Bon
    $couleur = if ($x.Bon -eq $x.Total) { 'Green' } else { 'Yellow' }
    Write-Host ("{0,-22} {1,5} / {2,-5}" -f $f, $x.Bon, $x.Total) -ForegroundColor $couleur
    $liste = @($erreurs | Where-Object { $_.Famille -eq $f })
    foreach ($e in $(if ($Tout) { $liste } else { $liste | Select-Object -First $Exemples })) {
        Write-Host "    « $($e.Phrase) »" -ForegroundColor Red
        Write-Host "        attendu : $($e.Attendu)"
        Write-Host "        obtenu  : $($e.Obtenu)"
    }
}
# Les morceaux qui font échouer le plus de phrases (pour corriger par paquets)
$compte = @{}
foreach ($e in $erreurs) { foreach ($m in @($e.Morceaux)) { if ($m) { $compte[$m] = 1 + [int]$compte[$m] } } }
if ($compte.Count) {
    Write-Host ''
    Write-Host 'Morceaux en cause (nombre de phrases ratées) :'
    $compte.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { Write-Host ("    {0,4}  {1}" -f $_.Value, $_.Key) }
}
Write-Host ''
Write-Host "Catalogue : $bons / $total phrases comprises" -ForegroundColor $(if ($bons -eq $total) { 'Green' } else { 'Yellow' })
exit $(if ($bons -eq $total) { 0 } else { 1 })
