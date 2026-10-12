# Evermind : l'assistant. Une petite IA (Qwen3 4B, lancée avec llama.cpp) tourne sur le PC, comprend ce qu'on
# lui dit librement et répond avec ce qu'Evermind doit faire. Evermind vérifie tout avant d'agir :
#   - les dates passent par ses propres règles (comprendre.ps1), jamais par un calcul de l'IA ;
#   - un rendez-vous à modifier ou supprimer doit exister dans l'agenda ;
#   - avant chaque changement, l'agenda est mis de côté : « annule » revient en arrière.
# Rien ne part sur Internet. L'IA s'arrête après 10 minutes sans question, pour laisser la mémoire aux jeux.
# Chargé par Evermind.ps1, qui définit $AppDir et $ModulesDir.

$CerveauVeille = 600   # secondes sans question avant d'arrêter l'IA

# Phrases qui ne sont pas un nouveau rendez-vous mais une demande (décaler, supprimer, question...)
$RxCommande = "^\s*(?:(?:euh\s*,?\s*)?(?:est-ce que tu (?:peux|pourrais)|tu (?:peux|pourrais)|peux-tu|pourrais-tu|(?:j'aimerais|je voudrais|je veux|il faut) que tu)\s+(?:me\s+|m')?)?(?:d[ée]cale|d[ée]place|repousse|avance|reporte|change|modifie|renomme|supprime[rsz]?|enl[èe]ve[rsz]?|efface[rsz]?|retire[rsz]?|annule[rsz]?|ajoute\s+\S+.*\s+(?:à|au|aux)\s+(?:la|le|l'|mon|ma|mes|ce|cette)\b|j'ai (?:fini|fait|appel|pay|achet)|c'est (?:fait|bon)|qu'est-ce|quand|est-ce que j'ai|combien|quels?|quelles?|dis-moi|montre|liste|rappelle-moi (?:quand|ce que))|\?\s*$"
function Test-EstCommande([string]$Texte) { $Texte -match $RxCommande }

# ---------------------------------------------------------------------------
# Démarrer et arrêter l'IA
# ---------------------------------------------------------------------------
function Start-Cerveau {
    if (-not (Test-CerveauInstalle)) { return $false }
    if ($script:Cerveau -and -not $script:Cerveau.Process.HasExited) { $script:Cerveau.Dernier = Get-Date; return $true }
    try {
        $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
        $threads = [math]::Max(2, [math]::Min(8, [int]([Environment]::ProcessorCount / 2)))
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $LlamaExe
        # -ngl 99 : tout sur la carte graphique s'il y en a une (Vulkan), sinon le processeur fait le travail
        $psi.Arguments = "-m `"$IaModele`" --host 127.0.0.1 --port $port -ngl 99 -c 8192 -t $threads --no-webui"
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $IaDir
        $p = [Diagnostics.Process]::Start($psi)
    } catch { Write-Log "Assistant impossible à démarrer : $_"; return $false }
    try { $p.PriorityClass = 'BelowNormal' } catch {}   # (un jeu passe avant)
    $script:Cerveau = @{ Process = $p; Port = $port; Dernier = Get-Date }
    Write-Log "Assistant démarré (port $port)"
    if (-not $script:CerveauTimer) {
        $script:CerveauTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:CerveauTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:CerveauTimer.Add_Tick({
            # En veille après 10 minutes sans question : la mémoire est rendue aux jeux
            $c = $script:Cerveau
            if (-not $c -or $c.Process.HasExited) { $script:CerveauTimer.Stop(); return }
            if (-not $script:Demande -and ((Get-Date) - $c.Dernier).TotalSeconds -gt $CerveauVeille) { Stop-Cerveau; Write-Log 'Assistant mis en veille' }
        })
    }
    $script:CerveauTimer.Start()
    $true
}

function Stop-Cerveau {
    $c = $script:Cerveau
    $script:Cerveau = $null
    if ($c) { try { if (-not $c.Process.HasExited) { $c.Process.Kill() } } catch {} }
}

# ---------------------------------------------------------------------------
# Ce que l'IA sait : la date, l'heure et l'agenda (avec un code court par rendez-vous)
# ---------------------------------------------------------------------------
function Get-ContexteIA {
    $now = Get-Date; $today = $now.Date
    $vus = @{}; $liste = New-Object System.Collections.ArrayList
    foreach ($it in (Get-AgendaEntre $today $today.AddDays(90))) { if (-not $vus.ContainsKey($it.RV.Id)) { $vus[$it.RV.Id] = 1; [void]$liste.Add($it) } }
    foreach ($r in $script:Agenda) {
        if ($vus.ContainsKey($r.Id)) { continue }
        $n = Get-NextOccurrence $r.Repetition $r.Quand $today
        if ($n -ge $today) { $vus[$r.Id] = 1; [void]$liste.Add([pscustomobject]@{ RV = $r; Prochain = $n }) }
    }
    $codes = @{}; $lignes = @()
    # Les rendez-vous des 30 derniers jours viennent après (« supprime le coiffeur » d'avant-hier)
    $passes = @($script:Agenda | Where-Object { -not $vus.ContainsKey($_.Id) -and -not $_.Repetition -and $_.Quand -ge $today.AddDays(-30) -and $_.Quand -lt $now } | Sort-Object Quand -Descending | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ RV = $_; Prochain = $_.Quand } })
    foreach ($it in @($liste | Sort-Object Prochain | Select-Object -First 40) + $passes) {
        $r = $it.RV; $c = 'e' + $r.Id.Substring(0, 5); $codes[$c] = $r.Id   # même code d'une phrase à l'autre
        $l = "- [$c] $(Get-TitreAffiche $r.Titre) ($($Types[(Get-TypeRV $r)].Nom)) : $(Format-QuandRV $r $it.Prochain) ($(Format-Relatif $it.Prochain))"
        $rep = Format-Repetition $r.Repetition
        if ($rep) { $l += ", revient $rep$(if (-not $r.Repetition.Jusqua) { ' (sans fin : il a lieu aussi tous les mois suivants)' })" }
        if ($r.Lieu) { $l += ". Lieu : $($r.Lieu)" }
        if (@($r.Avec).Count) { $l += ". Avec : $(@($r.Avec) -join ', ')" }
        if (@($r.APreparer).Count) { $l += ". À prendre : $(@($r.APreparer | ForEach-Object { $_.Texte }) -join ', ')" }
        if ($r.Notes) { $l += ". Notes : $($r.Notes -replace '\s+', ' ')" }
        if ($r.Important) { $l += '. Important' }
        if (@($r.Fichiers).Count) { $l += ". Dossiers : $(@($r.Fichiers | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')$(if ($r.OuvrirAuDebut) { ' (ouverts à l''heure)' })" }
        if ($r.Fait) { $l += '. Déjà fait' }
        $lignes += $l
    }
    if (-not $lignes) { $lignes = @('(son agenda est vide)') }
    $jour = $today.ToString('dddd d MMMM yyyy', $Fr)
    @{ Codes = $codes; Systeme = @"
Tu es Evermind, l'assistant agenda vocal de l'utilisateur. Tu le tutoies et tu réponds en français, en une ou deux phrases courtes et naturelles, comme un pote sympa.
Nous sommes le $jour, il est $(Format-Heure $now).

Son agenda (les identifiants entre crochets servent à désigner un rendez-vous) :
$($lignes -join "`n")

Tu réponds avec un objet JSON : "actions" (ce qu'Evermind doit faire) et "reponse" (ce que tu lui dis).
Actions possibles :
- "creer" : nouveau rendez-vous. Dans "phrase", écris une phrase simple avec le quoi et le quand, en gardant les mots de l'utilisateur pour la date (demain, mardi prochain, le 23 octobre, tous les lundis à 21 h...). Ne calcule jamais une date toi-même. Ajoute "lieu", "personnes", "notes", "choses_a_prendre", "important" seulement s'ils sont dits.
- "modifier" : changer un rendez-vous existant, désigné par "id". Pour changer le jour ou l'heure, mets dans "phrase" le nouveau moment avec les mots de l'utilisateur (ex : « jeudi à 15 h ») : jamais de numéro de jour que tu aurais calculé. Sinon : "titre", "lieu", "personnes" (gens à ajouter), "retirer_personnes" (gens à enlever), "notes", "choses_a_prendre" (objets à emporter ou choses à préparer), "important" (true ou false), "rappels" (quand le prévenir : « la veille », « 2 heures avant », « le matin même »).
- Un rendez-vous qui revient a lieu à TOUTES ses dates à venir (jusqu'à sa date de fin s'il en a une), pas seulement la prochaine montrée dans la liste : « les raids de novembre » existent si le raid revient tous les lundis sans fin.
- Un rendez-vous qui revient peut s'arrêter à une date : garde les mots de l'utilisateur dans "phrase" (« tous les lundis d'octobre », « tous les mardis jusqu'au 15 décembre »).
- Dossiers et fichiers : avec "creer" ou "modifier", "dossiers" relie des dossiers à un rendez-vous (le nom de la personne ou du dossier, par exemple ["Monsieur Richard"]) ; "ouvrir_au_debut": true si l'utilisateur veut qu'ils s'ouvrent tout seuls à l'heure du rendez-vous (« ouvre son dossier au début de la réunion »).
- "ouvrir" : ouvrir tout de suite les dossiers et fichiers d'un rendez-vous ("id"), ou un dossier par son nom ("dossiers": ["Monsieur Richard"]). « Relie », « rattache », « associe », « joins » un dossier à un rendez-vous = "modifier" avec "dossiers", jamais "ouvrir".
- "supprimer" : enlever un rendez-vous ("id"). Pour un rendez-vous qui revient, si l'utilisateur n'enlève qu'une partie des fois, recopie ses mots dans "periode" (« le 19 octobre », « en octobre 2026 », « à partir de novembre », « jusqu'au 15 mars », « cette semaine ») : Evermind enlève seulement ces fois-là. Sans "periode", toutes les fois sont supprimées. « Supprime », « efface », « enlève », « retire » veulent toujours dire "supprimer", jamais "modifier".
- "fait" : une chose à faire est terminée ("id").
- "annuler" : défaire la dernière chose qu'Evermind a faite.
Pour une question sur l'agenda ou une simple discussion, ne mets aucune action et réponds dans "reponse" en t'appuyant sur l'agenda.
Le verbe décide de l'action : « crée », « crées », « ajoute », « note », « mets », « programme » = creer (même s'il dit « l'événement ») ; « supprime », « efface », « enlève », « retire » = supprimer ; « décale », « déplace », « change », « c'est plutôt » = modifier. Tu ne demandes « lequel ? » que pour supprimer ou modifier, jamais pour créer.
Un rendez-vous sans heure est pour toute la journée : ne demande jamais l'heure, garde juste le jour dans « phrase ». Un événement sur plusieurs jours est UN seul événement : garde les jours dans « phrase » (« ElleFest du 27 au 29 octobre », « salon les 5, 6 et 7 novembre »). Une liste (courses, choses à emporter) va dans « choses_a_prendre », un élément par case.
La phrase vient d'une dictée qui se trompe parfois : un mot qui ne veut rien dire est sûrement un mot proche (« sucrime » = supprime, « décade » = décale, « effaces-le » = efface). Devine le bon mot ; si tu n'es vraiment pas sûr, demande au lieu d'agir. N'écris jamais dans les notes un mot que tu n'as pas compris.
Tu peux faire plusieurs actions d'un coup (« supprime tout ce que j'ai demain »). Si la phrase demande deux choses (« supprime le X et mets-le sur 3 jours »), fais les DEUX actions ; pour changer les jours d'un rendez-vous existant, « modifier » avec la nouvelle « phrase » suffit (« du 27 au 29 octobre »).
Pour désigner un rendez-vous, sers-toi de son nom, de sa date ou de sa sorte (« l'événement du 23 octobre », « mon rendez-vous de mardi », « l'anniversaire »).
Si tu ne sais vraiment pas de quel rendez-vous il parle, ne fais rien et demande-lui lequel en citant leurs noms.
Tu te souviens de la conversation : si l'utilisateur répond à ta question « lequel ? », fais sur ce rendez-vous l'action qu'il demandait juste avant (supprimer, décaler...). Ne recrée jamais un rendez-vous qui est déjà dans l'agenda.
Règles : ne montre jamais les identifiants à l'utilisateur. Ne remplis "notes", "lieu", "personnes", "choses_a_prendre" que si l'utilisateur les dit vraiment. Toute demande de rappel, de chose à ne pas oublier ou d'événement à noter est une action "creer".

Exemples, avec un AUTRE agenda imaginaire (ne les confonds jamais avec le vrai agenda ci-dessus) :
  [p1] Piscine : lundi 3 mars à 18 h, revient tous les lundis. [b2] Bowling avec les potes : vendredi 7 mars à 21 h. [c3] Coiffeur : mardi 4 mars à 10 h.
Utilisateur : « mets-moi un rappel pour appeler le garage lundi à 9 h »
{"actions":[{"action":"creer","phrase":"appeler le garage lundi à 9 h"}],"reponse":"C'est noté, je te rappellerai d'appeler le garage lundi à 9 h."}
Utilisateur : « je veux que tu me crées l'événement anniversaire de Jordan le 23 octobre »
{"actions":[{"action":"creer","phrase":"anniversaire de Jordan le 23 octobre"}],"reponse":"C'est noté, l'anniversaire de Jordan le 23 octobre."}
Utilisateur : « fais-moi un événement faire les courses samedi avec la liste : lait, œufs, pain »
{"actions":[{"action":"creer","phrase":"faire les courses samedi","choses_a_prendre":["lait","œufs","pain"]}],"reponse":"C'est noté : les courses samedi, avec ta liste."}
Utilisateur : « crée un anniversaire pour Paul le 2 mai, il aura 30 ans »
{"actions":[{"action":"creer","phrase":"anniversaire de Paul le 2 mai, il aura 30 ans"}],"reponse":"C'est noté, l'anniversaire de Paul le 2 mai."}
Utilisateur : « ajoute Tom au bowling »
{"actions":[{"action":"modifier","id":"b2","personnes":["Tom"]}],"reponse":"J'ai ajouté Tom au bowling."}
Utilisateur : « décale le bowling à samedi, même heure »
{"actions":[{"action":"modifier","id":"b2","phrase":"samedi"}],"reponse":"Le bowling passe à samedi, même heure."}
Utilisateur : « la piscine c'est plutôt à 19 h »
{"actions":[{"action":"modifier","id":"p1","phrase":"lundi à 19 h"}],"reponse":"La piscine passe à 19 h lundi."}
Utilisateur : « pour la piscine, prends mon bonnet »
{"actions":[{"action":"modifier","id":"p1","choses_a_prendre":["bonnet"]}],"reponse":"J'ai noté le bonnet pour la piscine."}
Utilisateur : « j'aimerais que tu effaces l'événement du 4 mars »
(le 4 mars, il n'y a que le coiffeur) {"actions":[{"action":"supprimer","id":"c3"}],"reponse":"C'est fait, j'ai effacé le coiffeur du 4 mars."}
Utilisateur : « supprime le rendez-vous de lundi »
(lundi, il n'y a que la piscine) {"actions":[{"action":"supprimer","id":"p1"}],"reponse":"J'ai supprimé la piscine de lundi."}
Utilisateur : « enlève la piscine à partir d'avril »
{"actions":[{"action":"supprimer","id":"p1","periode":"à partir d'avril"}],"reponse":"C'est fait, plus de piscine à partir d'avril."}
Utilisateur : « supprime toutes les piscines de mars »
{"actions":[{"action":"supprimer","id":"p1","periode":"en mars"}],"reponse":"C'est fait, j'ai enlevé les piscines de mars."}
Utilisateur : « supprime le rendez-vous »
(on ne sait pas lequel) {"actions":[],"reponse":"Lequel ? La piscine, le bowling ou le coiffeur ?"}
Utilisateur, juste après : « le coiffeur »
{"actions":[{"action":"supprimer","id":"c3"}],"reponse":"J'ai supprimé le coiffeur."}
Pour le vrai agenda, prends toujours les identifiants et les jours de la liste du haut.
"@ }
}

$SchemaIA = @{
    type = 'object'; required = @('actions', 'reponse')
    properties = @{
        actions = @{ type = 'array'; items = @{ type = 'object'; required = @('action')
            properties = @{
                action = @{ type = 'string'; enum = @('creer', 'modifier', 'supprimer', 'fait', 'annuler', 'ouvrir') }
                id = @{ type = 'string' }; phrase = @{ type = 'string' }; titre = @{ type = 'string' }; lieu = @{ type = 'string' }
                personnes = @{ type = 'array'; items = @{ type = 'string' } }; notes = @{ type = 'string' }
                choses_a_prendre = @{ type = 'array'; items = @{ type = 'string' } }; important = @{ type = 'boolean' }; periode = @{ type = 'string' }
                rappels = @{ type = 'array'; items = @{ type = 'string' } }; retirer_personnes = @{ type = 'array'; items = @{ type = 'string' } }
                dossiers = @{ type = 'array'; items = @{ type = 'string' } }; ouvrir_au_debut = @{ type = 'boolean' }
            } } }
        reponse = @{ type = 'string' }
    }
}

# ---------------------------------------------------------------------------
# Demander à l'IA (en arrière plan : la fenêtre reste fluide)
# ---------------------------------------------------------------------------
# Source : 'voix', 'barre' (texte tapé) ou 'test'. Retourne $false si l'assistant n'est pas là.
# Ce qui est envoyé à l'IA : consignes et agenda, conversation récente, la demande (ou la correction d'une erreur)
function Get-QuestionIA([string]$Texte, $Relance) {
    $ctx = Get-ContexteIA
    # Mémoire de la conversation : les 3 derniers échanges, s'ils datent de moins de 3 minutes
    if (-not $script:Conversation -or ((Get-Date) - $script:ConversationQuand).TotalMinutes -gt 3) { $script:Conversation = New-Object System.Collections.ArrayList }
    $messages = @(@{ role = 'system'; content = $ctx.Systeme }) + @($script:Conversation | Select-Object -Last 6) + @(@{ role = 'user'; content = $Texte })
    if ($Relance) { $messages = @($Relance.Messages) + @(@{ role = 'assistant'; content = $Relance.Reponse }, @{ role = 'user'; content = $Relance.Correction }); $ctx.Codes = $Relance.Codes }
    $corps = @{ messages = $messages
                temperature = 0; max_tokens = 400
                response_format = @{ type = 'json_schema'; json_schema = @{ name = 'reponse'; schema = $SchemaIA } } } | ConvertTo-Json -Depth 20 -Compress
    @{ Ctx = $ctx; Messages = $messages; Corps = $corps }
}

function Invoke-Commande([string]$Texte, [string]$Source, $Relance) {
    if ($script:Demande -and -not $Relance) { return $true }   # une question à la fois
    if (-not (Start-Cerveau)) { return $false }
    $q = Get-QuestionIA $Texte $Relance
    $ctx = $q.Ctx; $messages = $q.Messages; $corps = $q.Corps
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($Port, $Corps)
        # L'IA met quelques secondes à se charger la première fois : on attend qu'elle soit prête
        $limite = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $limite) {
            try { $h = [Net.WebRequest]::Create("http://127.0.0.1:$Port/health"); $h.Timeout = 1500; $rh = $h.GetResponse(); $rh.Close(); break }
            catch { Start-Sleep -Milliseconds 250 }
        }
        $req = [Net.WebRequest]::Create("http://127.0.0.1:$Port/v1/chat/completions")
        $req.Method = 'POST'; $req.ContentType = 'application/json; charset=utf-8'; $req.Timeout = 120000
        $b = [Text.Encoding]::UTF8.GetBytes($Corps)
        $s = $req.GetRequestStream(); $s.Write($b, 0, $b.Length); $s.Close()
        $resp = $req.GetResponse()
        $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd(); $resp.Close()
        $txt
    }).AddArgument($script:Cerveau.Port).AddArgument($corps)
    $script:Demande = @{ PS = $ps; Handle = $ps.BeginInvoke(); Process = $script:Cerveau.Process; Codes = $ctx.Codes; Messages = $messages; Relance = [bool]$Relance; Texte = $Texte; Source = $Source; Debut = [Diagnostics.Stopwatch]::StartNew() }
    if ($Source -eq 'voix') { Show-Bulle 'Je réfléchis...' }
    Set-VoixEtat "Je réfléchis à : « $Texte »"
    if (-not $script:DemandeTimer) {
        $script:DemandeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:DemandeTimer.Interval = [TimeSpan]::FromMilliseconds(100)
        $script:DemandeTimer.Add_Tick({ Step-Demande })
    }
    $script:DemandeTimer.Start()
    $true
}

function Step-Demande {
    $d = $script:Demande
    if (-not $d) { $script:DemandeTimer.Stop(); return }
    if (-not $d.Handle.IsCompleted) {
        # L'IA s'est arrêtée (fichier manquant, plus de mémoire...) : inutile d'attendre
        $mort = $d.Process -and $d.Process.HasExited
        if ($mort) { Write-Log "Assistant arrêté tout seul (code $($d.Process.ExitCode))" }
        if (-not $mort -and $d.Debut.Elapsed.TotalSeconds -lt 150) { return }
        try { $d.PS.Stop() } catch {}
    }
    $script:Demande = $null
    $script:DemandeTimer.Stop()
    if ($script:Cerveau) { $script:Cerveau.Dernier = Get-Date }
    $reponse = $null
    try {
        $brut = @($d.PS.EndInvoke($d.Handle))[-1]
        $reponse = (ConvertFrom-Json $brut).choices[0].message.content | ConvertFrom-Json
    } catch { Write-Log "Assistant : pas de réponse utilisable ($($_.Exception.Message))" }
    $d.PS.Dispose()
    Write-Log "Assistant ($([math]::Round($d.Debut.Elapsed.TotalSeconds, 1)) s) : « $($d.Texte) » -> $(if ($reponse) { $reponse | ConvertTo-Json -Depth 6 -Compress } else { 'rien' })"
    if (-not $reponse) {
        # L'IA n'a pas répondu : les règles d'Evermind prennent le relais
        if ($d.Source -eq 'voix') { Invoke-DicteeRegles $d.Texte } else { Show-FormMessage 'L''assistant n''a pas répondu. Réessaie dans un instant.' $Colors.bad }
        return
    }
    $decision = Get-DecisionIA $d $reponse
    if ($decision.Relance) {
        $script:Demande = $null
        [void](Invoke-Commande $d.Texte $d.Source $decision.Relance)
        return
    }
    $reponse = $decision.Reponse
    # Retenu pour la phrase suivante (« lequel ? » puis « le dentiste »)
    [void]$script:Conversation.Add(@{ role = 'user'; content = $d.Texte })
    [void]$script:Conversation.Add(@{ role = 'assistant'; content = ($reponse | ConvertTo-Json -Depth 6 -Compress) })
    $script:ConversationQuand = Get-Date
    Invoke-ActionsIA $reponse $d.Codes $d.Texte $d.Source
}

# Que faire de la réponse de l'IA ($d : Texte, Relance, Messages, Codes) : @{ Relance = ... } pour lui redemander
# en lui signalant son erreur, ou @{ Reponse = ... } à appliquer. Utilisé aussi par les catalogues de test.
function Get-DecisionIA($d, $reponse) {
    $relance = { param($correction) @{ Relance = @{ Messages = $d.Messages; Codes = $d.Codes; Reponse = ($reponse | ConvertTo-Json -Depth 6 -Compress); Correction = $correction } } }
    # « Ouvre le dossier de Monsieur Richard » : pas besoin de l'IA
    $ouv = Get-OuvertureTexte $d.Texte
    if ($ouv) {
        $id = @(@($reponse.actions) | Where-Object { $_.action -eq 'ouvrir' -and $_.id })
        if ($id.Count) { $ouv | Add-Member -NotePropertyName id -NotePropertyValue $id[0].id }
        return @{ Reponse = [pscustomobject]@{ actions = @($ouv); reponse = '' } }
    }
    # « Je suis du matin lundi et mardi, de nuit jeudi » : des postes de travail, lus par les règles d'Evermind
    $hor = Get-HorairesTravail $d.Texte
    $inH = Get-IntentionsTexte $d.Texte
    if ($hor -and -not $inH.Supp -and -not $inH.Modif -and -not $inH.Question) {
        return @{ Reponse = [pscustomobject]@{ actions = @([pscustomobject]@{ action = 'horaires'; Liste = @($hor) }); reponse = '' } }
    }
    # « Supprime l'événement » sans dire lequel (ni nom, ni date), et rien dans la conversation qui le dise : on demande
    $q = Get-QuestionVague $d.Texte $d.Codes
    if ($q) { Write-Log 'Assistant : demande trop vague, on demande lequel'; return @{ Reponse = [pscustomobject]@{ actions = @(); reponse = $q } } }
    # L'action ne correspond pas au verbe (« supprime » mais l'IA modifie...) : on lui redemande une fois en le lui
    # signalant ; si elle se trompe encore, rien n'est touché et Evermind demande de redire autrement.
    $ecart = Get-EcartAction $d.Texte @($reponse.actions | Where-Object { $_ -and $_.action }) $d.Codes
    if ($ecart) {
        Write-Log "Assistant : $ecart"
        if (-not $d.Relance) { return (& $relance $ecart) }
        # Toujours pas : une création claire est faite par les règles d'Evermind ; sinon, rien n'est touché
        $in = Get-IntentionsTexte $d.Texte
        if ($in.Creer -and -not $in.Supp -and -not $in.Modif -and -not $in.Question) {
            $p = Read-Phrase $d.Texte
            if (-not $p.Manque -and $p.Titre) { Write-Log 'Assistant : création faite par les règles'; return @{ Reponse = [pscustomobject]@{ actions = @([pscustomobject]@{ action = 'creer'; phrase = $d.Texte }); reponse = '' } } }
        }
        if ($in.Question) { return @{ Reponse = [pscustomobject]@{ actions = @(); reponse = [string]$reponse.reponse } } }
        return @{ Reponse = [pscustomobject]@{ actions = @(); reponse = 'Je ne suis pas sûr d''avoir bien compris, je n''ai rien touché. Tu peux le redire autrement ?' } }
    }
    # Réponse qui dit « c'est fait » sans aucune action : l'IA s'est trompée, on lui redemande une fois en le lui signalant
    $sansAction = -not @($reponse.actions | Where-Object { $_ -and $_.action }).Count
    # Un rendez-vous dit tel quel, sans verbe (« boulot mardi de 6 h à 14 h », « dentiste jeudi à 15 h ») : comme dans la
    # barre, il est noté (l'IA demande parfois « tu veux que je le programme ? »)
    $inS = Get-IntentionsTexte $d.Texte
    if ($sansAction -and -not $inS.Question -and -not $inS.Supp -and -not $inS.Modif) {
        $p = Read-Phrase $d.Texte
        if (-not $p.Manque -and $p.Titre -and $p.Quand -and @($p.Titre -split '\s+').Count -le 6 -and (Test-TitreDit $p.Titre $d.Texte)) {
            Write-Log 'Assistant : rendez-vous dit tel quel, noté par les règles'
            return @{ Reponse = [pscustomobject]@{ actions = @([pscustomobject]@{ action = 'creer'; phrase = $d.Texte }); reponse = '' } }
        }
    }
    if ($sansAction -and [string]$reponse.reponse -match "(?i)\b(c'est (bien )?noté|j'ai (bien |déjà )?(noté|ajouté|créé|mis|supprimé|effacé|enlevé|décalé|déplacé|changé|modifié|annulé|programmé|planifié)|c'est fait|est (bien )?(supprimé|décalé|ajouté|noté|programmé|planifié))") {
        if (-not $d.Relance) {
            Write-Log 'Assistant : réponse sans action, on lui redemande'
            return (& $relance 'Tu as répondu que c''était fait, mais "actions" est vide : rien n''a été fait. Redonne le JSON avec la bonne action.')
        }
        # Toujours rien : pour une création, les règles d'Evermind s'en chargent
        $p = Read-Phrase $d.Texte
        if (-not $p.Manque -and $d.Texte -match "(?i)\b(cr[ée]{1,2}[rsz]?|ajoute[rsz]?|note[rsz]?|met[st]?|mettre|programme[rsz]?)\b" -and $d.Texte -notmatch "(?i)\b(supprime|efface|enl[èe]ve|retire|d[ée]cale|d[ée]place|change|modifie)") {
            Write-Log 'Assistant : création faite par les règles'
            return @{ Reponse = [pscustomobject]@{ actions = @([pscustomobject]@{ action = 'creer'; phrase = $d.Texte }); reponse = '' } }
        }
    }
    @{ Reponse = $reponse }
}

# ---------------------------------------------------------------------------
# Faire ce que l'IA propose, après vérification
# ---------------------------------------------------------------------------
function Get-PhraseNote($r) {
    $rep = Format-Repetition $r.Repetition
    if ($r.Journee) { $q = if ($rep) { $rep } else { Format-QuandRV $r $r.Quand }; return @{ Ecrit = "$($r.Titre), $q"; Dit = "$($r.Titre), $q" } }
    if ($rep) { return @{ Ecrit = "$($r.Titre), $rep à $(Format-Heure $r.Quand)"; Dit = "$($r.Titre), $rep à $((Format-QuandParle $r.Quand) -replace '^.* à ', '')" } }
    $prochain = Get-NextOccurrence $r.Repetition $r.Quand (Get-Date)
    @{ Ecrit = "$($r.Titre), $(Format-QuandRV $r $prochain)"; Dit = "$($r.Titre), $(Format-QuandParle $prochain $r)" }
}

# Copie de l'agenda avant un changement, pour « annule » (les 20 dernières)
function Save-Annulation {
    if (-not $script:Annulations) { $script:Annulations = New-Object System.Collections.ArrayList }
    [void]$script:Annulations.Add((ConvertTo-Json -InputObject (Get-AgendaDonnees) -Depth 8 -Compress))
    while ($script:Annulations.Count -gt 20) { $script:Annulations.RemoveAt(0) }
}

function Restore-Annulation {
    if (-not $script:Annulations -or -not $script:Annulations.Count) { return $false }
    $json = $script:Annulations[$script:Annulations.Count - 1]
    $script:Annulations.RemoveAt($script:Annulations.Count - 1)
    # La copie est relue entièrement avant de remplacer l'agenda : en cas de problème, rien n'est perdu
    try {
        $liste = ConvertFrom-Json $json      # (sans @() : PowerShell 5.1 rendrait la liste comme un seul élément)
        $nouveau = New-Object System.Collections.ArrayList
        foreach ($x in $liste) { if ($x) { [void]$nouveau.Add((ConvertTo-RendezVous $x)) } }
    } catch { Write-Log "Annulation impossible : $_"; return $false }
    $script:Agenda = $nouveau
    Save-Agenda
    Write-Log 'Dernière action annulée'
    $true
}

# Ce que la phrase demande, d'après ses verbes (« pour retirer de l'argent » est ce qu'il y a à faire, pas un ordre)
function Get-IntentionsTexte([string]$Texte) {
    $t = ' ' + $Texte.ToLower() + ' '
    $pas = "(?<!\b(?:pour|de|à|a)\s)(?<!\bd')"
    $question = ($t -match '\?\s*$' -or $t -match "^\s*(?:qu'est-ce|c'est quand|quand|o[ùu]|combien|quel(?:le)?s?|est-ce que j'ai|est-ce que je|ai-je|suis-je|j'ai quoi|dis-moi|rappelle-moi (?:quand|ce que|o[ùu]))\b") -and $t -notmatch "\b(?:peux|pourrais|veux)[- ]tu\b"
    @{
        Supp = $t -match "$pas\b(supprim|suprim|sucrim|effac|enl[èe]v|retir|vir[ée]|d[ée]gag)\w*" -or $t -match "\bannul\w*\s+(?:le|la|les|l'|mon|ma|mes|ce|cette|tous|toutes)\s*(?!derni|ce que|ça|cela)\w" -or $t -match "\best\s+annul[ée]"
        Modif = $t -match "$pas\b(d[ée]cal|d[ée]cad|d[ée]plac|repouss|recul|retard|avance|report|chang|modifi|renomm)\w*"
        Creer = $t -match "\b(cr[ée]{1,2}[rsz]?\b|cr[ée]e-|ajout|rajout|mets|met\b|mettre|mett(?:e|es|ez|ions)\b|note[rsz]?\b|programm|planifi|rappel|oubli|pense|fai[st][- ]moi|fai[st]\s+(?:un|une)\s+(?:nouvel(?:le)?\s+)?(?:[ée]v[èée]nement|rendez-vous|rdv|rappel))"
        Question = $question
    }
}

# Le titre vient-il des mots de l'utilisateur ? (l'IA a déjà écrit « foot » pour « sport »)
function Test-TitreDit([string]$Titre, [string]$Texte) {
    $sans = { param($s) ' ' + ($s.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '') + ' ' }
    $t = & $sans $Texte
    $mots = @([regex]::Matches((& $sans $Titre), '[a-z]{3,}') | ForEach-Object { $_.Value } | Where-Object { $_ -notin 'anniversaire', 'rendez', 'vous', 'avec', 'chez', 'des', 'les', 'une', 'pour' })
    -not $mots.Count -or @($mots | Where-Object { $t -match "\b$_" }).Count -eq $mots.Count
}

# Supprimer ou changer « l'événement », « le rendez-vous », sans nom ni date, au début d'une conversation : la question
# « Lequel ? » avec les noms des prochains rendez-vous ; sinon $null
function Get-QuestionVague([string]$Texte, $Codes) {
    if ($script:Conversation -and $script:Conversation.Count -and ((Get-Date) - $script:ConversationQuand).TotalMinutes -le 3) { return $null }
    $in = Get-IntentionsTexte $Texte
    if (-not ($in.Supp -or $in.Modif) -or $in.Creer) { return $null }
    $t = $Texte.ToLower()
    if ($t -notmatch "\b(?:l'|le |la |un |une |cet |ce |cette |mon |ma )\s*(?:[ée]v[èée]nement|rendez-vous|rdv|truc|rappel)\b") { return $null }
    if ($Codes -and (Test-DesigneExistant $Texte @() $Codes)) { return $null }
    $sans = ' ' + ($t.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '') + ' '
    if ($Codes -and @($Codes.Values | ForEach-Object { Get-RendezVous $_ } | Where-Object { $_ } | Where-Object { $rv = $_; @(Get-MotsTitre $rv.Titre | Where-Object { $sans -match "\b$_" }).Count }).Count) { return $null }
    $p = Read-Phrase "x $Texte"
    if ($p.Jour -or $p.Repetition -or $null -ne $p.Heure -or $Texte -match "(?i)\b(?:$RxJour|$RxMois|demain|aujourd'hui|hier|semaine|\d{1,2})\b") { return $null }
    $noms = @(Get-Upcoming | Select-Object -First 6 | ForEach-Object { Get-TitreAffiche $_.RV.Titre } | Select-Object -Unique)
    if (-not $noms.Count) { return 'Ton agenda est vide, il n''y a rien à changer.' }
    $liste = if ($noms.Count -gt 1) { "$(($noms | Select-Object -SkipLast 1) -join ', ') ou $($noms[-1])" } else { $noms[0] }
    "Lequel ? $liste ?"
}

# La phrase désigne-t-elle un rendez-vous existant avec un article défini (« le foot », « mon dentiste », « à la soirée ») ?
# Sans $Actions : n'importe quel rendez-vous de l'agenda envoyé à l'IA.
function Test-DesigneExistant([string]$Texte, $Actions, $Codes) {
    $t = ' ' + ($Texte.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '') + ' '
    $ids = if (@($Actions).Count) { @(@($Actions) | Where-Object { $_.id } | ForEach-Object { ([string]$_.id).Trim('[] ') } | Where-Object { $Codes.ContainsKey($_) } | ForEach-Object { $Codes[$_] }) } else { @($Codes.Values) }
    foreach ($id in $ids) {
        $rv = Get-RendezVous $id
        if (-not $rv) { continue }
        foreach ($w in @(Get-MotsTitre $rv.Titre)) {
            if ($t -match "(?:\b(?:le|la|les|mon|ma|mes|ce|cette|ton|ta|du|au|aux|des)\s+|\bl')(?:\w+\s+){0,2}$w") { return $true }
        }
    }
    $false
}

# Rappels dits dans une phrase : « la veille », « 2 heures avant », « le matin même », « à l'heure » (codes d'Evermind)
function Read-RappelsTexte([string]$Texte) {
    $p = Read-Phrase "x le 1/1/2099 à 12 h $Texte" ([datetime]'2026-01-01')
    @($p.Rappels | Where-Object { $_ })
}

# Une phrase comprise par les règles dit-elle plus (ou autre chose) que celle de l'IA ?
function Test-PhrasePlusRiche($pu, $p) {
    if ($p.Manque) { return $true }
    if ($pu.Repetition -and -not $p.Repetition) { return $true }
    if ($pu.Repetition -and $p.Repetition -and (($pu.Repetition | ConvertTo-Json -Compress) -ne ($p.Repetition | ConvertTo-Json -Compress))) { return $true }
    if ($pu.Fin -and -not $p.Fin) { return $true }
    if (@($pu.Jours | Where-Object { $_ }).Count -gt @($p.Jours | Where-Object { $_ }).Count) { return $true }
    # (à la minute près : « dans une minute » lu deux fois n'a pas exactement les mêmes secondes)
    if ($pu.Quand -and $p.Quand -and [math]::Abs(([datetime]$pu.Quand - [datetime]$p.Quand).TotalMinutes) -ge 1) { return $true }
    $false
}

# Garde-fou : le verbe de la demande décide de la sorte d'action. Retourne ce qui ne va pas (pour le dire à l'IA), ou rien.
#   « supprime / efface / enlève / retire » : il faut une suppression ; « décale / déplace / change » : pas de
#   suppression ni de création ; « crée / ajoute / mets / note » : pas de suppression. Une phrase qui mélange les
#   verbes, ou une question (« lequel ? », sans action), passe telle quelle.
function Get-EcartAction([string]$Texte, $Actions, $Codes) {
    $in = Get-IntentionsTexte $Texte
    $supp = $in.Supp; $modif = $in.Modif; $creer = $in.Creer
    $sortes = @(@($Actions) | ForEach-Object { [string]$_.action })
    # Une question (« qu'est-ce que je dois apporter ? ») ne change rien à l'agenda
    if ($in.Question -and -not $supp -and -not $modif -and -not $creer -and @($sortes | Where-Object { $_ -ne 'annuler' }).Count) {
        return 'C''est une QUESTION : réponds seulement dans "reponse", avec "actions" vide. Ne modifie rien.'
    }
    # Une création demandée (« mets-moi coiffeur mardi ») : l'IA ne doit pas refuser, ni modifier un autre rendez-vous
    if ($creer -and -not $supp -and -not $modif -and -not $in.Question) {
        if (-not $sortes.Count) { return 'L''utilisateur demande de CRÉER un nouvel événement (il n''a pas besoin d''exister déjà). Utilise l''action "creer" avec sa phrase.' }
        # « crée un rendez-vous avec les dossiers de M. Richard » : créer (et relier), pas seulement ouvrir
        if ($sortes -notcontains 'creer' -and $sortes -contains 'ouvrir' -and $Texte -notmatch '(?i)\bouvr') { return 'L''utilisateur demande de CRÉER un nouvel événement, il n''a pas demandé d''ouvrir quoi que ce soit : utilise "creer" avec sa phrase (et "dossiers" si un dossier est nommé).' }
        if ($sortes -notcontains 'creer' -and $sortes -contains 'modifier' -and $Codes) {
            # Modifier n'a de sens que si la phrase parle d'un rendez-vous qui existe (« ajoute Paul à la soirée »)
            $t = ' ' + ($Texte.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '') + ' '
            $cites = @(@($Actions) | Where-Object { $_.action -eq 'modifier' -and $_.id } | ForEach-Object {
                $code = ([string]$_.id).Trim('[] '); if ($Codes.ContainsKey($code)) { Get-RendezVous $Codes[$code] } } | Where-Object { $_ } |
                Where-Object { $rv = $_; @(Get-MotsTitre $rv.Titre | Where-Object { $t -match "\b$_" }).Count })
            if (-not $cites.Count) { return 'L''utilisateur demande de CRÉER un nouvel événement, pas de modifier un rendez-vous existant. Utilise l''action "creer" avec sa phrase.' }
        }
    }
    # « Relie / rattache / associe / joins le dossier de X au dentiste » : relier, pas ouvrir
    if ($Texte -match "(?i)\b(?:reli|rattach|associ|joins|joindre|attach|lie[rsz]?\b|ajoute[rsz]?\s+(?:le|les)\s+(?:dossier|fichier))\w*" -and $sortes -contains 'ouvrir' -and $sortes -notcontains 'modifier' -and $sortes -notcontains 'creer') {
        return 'L''utilisateur veut RELIER un dossier à un rendez-vous existant, pas l''ouvrir : utilise "modifier" avec l''id du rendez-vous et "dossiers" (par exemple ["Madame Dupont"]).'
    }
    # « Ouvre son dossier au début de la réunion » : à l'heure, pas maintenant
    if ($sortes -contains 'ouvrir' -and $Texte -match "(?i)\b(?:au d[ée]but|à l'heure|au moment|quand (?:elle|il|ça) commence)\b") {
        return 'L''utilisateur veut que les dossiers s''ouvrent À L''HEURE du rendez-vous, pas maintenant : utilise "modifier" avec son id et "ouvrir_au_debut": true (et "dossiers" si un dossier est nommé).'
    }
    if (-not $sortes.Count) { return $null }
    # « annule le foot » : supprimer le foot ; « annule » tout seul : défaire la dernière action
    if ($sortes -contains 'annuler' -and $supp -and $Codes -and (Test-DesigneExistant $Texte @() $Codes)) { return 'Ici « annule » vise un rendez-vous précis : utilise "supprimer" avec son id, pas "annuler" (qui défait seulement la dernière action d''Evermind).' }
    # Création d'un NOUVEL événement qui porte le nom d'un existant (« ajoute dentiste vendredi », « mets un rendez-vous foot ») :
    # « le dentiste », « mon foot », « à la soirée » désignent l'existant ; sinon c'est un nouveau
    if ($creer -and -not $supp -and -not $modif -and $sortes -contains 'modifier' -and $sortes -notcontains 'creer' -and $Codes -and -not (Test-DesigneExistant $Texte $Actions $Codes)) {
        $pu = Read-Phrase $Texte
        if (-not $pu.Manque -and ($pu.Jour -or $pu.Repetition)) { return 'L''utilisateur demande de CRÉER un NOUVEL événement (un autre, même s''il porte le même nom qu''un rendez-vous existant). Utilise "creer" avec sa phrase, ne modifie pas l''existant.' }
    }
    # « rappelle-moi la veille pour la soirée » : un rappel pour un rendez-vous existant, pas un nouvel événement
    if ($sortes -contains 'creer' -and $Codes -and (Read-RappelsTexte $Texte).Count -and (Test-DesigneExistant $Texte @() $Codes) -and (Read-Phrase $Texte).Manque) {
        return 'L''utilisateur veut être PRÉVENU pour un rendez-vous qui existe déjà : utilise "modifier" avec son id et "rappels" (par exemple ["la veille"]), ne crée rien.'
    }
    if ($supp -and -not $modif -and -not $creer -and $sortes -notcontains 'supprimer') {
        return 'L''utilisateur demande de SUPPRIMER, mais "actions" ne contient aucune action "supprimer". Utilise "supprimer" avec l''id ; s''il ne parle que de certaines dates d''un rendez-vous qui revient, ajoute "periode" avec ses mots. Ne modifie rien.'
    }
    if ($modif -and -not $supp -and -not $creer -and ($sortes -contains 'supprimer' -or $sortes -contains 'creer')) {
        return 'L''utilisateur demande de DÉCALER ou CHANGER un rendez-vous existant : utilise seulement "modifier", sans supprimer ni créer.'
    }
    # Deux choses demandées (« supprime le X et mets-le sur 3 jours ») mais une seule faite
    if ($supp -and ($creer -or $modif) -and $sortes -contains 'supprimer' -and $sortes -notcontains 'creer' -and $sortes -notcontains 'modifier') {
        return 'L''utilisateur demande DEUX choses : supprimer, mais aussi créer ou changer quelque chose. Tu n''as fait que la suppression. Si en fait il veut changer un rendez-vous (par exemple le mettre sur plusieurs jours), utilise seulement "modifier" avec la nouvelle "phrase" au lieu de le supprimer. Sinon, fais les deux actions.'
    }
    if ($creer -and -not $supp -and $sortes -contains 'supprimer') {
        return 'L''utilisateur demande d''AJOUTER ou de CRÉER, pas de supprimer : n''utilise pas "supprimer".'
    }
    $null
}
# Garde-fou : l'IA se trompe parfois d'identifiant (« décale le dentiste » appliqué au raid). Si la demande et sa
# réponse parlent d'un seul rendez-vous de l'agenda, et pas de celui qu'elle a désigné, c'est celui-là qui compte.
function Get-MotsTitre([string]$Titre) {
    $t = $Titre.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    @([regex]::Matches($t, '[a-z]{4,}') | ForEach-Object { $_.Value } | Where-Object { $_ -notin 'anniversaire', 'rendez', 'vous', 'avec', 'chez', 'faire', 'pour', 'tous', 'evenement' })
}
# L'IA glisse parfois ses champs dans la phrase (« réunion avec Mr Richard dans 5 minutes','dossiers':['Mr Richard'],
# 'ouvrir_au_debut':true} », « courses samedi','choses_a_prendre(['lait']) ») : la phrase est coupée et les champs
# récupérés (sans écraser ceux qu'elle a bien remplis)
function Repair-ActionIA($a) {
    $ph = [string]$a.phrase
    $m = [regex]::Match($ph, "\s*['""]\s*[,;{]\s*['""]?[a-z_]+['""]?\s*[:=(]|\s*['""]?\s*[,;]?\s*['""]?\b[a-z]+_[a-z_]+['""]?\s*[:=(\[]|\s*['""]\s*[}\]]|\s*\{\s*['""]")
    if (-not $m.Success) { return }
    $reste = $ph.Substring($m.Index)
    foreach ($c in [regex]::Matches($reste, "['""]?(?<k>dossiers|ouvrir_au_debut|personnes|choses_a_prendre|lieu|notes|important|rappels|titre)['""]?\s*[:=(]\s*\(?\s*(?<v>\[[^\]]*\]|true|false|""[^""]*""|'[^']*')")) {
        $k = $c.Groups['k'].Value; $v = $c.Groups['v'].Value
        if ($null -ne $a.$k -and @($a.$k | Where-Object { $_ }).Count) { continue }
        $val = if ($v -match '^\[') { , @([regex]::Matches($v, "['""](?<s>[^'""]+)['""]") | ForEach-Object { $_.Groups['s'].Value }) }
               elseif ($v -in 'true', 'false') { $v -eq 'true' } else { $v.Trim('''"') }
        $a | Add-Member -NotePropertyName $k -NotePropertyValue $val -Force
    }
    $a | Add-Member -NotePropertyName phrase -NotePropertyValue (($ph.Substring(0, $m.Index) -replace "['""\[\]\(\)\{\},;:\s]+$", '').Trim()) -Force
    Write-Log "Assistant : phrase réparée « $($a.phrase) »"
}

function Get-CibleIA($Rv, $Codes, [string]$Dit) {
    $d = ' ' + ($Dit.ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '') + ' '
    $nomme = { param($r) @(Get-MotsTitre $r.Titre | Where-Object { $d -match "\b$_" }).Count -gt 0 }
    if ($Rv -and (& $nomme $Rv)) { return $Rv }
    # (un titre sans mot à vérifier, « Anniversaire de Léa », ne gagne pas contre un autre rendez-vous nommé :
    # « efface-le » → « le tennis est supprimé » avec le numéro de l'anniversaire, c'est le tennis)
    $autres = @($Codes.Values | Select-Object -Unique | ForEach-Object { Get-RendezVous $_ } | Where-Object { $_ -and (& $nomme $_) })
    if ($Rv -and -not @(Get-MotsTitre $Rv.Titre).Count -and $autres.Count -ne 1) { return $Rv }
    if ($autres.Count -eq 1) {
        if ($Rv) { Write-Log "Assistant : « $($Rv.Titre) » désigné, mais il parlait de « $($autres[0].Titre) »" }
        return $autres[0]
    }
    $Rv
}

# ($ReponseIA, pas $R : $r, le rendez-vous créé, est la même variable pour PowerShell)
function Invoke-ActionsIA($ReponseIA, $Codes, [string]$Texte, [string]$Source) {
    $dits = New-Object System.Collections.ArrayList
    $ecrits = New-Object System.Collections.ArrayList
    $aCorriger = $null
    $cree = $null
    $actions = @($ReponseIA.actions | Where-Object { $_ -and $_.action })
    # Un même rendez-vous supprimé puis modifié dans la même réponse (« supprime-le et mets-le sur 3 jours ») :
    # c'est un changement, la modification l'emporte (sinon elle n'aurait plus rien à modifier)
    $modifies = @($actions | Where-Object { $_.action -eq 'modifier' -and $_.id } | ForEach-Object { ([string]$_.id).Trim('[] ') })
    if ($modifies.Count) { $actions = @($actions | Where-Object { -not ($_.action -eq 'supprimer' -and $modifies -contains ([string]$_.id).Trim('[] ')) }) }
    # « supprime mes rendez-vous de la semaine prochaine », « supprime tout ce que j'ai demain » : Evermind trouve lui-même
    # tout ce qui tombe dans la période (y compris les fois des rendez-vous qui reviennent, qui sautent juste ces jours-là)
    $vrac = Get-SuppressionsPeriode $Texte
    if ($null -ne $vrac) { $actions = $vrac }
    if (@($actions | Where-Object { $_.action -ne 'annuler' }).Count) { Save-Annulation }
    foreach ($a in $actions) {
        $rv = $null
        if ($a.Cible) { $rv = $a.Cible }
        elseif ($a.id) { $code = ([string]$a.id).Trim('[] '); if ($Codes.ContainsKey($code)) { $rv = Get-RendezVous $Codes[$code] } }
        # « crée la réunion et ouvre son dossier au début » : l'IA désigne l'événement qu'elle vient de créer par un
        # numéro inventé (« 1 », « 2 ») ou sans numéro : c'est lui, pas un autre rendez-vous de l'agenda
        # ... ou même avec le numéro d'un AUTRE rendez-vous : si l'utilisateur n'a rien demandé de changer (aucun verbe
        # « décale », « change »...), une modification qui accompagne la création ne peut viser que le nouvel événement
        $surCree = $cree -and -not $a.Cible -and (($a.action -in 'modifier', 'ouvrir' -and -not $rv) -or
            ($a.action -eq 'modifier' -and -not $a.phrase -and -not (Get-IntentionsTexte $Texte).Modif -and -not (Get-IntentionsTexte $Texte).Supp))
        if ($surCree) { $rv = $cree }
        elseif (-not $a.Cible -and $a.action -notin 'creer', 'annuler', 'horaires' -and @($actions | Where-Object { $_.action -notin 'creer', 'annuler', 'horaires' }).Count -eq 1) { $rv = Get-CibleIA $rv $Codes "$Texte $($ReponseIA.reponse)" }
        # Une note qui redit seulement « ouvrir à l'heure » n'en est pas une
        if ($a.action -eq 'modifier' -and $a.ouvrir_au_debut -and $a.notes -and [string]$a.notes -match '(?i)\b(dossier|fichier|ouvr)') { $a.notes = $null }
        $nom = if ($rv) { Get-TitreAffiche $rv.Titre } else { '' }
        if ($a.action -in 'creer', 'modifier' -and $a.phrase) { Repair-ActionIA $a }
        if ($a.action -eq 'creer') {
            $p = Read-Phrase ([string]$a.phrase)
            # Une simple création : si la phrase de l'utilisateur, lue par les règles d'Evermind, dit plus que celle de
            # l'IA (répétition, plusieurs jours, autre jour ou heure), c'est elle qui compte : l'IA résume parfois trop
            # (« toutes les deux semaines le jeudi » devenu « le jeudi »)
            $seule = @($actions).Count -eq 1 -and (Get-IntentionsTexte $Texte).Creer -and -not (Get-IntentionsTexte $Texte).Supp -and -not (Get-IntentionsTexte $Texte).Modif
            if ($seule) {
                $pu = Read-Phrase $Texte
                if (-not $pu.Manque -and $pu.Titre -and ((Test-PhrasePlusRiche $pu $p) -or -not (Test-TitreDit $p.Titre $Texte))) {
                    Write-Log "Création : la phrase dite est mieux comprise que « $($a.phrase) »"
                    # Le moment vient de la phrase dite ; mais si son titre a gardé plusieurs phrases ou s'allonge
                    # beaucoup, celui de l'IA (court et propre) reste, avec ses personnes
                    if (-not $p.Manque -and $p.Titre -and (Test-TitreDit $p.Titre $Texte) -and ($pu.Titre -match '[.!?;]\s' -or $pu.Titre.Length -gt $p.Titre.Length + 20)) {
                        Write-Log "Création : titre de l'IA gardé (« $($p.Titre) » plutôt que « $($pu.Titre) »)"
                        $pu.Titre = $p.Titre; $pu.Avec = @($p.Avec)
                    }
                    $p = $pu
                }
            }
            if ($p.Manque) {
                $aCorriger = [string]$a.phrase
                [void]$dits.Add($Manques[$p.Manque]); [void]$ecrits.Add($Manques[$p.Manque])
                continue
            }
            $det = Get-DetailsPhrase $p
            if ($a.lieu) { $det.Lieu = [string]$a.lieu }
            if (@($a.personnes).Count) { $det.Avec = @(@($det.Avec) + @($a.personnes) | Where-Object { $_ } | Select-Object -Unique) }
            if ($a.notes) { $det.Notes = [string]$a.notes }
            if (@($a.choses_a_prendre).Count) { $det.APreparer = @(@($det.APreparer) + @($a.choses_a_prendre | Where-Object { $_ } | ForEach-Object { Get-Majuscule ([string]$_) }) | Select-Object -Unique) }
            if ($a.important) { $det.Important = $true }
            # Dossiers : ceux que l'IA a notés (des noms, retrouvés dans les dossiers de recherche, ou des chemins),
            # sinon ceux des personnes avec qui c'est (« réunion avec Monsieur Richard »)
            $doss = Resolve-Dossiers $a.dossiers
            if ($doss.Chemins.Count) { $det.Fichiers = @(@($det.Fichiers) + $doss.Chemins | Select-Object -Unique) }
            if (-not @($det.Fichiers).Count) { $det.Fichiers = @(Get-DossiersAuto ([string]$a.titre + ' ' + $p.Titre) $det.Avec) }
            if ($a.ouvrir_au_debut -or $Texte -match "(?i)\bouvr\w*\b.*\b(?:au d[ée]but|à l'heure|au moment|quand (?:elle|il|ça) commence)") { $det.OuvrirAuDebut = [bool]@($det.Fichiers).Count }
            if ($seule -and -not $pu.Manque) {
                # Les détails dits par l'utilisateur comptent même si l'IA les a oubliés (« un truc important : ... »)
                if ($pu.Important) { $det.Important = $true }
                if ($pu.Rappels -and -not $det.Rappels) { $det.Rappels = @($pu.Rappels) }
                if ($pu.Lieu -and -not $det.Lieu) { $det.Lieu = $pu.Lieu }
                if (@($pu.Avec).Count) { $det.Avec = @(@($det.Avec) + @($pu.Avec) | Where-Object { $_ } | Select-Object -Unique) }
                if (@($pu.APreparer).Count -and -not @($det.APreparer).Count) { $det.APreparer = @($pu.APreparer) }
            }
            $titre = if ($p.Titre) { $p.Titre } elseif ($a.titre) { [string]$a.titre } else { '' }
            # Déjà là : même nom, même moment et mêmes personnes (deux « Réunion » le même jour avec deux personnes différentes, c'est permis)
            $avecDit = (@($det.Avec | Where-Object { $_ } | ForEach-Object { Get-MotsNom $_ }) | Sort-Object) -join ' '
            $deja = @(Get-AgendaEntre $p.Quand.Date $p.Quand.Date.AddDays(1) | Where-Object {
                $_.RV.Titre -eq (Get-TitreAffiche $titre) -and ($p.Journee -or [math]::Abs(($_.Prochain - $p.Quand).TotalMinutes) -lt 1) -and
                ((@($_.RV.Avec | Where-Object { $_ } | ForEach-Object { Get-MotsNom $_ }) | Sort-Object) -join ' ') -eq $avecDit })
            if ($deja.Count) { [void]$dits.Add("$(Get-TitreAffiche $titre) est déjà dans ton agenda."); [void]$ecrits.Add("Déjà dans l'agenda : $(Get-TitreAffiche $titre)."); continue }
            $creations = @(Get-CreationsPhrase $p)
            $quands = @($creations | ForEach-Object { $_.Quand })
            $r = $null
            foreach ($c in $creations) { $det.Fin = $c.Fin; $x = Add-RendezVous (Get-TitreAffiche $titre) $c.Quand $p.Repetition $p.Type $p.Journee $det; if (-not $r) { $r = $x } }
            $cree = $r
            if (@($p.Blocs | Where-Object { $_ }).Count -gt 1) {
                $liste = @($creations | ForEach-Object { "du $($_.Quand.ToString('d', $Fr) -replace '/.*$', '') au $(([datetime]$_.Fin).ToString('d MMMM', $Fr))" })
                $txt = "$(($liste | Select-Object -SkipLast 1) -join ', ') et $($liste[-1])"
                [void]$ecrits.Add("C'est noté : $(Get-TitreAffiche $titre), $txt ($($creations.Count) événements).")
                [void]$dits.Add("C'est noté : $(Get-TitreAffiche $titre), $txt.")
                continue
            }
            if ($quands.Count -gt 1) {
                $liste = @($quands | ForEach-Object { $_.ToString('dddd d', $Fr) }); $mois = $quands[-1].ToString('MMMM', $Fr)
                $jours = "$(($liste | Select-Object -SkipLast 1) -join ', ') et $($liste[-1]) $mois"
                [void]$ecrits.Add("C'est noté : $(Get-TitreAffiche $titre), $jours ($($quands.Count) événements).")
                [void]$dits.Add("C'est noté : $(Get-TitreAffiche $titre), $jours.")
                continue
            }
            $n = Get-PhraseNote $r
            $tf = (Get-TexteFichiers $r).TrimEnd('.'); if ($tf) { $n.Ecrit += '.' + $tf; $n.Dit += '.' + $tf }
            $tf = Get-TexteSoucisDossiers $doss.Soucis $r; if ($tf) { $n.Ecrit += '.' + $tf; $n.Dit += '.' + $tf }
            [void]$ecrits.Add("C'est noté : $($n.Ecrit).")
            $dit = "C'est noté : $($n.Dit)."
            $conf = @(if (-not $r.Journee) { Get-Conflits $r.Quand $r.Fin $r.Id })   # (@ autour : un seul conflit se compte aussi)
            if ($conf.Count) { $dit += " Attention, tu as déjà $(Get-TitreAffiche $conf[0].RV.Titre) à ce moment-là."; [void]$ecrits.Add("⚠ En même temps que $(Get-TitreAffiche $conf[0].RV.Titre).") }
            # Un mot de date resté dans le titre : une partie de la phrase n'a pas été comprise, on le dit au lieu de faire semblant
            $reste = [regex]::Match(" $($r.Titre) ", "(?i)(?:\b(?:et|de|d'|du|en|à)\s+)*\b(?:$RxMois|$RxJour)s?\b(?:\s+\d{4})?|\b(?:19|20)\d{2}\b")
            if ($reste.Success -and $titre -notmatch '(?i)^anniversaire') {
                Write-Log "Création : « $($reste.Value.Trim()) » pas compris dans « $($a.phrase) »"
                $dit += " Par contre, je n'ai pas compris « $($reste.Value.Trim()) » : vérifie l'événement."
                [void]$ecrits.Add("⚠ Pas compris : « $($reste.Value.Trim()) ». Vérifie l'événement.")
            }
            [void]$dits.Add($dit)
        }
        elseif ($a.action -eq 'horaires') {
            $x = Get-TexteHoraires @(Add-HorairesTravail $a.Liste)
            [void]$dits.Add($x.Dit); [void]$ecrits.Add($x.Ecrit)
        }
        elseif ($a.action -eq 'annuler') {
            if (Restore-Annulation) { [void]$dits.Add('J''ai annulé ma dernière action.'); [void]$ecrits.Add('Dernière action annulée.') }
            else { [void]$dits.Add('Il n''y a rien à annuler.'); [void]$ecrits.Add('Rien à annuler.') }
        }
        elseif ($a.action -eq 'ouvrir') {
            $x = Invoke-OuvrirIA $rv $a
            [void]$dits.Add($x.Dit); [void]$ecrits.Add($x.Ecrit)
        }
        elseif (-not $rv) {
            [void]$dits.Add('Je n''ai pas trouvé de quel rendez-vous tu parles.'); [void]$ecrits.Add('Rendez-vous introuvable.')
        }
        elseif ($a.action -eq 'supprimer' -and @((Get-ModifsTexte $Texte $rv).Retirer).Count) {
            $gens = @((Get-ModifsTexte $Texte $rv).Retirer)
            $r = Invoke-ModifierIA $rv ([pscustomobject]@{ action = 'modifier'; retirer_personnes = $gens })
            [void]$dits.Add("J'ai retiré $($gens -join ' et ') de $nom."); [void]$ecrits.Add("Retiré de $($nom) : $($gens -join ', ').")
        }
        elseif ($a.action -eq 'supprimer') {
            if ($a.periode) { $x = Remove-PeriodeRV $rv ([string]$a.periode); [void]$dits.Add($x.Dit); [void]$ecrits.Add($x.Ecrit) }
            else {
                Remove-RendezVous $rv.Id
                $tout = if ($rv.Repetition) { ' (toutes les fois)' } else { '' }
                [void]$dits.Add("J'ai supprimé $nom$tout."); [void]$ecrits.Add("Supprimé : $nom$tout. (Dis « annule » pour revenir en arrière.)")
            }
        }
        elseif ($a.action -eq 'fait') {
            Set-RendezVousDetail $rv.Id 'Fait' $true
            [void]$dits.Add("Bien joué, $nom c'est fait."); [void]$ecrits.Add("Fait : $nom.")
        }
        elseif ($a.action -eq 'modifier') {
            # « même heure » : seule la date change, quelle que soit l'heure que l'IA a cru lire
            if ($a.phrase -and $Texte -match "(?i)\bm[êe]me (heure|horaire)") {
                $a.phrase = ([string]$a.phrase -replace "(?i)\s*(?:(?:de|à|a)\s+)?\d{1,2}\s*h(?:\s*\d{2})?(?:\s*(?:à|a|-)\s*\d{1,2}\s*h(?:\s*\d{2})?)?", '').Trim()
            }
            # Ce qu'Evermind lit lui-même dans la phrase, plus sûr que l'IA pour ces cas-là
            # (pas pour l'événement qu'on vient de créer : la phrase dite a déjà servi à le créer)
            $lu = if ($surCree) { @{ Retirer = @(); Rappels = @(); Personnes = @(); AuDebut = $false } } else { Get-ModifsTexte $Texte $rv }
            if ($lu.Arret) {
                # « le raid, c'est fini après novembre » : la série s'arrête (les fois d'après sont enlevées)
                $x = Remove-PeriodeRV $rv $lu.Arret; [void]$dits.Add($x.Dit); [void]$ecrits.Add($x.Ecrit); continue
            }
            if ($lu.Etendre) { Write-Log "Modification : étalé, « $($lu.Etendre) »"; $a | Add-Member -NotePropertyName phrase -NotePropertyValue $lu.Etendre -Force }
            elseif ($lu.Decalage) { $a | Add-Member -NotePropertyName phrase -NotePropertyValue $lu.Decalage -Force }
            elseif ($lu.Jour -and [string]$a.phrase -notmatch "(?i)\b$(($lu.Jour -split ' ')[0])") { Write-Log "Modification : le jour dit ($($lu.Jour)) remplace « $($a.phrase) »"; $a | Add-Member -NotePropertyName phrase -NotePropertyValue $lu.Jour -Force }
            if ($lu.Retirer.Count) { $a | Add-Member -NotePropertyName retirer_personnes -NotePropertyValue @(@($a.retirer_personnes) + $lu.Retirer | Where-Object { $_ } | Select-Object -Unique) -Force; if ($a.notes -and ([string]$a.notes).Length -lt 40) { $a.notes = $null } }
            if ($lu.AuDebut) { $a | Add-Member -NotePropertyName ouvrir_au_debut -NotePropertyValue $true -Force }
            if ($lu.Rappels.Count) { $a | Add-Member -NotePropertyName rappels -NotePropertyValue @(@($a.rappels) + $lu.Rappels | Where-Object { $_ } | Select-Object -Unique) -Force; if ($a.notes -and ([string]$a.notes) -match '(?i)pr[ée]ven|rappel') { $a.notes = $null } }
            if ($lu.Titre) { $a | Add-Member -NotePropertyName titre -NotePropertyValue $lu.Titre -Force; if ($a.phrase -and ([string]$a.phrase).Trim() -eq $lu.Titre) { $a.phrase = $null } }
            if ($lu.Personnes.Count) {
                $a | Add-Member -NotePropertyName personnes -NotePropertyValue @(@($a.personnes) + $lu.Personnes | Where-Object { $_ } | Select-Object -Unique) -Force
                # « Paul est invité » dans les notes : c'était juste la personne
                if ($a.notes -and ([string]$a.notes).Length -lt 40 -and @($lu.Personnes | Where-Object { ([string]$a.notes) -match [regex]::Escape($_) }).Count) { $a.notes = $null }
            }
            $r = Invoke-ModifierIA $rv $a
            if ($surCree) {
                # Un réglage de l'événement qu'on vient de créer : une petite phrase, pas un deuxième « c'est changé »
                $deja = ($dits -join ' ') -match "ouvrirai"
                $s = Get-TexteSoucisDossiers (Resolve-Dossiers $a.dossiers).Soucis $r
                if ($r.OuvrirAuDebut -and -not $deja) { [void]$dits.Add("J'ouvrirai $(if (@($r.Fichiers).Count -eq 1) { Get-NomFichier $r.Fichiers[0] } else { 'ses dossiers' }) à l'heure."); [void]$ecrits.Add('Ouverture à l''heure du rendez-vous.') }
                elseif ($a.ouvrir_au_debut -and -not @($r.Fichiers).Count) { [void]$dits.Add("Par contre, je n'ai pas trouvé de dossier à ouvrir."); [void]$ecrits.Add('Aucun dossier trouvé à ouvrir.') }
                elseif ($s) { [void]$dits.Add($s.Trim()); [void]$ecrits.Add($s.Trim()) }
                continue
            }
            $n = Get-PhraseNote $r
            $tf = Get-TexteSoucisDossiers (Resolve-Dossiers $a.dossiers).Soucis $null; if ($tf) { $n.Ecrit += '.' + $tf; $n.Dit += '.' + $tf }
            [void]$dits.Add("C'est changé : $($n.Dit)."); [void]$ecrits.Add("C'est changé : $($n.Ecrit).")
        }
    }
    if (-not $actions.Count) {
        $t = if ($ReponseIA.reponse) { [string]$ReponseIA.reponse } else { 'Je n''ai pas compris, tu peux reformuler ?' }
        [void]$dits.Add($t); [void]$ecrits.Add($t)
    }
    $ecrit = (@($ecrits) | Select-Object -Unique) -join ' '
    $dit = (@($dits) | Select-Object -Unique) -join ' '
    Set-VoixEtat "Tu as dit : « $Texte »"
    Show-FormMessage $ecrit $(if ($aCorriger -or -not $actions.Count) { '#C9C3DD' } else { $Colors.ok })
    if ($aCorriger) {
        # Il manque quelque chose pour créer : la phrase va dans la barre pour la compléter
        Show-MainWindow
        $ui.InPhrase.Text = $aCorriger; $ui.InPhrase.CaretIndex = $aCorriger.Length; [void]$ui.InPhrase.Focus()
    } elseif ($Source -eq 'barre') { $ui.InPhrase.Text = '' }
    if ($Source -eq 'voix') { Show-Bulle $ecrit 6000 }
    if ($Source -ne 'barre' -or -not $actions.Count) { Invoke-Parole $dit }
    Update-Agenda
}

# Supprimer seulement certaines fois d'un rendez-vous qui revient, comme les grands agendas (cette fois, les suivantes...) :
#   plus rien ne reste : il est supprimé ; les premières fois : il recommence plus tard ; les dernières : il s'arrête
#   plus tôt (Jusqua) ; au milieu : ces jours-là sont sautés (Sauf).
function Copy-Repetition($Rep) {
    $r = [ordered]@{}
    foreach ($k in 'Type', 'Jour', 'Mois', 'Jours', 'Intervalle', 'Rang', 'Jusqua', 'Sauf') { if ($null -ne $Rep.$k) { $r[$k] = $Rep.$k } }
    $r
}

function Remove-PeriodeRV($rv, [string]$Periode) {
    $nom = Get-TitreAffiche $rv.Titre
    $per = Read-Periode $Periode
    if (-not $per -and $Periode -match "(?i)\b(?:tous|toutes|tout|toujours|chaque|enti[èe]re?)\b") { $per = @{ Debut = $null; Fin = $null } }   # « tous les mois » : toutes les fois
    if (-not $per) { return @{ Dit = "Je n'ai pas compris quelles dates enlever pour $nom, je n'ai rien touché."; Ecrit = "Rien supprimé : je n'ai pas compris « $Periode »." } }
    $D = $per.Debut; $F = $per.Fin; $J = @($per.Jours | Where-Object { $_ })
    # (jours dits un par un : ceux-là seulement, pas ceux d'entre eux)
    # (« $jour », pas « $d » : PowerShell confond $d et $D, le début de la période)
    $dans = { param($jour) if ($J.Count) { return $J -contains $jour.Date }; (-not $D -or $jour -ge $D) -and (-not $F -or $jour -le $F) }
    $annule = ' (Dis « annule » pour revenir en arrière.)'
    if (-not $rv.Repetition) {
        if (& $dans $rv.Quand.Date) { Remove-RendezVous $rv.Id; return @{ Dit = "J'ai supprimé $nom."; Ecrit = "Supprimé : $nom.$annule" } }
        return @{ Dit = "$nom n'est pas à ces dates-là, je n'ai rien supprimé."; Ecrit = "Rien supprimé : $nom n'est pas à ces dates-là." }
    }
    # Toutes les fois de la série (jusqu'à sa fin, ou sur 3 ans si elle ne s'arrête jamais)
    $occ = New-Object System.Collections.ArrayList
    $limite = $rv.Quand.AddYears(3); $from = $rv.Quand
    for ($i = 0; $i -lt 1200; $i++) {
        $q = Get-NextOccurrence $rv.Repetition $rv.Quand $from
        if ($q -eq [datetime]::MinValue -or $q -lt $from -or $q -gt $limite) { break }
        [void]$occ.Add($q); $from = $q.AddMinutes(1)
    }
    $fini = [bool]$rv.Repetition.Jusqua
    $enlevees = @($occ | Where-Object { & $dans $_.Date })
    if (-not $enlevees.Count) { return @{ Dit = "Il n'y a pas de $nom à ces dates-là, je n'ai rien supprimé."; Ecrit = "Rien supprimé : pas de $nom à ces dates-là." } }
    $avant = @($occ | Where-Object { $D -and $_.Date -lt $D })
    $apres = @($occ | Where-Object { $F -and $_.Date -gt $F })
    $rep = Copy-Repetition $rv.Repetition
    $quand = $rv.Quand
    $n = if ($enlevees.Count -eq 1) { "le $($enlevees[0].ToString('dddd d MMMM', $Fr))" } else { "$($enlevees.Count) fois" }
    if (-not $avant.Count -and -not $apres.Count -and ($fini -or -not $F)) {
        Remove-RendezVous $rv.Id
        return @{ Dit = "J'ai supprimé $nom (toutes les fois)."; Ecrit = "Supprimé : $nom, toutes les fois.$annule" }
    }
    if (-not $avant.Count) {
        $quand = $apres[0]; $dit = "J'ai enlevé $nom $n. Il reprend le $($quand.ToString('dddd d MMMM', $Fr))."
    } elseif (-not $apres.Count -and ($fini -or -not $F)) {
        $rep.Jusqua = $D.AddDays(-1).ToString('yyyy-MM-dd')
        # (une série qui ne s'arrêtait pas : « s'arrête », plutôt que « enlevé 150 fois »)
        $dit = if ($F) { "J'ai enlevé $nom $n. Le dernier est le $($avant[-1].ToString('dddd d MMMM', $Fr))." } else { "C'est noté : $nom s'arrête. Le dernier est le $($avant[-1].ToString('dddd d MMMM', $Fr))." }
    } else {
        $rep.Sauf = @(@($rep.Sauf) + @($enlevees | ForEach-Object { $_.ToString('yyyy-MM-dd') }) | Where-Object { $_ } | Select-Object -Unique | Select-Object -Last 300)
        $dit = "J'ai enlevé $nom $n. Les autres fois restent."
    }
    $fin = if ($rv.Fin) { $quand + ($rv.Fin - $rv.Quand) } else { $null }
    [void](Update-RendezVous $rv.Id $rv.Titre $quand $rep (Get-TypeRV $rv) ([bool]$rv.Journee) @{ Fin = $fin })
    @{ Dit = $dit; Ecrit = "$dit$annule" }
}

# « Ouvre le dossier de Monsieur Richard » : les fichiers d'un rendez-vous, sinon un dossier retrouvé par son nom.
# Un rendez-vous sans fichiers mais dont Evermind trouve le dossier : il l'ouvre, et le relie au passage.
function Invoke-OuvrirIA($rv, $a) {
    $chemins = @()
    if ($rv -and @($rv.Fichiers).Count) { $chemins = @($rv.Fichiers) }
    elseif ($rv) {
        $chemins = @(Get-DossiersAuto $rv.Titre $rv.Avec)
        if ($chemins.Count) { Set-RendezVousDetail $rv.Id 'Fichiers' $chemins }
    }
    if (-not $chemins.Count) { $doss = Resolve-Dossiers $a.dossiers; $chemins = @($doss.Chemins) }
    if (-not $chemins.Count) {
        if (@($doss.Soucis).Count) { $s = Get-Majuscule $doss.Soucis[0]; return @{ Dit = "$s."; Ecrit = "$s." } }
        $nom = @(@($a.dossiers) + $(if ($rv) { $rv.Titre })) | Where-Object { $_ } | Select-Object -First 1
        return @{ Dit = "Je n'ai pas trouvé de dossier $(if ($nom) { "pour $nom" }). Ajoute-le dans la fiche du rendez-vous, ou dans les dossiers où je cherche (Réglages)."; Ecrit = "Dossier introuvable$(if ($nom) { " : $nom" }). (Réglages, Général : les dossiers où je cherche.)" }
    }
    $n = 0; foreach ($f in $chemins) { if (Open-Fichier $f) { $n++ } }
    $quoi = if ($chemins.Count -eq 1) { Get-NomFichier $chemins[0] } else { "$($chemins.Count) dossiers et fichiers" }
    @{ Dit = "J'ouvre $quoi."; Ecrit = "Ouvert : $(@($chemins | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')." }
}

# Ouvrir tout de suite, dit clairement (« ouvre le dossier de Monsieur Richard ») : sans attendre l'avis de l'IA.
# Retourne l'action, ou $null (« au début de la réunion » est une modification, pas une ouverture maintenant).
function Get-OuvertureTexte([string]$Texte) {
    $t = $Texte.Trim()
    if ($t -match "(?i)\b(?:au d[ée]but|à l'heure|au moment|quand (?:elle|il|ça) commence|demain|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b") { return $null }
    $m = [regex]::Match($t, "(?i)^\W*(?:(?:ok\W+)?[èe]ve\W+)?(?:(?:est-ce que )?(?:tu peux|peux-tu|pourrais-tu)\s+(?:m'|me\s+)?|(?:je veux|j'aimerais|il faut) que tu\s+(?:m'|me\s+)?)?ouvr\w*(?:[- ]moi)?\s+(?:le|les|mon|mes)\s+(?:dossier|dossiers|fichiers?|documents?)\s+(?:(?:de|du|des|pour)\s+|d')?(?<n>.+?)\s*[.!?]*$")
    if (-not $m.Success) { return $null }
    $n = $m.Groups['n'].Value -replace "(?i)^(?:la |le |l'|ma |mon )?(?:r[ée]union|rendez-vous|rdv)\s+(?:avec\s+)?", ''
    [pscustomobject]@{ action = 'ouvrir'; dossiers = @($n.Trim()) }
}

# Suppression de tout ce qui tombe dans une période : la liste des actions, ou $null si la phrase ne demande pas ça.
# « mes rendez-vous » laisse les anniversaires ; « tout ce que j'ai », « tout », « mon agenda » les enlève aussi.
function Get-SuppressionsPeriode([string]$Texte) {
    $t = $Texte.Trim()
    $m = [regex]::Match($t, "(?i)\b(?:supprim|suprim|efface|enl[èe]v|vide|annul|retir|vire)\w*\s+(?:moi\s+)?(?:(?<tout>tout|toute)s?\s+)?(?:(?:mes|les)\s+(?<quoi>rendez-vous|rdv|[ée]v[ée]nements?|trucs|activit[ée]s|cr[ée]neaux)|(?<tout2>tout ce que j'ai(?: de pr[ée]vu)?|tout mon agenda|mon agenda))\s+(?<p>.+?)\s*[.!?]?$")
    if (-not $m.Success) { return $null }
    # (« de » seul, pas le début de « demain »)
    $per = Read-Periode ($m.Groups['p'].Value -replace "^(?i)(?:(?:de|du|des|pour|pendant)\s+|d')", '')
    if (-not $per -or -not $per.Debut -or -not $per.Fin) { return $null }
    $tout = $m.Groups['tout'].Success -or $m.Groups['tout2'].Success -or $m.Groups['quoi'].Value -match '(?i)v[ée]nement|truc|activit'
    $vus = @{}
    @(Get-AgendaEntre $per.Debut $per.Fin.AddDays(1) | Where-Object { $tout -or (Get-TypeRV $_.RV) -ne 'anniv' } | ForEach-Object {
        if (-not $vus.ContainsKey($_.RV.Id)) { $vus[$_.RV.Id] = 1; [pscustomobject]@{ action = 'supprimer'; Cible = $_.RV; periode = $m.Groups['p'].Value } }
    })
}

# Ce qu'une demande de modification dit clairement, lu sans l'IA :
#   Decalage : « repousse d'une heure », « avance de 30 minutes », « décale de 2 jours » (nouveau moment, en mots)
#   Titre : « renomme le foot en match de foot » ; Personnes : « ajoute Paul et Inès », « invite Tom »
#   Arret : « le raid, c'est fini après novembre », « plus de raid à partir de décembre » (période à enlever)
function Get-ModifsTexte([string]$Texte, $rv) {
    $res = @{ Decalage = $null; Titre = $null; Personnes = @(); Arret = $null; Retirer = @(); Rappels = @(); Jour = $null; AuDebut = $false }
    # « ouvre son dossier au début de la réunion » : ses fichiers s'ouvriront tout seuls à l'heure
    if ($Texte -match "(?i)\bouvr\w*\b.*\b(?:au d[ée]but|à l'heure|au moment|quand (?:elle|il|ça) commence)") { $res.AuDebut = $true }
    $t = $Texte.Trim()
    $majX = "[A-ZÉÈÊÀÂÎÏÔÛÇ][\p{L}'-]+"
    # « retire Tom de la soirée » : seulement des gens qui y sont
    foreach ($m in [regex]::Matches($t, "\b(?:[Rr]etire|[Ee]nl[èe]ve|[Ss]upprime|[Vv]ire)\s+(?<n>$majX(?:\s*(?:,|et)\s*$majX)*)\s+(?:de|du|des|d')")) {
        $res.Retirer += @($m.Groups['n'].Value -split '\s*(?:,|\bet\b)\s*' | Where-Object { $n = $_; $rv -and @($rv.Avec | Where-Object { $_ -ieq $n }).Count })
    }
    if ($t -match "(?i)\b(?:pr[ée]viens|rappelle|avertis|rappel)") { $res.Rappels = @(Read-RappelsTexte $t) }
    # « mets la soirée sur deux jours », « étale le séminaire sur une semaine » (sans autre date) : à partir de son jour
    if ($rv -and $t -match "(?i)\b(?:sur|pendant|durant)\s+(?<n>$RxNombre|une|un)\s+(?<u>jours?|semaines?)\b" -and $t -notmatch "(?i)\b(?:$RxJour|$RxMois|demain|aujourd'hui|apr[èe]s-demain)\b") {
        $nDit = $Matches['n']; $uDit = $Matches['u']   # (gardés avant tout autre -match, qui écraserait $Matches)
        $n = ConvertFrom-Nombre $(if ($nDit -match '^une?$') { '1' } else { $nDit })
        if ($uDit -match '^s') { $n *= 7 }
        if ($n -ge 2 -and $n -le 366) {
            $base = Get-NextOccurrence $rv.Repetition $rv.Quand (Get-Date).Date; if ($base -eq [datetime]::MinValue) { $base = $rv.Quand }
            $res.Etendre = "le $($base.ToString('d MMMM yyyy', $Fr))$(if (-not $rv.Journee) { ' à ' + (Format-Heure $base) }) sur $n jours"
        }
    }
    # « déplace le foot à la semaine prochaine (même jour, même heure) »
    if ($rv -and $t -match "(?i)\b(?:d[ée]cal|d[ée]plac|repouss|report|mets|passe)\w*\b.*?\b(?:à|a)\s+la\s+semaine\s+(?:prochaine|d'apr[èe]s|suivante)") {
        $base = Get-NextOccurrence $rv.Repetition $rv.Quand (Get-Date); if ($base -eq [datetime]::MinValue) { $base = $rv.Quand }
        $n7 = $base.AddDays(7)
        $res.Decalage = "le $($n7.ToString('d MMMM yyyy', $Fr))$(if (-not $rv.Journee) { " à $($n7.Hour) h $($n7.ToString('mm'))" })"
    }
    # Nouveau jour de la semaine (« le raid passe au mardi », « le foot c'est plutôt vendredi ») : si l'IA ne l'a pas repris,
    # c'est le jour dit qui compte (à la même heure, ou à l'heure dite)
    if ($rv -and -not $res.Decalage -and ((Get-IntentionsTexte $t).Modif -or $t -match "(?i)\b(?:passe|bouge|plut[ôo]t|maintenant)\b")) {
        $wds = @([regex]::Matches($t.ToLower(), "\b$RxJour") | ForEach-Object { $_.Value } | Select-Object -Unique)
        if ($wds.Count -eq 1 -and $t -notmatch "(?i)\b\d{1,2}\s+$RxMois") {
            $h = [regex]::Match($t, "(?i)\b\d{1,2}\s*h(?:\s*\d{2})?\b|\bmidi\b")
            $res.Jour = "$($wds[0])$(if ($h.Success) { " à $($h.Value)" })"
        }
    }
    # Série chaque mois : « le loyer, c'est le 3 maintenant »
    if ($rv -and $rv.Repetition -and [string]$rv.Repetition.Type -eq 'mois' -and -not $rv.Repetition.Rang) {
        $m = [regex]::Match($t, "(?i)\b(?:le|au)\s+(?<d>\d{1,2}|1er|premier)\b(?!\s*(?:(?:$RxMois)\b|/|h\b|heures?|:))")
        if ($m.Success) { $d = ConvertFrom-Nombre ($m.Groups['d'].Value -replace 'er$', ''); if ($d -ge 1 -and $d -le 31) { $res.Decalage = "le $d de chaque mois" } }
    }
    $m = [regex]::Match($t, "(?i)\b(?<v>repouss|d[ée]cal|recul|retard|avanc)\w*\b.*?\b(?:de\s+|d')(?:(?<n>\d+|une?|deux|trois|quatre|cinq|six|sept|huit|dix|quinze|trente|quarante-cinq)\s*(?<u>heures?|h\b|minutes?|min\b|jours?|semaines?)|(?<dh>une demi[- ]heure)|(?<qh>un quart d'heure))")
    if ($m.Success -and $rv) {
        $n = if ($m.Groups['dh'].Success) { 30; $u = 'm' } elseif ($m.Groups['qh'].Success) { 15; $u = 'm' } else { ConvertFrom-Nombre ($m.Groups['n'].Value -replace '^une?$', 'un') }
        if (-not $m.Groups['dh'].Success -and -not $m.Groups['qh'].Success) { $u = $m.Groups['u'].Value.ToLower().Substring(0, 1) }
        if ($n -and $n -gt 0) {
            $signe = if ($m.Groups['v'].Value -match '^(?i)avanc') { -1 } else { 1 }
            $base = Get-NextOccurrence $rv.Repetition $rv.Quand (Get-Date)
            if ($base -eq [datetime]::MinValue) { $base = $rv.Quand }
            $nouveau = switch ($u) { 'h' { $base.AddHours($signe * $n) } 'm' { $base.AddMinutes($signe * $n) } 'j' { $base.AddDays($signe * $n) } 's' { $base.AddDays(7 * $signe * $n) } }
            $res.Decalage = "le $($nouveau.ToString('d MMMM yyyy', $Fr))$(if (-not $rv.Journee) { " à $($nouveau.Hour) h $($nouveau.ToString('mm'))" })"
        }
    }
    $m = [regex]::Match($t, "(?i)\b(?:renomme|rebaptise|appelle)[- ]?(?:le|la|les|l')?\b.*?\s+en\s+(?<t>.+?)\s*[.!]?$")
    if (-not $m.Success) { $m = [regex]::Match($t, "(?i)\bchange\s+(?:le\s+)?(?:nom|titre)\b.*?\s+en\s+(?<t>.+?)\s*[.!]?$") }
    if ($m.Success) { $res.Titre = $m.Groups['t'].Value.Trim(' «»"''') }
    $maj = "[A-ZÉÈÊÀÂÎÏÔÛÇ][\p{L}'-]+"
    foreach ($m in [regex]::Matches($t, "\b(?:[Aa]joute|[Rr]ajoute|[Ii]nvite)\s+(?<n>$maj(?:\s*(?:,|et)\s*$maj)*)")) {
        $res.Personnes += @($m.Groups['n'].Value -split '\s*(?:,|\bet\b)\s*' | Where-Object { $_ -and $_ -cmatch '^[A-ZÉÈÊÀÂÎÏÔÛÇ]' })
    }
    if ($rv -and $rv.Repetition -and $t -match "(?i)\b(?:c'est fini|fini|termin\w*|arr[êe]t\w*|stop\w*|plus de|plus d')\b") {
        $m = [regex]::Match($t, "(?i)(?<p>(?:apr[èe]s|[àa] partir d(?:u|e|')|d[èe]s|depuis)\s*.+?)\s*[.!]?$")
        if ($m.Success -and (Read-Periode $m.Groups['p'].Value)) { $res.Arret = $m.Groups['p'].Value }
    }
    $res
}

# Modifier : nouveau moment (lu par les règles d'Evermind), titre, lieu, personnes, notes, choses à prendre
function Invoke-ModifierIA($rv, $a) {
    $quand = $rv.Quand; $rep = $rv.Repetition; $journee = [bool]$rv.Journee
    $duree = if ($rv.Fin) { $rv.Fin - $rv.Quand } else { $null }
    $fin = $rv.Fin
    if ($a.phrase) {
        $p = Read-Phrase ([string]$a.phrase)
        $base = (Get-NextOccurrence $rv.Repetition $rv.Quand (Get-Date).Date).Date
        if ($base -eq [datetime]::MinValue) { $base = $rv.Quand.Date }
        $nouveau = $null
        # Juste un jour (« jeudi ») pour un rendez-vous qui a une heure : il garde son heure
        # (sauf pour le mettre sur plusieurs jours : « du 27 au 29 octobre » devient un événement de plusieurs jours)
        $plusieurs = $p.Fin -and $p.Quand -and ([datetime]$p.Fin).Date -gt ([datetime]$p.Quand).Date
        $jourSeul = $p.Journee -and -not $journee -and $null -eq $p.Heure -and [string]$a.phrase -notmatch '(?i)journée' -and -not $plusieurs
        if ($p.Quand -and -not $jourSeul) { $nouveau = $p.Quand; $journee = [bool]$p.Journee }
        elseif ($p.Jour) { $nouveau = $p.Jour + $rv.Quand.TimeOfDay }                  # nouveau jour, même heure
        elseif ($null -ne $p.Heure) { $nouveau = $base + $p.Heure; $journee = $false }  # même jour, nouvelle heure
        elseif ($p.Repetition) {
            # Seulement la répétition change (« tous les lundis jusqu'au 31 octobre ») : il garde son heure
            $n = Get-NextOccurrence $p.Repetition ((Get-Date).Date + $rv.Quand.TimeOfDay) (Get-Date).Date
            $nouveau = if ($n -ne [datetime]::MinValue) { $n } else { $rv.Quand }
        }
        if ($nouveau) {
            $quand = $nouveau
            if ($p.Repetition) { $rep = $p.Repetition }
            elseif ($rep) {
                # Un rendez-vous qui revient suit son nouveau jour
                $rep = switch ([string]$rep.Type) {
                    'semaine' { [ordered]@{ Type = 'semaine'; Jour = [int]$quand.DayOfWeek } }
                    'mois'    { [ordered]@{ Type = 'mois'; Jour = $quand.Day } }
                    'an'      { [ordered]@{ Type = 'an'; Jour = $quand.Day; Mois = $quand.Month } }
                    default   { $rep }
                }
                if ($rep -is [Collections.IDictionary]) {
                    if ($rv.Repetition.Jusqua) { $rep.Jusqua = [string]$rv.Repetition.Jusqua }   # garde sa date de fin
                    if ($rv.Repetition.Intervalle) { $rep.Intervalle = [int]$rv.Repetition.Intervalle }   # et son rythme
                }
            }
            $fin = if ($p.Fin) { $p.Fin } elseif ($duree -and -not $journee) { $quand + $duree } else { $null }
        }
    }
    $det = @{ Fin = $fin }
    if ($a.lieu) { $det.Lieu = [string]$a.lieu }
    if (@($a.personnes).Count) { $det.Avec = @(@($rv.Avec) + @($a.personnes) | Where-Object { $_ } | Select-Object -Unique) }
    if ($a.notes) { $det.Notes = (@($rv.Notes, [string]$a.notes) | Where-Object { $_ }) -join "`n" }
    if (@($a.choses_a_prendre).Count) {
        $deja = @($rv.APreparer | ForEach-Object { $_.Texte })
        $det.APreparer = @(@($rv.APreparer) + @($a.choses_a_prendre | Where-Object { $_ -and $deja -notcontains $_ } | ForEach-Object { [pscustomobject]@{ Texte = (Get-Majuscule ([string]$_)); Fait = $false } }))
    }
    if ($null -ne $a.important) { $det.Important = [bool]$a.important }
    if (@($a.rappels | Where-Object { $_ }).Count) {
        $codes = @(@($a.rappels) | ForEach-Object { if ([string]$_ -match '^(m\d+|veille|matin)$') { [string]$_ } else { Read-RappelsTexte ([string]$_) } } | Where-Object { $_ })
        if ($codes.Count) { $det.Rappels = @(@(Get-RappelsRV $rv) + $codes | Select-Object -Unique) }
    }
    if (@($a.dossiers | Where-Object { $_ }).Count) {
        $ajout = @((Resolve-Dossiers $a.dossiers).Chemins)
        if ($ajout.Count){ $det.Fichiers = @(@($rv.Fichiers) + $ajout | Select-Object -Unique) }
    }
    if ($null -ne $a.ouvrir_au_debut) {
        if (-not $det.Contains('Fichiers') -and [bool]$a.ouvrir_au_debut -and -not @($rv.Fichiers).Count) { $det.Fichiers = @(Get-DossiersAuto $rv.Titre $rv.Avec) }
        $det.OuvrirAuDebut = [bool]$a.ouvrir_au_debut -and (@($rv.Fichiers).Count -or @($det.Fichiers).Count)
    }
    if (@($a.retirer_personnes | Where-Object { $_ }).Count) {
        $avant = if ($det.Contains('Avec')) { @($det.Avec) } else { @($rv.Avec) }
        $det.Avec = @($avant | Where-Object { $x = $_; -not @($a.retirer_personnes | Where-Object { $_ -ieq $x }).Count })
    }
    $titre = if ($a.titre -and $a.titre -ne $rv.Titre) { [string]$a.titre } else { $rv.Titre }
    Update-RendezVous $rv.Id (Get-TitreAffiche $titre) $quand $rep (Get-TypeRV $rv) $journee $det
}
