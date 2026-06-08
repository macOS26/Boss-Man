using System.IO;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace BossMan;

sealed class MainForm : Form
{
    readonly WebView2 _wv = new() { Dock = DockStyle.Fill };

    public MainForm()
    {
        Text = "BOSS-MAN";
        WindowState = FormWindowState.Maximized;
        Controls.Add(_wv);
        Load += async (_, _) =>
        {
            await _wv.EnsureCoreWebView2Async();
            var playDir = Path.Combine(AppContext.BaseDirectory, "play");
            _wv.CoreWebView2.SetVirtualHostNameToFolderMapping(
                "bossman.local", playDir, CoreWebView2HostResourceAccessKind.Allow);
            _wv.CoreWebView2.Navigate("https://bossman.local/local.html");
        };
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
