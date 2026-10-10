# Vérifie que Evermind comprend bien les phrases en français de tous les jours.
# Le « maintenant » est fixé au samedi 10 octobre 2026 à 18 h 30 pour que les résultats ne changent pas.
#
#   .\outils\tester-phrases.ps1
#
# Code de sortie : 0 si toutes les phrases sont comprises comme prévu, 1 sinon.

$racine = Split-Path $PSScriptRoot -Parent
. (Join-Path $racine 'Evermind\fichiers\modules\comprendre.ps1')
$now = [datetime]'2026-10-10 18:30'

# Phrase, puis ce qu'on attend : « date heure », titre, répétition (Type/Jour/Mois) ou manque
$cas = @(
    , @('le 27 février, rendez-vous dentiste à 15 h', '2027-02-27 15:00', 'dentiste')
    , @('demain à 18 h foot', '2026-10-11 18:00', 'foot')
    , @('après-demain à 9h coiffeur', '2026-10-12 09:00', 'coiffeur')
    , @('apres demain a 9h coiffeur', '2026-10-12 09:00', 'coiffeur')
    , @('mardi prochain à 15 h 30 dentiste', '2026-10-13 15:30', 'dentiste')
    , @('dans 3 jours appeler maman à midi', '2026-10-13 12:00', 'appeler maman')
    , @('dans trois jours à 14 h banque', '2026-10-13 14:00', 'banque')
    , @('dans 2 semaines à 10 h dentiste', '2026-10-24 10:00', 'dentiste')
    , @('le 27 à 10 h garage', '2026-10-27 10:00', 'garage')
    , @('le 5 à 10 h garage', '2026-11-05 10:00', 'garage')
    , @('ce soir match à 21 h', '2026-10-10 21:00', 'match')
    , @('ce soir apéro', '2026-10-10 20:00', 'apéro')
    , @('demain soir à 8 h resto', '2026-10-11 20:00', 'resto')
    , @('demain matin médecin', '2026-10-11 09:00', 'médecin')
    , @('à 3 h de l''après-midi réunion lundi', '2026-10-12 15:00', 'réunion')
    , @('vendredi à 9 h 30 du matin kiné', '2026-10-16 09:30', 'kiné')
    , @('le 1er mars à 10 h banque', '2027-03-01 10:00', 'banque')
    , @('le 27/02 à 15 h dentiste', '2027-02-27 15:00', 'dentiste')
    , @('le 12/11/2026 à 8h45 contrôle technique', '2026-11-12 08:45', 'contrôle technique')
    , @('1/12 18h noël des potes', '2026-12-01 18:00', 'noël des potes')
    , @('rdv chez le coiffeur jeudi à 14h30', '2026-10-15 14:30', 'chez le coiffeur')
    , @('j''ai rendez-vous chez le dentiste le 3 novembre à 11 h', '2026-11-03 11:00', 'chez le dentiste')
    , @("J’ai un rendez-vous chez le médecin demain à 10h", '2026-10-11 10:00', 'chez le médecin')
    , @('dans une heure sortir le linge', '2026-10-10 19:30', 'sortir le linge')
    , @('dans 30 minutes pizza', '2026-10-10 19:00', 'pizza')
    , @('dans une demi-heure appeler Tom', '2026-10-10 19:00', 'appeler Tom')
    , @('à 20 h raid', '2026-10-10 20:00', 'raid')
    , @('à 10 h piscine', '2026-10-11 10:00', 'piscine')
    , @('rendez-vous à 16h30', '2026-10-11 16:30', '')
    , @('à midi et demi déjeuner avec Paul demain', '2026-10-11 12:30', 'déjeuner', '', 'sortie', 'avec=Paul')
    , @('à 15 h et quart dentiste demain', '2026-10-11 15:15', 'dentiste')
    , @('à 9 h moins le quart demain bus', '2026-10-11 08:45', 'bus')
    , @('quinze heures trente demain dentiste', '2026-10-11 15:30', 'dentiste')
    , @('le vingt-sept février à quinze heures dentiste', '2027-02-27 15:00', 'dentiste')
    , @('à 2 h dentiste demain', '2026-10-11 14:00', 'dentiste')
    , @('samedi 24 octobre à 21 h soirée', '2026-10-24 21:00', 'soirée')
    , @('Anniversaire de Léa le 12 mars à 19 h', '2027-03-12 19:00', 'Anniversaire de Léa', 'an/12/3', 'anniv')
    , @('le mardi 20 octobre à 14 h', '2026-10-20 14:00', '')
    , @('mardi 13 à 15 h dentiste', '2026-10-13 15:00', 'dentiste')
    , @('mercredi de la semaine prochaine à 10 h réunion', '2026-10-14 10:00', 'réunion')
    , @('ce samedi à 20 h ciné', '2026-10-10 20:00', 'ciné')
    , @('samedi à 20 h ciné', '2026-10-17 20:00', 'ciné')
    , @('aujourd''hui à 19 h appel', '2026-10-10 19:00', 'appel')
    , @('rappelle-moi d''appeler le garage demain à 9 h', '2026-10-11 09:00', 'appeler le garage')
    , @('demain après-midi courses', '2026-10-11 14:00', 'courses')
    # Rendez-vous qui reviennent
    , @('tous les lundis à 20 h raid avec les potes', '2026-10-12 20:00', 'raid', 'semaine/1', 'jeu', 'avec=les potes')
    , @('chaque samedi à 18 h foot', '2026-10-17 18:00', 'foot', 'semaine/6')
    , @('chaque mois le 5 à 10 h payer le loyer', '2026-11-05 10:00', 'payer le loyer', 'mois/5')
    , @('le 15 de chaque mois à 9 h facture', '2026-10-15 09:00', 'facture', 'mois/15')
    , @('le 1er de chaque mois à 9 h relevé', '2026-11-01 09:00', 'relevé', 'mois/1')
    , @('tous les jours à 22 h médicaments', '2026-10-10 22:00', 'médicaments', 'jour')
    , @('tous les ans le 12 mars à 19 h anniversaire de Léa', '2027-03-12 19:00', 'Anniversaire de Léa', 'an/12/3', 'anniv')
    , @('toutes les semaines mardi à 18 h sport', '2026-10-13 18:00', 'sport', 'semaine/2')
    # Ordres et politesse autour du rendez-vous, sortes de rendez-vous
    , @('Créer un rdv anniversaire Jordan le 12 mars', '2027-03-12 journée', 'Anniversaire de Jordan', 'an/12/3', 'anniv')
    , @('Crée un rendez-vous chez le dentiste demain à 15 h', '2026-10-11 15:00', 'chez le dentiste', '', 'sante')
    , @('est-ce que tu peux ajouter un évènement soirée chez Max samedi à 21 h', '2026-10-17 21:00', 'soirée chez Max', '', 'sortie')
    , @('Euh, mets-moi un rendez-vous chez le médecin lundi à 9 h s''il te plaît', '2026-10-12 09:00', 'chez le médecin', '', 'sante')
    , @('note dans mon agenda raid avec les potes vendredi à 21 h', '2026-10-16 21:00', 'raid', '', 'jeu', 'avec=les potes')
    , @('ajoute foot mercredi à 19 h', '2026-10-14 19:00', 'foot', '', 'sport')
    , @('rappelle-moi de payer le loyer le 5 à 10 h', '2026-11-05 10:00', 'payer le loyer', '', 'rappel')
    , @('Je voudrais créer un événement : réunion avec le client jeudi à 14 h', '2026-10-15 14:00', 'réunion', '', 'travail', 'avec=le client')
    , @('crée un rendez-vous train pour Lyon le 2 novembre à 7 h 40', '2026-11-02 07:40', 'train pour Lyon', '', 'voyage')
    , @('anniversaire de Léa le 3 avril', '2027-04-03 journée', 'Anniversaire de Léa', 'an/3/4', 'anniv')
    , @('anniv Inès le 20 octobre', '2026-10-20 journée', 'Anniversaire d''Inès', 'an/20/10', 'anniv')
    , @('mon anniversaire le 10 octobre', '2026-10-10 journée', 'Anniversaire', 'an/10/10', 'anniv')
    , @('le 20 octobre toute la journée salon du jeu vidéo', '2026-10-20 journée', 'salon du jeu vidéo', '', 'jeu')
    , @('crée un rendez-vous garage mardi à 8 h', '2026-10-13 08:00', 'garage', '', 'rdv')
    , @('anniversaire de Léa', 'jour', 'Anniversaire de Léa', '', 'anniv')
    , @('Créer un rendez-vous le 23 octobre à minuit une anniversaire Jordan.', '2026-10-23 journée', 'Anniversaire de Jordan', 'an/23/10', 'anniv')
    , @('Crée un anniversaire pour Jordan le 23 octobre.', '2026-10-23 journée', 'Anniversaire de Jordan', 'an/23/10', 'anniv')
    , @('J''aimerais que tu me crée un rendez-vous pour le 23 octobre et que tu mettes un anniversaire Jordan.', '2026-10-23 journée', 'Anniversaire de Jordan', 'an/23/10', 'anniv')
    , @('Est-ce que tu peux me mettre un rendez-vous chez le coiffeur mardi à 10 h', '2026-10-13 10:00', 'chez le coiffeur', '', 'rdv')
    , @('je voudrais que tu notes foot avec Tom jeudi à 18 h', '2026-10-15 18:00', 'foot', '', 'sport', 'avec=Tom')
    , @('jeudi 13 octobre à 15 h dentiste', '2026-10-15 15:00', 'dentiste', '', 'sante')
    # Sans heure : toute la journée ; listes dites d'un coup
    , @('samedi faire les courses : lait, œufs et pain', '2026-10-17 journée', 'faire les courses', '', 'rappel', 'liste=Lait+Œufs+Pain')
    , @('Crée un événement faire les courses avec la liste lait, beurre, farine', '2026-10-10 journée', 'faire les courses', '', 'rappel', 'liste=Lait+Beurre+Farine')
    , @('mardi courses', '2026-10-13 journée', 'courses', '', 'rappel')
    , @('le 20 octobre salon du jeu vidéo', '2026-10-20 journée', 'salon du jeu vidéo', '', 'jeu')
    , @('dimanche ménage', '2026-10-11 journée', 'ménage', '', 'rdv')
    # Détails : avec qui, où, fin, rappels, importance, lien, âge
    , @('déjeuner avec Paul et Léa samedi à midi', '2026-10-17 12:00', 'déjeuner', '', 'sortie', 'avec=Paul+Léa')
    , @('concert au Zénith de Paris le 14 novembre de 20 h à 23 h', '2026-11-14 20:00', 'concert', '', 'sortie', 'lieu=Zénith de Paris;fin=23:00')
    , @('réunion à Paris lundi de 2 h à 4 h', '2026-10-12 14:00', 'réunion', '', 'travail', 'lieu=Paris;fin=16:00')
    , @('foot jeudi à 19 h pendant 1 h 30', '2026-10-15 19:00', 'foot', '', 'sport', 'fin=20:30')
    , @('soirée chez Max samedi à 21 h jusqu''à 2 h', '2026-10-17 21:00', 'soirée chez Max', '', 'sortie', 'fin=02:00')
    , @('dentiste mardi à 15 h, rappelle-moi 2 jours avant et 1 h avant, c''est important', '2026-10-13 15:00', 'dentiste', '', 'sante', 'rappels=m2880,m60;important')
    , @('rendez-vous banque vendredi à 10 h rappelle-moi la veille', '2026-10-16 10:00', 'banque', '', 'rdv', 'rappels=veille')
    , @('raid jeudi à 21 h https://discord.gg/abc123', '2026-10-15 21:00', 'raid', '', 'jeu', 'lien=https://discord.gg/abc123')
    , @('anniversaire de Jordan le 12 mars, il aura 25 ans', '2027-03-12 journée', 'Anniversaire de Jordan', 'an/12/3', 'anniv', 'naissance=2002')
    , @('anniversaire de Léa le 3 avril, née en 1999', '2027-04-03 journée', 'Anniversaire de Léa', 'an/3/4', 'anniv', 'naissance=1999')
    , @('visite appartement mercredi à 18 h, adresse : 12 rue des Lilas', '2026-10-14 18:00', 'visite appartement', '', 'rdv', 'lieu=12 rue des Lilas')
    # Ce qui manque ou ne va pas
    , @('demain dentiste', '2026-10-11 journée', 'dentiste')
    , @('le 27 février dentiste', '2027-02-27 journée', 'dentiste')
    , @('dentiste', 'quand', 'dentiste')
    , @('aujourd''hui à 8 h dentiste', 'passe', 'dentiste')
    , @('le 31 février à 10 h', 'invalide', '')
    , @('tous les lundis raid', '2026-10-12 journée', 'raid', 'semaine/1')
)

$ok = 0; $ko = 0
foreach ($c in $cas) {
    $p = Read-Phrase $c[0] $now
    $obtenu = if ($p.Manque) { $p.Manque } elseif ($p.Journee) { $p.Quand.ToString('yyyy-MM-dd') + ' journée' } else { $p.Quand.ToString('yyyy-MM-dd HH:mm') }
    $rep = if ($p.Repetition) { (@($p.Repetition.Type, $p.Repetition.Jour, $p.Repetition.Mois) | Where-Object { $null -ne $_ -and "$_" -ne '' }) -join '/' } else { '' }
    $attenduRep = if ($c.Count -gt 3) { $c[3] } else { '' }
    $attenduType = if ($c.Count -gt 4) { $c[4] } else { $p.Type }
    $d = @()
    if (@($p.Avec).Count) { $d += 'avec=' + (@($p.Avec) -join '+') }
    if ($p.Lieu) { $d += "lieu=$($p.Lieu)" }
    if ($p.Fin) { $d += 'fin=' + $p.Fin.ToString('HH:mm') }
    if ($p.Rappels) { $d += 'rappels=' + (@($p.Rappels) -join ',') }
    if ($p.Important) { $d += 'important' }
    if ($p.Lien) { $d += "lien=$($p.Lien)" }
    if ($p.Naissance) { $d += "naissance=$($p.Naissance)" }
    if (@($p.APreparer).Count) { $d += 'liste=' + (@($p.APreparer) -join '+') }
    $details = $d -join ';'
    $attenduDetails = if ($c.Count -gt 5) { $c[5] } else { '' }
    $bon = $obtenu -eq $c[1] -and $p.Titre -ceq $c[2] -and $rep -eq $attenduRep -and $p.Type -eq $attenduType -and $details -ceq $attenduDetails
    if ($bon) { $ok++ } else {
        $ko++
        Write-Host ("ÉCHEC  « {0} »" -f $c[0]) -ForegroundColor Red
        Write-Host ("        attendu : {0} | {1} | {2} | {3} | {4}" -f $c[1], $c[2], $attenduRep, $attenduType, $attenduDetails)
        Write-Host ("        obtenu  : {0} | {1} | {2} | {3} | {4}" -f $obtenu, $p.Titre, $rep, $p.Type, $details)
    }
}
$col = if ($ko) { 'Red' } else { 'Green' }
Write-Host "Phrases comprises : $ok / $($ok + $ko)" -ForegroundColor $col
exit [int]($ko -gt 0)
