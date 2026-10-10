# Evermind : se réveiller quand on dit « OK Eve », sans toucher au clavier.
#   1. Vosk (petit, léger, sur le PC) écoute le micro en continu et ne sait reconnaître que « ok ève » ;
#      tout le reste est oublié aussitôt. Rien n'est enregistré ni envoyé.
#   2. Un « OK Eve » clair et seul : bip, puis on dit sa demande.
#      Sinon (pas sûr, ou demande dans la même phrase : « OK Eve, supprime le foot ») : Whisper relit la phrase
#      pour confirmer. Un faux réveil (« OK, on y va ») est ignoré sans rien montrer ni dire.
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
    Write-Log 'Écoute « OK Eve » active'
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
    $occupe = [bool]($script:Ecoute -or $script:Transcription -or $script:Demande -or $script:Piper)
    $parle = ((Get-Date) -lt $script:EveilReprise) -or ($script:Synth -and [string]$script:Synth.State -eq 'Speaking')
    $e.Pause = $occupe -or $parle
    if (-not $e.Detecte) { return }
    $e.Detecte = $false
    if ($occupe) { return }
    # Toujours confirmé par Whisper (Vosk peut prendre « OK, on y va » pour « OK Eve »). En attendant, on enregistre
    # sans bip ni bulle : si c'est bien « OK Eve », ce qui a été dit juste après n'est pas perdu.
    $wav = Join-Path $env:TEMP "evermind-$PID-eveil.wav"
    try { $e.SaveWav($wav) } catch { Write-Log "Écoute « OK Eve » : $_"; return }
    # Le début de la phrase est gardé à part : si « OK Eve » est confirmé, il sera relu avec la suite enregistrée par le micro
    $script:EveilDebut = Join-Path $env:TEMP "evermind-$PID-eveil-debut.wav"
    Copy-Item -LiteralPath $wav -Destination $script:EveilDebut -Force
    if (-not $EnTest) { Start-Ecoute 'eveil' -Silencieux }
    Start-Transcription $wav 'eveil'
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
