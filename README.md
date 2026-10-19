# Evermind

L'agenda qui se souvient de tout pour toi, petite sœur de [Nevermind](https://github.com/JordanJacquot/Nevermind).
Tu lui parles comme à quelqu'un : il note, décale, supprime, répond à tes questions, ouvre les bons dossiers à
l'heure de tes réunions et te rappelle tes rendez-vous.

Tout reste sur ton PC : la dictée, la voix et l'assistant tournent en local. Rien n'est envoyé sur Internet.

## Installer

Evermind s'installe avec **[Mindset](https://github.com/JordanJacquot/Mindset/releases/latest)**, le portail de la suite :
installe Mindset, puis Evermind depuis Mindset, qui le garde ensuite à jour et le lance avec Windows. La voix et l'assistant
s'installent ensuite dans Evermind, comme avant (un clic, téléchargés une seule fois, puis tout marche sans Internet).
Tu avais déjà un Evermind ? Mindset le reprend sans rien perdre : rendez-vous, réglages, voix et assistant restent.

Il faut Windows 10 ou 11 (64 bits) et au moins 8 Go de mémoire. Avec une carte graphique, l'assistant répond plus vite.

## Ce qu'il sait faire (0.11.0)

- **Parler à Evermind** : dis « OK Evermind » (ou Ctrl + Maj + Espace, même en jeu), puis « décale le dentiste à jeudi »,
  « supprime tous les raids de novembre », « pour le foot prends mes crampons », « qu'est-ce que j'ai demain ? »,
  « annule ». L'assistant d'Evermind Mobile comprend (ses règles pour les demandes
  courantes, tout de suite ; son modèle entraîné, Evermind 0.6B avec llama.cpp, pour les phrases longues), Evermind
  vérifie tout avant d'agir et garde de quoi revenir en arrière. Elle répond avec une voix naturelle (Kokoro, 5 voix françaises).
- **Écrire ou dicter un rendez-vous** : « mardi prochain à 15 h dentiste », « foot tous les lundis à 19 h sauf en
  novembre », « séminaire la première semaine des trois prochains mois », « ElleFest du 27 au 29 octobre ».
- **Agenda** : calendrier du mois, liste « À venir » ou du jour choisi, fiche détaillée, formulaire.
  Les rendez-vous passés sont validés tout seuls (✓) et peuvent toujours être décalés.
- **Sortes de rendez-vous** : anniversaire (avec l'âge), santé, voyage, travail, sport, jeu, sortie, à faire,
  rendez-vous ; chacune avec son icône et sa couleur.
- **Détails** : heure de fin, lieu (itinéraire), avec qui, lien, notes, choses à préparer, important ;
  avertissement si deux rendez-vous tombent en même temps.
- **Dossiers et fichiers** : « réunion avec Monsieur Richard » relie tout seul son dossier (trouvé sur le Bureau,
  dans les Documents ou les dossiers choisis) ; Evermind peut l'ouvrir tout de suite ou à l'heure de la réunion.
- **Rappels** : la veille, le matin même, 1 h avant... dans une alerte aux couleurs d'Evermind
  (« Voir », « Dans 10 min »).
- **Réglages** : casque et micro par défaut, voix, assistant, thèmes de couleur et thèmes personnalisés à importer,
  dossiers où chercher, ce que fait la croix (réduire près de l'horloge ou quitter).

## Pour les développeurs

- `outils\construire.ps1` : crée l'icône, `Evermind\Evermind.exe` et `release\Evermind.zip` (Evermind fermé ; le zip n'est pas
  dans le dépôt). `outils\publier.ps1 -Version x.y.z` le signe et le publie dans une Release, où Mindset le prend.
- `outils\tester.ps1 [-Voix <dossier>]` : tous les tests. Les phrases (`catalogue-phrases.ps1`, près de 3 000),
  les demandes à l'assistant (`catalogue-assistant.ps1`), les dossiers et les rappels, puis l'app lancée hors de
  l'écran dans une cinquantaine de situations (captures dans `_test`).
- Les erreurs de compréhension se corrigent par familles de phrases, avec un exemple ajouté aux catalogues.
- Les fichiers téléchargés (Whisper, Kokoro, llama.cpp, Vosk, modèles) ont des versions et des empreintes fixées.
- Les scripts sont en UTF-8 avec BOM (sinon PowerShell 5.1 abîme les accents).
- Les thèmes personnalisés (images de personnages) ne sont pas dans le dépôt.
