// Evermind : fonctions natives de Windows, compilées au lancement par Evermind.ps1.
using System;
using System.Runtime.InteropServices;

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
