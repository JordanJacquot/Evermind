# Evermind : se réveiller quand on dit « OK Eve », sans toucher au clavier.
#   1. Vosk (petit, léger, sur le PC) écoute le micro en continu et ne sait reconnaître que « ok ève » ;
#      tout le reste est oublié aussitôt. Rien n'est enregistré ni envoyé.
#   2. « OK Eve » tout seul : bip tout de suite, on dit sa demande ; Whisper vérifie en même temps et coupe l'écoute
#      si ce n'était pas « OK Eve ». Demande dans la même phrase (« OK Eve, supprime le foot ») : Whisper relit la
#      phrase d'abord, sans bip. Un faux réveil (« OK, on y va ») est ignoré sans rien dire.
#   L'écoute se met en pause pendant qu'Evermind écoute, réfléchit ou parle (il ne se réveille pas tout seul).
# Chargé par Evermind.ps1, après voix.ps1.

$EveilDir   = Join-Path $VoixDir 'eveil'
$VoskDir    = Join-Path $EveilDir 'vosk-win64-0.3.45'
$VoskModele = Join-Path $EveilDir 'vosk-model-small-fr-0.22'
$VoixFichiers += @(
    @{ Pack = 'eveil'; Nom = 'écoute de « OK Eve »'; Url = 'https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-win64-0.3.45.zip'
       Sha256 = 'F1DCC9CCA460630F81EA8F71794F69C80BED6556D2A4E6237B5785E1D2DFF34B'; Taille = 14882445
       Extraire = '^vosk-win64-0\.3\.45/(libvosk|libstdc\+\+-6|libgcc_s_seh-1|libwinpthread-1)\.dll$'; Vers = 'eveil'; Garder = (Join-Path $VoskDir 'libvosk.dll') }
    @{ Pack = 'eveil'; Nom = 'écoute de « OK Eve »'; Url = 'https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip'
       Sha256 = 'CABF6180E177EB9B3A9A9D43A437BD5E549F3A7D09525E5D69A3FED787BE12AD'; Taille = 42233323
       Extraire = '^vosk-model-small-fr-0\.22/.+[^/]$'; Vers = 'eveil'; Garder = (Join-Path $VoskModele 'am\final.mdl') }
)

function Test-EveilInstalle { (Get-VoixManquants 'eveil').Count -eq 0 }
function Test-EveilActif { [bool]$script:Eveil }

function Start-Eveil {
    $test = [bool]$env:EVERMIND_EVEIL_WAV
    if ($EnTest -and -not $test) { return }
    if ($script:Eveil -or -not (Test-EveilInstalle) -or -not (Test-DicteeInstallee)) { return }
    if (-not $test -and -not (Get-Setting 'Eveil' $false)) { return }
    $e = New-Object EMEveil
    if (-not $e.Charger($VoskDir, $VoskModele)) { Write-Log "Écoute « OK Eve » impossible : $($e.Erreur)"; return }
    if (-not $test) {
        $err = $e.Start()
        if ($err -ne 0) { Write-Log "Écoute « OK Eve » : micro indisponible (code $err)"; return }
    }
    $script:Eveil = $e
    if (-not $script:EveilTimer) {
        $script:EveilTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:EveilTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $script:EveilTimer.Add_Tick({ Step-Eveil })
    }
    $script:EveilTimer.Start()
    Write-Log "Écoute « OK Eve » active (micro : $(if ([EMMicros]::Choisi -ne [uint32]::MaxValue) { @([EMMicros]::Noms())[[EMMicros]::Choisi] } else { 'celui de Windows' }))"
    try { [void](Start-WhisperServeur) } catch {}   # Whisper prêt d'avance : la réponse arrive plus vite
    Update-RaccourciTexte
    if ($test) {
        # Test automatique : un fichier son passe comme s'il venait du micro
        $b = [IO.File]::ReadAllBytes($env:EVERMIND_EVEIL_WAV)
        $pcm = New-Object byte[] ($b.Length - 44); [Array]::Copy($b, 44, $pcm, 0, $pcm.Length)
        $e.TestPcm($pcm, [BitConverter]::ToInt32($b, 24))
        Write-Log "Écoute de test : candidat $($e.Detecte), demande $($e.AvecCommande), confiance $([math]::Round($e.ConfMin, 2)), phrases $($e.Phrases)"
    }
}

function Stop-Eveil {
    if ($script:EveilTimer) { $script:EveilTimer.Stop() }
    if ($script:Eveil) { try { $script:Eveil.Stop() } catch {}; $script:Eveil = $null; Write-Log 'Écoute « OK Eve » arrêtée' }
    Update-RaccourciTexte
}

function Step-Eveil {
    $e = $script:Eveil
    if (-not $e) { $script:EveilTimer.Stop(); return }
    try {
        # Sécurité : une phrase d'Evermind qui ne finit jamais ne doit pas laisser « OK Eve » sourd pour toujours
        if ($script:Parle -and $script:Parle.Debut -and $script:Parle.Debut.Elapsed.TotalSeconds -gt 40) { Write-Log 'Voix bloquée : « OK Eve » reprend'; $script:Parle = $null }
        Test-MicroRevenu
        $occupe = [bool]($script:Ecoute -or $script:Transcription -or $script:Demande -or $script:Parle)
        $parle = ((Get-Date) -lt $script:EveilReprise) -or ($script:Synth -and [string]$script:Synth.State -eq 'Speaking')
        $e.Pause = $occupe -or $parle
        # Diagnostic : ce que l'écoute a cru entendre, et (les 3 premières minutes) si le micro envoie bien du son
        if ($e.Indices) { $i = $e.Indices; $e.Indices = ''; Write-Log "Écoute : entendu$i" }
        if (-not $script:EveilDiag -or ((Get-Date) - $script:EveilDiag).TotalSeconds -ge 60) {
            if ($script:EveilDiag -and ++$script:EveilDiagN -le 3) { Write-Log "Écoute : son max $([math]::Round($e.NiveauMax, 4)), $($e.Paquets) morceaux$(if ($e.Pause) { ', en pause' })" }
            # Une minute de silence complet (pas même le bruit de la pièce) : le micro est coupé ou ce n'est pas le bon
            if ($script:EveilDiag -and $e.Paquets -gt 300 -and $e.NiveauMax -lt 0.0008 -and -not $script:MicroMuetDit) {
                $script:MicroMuetDit = $true
                $nom = if ([EMMicros]::Choisi -ne [uint32]::MaxValue) { @([EMMicros]::Noms())[[EMMicros]::Choisi] } else { 'le micro de Windows' }
                Write-Log "Écoute : aucun son ne vient de $nom"
                Show-Notify 'Evermind n''entend rien' "Aucun son ne vient de « $nom » (coupé ?). Choisis le bon micro dans les réglages d'Evermind."
            }
            $e.NiveauMax = 0; $e.Paquets = 0; $script:EveilDiag = Get-Date
        }
        if (-not $e.Detecte) { return }
        $e.Detecte = $false
        if ($occupe) { Write-Log 'OK Eve entendu, mais Evermind était occupé'; return }
        $wav = Join-Path $env:TEMP "evermind-$PID-eveil.wav"
        $e.SaveWav($wav)
        # Le début de la phrase est gardé à part : il sera relu avec la suite enregistrée par le micro
        $script:EveilDebut = Join-Path $env:TEMP "evermind-$PID-eveil-debut.wav"
        Copy-Item -LiteralPath $wav -Destination $script:EveilDebut -Force
        # Ce qui servira juste après se prépare pendant qu'on parle : la voix qui répondra
        if (-not $EnTest -and $VoixListe[(Get-VoixChoisie)].Moteur -eq 'kokoro') { try { [void](Start-KokoroServeur) } catch {} }
        if ($e.AvecCommande) {
            # « OK Eve, supprime le foot » (ou un faux réveil comme « OK, on y va ») : Whisper confirme d'abord,
            # sans bip ni bulle ; en attendant, la suite est enregistrée pour ne rien perdre.
            if (-not $EnTest) { Start-Ecoute 'eveil' -Silencieux }
            Start-Transcription $wav 'eveil'
        } else {
            # « OK Eve » tout seul : bip tout de suite, Whisper vérifie pendant qu'on dit sa demande
            Write-Log "OK Eve entendu (confiance $([math]::Round($e.ConfMin, 2)))"
            if (-not $EnTest) { Start-Ecoute 'eveil'; if ($script:Ecoute) { $script:Ecoute.Prefixe = $script:EveilDebut } }
            Start-Transcription $wav 'verif'
        }
    } catch { Write-Log "Écoute « OK Eve » : $_" }
}

# Vérification d'un « OK Eve » dit tout seul (Evermind écoute déjà)
function Confirm-Reveil([string]$Texte) {
    if ($Texte -match "(?i)^\W*(?:ok|okay|o\.\s?k\.?|hey|hé)\W*(?:ève|eve|eva|èv|ev)\b") { return }
    Write-Log "Faux réveil ignoré : « $($Texte.Trim()) »"
    $e = $script:Ecoute
    if ($e -and $e.Source -eq 'eveil') {
        Stop-EcouteSansSuite
        Invoke-Bip $false; Hide-Bulle; Set-VoixEtat ''
    }
}
# Ce que Whisper a lu de la phrase qui a peut-être réveillé Evermind
function Invoke-Reveil([string]$Texte) {
    $m = [regex]::Match($Texte.Trim(), "^\W*(?:ok|okay|o\.\s?k\.?|hey|hé)\W*(?:ève|eve|eva|èv|ev)\b\W*(?<reste>.*)$", 'IgnoreCase')
    if (-not $m.Success) {
        Stop-EcouteSansSuite
        Write-Log "Faux réveil ignoré : « $($Texte.Trim()) »"
        return
    }
    $reste = $m.Groups['reste'].Value.Trim()
    $e = $script:Ecoute
    if ($e -and $e.Silencieux) {
        # Le micro enregistre déjà la suite : on attend que la personne se taise, puis Whisper relit toute la phrase.
        # Si rien n'est dit après (tout tenait dans la première phrase), ce qui a été compris suffit.
        $e.Prefixe = $script:EveilDebut
        $e.Reste = if ($reste -match '\w{2,}') { $reste } else { '' }
        $e.Confirme = [Diagnostics.Stopwatch]::StartNew()
        if ($e.Reste) { Write-Log 'OK Eve, avec le début de la demande' } else { Write-Log 'OK Eve' }
        [void](Confirm-EcouteEveil)
        return
    }
    if ($reste -match '\w{2,}') {
        Write-Log 'OK Eve, avec la demande'
        Invoke-Bip $true
        Invoke-Dictee $reste
        return
    }
    Write-Log 'OK Eve'
    if (-not $EnTest) { Start-Ecoute 'eveil' }
}

# Réglages : l'interrupteur « Réagir quand je dis OK Eve »
function Update-EveilReglage {
    $on = [bool](Get-Setting 'Eveil' $false)
    $ui.ChkEveil.IsChecked = $on
    $dl = $script:VoixDl
    $ui.EveilEtat.Text = if ($dl -and -not $dl.Fini -and $dl.Pack -eq 'eveil') { 'Installation en cours...' }
        elseif (-not (Test-DicteeInstallee)) { 'Installe d''abord la voix (écran principal).' }
        elseif ($on -and (Test-EveilActif)) { 'Actif : dis « OK Eve », puis ta demande. Tout reste sur ton PC, rien n''est enregistré.' }
        elseif ($on) { 'Activé, en attente du micro.' }
        else { 'Evermind écoute en continu, sur ton PC uniquement, et ne réagit qu''à « OK Eve ». Petit téléchargement (57 Mo) la première fois.' }
}

function Set-EveilReglage([bool]$On) {
    Set-Setting 'Eveil' $On
    if ($On) {
        if (-not (Test-DicteeInstallee)) { Set-Setting 'Eveil' $false }
        elseif (-not (Test-EveilInstalle)) { Start-VoixInstall 'eveil' }
        else { Start-Eveil }
    } else { Stop-Eveil }
    Update-EveilReglage
}

function Update-RaccourciTexte {
    $ui.RaccourciTexte.Text = if (Test-EveilActif) { 'Dis « OK Eve » ou Ctrl + Maj + Espace, même en jeu' }
        elseif ($script:VoixHotkeyOk -or $EnTest) { 'Dictée : Ctrl + Maj + Espace, même en jeu' }
        else { 'Le raccourci Ctrl + Maj + Espace est déjà pris par un autre programme' }
}
