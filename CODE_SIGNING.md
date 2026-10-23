# Code signing policy

*Version française plus bas : [Politique de signature du code](#politique-de-signature-du-code).*

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

> **Status:** the application to SignPath Foundation is in progress. Until it is accepted, the releases are not
> Authenticode signed, and the notes of each [Release](../../releases) give the SHA-256 of `Evermind.zip`.

## What is signed

- `Evermind.exe` and the PowerShell scripts (`.ps1`) of Evermind (`fichiers\Evermind.ps1` and `fichiers\modules\*.ps1`),
  all built from this repository.
- Not signed: the other files of the app cannot carry a signature (the window `interface.xaml`, the backup launcher
  `Lancer Evermind (secours).bat`, the C# sources `natif.cs` and `voix-kokoro.cs`). `natif.cs` is compiled in memory
  when Evermind starts; `voix-kokoro.cs` is compiled on your PC into `EvermindVoix.exe` (in Evermind's data folder)
  after you install the voice. Both are compiled with the C# compiler that comes with Windows.
- The `Evermind.zip` package contains no file from other authors. The voice, dictation and assistant modules are
  downloaded separately, only when you ask for them (see below); they are never in the package and never signed with
  this certificate.

## How a release is built and signed

1. The version is tagged in this repository (`v<version>`).
2. The [Release workflow](.github/workflows/release.yml) builds `Evermind.exe` on a GitHub hosted runner, from the
   tagged source only (no executable is stored in this repository), and uploads the `Evermind` folder as a workflow
   artifact.
3. The workflow sends a signing request to SignPath. SignPath checks that the artifact comes from this workflow and
   this repository. **Every signing request is approved manually** by an approver (see below).
4. The maintainer downloads the signed `Evermind.zip` produced by the workflow, adds the detached RSA signature
   `Evermind.zip.sig` (Mindset uses it to verify updates; it does not change any file inside the zip) and publishes
   the Release.

## Team and roles

| Role | Members |
|---|---|
| Committers and reviewers | [Jordan Jacquot](https://github.com/JordanJacquot) |
| Approvers | [Jordan Jacquot](https://github.com/JordanJacquot) |

- Committers can change the code of this repository. Changes proposed by anyone else (pull requests) are reviewed
  by a committer before they are merged.
- Every signing request is approved by an approver.
- All team members use multi-factor authentication on GitHub and on SignPath.

## Privacy policy

Evermind has no account, no advertising, no telemetry and no statistics. Your appointments, your settings and what
you say stay on your PC: the dictation (Whisper), the assistant (Evermind 0.6B with llama.cpp) and the voice (Kokoro)
all run on your PC. **Evermind never connects to the Internet by itself**: every connection listed below only happens
when you press a button.

### Automatic

None.

- Updates: Evermind does not look for its updates. Mindset installs and updates it (see
  [Mindset's own policy](https://github.com/JordanJacquot/Mindset/blob/main/CODE_SIGNING.md), with its switch
  "Chercher les nouvelles versions").
- A copy of Evermind that is not managed by Mindset does not start: it only shows a window that explains how to
  install Mindset. Its button opens Mindset, or the Mindset download page in your web browser. (The code that let
  older copies update themselves, `modules\maj.ps1`, is still there but never runs: such a copy stops before it,
  and a copy managed by Mindset skips it.)
- Whisper and the assistant run as small local servers that only accept connections from your PC itself
  (`127.0.0.1`): nothing goes out of your PC.
- "OK Evermind" (off by default, Réglages > Assistant > "Réagir quand je dis « OK Evermind »"): when it is on, Vosk
  listens to the microphone on your PC and only reacts to "OK Evermind"; everything else is forgotten at once. The
  sound of a request (after "OK Evermind", or with Ctrl + Shift + Space) is written to a temporary file on your PC
  (`%TEMP%`) for Whisper. Nothing is sent.

### Only when you ask for it (a button)

Each module is downloaded once, from fixed addresses, with a fixed version: every file must have exactly the expected
SHA-256, otherwise it is refused. The requests are standard HTTPS requests (user agent `Evermind`) and send nothing
about you. Downloads from `github.com` are served by `objects.githubusercontent.com` or
`release-assets.githubusercontent.com`.

| What | Button | Downloaded from |
|---|---|---|
| The voice: dictation and natural voice (531 MB) | "Installer la voix" | whisper.cpp from `github.com/ggml-org/whisper.cpp`; the French model from `huggingface.co/ggerganov/whisper.cpp`; the voice engine sherpa-onnx from `api.nuget.org`; the Kokoro voice model from `github.com/k2-fsa/sherpa-onnx` |
| The assistant (693 MB) | "Installer l'assistant" | llama.cpp from `github.com/ggml-org/llama.cpp`; the Evermind 0.6B model and the assistant program from `github.com/JordanJacquot/Evermind-Mobile`; Java (Eclipse Temurin 21) from `github.com/adoptium/temurin21-binaries` |
| Listening for "OK Evermind" (54 MB) | Turning on "Réagir quand je dis « OK Evermind »" the first time | Vosk from `github.com/alphacep/vosk-api`; the small French model from `alphacephei.com` |
| A link saved in an appointment | "Ouvrir" | It opens in your web browser |
| The route to the place of an appointment | "Itinéraire" | Google Maps opens in your web browser, with the place you wrote |
| Mindset (copy outside Mindset only) | "Télécharger Mindset" | Mindset's download page on GitHub opens in your web browser |

### Third party components (downloaded separately, never signed by us)

| Component | Author | License |
|---|---|---|
| whisper.cpp 1.9.2 (`whisper-cli.exe`, `whisper-server.exe` and their DLLs) | ggml-org | MIT |
| Whisper small model (`ggml-small-q5_1.bin`) | OpenAI, converted by ggerganov | MIT |
| sherpa-onnx 1.13.8 (`sherpa-onnx.dll`, `sherpa-onnx-c-api.dll`) with ONNX Runtime (`onnxruntime.dll`) | k2-fsa; Microsoft | Apache 2.0; MIT |
| Kokoro multi-lang v1.0 voice model, with the eSpeak NG pronunciation data | hexgrad, packaged by k2-fsa; eSpeak NG | Apache 2.0; GPL 3.0 (its `LICENSE` file is kept next to the model) |
| llama.cpp b11541, Vulkan build (`llama-server.exe` and its DLLs) | ggml-org | MIT |
| Evermind 0.6B model | trained for Evermind from Qwen3 0.6B (Alibaba Qwen) | Apache 2.0 (Qwen3) |
| Assistant program (`assistant-pc.jar` and the Kotlin libraries it uses) | the author of Evermind (source in the Evermind-Mobile repository); JetBrains and Google for the libraries | Apache 2.0 for the libraries |
| Eclipse Temurin 21 (Java runtime) | Adoptium | GPL 2.0 with the Classpath Exception |
| Vosk 0.3.45 (`libvosk.dll`, with the GCC runtime DLLs) | Alpha Cephei | Apache 2.0 (GCC runtime: GPL with the GCC Runtime Library Exception) |
| Vosk small French model 0.22 | Alpha Cephei | Apache 2.0 |

The assistant program is a small Java program, the same assistant as in Evermind Mobile: its rules understand the
common requests, and for long sentences it starts `llama-server` with the Evermind 0.6B model on `127.0.0.1`. Evermind
sends it the sentence and the agenda through a pipe, it answers with what to say and the new agenda. It only runs on
your PC, below normal priority, and stops after 10 minutes without a question.

## System changes and uninstallation

- Evermind changes no Windows setting. It writes in its data folder (`%LOCALAPPDATA%\Mindset\Evermind`, or
  `X:\Mindset\Donnees\Evermind` when Mindset is installed on another drive): appointments, settings, journal, and the
  modules you downloaded (`voix` subfolder); in Mindset's folder (`%LOCALAPPDATA%\Mindset`) to share the theme of the
  suite and ask Mindset to show its page; and temporary files in `%TEMP%`. Mindset starts it with Windows; an old "Evermind" start entry of the
  user (`HKCU\...\Run`) that starts the same copy is removed.
- Evermind is uninstalled from Mindset (its card), or together with Mindset. Its program files are removed. Its data
  folder is kept, so that a new installation finds everything again; the uninstaller of Mindset has a box "Supprimer
  aussi mes données" that deletes it too, and you can also delete this folder by hand.

---

# Politique de signature du code

Signature gratuite du code fournie par [SignPath.io](https://about.signpath.io), certificat de la
[SignPath Foundation](https://signpath.org).

> **Où on en est :** la demande auprès de la SignPath Foundation est en cours. En attendant, les versions ne sont pas
> signées (Authenticode), et les notes de chaque [version publiée](../../releases) donnent l'empreinte SHA-256 de
> `Evermind.zip`.

## Ce qui est signé

- `Evermind.exe` et les scripts PowerShell (`.ps1`) d'Evermind (`fichiers\Evermind.ps1` et
  `fichiers\modules\*.ps1`), tous construits depuis ce dépôt.
- Pas signés : les autres fichiers de l'appli ne peuvent pas porter de signature (la fenêtre `interface.xaml`, le
  lanceur de secours `Lancer Evermind (secours).bat`, les sources C# `natif.cs` et `voix-kokoro.cs`). `natif.cs` est
  compilé en mémoire au lancement d'Evermind ; `voix-kokoro.cs` est compilé sur ton PC en `EvermindVoix.exe` (dans le
  dossier de données d'Evermind) après l'installation de la voix. Les deux sont compilés par le compilateur C# fourni
  avec Windows.
- Le paquet `Evermind.zip` ne contient aucun fichier d'autres auteurs. Les modules de voix, de dictée et de
  l'assistant sont téléchargés à part, seulement quand tu le demandes (voir plus bas) ; ils ne sont jamais dans le
  paquet et jamais signés avec ce certificat.

## Comment une version est construite et signée

1. La version reçoit son étiquette dans ce dépôt (`v<version>`).
2. Le [workflow Release](.github/workflows/release.yml) construit `Evermind.exe` sur une machine de GitHub,
   seulement depuis le code de cette étiquette (aucun programme n'est gardé dans ce dépôt), et dépose le dossier
   `Evermind` comme artefact.
3. Le workflow envoie une demande de signature à SignPath, qui vérifie que l'artefact vient bien de ce workflow et de
   ce dépôt. **Chaque demande est approuvée à la main** par un approbateur (voir plus bas).
4. Le responsable récupère le `Evermind.zip` signé construit par le workflow, ajoute la signature RSA séparée
   `Evermind.zip.sig` (Mindset s'en sert pour vérifier les mises à jour ; elle ne change aucun fichier du zip) et
   publie la version.

## Équipe et rôles

| Rôle | Membres |
|---|---|
| Auteurs et relecteurs | [Jordan Jacquot](https://github.com/JordanJacquot) |
| Approbateurs | [Jordan Jacquot](https://github.com/JordanJacquot) |

- Les auteurs peuvent modifier le code de ce dépôt. Les changements proposés par quelqu'un d'autre (pull requests)
  sont relus par un auteur avant d'être acceptés.
- Chaque demande de signature est approuvée par un approbateur.
- Tous les membres de l'équipe utilisent la double authentification sur GitHub et sur SignPath.

## Confidentialité

Evermind n'a ni compte, ni publicité, ni télémétrie, ni statistiques. Tes rendez-vous, tes réglages et ce que tu dis
restent sur ton PC : la dictée (Whisper), l'assistant (Evermind 0.6B avec llama.cpp) et la voix (Kokoro) tournent
tous sur ton PC. **Evermind ne se connecte jamais à Internet tout seul** : chaque connexion de la liste plus bas ne
part que quand tu appuies sur un bouton.

### Automatiques

Aucune.

- Mises à jour : Evermind ne cherche pas ses mises à jour. C'est Mindset qui l'installe et le met à jour (voir
  [la politique de Mindset](https://github.com/JordanJacquot/Mindset/blob/main/CODE_SIGNING.md), avec son
  interrupteur « Chercher les nouvelles versions »).
- Une copie d'Evermind qui n'est pas gérée par Mindset ne démarre pas : elle montre seulement une fenêtre qui explique
  comment installer Mindset. Son bouton ouvre Mindset, ou la page de téléchargement de Mindset dans ton navigateur.
  (Le code qui permettait aux anciennes copies de se mettre à jour seules, `modules\maj.ps1`, est encore là mais ne
  tourne jamais : une telle copie s'arrête avant, et une copie gérée par Mindset le saute.)
- Whisper et l'assistant tournent comme de petits serveurs locaux qui n'acceptent que les connexions venant de ton
  PC lui-même (`127.0.0.1`) : rien ne sort de ton PC.
- « OK Evermind » (coupé au départ, Réglages > Assistant > « Réagir quand je dis « OK Evermind » ») : quand il est
  activé, Vosk écoute le micro sur ton PC et ne réagit qu'à « OK Evermind » ; tout le reste est oublié aussitôt. Le son
  d'une demande (après « OK Evermind », ou avec Ctrl + Maj + Espace) est écrit dans un fichier temporaire sur ton PC
  (`%TEMP%`) pour Whisper. Rien n'est envoyé.

### Seulement quand tu le demandes (un bouton)

Chaque module est téléchargé une seule fois, depuis des adresses fixes, dans une version fixe : chaque fichier doit
avoir exactement l'empreinte SHA-256 attendue, sinon il est refusé. Ce sont des demandes HTTPS ordinaires (nom du
programme `Evermind`), qui n'envoient rien sur toi. Les téléchargements depuis `github.com` sont servis par
`objects.githubusercontent.com` ou `release-assets.githubusercontent.com`.

| Quoi | Bouton | Téléchargé depuis |
|---|---|---|
| La voix : dictée et voix naturelle (531 Mo) | « Installer la voix » | whisper.cpp depuis `github.com/ggml-org/whisper.cpp` ; le modèle de français depuis `huggingface.co/ggerganov/whisper.cpp` ; le moteur de la voix sherpa-onnx depuis `api.nuget.org` ; le modèle de voix Kokoro depuis `github.com/k2-fsa/sherpa-onnx` |
| L'assistant (693 Mo) | « Installer l'assistant » | llama.cpp depuis `github.com/ggml-org/llama.cpp` ; le modèle Evermind 0.6B et le programme de l'assistant depuis `github.com/JordanJacquot/Evermind-Mobile` ; Java (Eclipse Temurin 21) depuis `github.com/adoptium/temurin21-binaries` |
| L'écoute de « OK Evermind » (54 Mo) | La première fois que tu actives « Réagir quand je dis « OK Evermind » » | Vosk depuis `github.com/alphacep/vosk-api` ; le petit modèle de français depuis `alphacephei.com` |
| Un lien noté dans un rendez-vous | « Ouvrir » | Il s'ouvre dans ton navigateur |
| Le chemin jusqu'au lieu d'un rendez-vous | « Itinéraire » | Google Maps s'ouvre dans ton navigateur, avec le lieu que tu as écrit |
| Mindset (seulement pour une copie hors de Mindset) | « Télécharger Mindset » | La page de téléchargement de Mindset sur GitHub s'ouvre dans ton navigateur |

### Composants d'autres auteurs (téléchargés à part, jamais signés par nous)

| Composant | Auteur | Licence |
|---|---|---|
| whisper.cpp 1.9.2 (`whisper-cli.exe`, `whisper-server.exe` et leurs DLL) | ggml-org | MIT |
| Modèle Whisper small (`ggml-small-q5_1.bin`) | OpenAI, converti par ggerganov | MIT |
| sherpa-onnx 1.13.8 (`sherpa-onnx.dll`, `sherpa-onnx-c-api.dll`) avec ONNX Runtime (`onnxruntime.dll`) | k2-fsa ; Microsoft | Apache 2.0 ; MIT |
| Modèle de voix Kokoro multi-lang v1.0, avec les données de prononciation d'eSpeak NG | hexgrad, préparé par k2-fsa ; eSpeak NG | Apache 2.0 ; GPL 3.0 (son fichier `LICENSE` est gardé à côté du modèle) |
| llama.cpp b11541, version Vulkan (`llama-server.exe` et ses DLL) | ggml-org | MIT |
| Modèle Evermind 0.6B | entraîné pour Evermind à partir de Qwen3 0.6B (Alibaba Qwen) | Apache 2.0 (Qwen3) |
| Programme de l'assistant (`assistant-pc.jar` et les bibliothèques Kotlin qu'il utilise) | l'auteur d'Evermind (code dans le dépôt Evermind-Mobile) ; JetBrains et Google pour les bibliothèques | Apache 2.0 pour les bibliothèques |
| Eclipse Temurin 21 (Java) | Adoptium | GPL 2.0 avec l'exception Classpath |
| Vosk 0.3.45 (`libvosk.dll`, avec les DLL d'exécution de GCC) | Alpha Cephei | Apache 2.0 (DLL de GCC : GPL avec l'exception GCC Runtime Library) |
| Petit modèle de français de Vosk 0.22 | Alpha Cephei | Apache 2.0 |

Le programme de l'assistant est un petit programme Java, le même assistant que dans Evermind Mobile : ses règles
comprennent les demandes courantes, et pour les phrases longues il lance `llama-server` avec le modèle Evermind 0.6B
sur `127.0.0.1`. Evermind lui passe la phrase et l'agenda par un tuyau interne, il répond ce qu'il faut dire et le
nouvel agenda. Il tourne seulement sur ton PC, en priorité basse, et s'arrête après 10 minutes sans question.

## Ce qui change sur le PC, et la désinstallation

- Evermind ne modifie aucun réglage de Windows. Il écrit dans son dossier de données
  (`%LOCALAPPDATA%\Mindset\Evermind`, ou `X:\Mindset\Donnees\Evermind` quand Mindset est installé sur un autre disque) :
  rendez-vous, réglages, journal, et les modules que tu as téléchargés (sous-dossier `voix`) ; dans le dossier de
  Mindset (`%LOCALAPPDATA%\Mindset`), pour partager le thème de la suite et demander à Mindset d'afficher sa page ; et
  des fichiers temporaires dans `%TEMP%`. C'est Mindset qui le
  lance avec Windows ; une ancienne entrée de démarrage « Evermind » de l'utilisateur (`HKCU\...\Run`) qui lance la
  même copie est retirée.
- Evermind se désinstalle depuis Mindset (sa carte), ou avec Mindset. Ses programmes sont supprimés. Son dossier de
  données est gardé, pour qu'une nouvelle installation retrouve tout ; le désinstalleur de Mindset a une case
  « Supprimer aussi mes données » qui le supprime aussi, et tu peux aussi supprimer ce dossier à la main.
