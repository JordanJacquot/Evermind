// Evermind.exe : le programme Evermind. Il exécute lui même le code d'Evermind (fichiers\Evermind.ps1)
// au lieu de le confier à powershell.exe : pour Windows, c'est une vraie application, avec son nom
// et son icône (barre des tâches, Gestionnaire des tâches, notifications).
// Compilé par construire.ps1. « Evermind.exe -Demarrage » : lancement avec Windows, caché près de l'horloge.
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Evermind")]
[assembly: AssemblyProduct("Evermind")]
[assembly: AssemblyDescription("L'agenda qui te rappelle tes rendez-vous à voix haute")]
// (le numéro de version est celui d'Evermind.ps1, ajouté par construire.ps1 à la compilation : la signature du code
// vérifie que l'exe porte la version de l'appli)

static class Lanceur
{
    [STAThread]
    static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        string dossier = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(Path.Combine(dossier, "fichiers"), "Evermind.ps1");

        if (!File.Exists(script))
        {
            MessageBox.Show(
                "Le dossier « fichiers » est introuvable à côté de ce programme.\n\n" +
                "Extrais d'abord tout le zip (clic droit sur le zip, puis « Extraire tout »), " +
                "puis lance Evermind depuis le dossier extrait.",
                "Evermind", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
        bool demarrage = Array.Exists(args, a => string.Equals(a, "-Demarrage", StringComparison.OrdinalIgnoreCase));

        try
        {
            // Le code tourne sur ce fil (STA, nécessaire aux fenêtres), sans les restrictions de scripts de Windows
            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(script);
                    if (demarrage) ps.AddParameter("Demarrage");
                    ps.Invoke();
                    if (ps.Streams.Error.Count > 0)
                    {
                        StringBuilder sb = new StringBuilder();
                        foreach (ErrorRecord e in ps.Streams.Error) sb.AppendLine(e.ToString() + " (" + e.InvocationInfo.PositionMessage + ")");
                        Journal("Erreurs : " + sb);
                    }
                }
            }
        }
        catch (Exception e)
        {
            Journal("Arrêt inattendu : " + e);
            MessageBox.Show("Evermind s'est arrêté à cause d'une erreur :\n\n" + e.Message, "Evermind", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }

    // Même journal que le code d'Evermind : il choisit le dossier de données (modules\donnees.ps1) et donne le chemin
    // du journal dans EVERMIND_JOURNAL. Si le code s'est arrêté avant, %LOCALAPPDATA%\Evermind (ou, s'il n'existe
    // plus, celui d'une copie installée par Mindset : %LOCALAPPDATA%\Mindset\Evermind, ou <X>:\Mindset\Donnees\Evermind).
    static void Journal(string texte)
    {
        try
        {
            string fichier = Environment.GetEnvironmentVariable("EVERMIND_JOURNAL");
            if (string.IsNullOrEmpty(fichier) || !fichier.EndsWith("journal.txt", StringComparison.OrdinalIgnoreCase))
            {
                string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string dir = Path.Combine(local, "Evermind");
                string mindset = Path.Combine(Path.Combine(local, "Mindset"), "Evermind");
                // Mindset installé sur un autre disque : <X>:\Mindset\Programmes\Evermind a ses données dans <X>:\Mindset\Donnees\Evermind
                DirectoryInfo racine = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\'));
                if (racine.Parent != null && racine.Parent.Parent != null && string.Equals(racine.Parent.Name, "Programmes", StringComparison.OrdinalIgnoreCase)
                    && string.Equals(racine.Parent.Parent.Name, "Mindset", StringComparison.OrdinalIgnoreCase))
                    mindset = Path.Combine(Path.Combine(racine.Parent.Parent.FullName, "Donnees"), "Evermind");
                if (!Directory.Exists(dir) && Directory.Exists(mindset)) dir = mindset;
                fichier = Path.Combine(dir, "journal.txt");
            }
            Directory.CreateDirectory(Path.GetDirectoryName(fichier));
            File.AppendAllText(fichier, DateTime.Now.ToString("s") + " " + texte + "\r\n", new UTF8Encoding(false));
        }
        catch { }
    }
}
