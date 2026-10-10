# Evermind

L'agenda qui se souvient de tout pour toi, petite sœur de [Nevermind](https://github.com/JordanJacquot/Nevermind).
Tu notes tes rendez-vous, Evermind te les rappelle à voix haute dans le casque, même en pleine partie.

Tout reste sur ton PC : rien n'est envoyé sur Internet.

## État actuel (0.1.0)

- Fenêtre « Néon verre » : ajouter un rendez-vous (quoi, quel jour, quelle heure), liste « À venir », suppression.
- Démarrage avec Windows (activé par défaut), caché près de l'horloge.
- La croix garde Evermind près de l'horloge ; clic droit sur son icône puis « Quitter » pour le fermer.
- Rendez-vous gardés dans `%LOCALAPPDATA%\Evermind\rendez-vous.json`.

À venir : saisie en français de tous les jours, rappels à voix haute, raccourci clavier et dictée, vue mois, réglages.

## Pour les développeurs

- `outils\construire.ps1` : crée l'icône, `Evermind\Evermind.exe` et `Evermind.zip`.
- `outils\tester.ps1` : lance l'app hors de l'écran avec des données de test et enregistre une capture dans `_test`.
- Les scripts sont en UTF-8 avec BOM (sinon PowerShell 5.1 abîme les accents).
