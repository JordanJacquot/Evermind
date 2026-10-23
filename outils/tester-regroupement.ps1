# Teste, sans écran ni Internet, ce qui met Evermind sur la ligne unique « Mindset » du Gestionnaire des tâches
# (il regroupe les programmes qui ont le même nom de fichier) :
#   1. le relais Evermind.exe (outils\relais.cs) lance Mindset.exe de SON dossier avec les mêmes arguments, puis se ferme ;
#   2. Get-CopieMindset (modules\voix.ps1) : un programme d'aide est lancé par sa copie Mindset.exe (ses dll à côté),
#      refaite quand l'original change ; copie impossible, l'original est lancé ; arrêt par le numéro du processus ;
#   3. aucun processus cherché ou arrêté par son nom dans le code d'Evermind (tout s'appelle maintenant Mindset.exe).
# Tout se passe dans un dossier de %TEMP%, avec de petits programmes de test compilés ici : aucun vrai module, rien
# d'Evermind ni de Mindset n'est touché.
# Code de sortie : 0 si tout est bon, 1 sinon.

$ErrorActionPreference = 'Stop'
$racine = Split-Path $PSScriptRoot -Parent
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$dossier = Join-Path $env:TEMP "evermind-regroupement-$PID"
$script:ok = $true
$script:Notes = New-Object System.Collections.ArrayList
function Test-Point([string]$Nom, [bool]$Bon, [string]$Detail = '') {
    if ($Bon) { Write-Host "OK     $Nom" -ForegroundColor Green } else { Write-Host "ÉCHEC  $Nom $Detail" -ForegroundColor Red; $script:ok = $false }
}
function Invoke-Csc([string[]]$Options) {
    $sortie = & $csc /nologo @Options 2>&1
    if ($LASTEXITCODE) { throw "Compilation impossible : $($sortie -join ' ')" }
}
function Write-Log([string]$Texte) { [void]$script:Notes.Add($Texte) }   # (le journal d'Evermind, pour Get-CopieMindset)
# Un processus suivi par son numéro, arrêté s'il tourne encore
function Stop-Numero([int]$Numero) {
    $p = Get-Process -Id $Numero -ErrorAction SilentlyContinue
    if ($p -and -not $p.WaitForExit(5000)) { try { $p.Kill(); [void]$p.WaitForExit(5000) } catch {} }
    -not (Get-Process -Id $Numero -ErrorAction SilentlyContinue)
}

$lances = New-Object System.Collections.Generic.List[int]
try {
    New-Item -ItemType Directory -Force -Path $dossier | Out-Null

    # -----------------------------------------------------------------------
    # 1. Le relais : un faux Mindset.exe note ce qu'il reçoit, puis attend fin.txt (15 s au plus)
    # -----------------------------------------------------------------------
    $app = Join-Path $dossier 'Programmes avec espaces\Evermind'
    New-Item -ItemType Directory -Force -Path $app | Out-Null
    $src = Join-Path $dossier 'faux-hote.cs'
    [IO.File]::WriteAllText($src, @'
using System; using System.IO; using System.Threading; using System.Diagnostics;
static class FauxHote {
    static void Main(string[] a) {
        string d = AppDomain.CurrentDomain.BaseDirectory;
        File.WriteAllText(Path.Combine(d, "recu.tmp"), string.Join("\n", a) + "\n--\n" + Process.GetCurrentProcess().MainModule.FileName + "\n" + Environment.CurrentDirectory);
        File.Move(Path.Combine(d, "recu.tmp"), Path.Combine(d, "recu.txt"));
        for (int i = 0; i < 150 && !File.Exists(Path.Combine(d, "fin.txt")); i++) Thread.Sleep(100);
    }
}
'@, (New-Object Text.UTF8Encoding $true))
    Invoke-Csc @('/target:winexe', "/out:$(Join-Path $app 'Mindset.exe')", $src)
    Invoke-Csc @('/target:winexe', '/reference:System.Windows.Forms.dll', "/out:$(Join-Path $app 'Evermind.exe')", (Join-Path $PSScriptRoot 'relais.cs'))

    $chrono = [Diagnostics.Stopwatch]::StartNew()
    $r = Start-Process -FilePath (Join-Path $app 'Evermind.exe') -ArgumentList '-Demarrage', '"deux mots"', 'x\"y' -WorkingDirectory $env:TEMP -PassThru
    $ferme = $r.WaitForExit(10000)
    Test-Point 'relais : se ferme aussitôt' ($ferme -and $r.ExitCode -eq 0) "(fermé : $ferme, code $(if ($ferme) { $r.ExitCode }))"
    $h = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($r.Id)" | Where-Object { $_.ExecutablePath -ieq (Join-Path $app 'Mindset.exe') })
    Test-Point 'relais : lance Mindset.exe de son dossier' ($h.Count -eq 1 -and $h[0].Name -eq 'Mindset.exe') "(trouvés : $($h.Count))"
    if ($h.Count) {
        $lances.Add([int]$h[0].ProcessId)
        Write-Host "       processus : $($h[0].Name) (PID $($h[0].ProcessId)) $($h[0].ExecutablePath)" -ForegroundColor DarkGray
        Write-Host "       relais fermé en $([math]::Round($chrono.Elapsed.TotalSeconds, 2)) s, Mindset.exe toujours ouvert : $([bool](Get-Process -Id $h[0].ProcessId -ErrorAction SilentlyContinue))" -ForegroundColor DarkGray
    }
    $recu = Join-Path $app 'recu.txt'
    for ($i = 0; $i -lt 100 -and -not (Test-Path -LiteralPath $recu); $i++) { Start-Sleep -Milliseconds 100 }
    $lignes = if (Test-Path -LiteralPath $recu) { @([IO.File]::ReadAllText($recu) -split "`n") } else { @() }
    Test-Point 'relais : mêmes arguments' (($lignes[0..3] -join '|') -eq '-Demarrage|deux mots|x"y|--') "(reçu : $($lignes -join '|'))"
    Test-Point 'relais : dossier de travail, celui d''Evermind' ($lignes.Count -ge 6 -and $lignes[5].TrimEnd('\') -ieq $app) "(reçu : $($lignes[5]))"
    [IO.File]::WriteAllText((Join-Path $app 'fin.txt'), '')
    if ($h.Count) { Test-Point 'relais : Mindset.exe arrêté par son numéro' (Stop-Numero ([int]$h[0].ProcessId)) }

    # -----------------------------------------------------------------------
    # 2. Get-CopieMindset (la vraie fonction, lue dans voix.ps1) avec un faux programme d'aide et sa dll
    # -----------------------------------------------------------------------
    $voixPs1 = Join-Path $racine 'Evermind\fichiers\modules\voix.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($voixPs1, [ref]$null, [ref]$null)
    $def = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-CopieMindset' }, $true)
    if (-not $def) { throw 'Get-CopieMindset introuvable dans voix.ps1' }
    . ([scriptblock]::Create($def.Extent.Text))

    $voix = Join-Path $dossier 'voix'
    New-Item -ItemType Directory -Force -Path $voix | Out-Null
    $srcDll = Join-Path $dossier 'aide.cs'; $srcExe = Join-Path $dossier 'faux-serveur.cs'
    [IO.File]::WriteAllText($srcExe, @'
using System; using System.Diagnostics;
static class FauxServeur {
    static void Main() {
#if V2
        const string version = "v2";
#else
        const string version = "v1";
#endif
        Console.WriteLine("PRET " + version + Aide.Texte() + " " + Process.GetCurrentProcess().MainModule.FileName);
        while (Console.ReadLine() != null) { }
    }
}
'@)
    $original = Join-Path $voix 'faux-serveur.exe'
    # (sa dll, à côté de lui, chargée par son nom : « +aide » prouve qu'elle est trouvée)
    [IO.File]::WriteAllText($srcDll, 'public static class Aide { public static string Texte() { return "+aide"; } }')
    Invoke-Csc @('/target:library', "/out:$(Join-Path $voix 'aide.dll')", $srcDll)
    function New-FauxServeur([string]$Version) {
        $tmp = Join-Path $dossier 'faux-serveur.exe'
        Invoke-Csc @('/target:exe', "/reference:$(Join-Path $voix 'aide.dll')", "/out:$tmp", "/define:$($Version.ToUpper())", $srcExe)
        Copy-Item -LiteralPath $tmp -Destination $original -Force
    }
    function Start-Aide([string]$Exe) {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $voix
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
        $p = [Diagnostics.Process]::Start($psi)
        $lances.Add($p.Id)
        @{ Process = $p; Ligne = $p.StandardOutput.ReadLine() }
    }
    New-FauxServeur 'v1'
    $empreinte = (Get-FileHash -LiteralPath $original).Hash

    $copie = Get-CopieMindset $original
    Test-Point 'copie : Mindset.exe à côté de l''original' ($copie -ieq (Join-Path $voix 'Mindset.exe') -and (Get-FileHash -LiteralPath $copie).Hash -eq $empreinte) "(rendu : $copie)"
    Test-Point 'copie : original intact' ((Get-FileHash -LiteralPath $original).Hash -eq $empreinte)
    $a = Start-Aide $copie
    $w = Get-CimInstance Win32_Process -Filter "ProcessId=$($a.Process.Id)"
    Write-Host "       processus : $($w.Name) (PID $($w.ProcessId)) $($w.ExecutablePath) : « $($a.Ligne) »" -ForegroundColor DarkGray
    Test-Point 'copie : tourne sous le nom Mindset.exe, avec sa dll' ($w.Name -eq 'Mindset.exe' -and $w.ExecutablePath -ieq $copie -and $a.Ligne -eq "PRET v1+aide $copie") "($($w.Name), « $($a.Ligne) »)"

    # Inchangé : la copie n'est pas refaite (l'attribut Archive, retiré ici, reviendrait sur une nouvelle copie)
    $f = Get-Item -LiteralPath $copie; $f.Attributes = $f.Attributes -band -bnot [IO.FileAttributes]::Archive
    $r2 = Get-CopieMindset $original
    Test-Point 'copie : pas refaite si l''original n''a pas changé' ($r2 -ieq $copie -and -not ((Get-Item -LiteralPath $copie).Attributes -band [IO.FileAttributes]::Archive))

    # Nouvelle version du module pendant que la copie tourne : copie impossible, l'original est lancé (et c'est noté)
    Start-Sleep -Milliseconds 1100   # (une date de fichier différente)
    New-FauxServeur 'v2'
    $empreinte2 = (Get-FileHash -LiteralPath $original).Hash
    $script:Notes.Clear()
    $r3 = Get-CopieMindset $original
    Test-Point 'copie ouverte : l''original est lancé à la place' ($r3 -ieq $original -and ($script:Notes -join ' ') -match 'lancé sous son nom') "(rendu : $r3)"
    Test-Point 'copie ouverte : rien de cassé, rien qui traîne' ((Get-FileHash -LiteralPath $original).Hash -eq $empreinte2 -and (Get-FileHash -LiteralPath $copie).Hash -eq $empreinte -and -not @(Get-ChildItem -LiteralPath $voix -Filter '*.tmp').Count)
    $b = Start-Aide $r3
    Test-Point 'original : marche toujours' ($b.Ligne -eq "PRET v2+aide $original") "(« $($b.Ligne) »)"

    # Arrêt par le processus (entrée fermée, comme Evermind le fait), jamais par le nom
    foreach ($x in $a, $b) { try { $x.Process.StandardInput.Close() } catch {} }
    Test-Point 'arrêt par le numéro du processus' ((Stop-Numero $a.Process.Id) -and (Stop-Numero $b.Process.Id))

    # Une fois fermée, la copie suit la nouvelle version
    $r4 = Get-CopieMindset $original
    $c = Start-Aide $r4
    Test-Point 'copie refaite après une nouvelle version' ($r4 -ieq $copie -and (Get-FileHash -LiteralPath $copie).Hash -eq $empreinte2 -and $c.Ligne -eq "PRET v2+aide $copie") "(« $($c.Ligne) »)"
    try { $c.Process.StandardInput.Close() } catch {}
    [void](Stop-Numero $c.Process.Id)

    # Module absent : le chemin est rendu tel quel, sans erreur
    $absent = Join-Path $voix 'absent.exe'
    Test-Point 'module absent : rien ne casse' ((Get-CopieMindset $absent) -eq $absent -and -not (Test-Path -LiteralPath (Join-Path $voix 'Mindset.exe.tmp')))
} catch {
    Test-Point 'regroupement' $false "($($_.Exception.Message))"
} finally {
    foreach ($n in $lances) { [void](Stop-Numero $n) }
    Remove-Item -LiteralPath $dossier -Recurse -Force -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------
# 3. Aucun processus cherché ou arrêté par son nom dans le code livré
# -----------------------------------------------------------------------
$parNom = 'Get-Process\s+(?!-Id\b)\S|Stop-Process\s+(?!-Id\b)\S|GetProcessesByName|Process\]::GetProcesses\(|Process\.GetProcesses\(|taskkill|Win32_Process\b.*\bName\s*='
$trouves = @(Get-ChildItem -LiteralPath (Join-Path $racine 'Evermind') -Recurse -File -Include '*.ps1', '*.cs', '*.bat' | Select-String -Pattern $parNom)
Test-Point 'aucun processus trouvé par son nom' (-not $trouves.Count) "($(@($trouves | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', '))"

if ($script:ok) { Write-Host 'Regroupement : tout est bon.' -ForegroundColor Green; exit 0 }
Write-Host 'Regroupement : des tests ont échoué.' -ForegroundColor Red
exit 1
