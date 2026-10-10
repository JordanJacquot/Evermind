# Evermind

L'agenda qui se souvient de tout pour toi, petite sœur de [Nevermind](https://github.com/JordanJacquot/Nevermind).
Tu lui parles comme à quelqu'un, il note, décale, supprime, répond à tes questions, et te rappelle tes rendez-vous à voix haute.

Tout reste sur ton PC : la dictée, la voix et l'assistant tournent en local. Rien n'est envoyé sur Internet.

## État actuel (0.6.0)

- **Assistant** : une petite IA locale (Qwen3 4B avec llama.cpp) comprend ce qu'on dit librement et agit :
  « décale le dentiste à jeudi », « ajoute Paul à la soirée », « pour le foot prends mes crampons », « supprime le foot »,
  « c'est bon j'ai appelé maman », « qu'est-ce que j'ai demain ? », « annule ». Evermind vérifie tout avant d'agir
  (les dates passent par ses propres règles) et garde de quoi revenir en arrière.
- **Voix** : Ctrl + Maj + Espace (même en jeu) ou le bouton micro. Dictée Whisper, réponse avec une voix naturelle
  (Piper : Siwis, Jessica ou Pierre, au choix dans les réglages).
- **Agenda** : calendrier du mois, liste « À venir » ou du jour choisi, formulaire pour ajouter ou modifier à la main.
- **Sortes de rendez-vous** : anniversaire (revient chaque année, sans heure, avec l'âge), santé, voyage, travail,
  sport, jeu, sortie, à faire (à cocher), rendez-vous ; chacune avec son icône et sa couleur.
- **Détails** : heure de fin, lieu (itinéraire), avec qui, lien (visio, Discord), rappels voulus, choses à préparer
  (cases à cocher, idées selon la sorte), notes, important ; avertissement si deux rendez-vous tombent en même temps.
- Démarrage avec Windows, caché près de l'horloge ; Evermind.exe est une vraie application (son nom et son icône).
- Rendez-vous gardés dans `%LOCALAPPDATA%\Evermind\rendez-vous.json`, modules de voix et d'IA dans `voix\`.

À venir : rappels à voix haute dans le casque (avec baisse du son des autres applis), notification Windows,
rattrapage au démarrage.

## Pour les développeurs

- `outils\construire.ps1` : crée l'icône, `Evermind\Evermind.exe` et `Evermind.zip`.
- `outils\tester-phrases.ps1` : vérifie que les phrases en français sont bien comprises (lancé aussi par `tester.ps1`).
- `outils\tester.ps1 [-Voix <dossier>]` : lance l'app hors de l'écran dans plusieurs situations (captures dans `_test`),
  avec la dictée et l'assistant si leurs fichiers sont dans le dossier donné.
- Les fichiers téléchargés (Whisper, Piper, llama.cpp, modèles) ont des versions et des empreintes SHA-256 fixées.
- Les scripts sont en UTF-8 avec BOM (sinon PowerShell 5.1 abîme les accents).
