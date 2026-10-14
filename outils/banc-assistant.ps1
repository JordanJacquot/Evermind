# Banc d'essai de l'assistant : envoie des conversations à l'IA avec les vraies consignes d'Evermind
# et un agenda d'exemple, et montre ce qu'elle répond (sans rien modifier).
#
#   .\outils\banc-assistant.ps1 [-Voix <dossier contenant ia\>]
#
# Chaque conversation est une liste de phrases ; « attendu » dit ce qu'on veut voir dans la dernière réponse.

# (par défaut : la voix d'Evermind, ou celle d'une copie installée par Mindset)
param([string]$Voix = $(@(@('Evermind\voix', 'Mindset\Evermind\voix') | ForEach-Object { Join-Path $env:LOCALAPPDATA $_ } | Where-Object { Test-Path -LiteralPath $_ }) + (Join-Path $env:LOCALAPPDATA 'Evermind\voix'))[0])
$ErrorActionPreference = 'Stop'
$racine = Split-Path $PSScriptRoot -Parent
$modules = Join-Path $racine 'Evermind\fichiers\modules'
$env:EVERMIND_VOIX = $Voix
$env:EVERMIND_DONNEES = Join-Path $racine '_test\banc'
Remove-Item $env:EVERMIND_DONNEES -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $env:EVERMIND_DONNEES | Out-Null
$exemple = Join-Path $racine '_test\donnees-agenda\rendez-vous.json'
if (-not (Test-Path $exemple)) { throw 'Lance d''abord outils\tester.ps1 (il crée l''agenda d''exemple).' }
Copy-Item $exemple $env:EVERMIND_DONNEES
foreach ($m in 'donnees', 'comprendre', 'agenda', 'details', 'voix', 'cerveau') { . (Join-Path $modules "$m.ps1") }

$exe = $LlamaExe; $port = 8099
$p = Start-Process $exe -ArgumentList "-m `"$IaModele`" --host 127.0.0.1 --port $port -ngl 99 -c 8192 --no-webui" -PassThru -WindowStyle Hidden
try {
    while ($true) { try { if ((Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch { Start-Sleep -Milliseconds 300 } }
    $ctx = Get-ContexteIA
    $nom = @{}; foreach ($k in $ctx.Codes.Keys) { $nom[$k] = (Get-RendezVous $ctx.Codes[$k]).Titre }
    # Les jours suivent l'agenda d'exemple (il est créé par rapport à aujourd'hui)
    $fr = [Globalization.CultureInfo]'fr-FR'
    $soiree = (Get-Date).Date.AddDays(6); $dentiste = (Get-Date).Date.AddDays(3); $anniv = (Get-Date).Date.AddDays(1)
    $conversations = @(
        @{ Phrases = @('Je veux que tu me crées l''événement anniversaire de Jordan le 23 octobre.'); Attendu = 'creer' }
        @{ Phrases = @("J'aimerais que tu effaces l'événement du $($soiree.Day) $($soiree.ToString('MMMM', $fr))."); Attendu = 'supprimer:Soirée chez Max' }
        @{ Phrases = @('Je veux que tu supprimes l''événement.', 'L''anniversaire de Léa.'); Attendu = 'supprimer:Anniversaire de Léa' }
        @{ Phrases = @("Supprime le rendez-vous de $($dentiste.ToString('dddd', $fr))."); Attendu = 'supprimer:Dentiste' }
        @{ Phrases = @("Euh, est-ce que tu peux me supprimer l'anniversaire qui est le $($anniv.Day), là, s'il te plaît ?"); Attendu = 'supprimer:Anniversaire de Léa' }
        @{ Phrases = @('Crée un rendez-vous chez le garagiste vendredi à 10 h.'); Attendu = 'creer' }
        @{ Phrases = @('Décale le foot à 20 h.'); Attendu = 'modifier:Foot' }
        @{ Phrases = @('Ajoute Paul à la soirée chez Max.'); Attendu = 'modifier:Soirée chez Max' }
        @{ Phrases = @('Qu''est-ce que j''ai cette semaine ?'); Attendu = 'aucune' }
        @{ Phrases = @('Mets-moi un rappel pour sortir les poubelles tous les mardis soir.'); Attendu = 'creer' }
        @{ Phrases = @('Crée un événement anniversaire de Jordan le 23 octobre.', 'Annule.'); Attendu = 'annuler' }
        @{ Phrases = @('Supprime tout ce que j''ai demain.'); Attendu = 'supprimer' }
        @{ Phrases = @('Le dentiste, c''est plutôt mercredi.'); Attendu = 'modifier:Dentiste' }
        @{ Phrases = @('Salut, ça va ?'); Attendu = 'aucune' }
        @{ Phrases = @('Sucrime dentiste.'); Attendu = 'supprimer:Dentiste' }
        @{ Phrases = @('Décade le foot à 20 h.'); Attendu = 'modifier:Foot' }
        @{ Phrases = @('Crée-moi un événement faire les courses samedi, avec la liste : lait, œufs, farine et beurre.'); Attendu = 'creer' }
        @{ Phrases = @('Ajoute un événement ménage dimanche.'); Attendu = 'creer' }
        @{ Phrases = @('Supprime-moi l''événement du genre de Troke Tops, s''il te plaît.'); Attendu = 'aucune' }
        @{ Phrases = @('J''aimerais que tu me crées un rendez-vous pour le 23 octobre et que tu mettes un anniversaire Jordan.', 'Finalement, efface-le.'); Attendu = 'supprimer' }
        @{ Phrases = @('Pour la soirée chez Max, note que c''est au 3e étage et que je dois apporter des chips.'); Attendu = 'modifier:Soirée chez Max' }
        @{ Phrases = @('Le raid de demain, mets-le plutôt à 22 h, et ajoute Tom.'); Attendu = 'modifier:Raid avec les potes' }
        @{ Phrases = @('C''est quand mon prochain rendez-vous chez le dentiste ?'); Attendu = 'aucune' }
        @{ Phrases = @('J''ai payé le loyer.'); Attendu = 'fait:Payer le loyer' }
    )
    $bons = 0; $total = 0
    foreach ($conv in $conversations) {
        $hist = @()
        foreach ($ph in $conv.Phrases) {
            $messages = @(@{ role = 'system'; content = $ctx.Systeme }) + $hist + @(@{ role = 'user'; content = $ph })
            $corps = @{ messages = $messages; temperature = 0; max_tokens = 400; response_format = @{ type = 'json_schema'; json_schema = @{ name = 'reponse'; schema = $SchemaIA } } } | ConvertTo-Json -Depth 20 -Compress
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-RestMethod "http://127.0.0.1:$port/v1/chat/completions" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($corps))
            $c = $r.choices[0].message.content
            $hist += @(@{ role = 'user'; content = $ph }, @{ role = 'assistant'; content = $c })
            $j = $c | ConvertFrom-Json
            $resume = if (@($j.actions).Count) { (@($j.actions) | ForEach-Object { "$($_.action)$(if ($_.id) { ':' + $nom[([string]$_.id).Trim('[] ')] })$(if ($_.phrase) { ' « ' + $_.phrase + ' »' })" }) -join ' + ' } else { 'aucune' }
            Write-Host ("  « {0} » ({1:N1} s)`n     -> {2} | {3}" -f $ph, $sw.Elapsed.TotalSeconds, $resume, $j.reponse)
        }
        $total++
        $bon = $resume -like "$($conv.Attendu)*"
        if ($bon) { $bons++ } else { Write-Host "     ÉCHEC : attendu $($conv.Attendu)" -ForegroundColor Red }
    }
    Write-Host "Conversations réussies : $bons / $total" -ForegroundColor $(if ($bons -eq $total) { 'Green' } else { 'Yellow' })
} finally { Stop-Process -Id $p.Id -Force }
