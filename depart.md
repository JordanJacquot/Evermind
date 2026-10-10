# Evermind : document de départ

Evermind est une nouvelle app Windows, petite sœur de Nevermind (même auteur, même style). Nevermind veut dire « oublie » ; Evermind se souvient de tout pour toi.
C'est un agenda qu'on remplit à la voix et qui te rappelle tes rendez-vous à voix haute, dans le casque, même en pleine partie.
Elle est faite pour moi et mes potes : elle doit rester très simple à utiliser (aucune connaissance informatique nécessaire).

## Ce que fait l'app

1. **Ajouter un rendez-vous à la voix**
   - Un raccourci clavier global (par exemple Ctrl + Maj + Espace) qui marche même en jeu : j'appuie, je parle, je relâche (ou il s'arrête tout seul quand je me tais).
   - Exemple : « le 27 février, rendez-vous dentiste à 15 h ».
   - L'app répond à voix haute pour confirmer : « C'est noté : dentiste, vendredi 27 février à 15 h ». Si elle n'a pas compris la date ou l'heure, elle le dit et me laisse corriger.
   - On peut aussi taper le rendez-vous au clavier.

2. **Comprendre le français de tous les jours**
   - « demain », « après-demain », « mardi prochain », « dans 3 jours », « le 27 », « le 27 février », « à 15 h », « à 15 h 30 », « à midi », « ce soir ».
   - Rendez-vous qui reviennent : « tous les lundis », « chaque mois le 5 ».
   - Règles écrites dans l'app, pas d'IA en ligne ni de clé.

3. **Rappeler à voix haute, dans le casque**
   - Par défaut : la veille (heure choisie, par exemple 20 h), le jour même le matin, et 1 h avant. Réglable par rendez-vous et dans les réglages.
   - Exemple : « N'oublie pas ton rendez-vous chez le dentiste demain à 15 h ».
   - Pendant le rappel, le son des autres applis (le jeu, Discord) baisse automatiquement, puis remonte.
   - Une notification Windows reste affichée en plus.
   - Si le PC était éteint à l'heure du rappel, il est donné dès le prochain démarrage.

4. **Un petit agenda à l'écran** pour voir, modifier, supprimer ses rendez-vous (vue liste « à venir » et vue mois).

5. **Démarrage avec Windows**, discret près de l'horloge, pour que les rappels marchent toujours.

## Choix techniques à valider au début

- **Reconnaissance vocale** : trois options.
  - Celle de Windows hors ligne (déjà installée en français, mais moyenne sur les phrases libres).
  - La dictée en ligne de Windows (meilleure, mais la voix part chez Microsoft).
  - **Whisper en local** (whisper.cpp, modèle « small » ou « base » en français, environ 150 Mo téléchargés une fois) : excellente compréhension, tout reste sur le PC. C'est l'option conseillée.
- **Voix** : voix françaises de Windows déjà présentes (Hortense, et les voix modernes Julie et Paul). Les voix modernes ne sont pas visibles par System.Speech : passer par l'API Windows.Media.SpeechSynthesis. Faire écouter les trois voix et laisser choisir dans les réglages.
- **Baisse du son des autres applis** : par les sessions audio de Windows (volume par application), en remettant exactement le volume d'avant.
- **Base technique** : la même que Nevermind pour réutiliser ce qui marche déjà (PowerShell + WPF, fonctions natives en C# compilées au lancement, lanceur .exe, mises à jour par les « releases » GitHub, tests automatiques avec captures d'écran). Limite connue : le « Contrôle intelligent des applications » de Windows bloque les apps non signées.
- **Données** : un fichier local (JSON) dans le dossier de données de l'app. Rien n'est envoyé sur Internet.

## Style et règles à respecter

- Tout en français, aucun tiret long (cadratin ou demi-cadratin) dans les fichiers ni dans les réponses.
- Même DA que Nevermind : « Néon verre » (fond de nuit, panneaux de verre translucides, accents cyan, violet, magenta, boutons en pilule). Logo : le N glitché de Nevermind devient un E.
- Ultra simple pour quelqu'un qui n'y connaît rien : phrases courtes, gros boutons, aucun jargon.
- Fichiers de script en UTF-8 avec BOM (PowerShell 5.1 abîme les accents sinon).
- Ne jamais injecter quoi que ce soit dans un jeu : Evermind parle par la sortie audio normale de Windows, elle ne touche pas aux jeux.

## Ordre de construction proposé

1. Socle : fenêtre, DA, démarrage avec Windows, icône près de l'horloge, fichier des rendez-vous.
2. Saisie au clavier + compréhension des dates en français (avec des tests sur beaucoup de phrases).
3. Rappels à voix haute + notification + baisse du son des autres applis + rattrapage au démarrage.
4. Raccourci global + enregistrement du micro + reconnaissance vocale (Whisper).
5. Agenda à l'écran (liste et mois), réglages (voix, heures des rappels, raccourci).
6. Installateur, mises à jour, tests automatiques, puis test par les potes.
