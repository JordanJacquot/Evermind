// Evermind : fonctions natives de Windows, compilées au lancement par Evermind.ps1.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// ---------------------------------------------------------------------------
// Les micros du PC : celui choisi dans les réglages (sinon celui de Windows), et un vumètre pour les comparer
// ---------------------------------------------------------------------------
public static class EMMicros
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CAPS { public ushort mid, pid; public uint ver; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string name; public uint fmts; public ushort ch, res; }
    [DllImport("winmm.dll")] static extern uint waveInGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int waveInGetDevCapsW(IntPtr id, ref CAPS c, int sz);

    public static uint Choisi = 0xFFFFFFFF;   // 0xFFFFFFFF : le micro par défaut de Windows

    // Noms des micros (Windows les coupe à 31 lettres)
    public static string[] Noms()
    {
        uint n = waveInGetNumDevs();
        string[] r = new string[n];
        for (uint d = 0; d < n; d++) { CAPS c = new CAPS(); waveInGetDevCapsW((IntPtr)d, ref c, Marshal.SizeOf(c)); r[d] = c.name ?? ""; }
        return r;
    }
}

// Le casque (ou les haut-parleurs) où Evermind parle : celui choisi dans les réglages, sinon celui de Windows.
// Joue un fichier .wav (la voix, les bips) ; une nouvelle lecture coupe la précédente.
public static class EMSortie
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CAPS { public ushort mid, pid; public uint ver; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string name; public uint fmts; public ushort ch, res; public uint support; }
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }
    [DllImport("winmm.dll")] static extern uint waveOutGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int waveOutGetDevCapsW(IntPtr id, ref CAPS c, int sz);
    [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr h, uint dev, ref WAVEFORMATEX f, IntPtr cb, IntPtr inst, uint flags);
    [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveOutReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr h);

    public static uint Choisi = 0xFFFFFFFF;   // 0xFFFFFFFF : la sortie par défaut de Windows
    static readonly object verrou = new object();
    static IntPtr h = IntPtr.Zero, hdr = IntPtr.Zero, buf = IntPtr.Zero;
    static Timer fin;
    static int numero;

    public static string[] Noms()
    {
        uint n = waveOutGetNumDevs();
        string[] r = new string[n];
        for (uint d = 0; d < n; d++) { CAPS c = new CAPS(); waveOutGetDevCapsW((IntPtr)d, ref c, Marshal.SizeOf(c)); r[d] = c.name ?? ""; }
        return r;
    }

    public static double JouerFichier(string chemin) { return Jouer(File.ReadAllBytes(chemin)); }

    // Joue un .wav en mémoire ; retourne sa durée en secondes (0 si impossible)
    public static double Jouer(byte[] wav)
    {
        WAVEFORMATEX f = new WAVEFORMATEX(); int debut = -1, taille = 0;
        for (int i = 12; i + 8 <= wav.Length; )
        {
            string id = Encoding.ASCII.GetString(wav, i, 4); int t = BitConverter.ToInt32(wav, i + 4);
            if (id == "fmt ")
            {
                f.wFormatTag = BitConverter.ToUInt16(wav, i + 8); f.nChannels = BitConverter.ToUInt16(wav, i + 10);
                f.nSamplesPerSec = BitConverter.ToUInt32(wav, i + 12); f.nAvgBytesPerSec = BitConverter.ToUInt32(wav, i + 16);
                f.nBlockAlign = BitConverter.ToUInt16(wav, i + 20); f.wBitsPerSample = BitConverter.ToUInt16(wav, i + 22);
            }
            else if (id == "data") { debut = i + 8; taille = Math.Min(t, wav.Length - debut); break; }
            i += 8 + t + (t & 1);
        }
        if (debut < 0 || f.nAvgBytesPerSec == 0) return 0;
        lock (verrou)
        {
            ArreterSansVerrou();
            int r = waveOutOpen(out h, Choisi, ref f, IntPtr.Zero, IntPtr.Zero, 0);
            if (r != 0 && Choisi != 0xFFFFFFFF) r = waveOutOpen(out h, 0xFFFFFFFF, ref f, IntPtr.Zero, IntPtr.Zero, 0);   // casque débranché
            if (r != 0) { h = IntPtr.Zero; return 0; }
            buf = Marshal.AllocHGlobal(taille); Marshal.Copy(wav, debut, buf, taille);
            WAVEHDR w = new WAVEHDR { lpData = buf, dwBufferLength = (uint)taille };
            hdr = Marshal.AllocHGlobal(Marshal.SizeOf(w)); Marshal.StructureToPtr(w, hdr, false);
            waveOutPrepareHeader(h, hdr, (uint)Marshal.SizeOf(w));
            waveOutWrite(h, hdr, (uint)Marshal.SizeOf(w));
            double duree = (double)taille / f.nAvgBytesPerSec;
            // La sortie est rendue une fois le son fini
            int ce = ++numero;
            fin = new Timer(_ => { lock (verrou) { if (ce == numero) ArreterSansVerrou(); } }, null, (int)(duree * 1000) + 600, Timeout.Infinite);
            return duree;
        }
    }

    public static void Arreter() { lock (verrou) { numero++; ArreterSansVerrou(); } }

    static void ArreterSansVerrou()
    {
        if (h == IntPtr.Zero) return;
        waveOutReset(h);
        if (hdr != IntPtr.Zero) { waveOutUnprepareHeader(h, hdr, (uint)Marshal.SizeOf(typeof(WAVEHDR))); Marshal.FreeHGlobal(hdr); hdr = IntPtr.Zero; }
        if (buf != IntPtr.Zero) { Marshal.FreeHGlobal(buf); buf = IntPtr.Zero; }
        waveOutClose(h); h = IntPtr.Zero;
    }
}

// Écoute tous les micros en même temps, juste pour montrer leur niveau (rien n'est gardé)
public class EMVumetre
{
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }
    [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, uint dev, ref WAVEFORMATEX f, IntPtr cb, IntPtr inst, uint flags);
    [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);

    public float[] Niveaux;
    volatile bool run;
    Thread th;

    public void Start(int nombre)
    {
        Niveaux = new float[nombre];
        run = true;
        th = new Thread(() => Boucle(nombre)) { IsBackground = true, Priority = ThreadPriority.BelowNormal };
        th.Start();
    }

    void Boucle(int nombre)
    {
        int taille = 3200, hs = Marshal.SizeOf(typeof(WAVEHDR));
        IntPtr[] h = new IntPtr[nombre], hd = new IntPtr[nombre * 2];
        for (int d = 0; d < nombre; d++)
        {
            WAVEFORMATEX f = new WAVEFORMATEX { wFormatTag = 1, nChannels = 1, nSamplesPerSec = 16000, wBitsPerSample = 16, nBlockAlign = 2, nAvgBytesPerSec = 32000 };
            if (waveInOpen(out h[d], (uint)d, ref f, IntPtr.Zero, IntPtr.Zero, 0) != 0) { h[d] = IntPtr.Zero; Niveaux[d] = -1; continue; }
            for (int b = 0; b < 2; b++)
            {
                WAVEHDR w = new WAVEHDR { lpData = Marshal.AllocHGlobal(taille), dwBufferLength = (uint)taille };
                hd[d * 2 + b] = Marshal.AllocHGlobal(hs); Marshal.StructureToPtr(w, hd[d * 2 + b], false);
                waveInPrepareHeader(h[d], hd[d * 2 + b], (uint)hs); waveInAddBuffer(h[d], hd[d * 2 + b], (uint)hs);
            }
            waveInStart(h[d]);
        }
        while (run)
        {
            Thread.Sleep(30);
            for (int i = 0; i < hd.Length; i++)
            {
                int d = i / 2;
                if (h[d] == IntPtr.Zero || hd[i] == IntPtr.Zero) continue;
                WAVEHDR w = (WAVEHDR)Marshal.PtrToStructure(hd[i], typeof(WAVEHDR));
                if ((w.dwFlags & 1) == 0) continue;
                double s = 0; int k = (int)w.dwBytesRecorded / 2;
                for (int j = 0; j < k; j++) { short v = Marshal.ReadInt16(w.lpData, j * 2); s += (double)v * v; }
                float rms = k > 0 ? (float)(Math.Sqrt(s / k) / 32768.0) : 0;
                Niveaux[d] = Math.Max(rms, Niveaux[d] * 0.8f);
                waveInUnprepareHeader(h[d], hd[i], (uint)hs);
                w.dwFlags = 0; w.dwBytesRecorded = 0; Marshal.StructureToPtr(w, hd[i], false);
                waveInPrepareHeader(h[d], hd[i], (uint)hs); waveInAddBuffer(h[d], hd[i], (uint)hs);
            }
        }
        for (int d = 0; d < nombre; d++)
        {
            if (h[d] == IntPtr.Zero) continue;
            waveInReset(h[d]);
            for (int b = 0; b < 2; b++)
            {
                IntPtr p = hd[d * 2 + b];
                WAVEHDR w = (WAVEHDR)Marshal.PtrToStructure(p, typeof(WAVEHDR));
                waveInUnprepareHeader(h[d], p, (uint)hs); Marshal.FreeHGlobal(w.lpData); Marshal.FreeHGlobal(p);
            }
            waveInClose(h[d]);
        }
    }

    public void Stop() { run = false; if (th != null) th.Join(1500); }
}

// ---------------------------------------------------------------------------
// Micro : enregistrement en 16 kHz mono (le format de Whisper), avec le niveau du son
// pour savoir quand on parle et quand on s'est tu.
// ---------------------------------------------------------------------------
public class EMMicro
{
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }

    [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, uint dev, ref WAVEFORMATEX f, IntPtr cb, IntPtr inst, uint flags);
    [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);
    [DllImport("winmm.dll")] static extern uint waveInGetNumDevs();

    const uint WAVE_MAPPER = 0xFFFFFFFF, CALLBACK_EVENT = 0x50000, WHDR_DONE = 1;
    const int Rate = 16000, BufBytes = 3200;   // tampons de 100 ms

    IntPtr h = IntPtr.Zero;
    readonly IntPtr[] hdrs = new IntPtr[4];
    readonly AutoResetEvent ev = new AutoResetEvent(false);
    readonly MemoryStream data = new MemoryStream();
    Thread th;
    volatile bool run;
    double floor = 0; int floorCount = 0;

    public volatile float Level;              // niveau du son, de 0 à 1 (pour l'animation)
    public volatile int Millis;               // durée enregistrée
    public volatile bool HeardVoice;          // on a entendu parler
    public volatile int MillisSinceVoice;     // depuis combien de temps on s'est tu

    public static bool HasDevice() { return waveInGetNumDevs() > 0; }
    static int HeaderSize { get { return Marshal.SizeOf(typeof(WAVEHDR)); } }

    // 0 si l'enregistrement a commencé, sinon le code d'erreur de Windows (micro absent ou refusé)
    public int Start()
    {
        WAVEFORMATEX f = new WAVEFORMATEX { wFormatTag = 1, nChannels = 1, nSamplesPerSec = Rate, wBitsPerSample = 16, nBlockAlign = 2, nAvgBytesPerSec = Rate * 2, cbSize = 0 };
        int r = waveInOpen(out h, EMMicros.Choisi, ref f, ev.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, CALLBACK_EVENT);
        if (r != 0) { h = IntPtr.Zero; return r; }
        for (int i = 0; i < hdrs.Length; i++)
        {
            WAVEHDR hd = new WAVEHDR { lpData = Marshal.AllocHGlobal(BufBytes), dwBufferLength = BufBytes };
            hdrs[i] = Marshal.AllocHGlobal(HeaderSize);
            Marshal.StructureToPtr(hd, hdrs[i], false);
            waveInPrepareHeader(h, hdrs[i], (uint)HeaderSize);
            waveInAddBuffer(h, hdrs[i], (uint)HeaderSize);
        }
        run = true;
        th = new Thread(Loop) { IsBackground = true };
        th.Start();
        return waveInStart(h);
    }

    void Loop()
    {
        while (run)
        {
            ev.WaitOne(200);
            for (int i = 0; i < hdrs.Length && run; i++)
            {
                WAVEHDR hd = (WAVEHDR)Marshal.PtrToStructure(hdrs[i], typeof(WAVEHDR));
                if ((hd.dwFlags & WHDR_DONE) == 0) continue;
                int n = (int)hd.dwBytesRecorded;
                if (n > 0)
                {
                    byte[] b = new byte[n];
                    Marshal.Copy(hd.lpData, b, 0, n);
                    lock (data) data.Write(b, 0, n);
                    Analyse(b, n);
                }
                waveInUnprepareHeader(h, hdrs[i], (uint)HeaderSize);
                hd.dwFlags = 0; hd.dwBytesRecorded = 0;
                Marshal.StructureToPtr(hd, hdrs[i], false);
                waveInPrepareHeader(h, hdrs[i], (uint)HeaderSize);
                waveInAddBuffer(h, hdrs[i], (uint)HeaderSize);
            }
        }
    }

    // Niveau du son ; le bruit de fond est mesuré sur les 300 premières millisecondes
    void Analyse(byte[] b, int n)
    {
        double sum = 0; int count = n / 2;
        for (int i = 0; i + 1 < n; i += 2) { short s = (short)(b[i] | (b[i + 1] << 8)); sum += (double)s * s; }
        double rms = count > 0 ? Math.Sqrt(sum / count) / 32768.0 : 0;
        int ms = count * 1000 / Rate;
        Millis += ms;
        Level = (float)Math.Min(1.0, rms * 8);
        if (floorCount < 3) { floor = (floor * floorCount + rms) / (floorCount + 1); floorCount++; return; }
        double seuil = Math.Max(0.012, floor * 3);
        if (rms > seuil) { HeardVoice = true; MillisSinceVoice = 0; }
        else MillisSinceVoice += ms;
    }

    public void Stop()
    {
        if (h == IntPtr.Zero) return;
        run = false;
        ev.Set();
        if (th != null) th.Join(1000);
        waveInReset(h);
        for (int i = 0; i < hdrs.Length; i++)
        {
            if (hdrs[i] == IntPtr.Zero) continue;
            WAVEHDR hd = (WAVEHDR)Marshal.PtrToStructure(hdrs[i], typeof(WAVEHDR));
            waveInUnprepareHeader(h, hdrs[i], (uint)HeaderSize);
            Marshal.FreeHGlobal(hd.lpData);
            Marshal.FreeHGlobal(hdrs[i]);
            hdrs[i] = IntPtr.Zero;
        }
        waveInClose(h);
        h = IntPtr.Zero;
    }

    // Enregistre ce qui a été entendu dans un fichier .wav
    public void SaveWav(string path)
    {
        byte[] pcm; lock (data) pcm = data.ToArray();
        using (BinaryWriter w = new BinaryWriter(File.Create(path)))
        {
            w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + pcm.Length);
            w.Write(new[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(Rate); w.Write(Rate * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(pcm.Length); w.Write(pcm);
        }
    }
}

// ---------------------------------------------------------------------------
// Écoute du mot de réveil « OK Eve » : Vosk (reconnaissance vocale locale, petite et légère) écoute le micro
// en continu sur son propre fil, et ne sait reconnaître que « ok ève » (tout le reste devient « inconnu »).
// Rien n'est enregistré ni envoyé : chaque phrase est oubliée dès qu'elle est finie, sauf celle qui commence par « OK Eve ».
// ---------------------------------------------------------------------------
public class EMEveil
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetDllDirectory(string p);
    [DllImport("libvosk.dll")] static extern void vosk_set_log_level(int l);
    [DllImport("libvosk.dll")] static extern IntPtr vosk_model_new(byte[] path);
    [DllImport("libvosk.dll")] static extern void vosk_model_free(IntPtr m);
    [DllImport("libvosk.dll")] static extern IntPtr vosk_recognizer_new_grm(IntPtr m, float rate, byte[] grm);
    [DllImport("libvosk.dll")] static extern void vosk_recognizer_set_words(IntPtr r, int w);
    [DllImport("libvosk.dll")] static extern int vosk_recognizer_accept_waveform(IntPtr r, byte[] data, int len);
    [DllImport("libvosk.dll")] static extern IntPtr vosk_recognizer_result(IntPtr r);
    [DllImport("libvosk.dll")] static extern IntPtr vosk_recognizer_final_result(IntPtr r);
    [DllImport("libvosk.dll")] static extern void vosk_recognizer_reset(IntPtr r);
    [DllImport("libvosk.dll")] static extern void vosk_recognizer_free(IntPtr r);

    [StructLayout(LayoutKind.Sequential)]
    struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }
    [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, uint dev, ref WAVEFORMATEX f, IntPtr cb, IntPtr inst, uint flags);
    [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, uint size);
    [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);

    const int Rate = 16000, BufBytes = 3200;
    const string Grammaire = "[\"ok ève\", \"[unk]\"]";
    IntPtr model = IntPtr.Zero, rec = IntPtr.Zero, h = IntPtr.Zero;
    readonly IntPtr[] hdrs = new IntPtr[4];
    readonly AutoResetEvent ev = new AutoResetEvent(false);
    readonly MemoryStream phrase = new MemoryStream();   // la phrase en cours (gardée seulement si elle commence par « OK Eve »)
    Thread th;
    volatile bool run;

    public volatile bool Pause;          // pendant qu'Evermind parle, écoute ou réfléchit
    public volatile bool Detecte;        // « OK Eve » vient d'être entendu
    public volatile bool AvecCommande;   // ... suivi d'autres mots dans la même phrase (« OK Eve, supprime le foot »)
    public double Seuil = 0.3;           // confiance minimale pour être « candidat » (Whisper confirme ensuite chaque fois)
    public double ConfMin;               // la plus petite confiance de « ok » et « ève » (0.99 et plus : sûr)
    public string Erreur = "";
    public string DernierTexte = "";
    byte[] pcmDetecte;
    public int RateDetecte = Rate;

    static int HeaderSize { get { return Marshal.SizeOf(typeof(WAVEHDR)); } }

    // Charge Vosk et son modèle français (environ une seconde)
    public bool Charger(string dossierLib, string dossierModele)
    {
        try
        {
            SetDllDirectory(dossierLib);
            vosk_set_log_level(-1);
            model = vosk_model_new(Encoding.UTF8.GetBytes(dossierModele + "\0"));
            if (model == IntPtr.Zero) { Erreur = "modèle illisible"; return false; }
            return true;
        }
        catch (Exception e) { Erreur = e.Message; return false; }
    }

    IntPtr NouveauRecognizer(int rate)
    {
        IntPtr r = vosk_recognizer_new_grm(model, rate, Encoding.UTF8.GetBytes(Grammaire + "\0"));
        vosk_recognizer_set_words(r, 1);
        return r;
    }

    // 0 si l'écoute du micro a commencé, sinon le code d'erreur de Windows
    public int Start()
    {
        if (model == IntPtr.Zero) return -1;
        rec = NouveauRecognizer(Rate);
        WAVEFORMATEX f = new WAVEFORMATEX { wFormatTag = 1, nChannels = 1, nSamplesPerSec = Rate, wBitsPerSample = 16, nBlockAlign = 2, nAvgBytesPerSec = Rate * 2, cbSize = 0 };
        int r = waveInOpen(out h, EMMicros.Choisi, ref f, ev.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, 0x50000);
        if (r != 0) { h = IntPtr.Zero; return r; }
        for (int i = 0; i < hdrs.Length; i++)
        {
            WAVEHDR hd = new WAVEHDR { lpData = Marshal.AllocHGlobal(BufBytes), dwBufferLength = BufBytes };
            hdrs[i] = Marshal.AllocHGlobal(HeaderSize);
            Marshal.StructureToPtr(hd, hdrs[i], false);
            waveInPrepareHeader(h, hdrs[i], (uint)HeaderSize);
            waveInAddBuffer(h, hdrs[i], (uint)HeaderSize);
        }
        run = true;
        th = new Thread(Boucle) { IsBackground = true, Priority = ThreadPriority.BelowNormal };
        th.Start();
        return waveInStart(h);
    }

    void Boucle()
    {
        bool enPause = false;
        while (run)
        {
            ev.WaitOne(200);
            for (int i = 0; i < hdrs.Length && run; i++)
            {
                WAVEHDR hd = (WAVEHDR)Marshal.PtrToStructure(hdrs[i], typeof(WAVEHDR));
                if ((hd.dwFlags & 1) == 0) continue;
                int n = (int)hd.dwBytesRecorded;
                if (Pause) { if (!enPause) { vosk_recognizer_reset(rec); phrase.SetLength(0); enPause = true; } }
                else if (n > 0)
                {
                    enPause = false;
                    byte[] b = new byte[n];
                    Marshal.Copy(hd.lpData, b, 0, n);
                    Traiter(rec, b, n, Rate);
                }
                waveInUnprepareHeader(h, hdrs[i], (uint)HeaderSize);
                hd.dwFlags = 0; hd.dwBytesRecorded = 0;
                Marshal.StructureToPtr(hd, hdrs[i], false);
                waveInPrepareHeader(h, hdrs[i], (uint)HeaderSize);
                waveInAddBuffer(h, hdrs[i], (uint)HeaderSize);
            }
        }
    }

    public volatile float NiveauMax;     // le son le plus fort entendu depuis la dernière lecture (diagnostic)
    public volatile int Paquets;         // morceaux de son reçus du micro (diagnostic)
    public string Indices = "";          // phrases où Vosk a cru entendre « ok » ou « ève », avec leur confiance (diagnostic)

    void Traiter(IntPtr r, byte[] b, int n, int rate)
    {
        double sum = 0; for (int i = 0; i + 1 < n; i += 2) { short s = (short)(b[i] | (b[i + 1] << 8)); sum += (double)s * s; }
        float rms = (float)(Math.Sqrt(sum / Math.Max(1, n / 2)) / 32768.0);
        if (rms > NiveauMax) NiveauMax = rms;
        Paquets++;
        phrase.Write(b, 0, n);
        if (phrase.Length > rate * 2 * 20) phrase.SetLength(0);   // jamais plus de 20 secondes en mémoire
        if (vosk_recognizer_accept_waveform(r, b, n) == 1) Analyser(PtrToString(vosk_recognizer_result(r)), rate);
    }

    // Fin d'une phrase : « ok » puis « ève », tout au début et sûrs à coup sûr ? Sinon la phrase est oubliée.
    public string Phrases = "";          // ce que Vosk a compris des dernières phrases (pour les tests)
    void Analyser(string json, int rate)
    {
        Phrases = (Phrases + " | " + System.Text.RegularExpressions.Regex.Match(json, "\"text\"\\s*:\\s*\"([^\"]*)\"").Groups[1].Value);
        if (Phrases.Length > 300) Phrases = Phrases.Substring(Phrases.Length - 300);
        var mots = System.Text.RegularExpressions.Regex.Matches(json, "\"conf\"\\s*:\\s*([0-9.]+)[^}]*?\"word\"\\s*:\\s*\"([^\"]*)\"");
        string vus = "";
        foreach (System.Text.RegularExpressions.Match mo in mots) if (mo.Groups[2].Value != "[unk]") vus += " " + mo.Groups[2].Value + " " + mo.Groups[1].Value;
        if (vus != "") lock (this) Indices += (Indices == "" ? "" : " |") + vus;
        if (mots.Count >= 2)
        {
            double c0 = double.Parse(mots[0].Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
            double c1 = double.Parse(mots[1].Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
            if (mots[0].Groups[2].Value == "ok" && mots[1].Groups[2].Value == "ève" && c0 >= Seuil && c1 >= Seuil && !Detecte)
            {
                AvecCommande = mots.Count > 2;
                ConfMin = Math.Min(c0, c1);
                pcmDetecte = phrase.ToArray();
                RateDetecte = rate;
                DernierTexte = json;
                Detecte = true;
            }
        }
        phrase.SetLength(0);
    }

    // La phrase qui a réveillé Evermind, en .wav (quand la demande était dans la même phrase)
    public void SaveWav(string path)
    {
        byte[] pcm = pcmDetecte ?? new byte[0];
        using (BinaryWriter w = new BinaryWriter(File.Create(path)))
        {
            w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + pcm.Length);
            w.Write(new[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(RateDetecte); w.Write(RateDetecte * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(pcm.Length); w.Write(pcm);
        }
    }

    // Tests automatiques : passe un fichier son (PCM 16 bits mono) comme s'il venait du micro
    public void TestPcm(byte[] pcm, int rate)
    {
        IntPtr r = NouveauRecognizer(rate);
        phrase.SetLength(0);
        for (int i = 0; i < pcm.Length; i += BufBytes)
        {
            int n = Math.Min(BufBytes, pcm.Length - i);
            byte[] b = new byte[n]; Array.Copy(pcm, i, b, 0, n);
            Traiter(r, b, n, rate);
        }
        Analyser(PtrToString(vosk_recognizer_final_result(r)), rate);
        vosk_recognizer_free(r);
        if (Detecte) pcmDetecte = pcm;   // en test, il n'y a pas de micro pour la suite : toute la phrase est gardée
    }

    public void Stop()
    {
        run = false; ev.Set();
        if (th != null) th.Join(1000);
        if (h != IntPtr.Zero)
        {
            waveInReset(h);
            for (int i = 0; i < hdrs.Length; i++)
            {
                if (hdrs[i] == IntPtr.Zero) continue;
                WAVEHDR hd = (WAVEHDR)Marshal.PtrToStructure(hdrs[i], typeof(WAVEHDR));
                waveInUnprepareHeader(h, hdrs[i], (uint)HeaderSize);
                Marshal.FreeHGlobal(hd.lpData); Marshal.FreeHGlobal(hdrs[i]); hdrs[i] = IntPtr.Zero;
            }
            waveInClose(h); h = IntPtr.Zero;
        }
        if (rec != IntPtr.Zero) { vosk_recognizer_free(rec); rec = IntPtr.Zero; }
    }

    static string PtrToString(IntPtr p)
    {
        if (p == IntPtr.Zero) return "";
        int n = 0; while (Marshal.ReadByte(p, n) != 0) n++;
        byte[] b = new byte[n]; Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }
}

// Lit les lignes d'un programme lancé à côté (la voix Kokoro) sur un fil à part :
// la fenêtre vient les chercher quand elle veut, sans jamais attendre.
public class EMLigneur
{
    readonly System.Collections.Concurrent.ConcurrentQueue<string> lignes = new System.Collections.Concurrent.ConcurrentQueue<string>();
    public EMLigneur(StreamReader lecteur)
    {
        Thread t = new Thread(() => { try { string l; while ((l = lecteur.ReadLine()) != null) lignes.Enqueue(l); } catch { } lignes.Enqueue(null); });
        t.IsBackground = true;
        t.Start();
    }
    public volatile bool Fini;
    // La prochaine ligne, ou "" s'il n'y en a pas encore ; null quand le programme s'est arrêté
    public string Suivante()
    {
        string l;
        if (!lignes.TryDequeue(out l)) return "";
        if (l == null) Fini = true;
        return l;
    }
}

public static class EMNative
{
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    // Barre de titre sombre, et sur Windows 11 de la couleur du fond de l'app (couleur en « 0xBBGGRR »)
    public static void SetDarkTitleBar(IntPtr hwnd, int captionBgr)
    {
        int on = 1;
        if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4);
        DwmSetWindowAttribute(hwnd, 35, ref captionBgr, 4);
    }

    // -----------------------------------------------------------------------
    // Raccourci clavier global (marche même en jeu) et état des touches
    // -----------------------------------------------------------------------
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hwnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    public static bool AddHotKey(IntPtr hwnd, int id, uint mods, uint vk) { return RegisterHotKey(hwnd, id, mods | 0x4000, vk); }   // 0x4000 : pas de répétition
    public static void RemoveHotKey(IntPtr hwnd, int id) { UnregisterHotKey(hwnd, id); }
    public static bool IsKeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

    // Fenêtre qui ne prend jamais le focus (la bulle « Je t'écoute » ne sort pas du jeu)
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    public static void MakeNoActivate(IntPtr hwnd)
    {
        SetWindowLong(hwnd, -20, GetWindowLong(hwnd, -20) | 0x08000000 | 0x80 | 0x20);   // WS_EX_NOACTIVATE, TOOLWINDOW, TRANSPARENT
    }

    // -----------------------------------------------------------------------
    // Identité dans la barre des tâches
    // -----------------------------------------------------------------------
    // Sans identité propre, Windows range la fenêtre avec PowerShell et affiche son icône bleue.
    // Avec la sienne, la barre des tâches montre l'icône d'Evermind, et une fois épinglée,
    // Evermind se relance avec son icône et son nom.
    [DllImport("shell32.dll", PreserveSig = false)]
    static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appId);

    public static void SetAppId(string appId) { SetCurrentProcessExplicitAppUserModelID(appId); }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    // PROPVARIANT réduit à ce qui sert ici : une chaîne (VT_LPWSTR)
    [StructLayout(LayoutKind.Explicit)]
    struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr p;
        [FieldOffset(8)] public long pad1;
        [FieldOffset(16)] public long pad2;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PROPERTYKEY key);
        void GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        void SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        void Commit();
    }

    [DllImport("shell32.dll", PreserveSig = false)]
    static extern void SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

    static readonly Guid AppUserModelKeys = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    static void SetString(IPropertyStore store, uint pid, string value)
    {
        PROPERTYKEY key = new PROPERTYKEY { fmtid = AppUserModelKeys, pid = pid };
        PROPVARIANT v = new PROPVARIANT { vt = 31, p = Marshal.StringToCoTaskMemUni(value) };   // 31 = VT_LPWSTR
        try { store.SetValue(ref key, ref v); }
        finally { Marshal.FreeCoTaskMem(v.p); }
    }

    // Identité, commande de relance, icône et nom de la fenêtre (utilisés quand on l'épingle)
    public static void SetWindowIdentity(IntPtr hwnd, string appId, string relaunchCommand, string iconPath, string name)
    {
        Guid iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        SHGetPropertyStoreForWindow(hwnd, ref iid, out store);
        try
        {
            SetString(store, 2, relaunchCommand);   // System.AppUserModel.RelaunchCommand
            SetString(store, 3, iconPath);          // System.AppUserModel.RelaunchIconResource
            SetString(store, 4, name);              // System.AppUserModel.RelaunchDisplayNameResource
            SetString(store, 5, appId);             // System.AppUserModel.ID, en dernier
            store.Commit();
        }
        finally { Marshal.ReleaseComObject(store); }
    }
}
