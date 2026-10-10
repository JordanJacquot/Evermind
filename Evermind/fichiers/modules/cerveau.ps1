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
    foreach ($it in ($liste | Sort-Object Prochain | Select-Object -First 40)) {
        $r = $it.RV; $c = 'e' + $r.Id.Substring(0, 5); $codes[$c] = $r.Id   # même code d'une phrase à l'autre
        $l = "- [$c] $(Get-TitreAffiche $r.Titre) ($($Types[(Get-TypeRV $r)].Nom)) : $(Format-QuandRV $r $it.Prochain) ($(Format-Relatif $it.Prochain))"
        $rep = Format-Repetition $r.Repetition
        if ($rep) { $l += ", revient $rep" }
        if ($r.Lieu) { $l += ". Lieu : $($r.Lieu)" }
        if (@($r.Avec).Count) { $l += ". Avec : $(@($r.Avec) -join ', ')" }
        if (@($r.APreparer).Count) { $l += ". À prendre : $(@($r.APreparer | ForEach-Object { $_.Texte }) -join ', ')" }
        if ($r.Notes) { $l += ". Notes : $($r.Notes -replace '\s+', ' ')" }
        if ($r.Important) { $l += '. Important' }
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
- "modifier" : changer un rendez-vous existant, désigné par "id". Pour changer le jour ou l'heure, mets dans "phrase" le nouveau moment avec les mots de l'utilisateur (ex : « jeudi à 15 h ») : jamais de numéro de jour que tu aurais calculé. Sinon : "titre", "lieu", "personnes" (gens à ajouter), "notes", "choses_a_prendre" (objets à emporter ou choses à préparer), "important".
- "supprimer" : enlever un rendez-vous ("id").
- "fait" : une chose à faire est terminée ("id").
- "annuler" : défaire la dernière chose qu'Evermind a faite.
Pour une question sur l'agenda ou une simple discussion, ne mets aucune action et réponds dans "reponse" en t'appuyant sur l'agenda.
Le verbe décide de l'action : « crée », « crées », « ajoute », « note », « mets », « programme » = creer (même s'il dit « l'événement ») ; « supprime », « efface », « enlève », « retire » = supprimer ; « décale », « déplace », « change », « c'est plutôt » = modifier. Tu ne demandes « lequel ? » que pour supprimer ou modifier, jamais pour créer.
Un rendez-vous sans heure est pour toute la journée : ne demande jamais l'heure, garde juste le jour dans « phrase ». Une liste (courses, choses à emporter) va dans « choses_a_prendre », un élément par case.
La phrase vient d'une dictée qui se trompe parfois : un mot qui ne veut rien dire est sûrement un mot proche (« sucrime » = supprime, « décade » = décale, « effaces-le » = efface). Devine le bon mot ; si tu n'es vraiment pas sûr, demande au lieu d'agir. N'écris jamais dans les notes un mot que tu n'as pas compris.
Tu peux faire plusieurs actions d'un coup (« supprime tout ce que j'ai demain »).
Pour désigner un rendez-vous, sers-toi de son nom, de sa date ou de sa sorte (« l'événement du 23 octobre », « mon rendez-vous de mardi », « l'anniversaire »).
Si tu ne sais vraiment pas de quel rendez-vous il parle, ne fais rien et demande-lui lequel en citant leurs noms.
Tu te souviens de la conversation : si l'utilisateur répond à ta question « lequel ? », fais sur ce rendez-vous l'action qu'il demandait juste avant (supprimer, décaler...). Ne recrée jamais un rendez-vous qui est déjà dans l'agenda.
Règles : ne montre jamais les identifiants à l'utilisateur. Ne remplis "notes", "lieu", "personnes", "choses_a_prendre" que si l'utilisateur les dit vraiment. Toute demande de rappel, de chose à ne pas oublier ou d'événement à noter est une action "creer".

Exemples, avec un AUTRE agenda imaginaire (ne les confonds jamais avec le vrai agenda ci-dessus) :
  [p1] Piscine : lundi 3 mars à 18 h. [b2] Bowling avec les potes : vendredi 7 mars à 21 h. [c3] Coiffeur : mardi 4 mars à 10 h.
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
{"actions":[{"action":"modifier","id":"b2","phrase":"samedi à 21 h"}],"reponse":"Le bowling passe à samedi, 21 h."}
Utilisateur : « la piscine c'est plutôt à 19 h »
{"actions":[{"action":"modifier","id":"p1","phrase":"lundi à 19 h"}],"reponse":"La piscine passe à 19 h lundi."}
Utilisateur : « pour la piscine, prends mon bonnet »
{"actions":[{"action":"modifier","id":"p1","choses_a_prendre":["bonnet"]}],"reponse":"J'ai noté le bonnet pour la piscine."}
Utilisateur : « j'aimerais que tu effaces l'événement du 4 mars »
(le 4 mars, il n'y a que le coiffeur) {"actions":[{"action":"supprimer","id":"c3"}],"reponse":"C'est fait, j'ai effacé le coiffeur du 4 mars."}
Utilisateur : « supprime le rendez-vous de lundi »
(lundi, il n'y a que la piscine) {"actions":[{"action":"supprimer","id":"p1"}],"reponse":"J'ai supprimé la piscine de lundi."}
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
                action = @{ type = 'string'; enum = @('creer', 'modifier', 'supprimer', 'fait', 'annuler') }
                id = @{ type = 'string' }; phrase = @{ type = 'string' }; titre = @{ type = 'string' }; lieu = @{ type = 'string' }
                personnes = @{ type = 'array'; items = @{ type = 'string' } }; notes = @{ type = 'string' }
                choses_a_prendre = @{ type = 'array'; items = @{ type = 'string' } }; important = @{ type = 'boolean' }
            } } }
        reponse = @{ type = 'string' }
    }
}

# ---------------------------------------------------------------------------
# Demander à l'IA (en arrière plan : la fenêtre reste fluide)
# ---------------------------------------------------------------------------
# Source : 'voix', 'barre' (texte tapé) ou 'test'. Retourne $false si l'assistant n'est pas là.
function Invoke-Commande([string]$Texte, [string]$Source, $Relance) {
    if ($script:Demande -and -not $Relance) { return $true }   # une question à la fois
    if (-not (Start-Cerveau)) { return $false }
    $ctx = Get-ContexteIA
    # Mémoire de la conversation : les 3 derniers échanges, s'ils datent de moins de 3 minutes
    if (-not $script:Conversation -or ((Get-Date) - $script:ConversationQuand).TotalMinutes -gt 3) { $script:Conversation = New-Object System.Collections.ArrayList }
    $messages = @(@{ role = 'system'; content = $ctx.Systeme }) + @($script:Conversation | Select-Object -Last 6) + @(@{ role = 'user'; content = $Texte })
    if ($Relance) { $messages = @($Relance.Messages) + @(@{ role = 'assistant'; content = $Relance.Reponse }, @{ role = 'user'; content = $Relance.Correction }); $ctx.Codes = $Relance.Codes }
    $corps = @{ messages = $messages
                temperature = 0; max_tokens = 400
                response_format = @{ type = 'json_schema'; json_schema = @{ name = 'reponse'; schema = $SchemaIA } } } | ConvertTo-Json -Depth 20 -Compress
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
    # Réponse qui dit « c'est fait » sans aucune action : l'IA s'est trompée, on lui redemande une fois en le lui signalant
    $sansAction = -not @($reponse.actions | Where-Object { $_ -and $_.action }).Count
    if ($sansAction -and [string]$reponse.reponse -match "(?i)\b(c'est noté|j'ai (noté|ajouté|créé|mis|supprimé|effacé|enlevé|décalé|déplacé|changé|modifié|annulé)|c'est fait|est (supprimé|décalé|ajouté|noté))") {
        if (-not $d.Relance) {
            Write-Log 'Assistant : réponse sans action, on lui redemande'
            $script:Demande = $null
            [void](Invoke-Commande $d.Texte $d.Source @{ Messages = $d.Messages; Codes = $d.Codes; Reponse = ($reponse | ConvertTo-Json -Depth 6 -Compress)
                Correction = 'Tu as répondu que c''était fait, mais "actions" est vide : rien n''a été fait. Redonne le JSON avec la bonne action.' })
            return
        }
        # Toujours rien : pour une création, les règles d'Evermind s'en chargent
        $p = Read-Phrase $d.Texte
        if (-not $p.Manque -and $d.Texte -match "(?i)\b(cr[ée]{1,2}[rsz]?|ajoute[rsz]?|note[rsz]?|met[st]?|mettre|programme[rsz]?)\b" -and $d.Texte -notmatch "(?i)\b(supprime|efface|enl[èe]ve|retire|d[ée]cale|d[ée]place|change|modifie)") {
            Write-Log 'Assistant : création faite par les règles'
            $reponse = [pscustomobject]@{ actions = @([pscustomobject]@{ action = 'creer'; phrase = $d.Texte }); reponse = '' }
        }
    }
    # Retenu pour la phrase suivante (« lequel ? » puis « le dentiste »)
    [void]$script:Conversation.Add(@{ role = 'user'; content = $d.Texte })
    [void]$script:Conversation.Add(@{ role = 'assistant'; content = ($reponse | ConvertTo-Json -Depth 6 -Compress) })
    $script:ConversationQuand = Get-Date
    Invoke-ActionsIA $reponse $d.Codes $d.Texte $d.Source
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

function Invoke-ActionsIA($R, $Codes, [string]$Texte, [string]$Source) {
    $dits = New-Object System.Collections.ArrayList
    $ecrits = New-Object System.Collections.ArrayList
    $aCorriger = $null
    $actions = @($R.actions | Where-Object { $_ -and $_.action })
    if (@($actions | Where-Object { $_.action -ne 'annuler' }).Count) { Save-Annulation }
    foreach ($a in $actions) {
        $rv = $null
        if ($a.id) { $code = ([string]$a.id).Trim('[] '); if ($Codes.ContainsKey($code)) { $rv = Get-RendezVous $Codes[$code] } }
        $nom = if ($rv) { Get-TitreAffiche $rv.Titre } else { '' }
        if ($a.action -eq 'creer') {
            $p = Read-Phrase ([string]$a.phrase)
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
            $titre = if ($p.Titre) { $p.Titre } elseif ($a.titre) { [string]$a.titre } else { '' }
            $deja = @(Get-AgendaEntre $p.Quand.Date $p.Quand.Date.AddDays(1) | Where-Object { $_.RV.Titre -eq (Get-TitreAffiche $titre) })
            if ($deja.Count) { [void]$dits.Add("$(Get-TitreAffiche $titre) est déjà dans ton agenda."); [void]$ecrits.Add("Déjà dans l'agenda : $(Get-TitreAffiche $titre)."); continue }
            $r = Add-RendezVous (Get-TitreAffiche $titre) $p.Quand $p.Repetition $p.Type $p.Journee $det
            $n = Get-PhraseNote $r
            [void]$ecrits.Add("C'est noté : $($n.Ecrit).")
            $dit = "C'est noté : $($n.Dit)."
            $conf = if ($r.Journee) { @() } else { @(Get-Conflits $r.Quand $r.Fin $r.Id) }
            if ($conf.Count) { $dit += " Attention, tu as déjà $(Get-TitreAffiche $conf[0].RV.Titre) à ce moment-là."; [void]$ecrits.Add("⚠ En même temps que $(Get-TitreAffiche $conf[0].RV.Titre).") }
            [void]$dits.Add($dit)
        }
        elseif ($a.action -eq 'annuler') {
            if (Restore-Annulation) { [void]$dits.Add('J''ai annulé ma dernière action.'); [void]$ecrits.Add('Dernière action annulée.') }
            else { [void]$dits.Add('Il n''y a rien à annuler.'); [void]$ecrits.Add('Rien à annuler.') }
        }
        elseif (-not $rv) {
            [void]$dits.Add('Je n''ai pas trouvé de quel rendez-vous tu parles.'); [void]$ecrits.Add('Rendez-vous introuvable.')
        }
        elseif ($a.action -eq 'supprimer') {
            Remove-RendezVous $rv.Id
            [void]$dits.Add("J'ai supprimé $nom."); [void]$ecrits.Add("Supprimé : $nom. (Dis « annule » pour revenir en arrière.)")
        }
        elseif ($a.action -eq 'fait') {
            Set-RendezVousDetail $rv.Id 'Fait' $true
            [void]$dits.Add("Bien joué, $nom c'est fait."); [void]$ecrits.Add("Fait : $nom.")
        }
        elseif ($a.action -eq 'modifier') {
            $r = Invoke-ModifierIA $rv $a
            $n = Get-PhraseNote $r
            [void]$dits.Add("C'est changé : $($n.Dit)."); [void]$ecrits.Add("C'est changé : $($n.Ecrit).")
        }
    }
    if (-not $actions.Count) {
        $t = if ($R.reponse) { [string]$R.reponse } else { 'Je n''ai pas compris, tu peux reformuler ?' }
        [void]$dits.Add($t); [void]$ecrits.Add($t)
    }
    $ecrit = $ecrits -join ' '
    $dit = $dits -join ' '
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

# Modifier : nouveau moment (lu par les règles d'Evermind), titre, lieu, personnes, notes, choses à prendre
function Invoke-ModifierIA($rv, $a) {
    $quand = $rv.Quand; $rep = $rv.Repetition; $journee = [bool]$rv.Journee
    $duree = if ($rv.Fin) { $rv.Fin - $rv.Quand } else { $null }
    $fin = $rv.Fin
    if ($a.phrase) {
        $p = Read-Phrase ([string]$a.phrase)
        $base = (Get-NextOccurrence $rv.Repetition $rv.Quand (Get-Date).Date).Date
        $nouveau = $null
        if ($p.Quand) { $nouveau = $p.Quand; $journee = [bool]$p.Journee }
        elseif ($p.Jour) { $nouveau = $p.Jour + $rv.Quand.TimeOfDay }                  # nouveau jour, même heure
        elseif ($null -ne $p.Heure) { $nouveau = $base + $p.Heure; $journee = $false }  # même jour, nouvelle heure
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
    $titre = if ($a.titre -and $a.titre -ne $rv.Titre) { [string]$a.titre } else { $rv.Titre }
    Update-RendezVous $rv.Id (Get-TitreAffiche $titre) $quand $rep (Get-TypeRV $rv) $journee $det
}
