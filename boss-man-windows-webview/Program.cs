using System.IO;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace BossMan;

sealed class MainForm : Form
{
    readonly WebView2 _wv = new() { Dock = DockStyle.Fill };

    const string ChromelessJS =
        "(function(){" +
        "var css='html,body{margin:0!important;padding:0!important;height:100%!important;overflow:hidden!important;background:#000!important;gap:0!important}" +
        "#game{width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;border-radius:0!important;aspect-ratio:auto!important}" +
        "#footer{display:none!important}';" +
        "var s=document.createElement('style');s.textContent=css;" +
        "(document.head||document.documentElement).appendChild(s);" +
        "})();";

    public MainForm()
    {
        Text = "BOSS-MAN";
        WindowState = FormWindowState.Maximized;
        Controls.Add(_wv);
        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.F11) ToggleFullscreen(); };
        Load += async (_, _) =>
        {
            await _wv.EnsureCoreWebView2Async();
            var playDir = Path.Combine(AppContext.BaseDirectory, "play");
            _wv.CoreWebView2.SetVirtualHostNameToFolderMapping(
                "bossman.local", playDir, CoreWebView2HostResourceAccessKind.Allow);
            _wv.CoreWebView2.ContainsFullScreenElementChanged += (_, _) =>
            {
                if (_wv.CoreWebView2.ContainsFullScreenElement) GoFullscreen();
                else ExitFullscreen();
            };
            _wv.CoreWebView2.NavigationCompleted += async (_, _) =>
                await _wv.ExecuteScriptAsync(ChromelessJS);
            _wv.CoreWebView2.Navigate("https://bossman.local/server.html");
        };
    }

    void ToggleFullscreen()
    {
        if (FormBorderStyle == FormBorderStyle.None) ExitFullscreen();
        else GoFullscreen();
    }

    void GoFullscreen()
    {
        FormBorderStyle = FormBorderStyle.None;
        WindowState = FormWindowState.Normal;
        WindowState = FormWindowState.Maximized;
    }

    void ExitFullscreen()
    {
        FormBorderStyle = FormBorderStyle.Sizable;
        WindowState = FormWindowState.Normal;
    }
}

static class Program
{
    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
    }
}
