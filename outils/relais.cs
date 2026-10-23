// Evermind.exe : le relais. Le vrai programme d'Evermind s'appelle Mindset.exe (outils\lanceur.cs), comme celui des
// autres applis de la suite, pour que le Gestionnaire des tâches les regroupe sur une seule ligne « Mindset ».
// Evermind.exe reste pour tout ce qui l'appelle encore (anciennes versions de Mindset, raccourcis, démarrage avec
// Windows, mise à jour d'une ancienne version) : il lance Mindset.exe de SON dossier avec les mêmes arguments, puis se
// ferme aussitôt. Compilé par construire.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[assembly: AssemblyTitle("Evermind")]
[assembly: AssemblyProduct("Evermind")]
[assembly: AssemblyDescription("Lance Evermind")]
// (le numéro de version est celui d'Evermind.ps1, ajouté par construire.ps1 à la compilation)

static class Relais
{
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);

    [STAThread]
    static int Main()
    {
        string dossier = AppDomain.CurrentDomain.BaseDirectory;
        string hote = Path.Combine(dossier, "Mindset.exe");
        if (!File.Exists(hote))
        {
            Application.EnableVisualStyles();
            MessageBox.Show(
                "Un fichier d'Evermind est introuvable (Mindset.exe, à côté de ce programme).\n\n" +
                "Réinstalle Evermind depuis Mindset.",
                "Evermind", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
        try
        {
            // Lancé d'un clic : la fenêtre d'Evermind a le droit de passer devant
            try { AllowSetForegroundWindow(-1); } catch { }
            ProcessStartInfo psi = new ProcessStartInfo(hote, Arguments(Environment.CommandLine));
            psi.UseShellExecute = false;
            psi.WorkingDirectory = dossier;
            using (Process.Start(psi)) { }
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show("Evermind n'a pas pu démarrer :\n\n" + e.Message, "Evermind", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // Les arguments tels quels : la ligne de commande sans le nom du programme. Le chemin de ce programme est retiré
    // s'il est là en entier (même sans guillemets malgré des espaces) ; sinon, même règle que Windows pour le premier
    // mot : entre guillemets, ou jusqu'au premier espace.
    static string Arguments(string ligne)
    {
        int i = 0;
        string moi = Assembly.GetExecutingAssembly().Location;
        if (ligne.StartsWith("\"" + moi + "\"", StringComparison.OrdinalIgnoreCase)) i = moi.Length + 2;
        else if (ligne.StartsWith(moi, StringComparison.OrdinalIgnoreCase) && (ligne.Length == moi.Length || ligne[moi.Length] == ' ' || ligne[moi.Length] == '\t')) i = moi.Length;
        else if (ligne.Length > 0 && ligne[0] == '"')
        {
            int fin = ligne.IndexOf('"', 1);
            i = fin < 0 ? ligne.Length : fin + 1;
        }
        else
        {
            while (i < ligne.Length && ligne[i] != ' ' && ligne[i] != '\t') i++;
        }
        return ligne.Substring(i).TrimStart(' ', '\t');
    }
}
