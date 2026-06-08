#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <unistd.h>
#include <limits.h>
#include <libgen.h>

static const char *CHROMELESS_JS =
    "(function(){"
    "var css='html,body{margin:0!important;padding:0!important;height:100%!important;"
    "overflow:hidden!important;background:#000!important;gap:0!important}"
    "#game{width:100vw!important;height:100vh!important;max-width:none!important;"
    "max-height:none!important;border-radius:0!important;aspect-ratio:auto!important}"
    "#footer{display:none!important}';"
    "var s=document.createElement('style');s.textContent=css;"
    "(document.head||document.documentElement).appendChild(s);"
    "})();";

static GtkWindow *main_window = NULL;
static gboolean is_fullscreen = FALSE;

static gboolean on_key_press(GtkWidget *widget, GdkEventKey *event, gpointer data)
{
    if (event->keyval == GDK_KEY_F11) {
        if (is_fullscreen) { gtk_window_unfullscreen(main_window); is_fullscreen = FALSE; }
        else               { gtk_window_fullscreen(main_window);   is_fullscreen = TRUE; }
        return TRUE;
    }
    return FALSE;
}

static void on_load_changed(WebKitWebView *wv, WebKitLoadEvent event, gpointer data)
{
    if (event == WEBKIT_LOAD_FINISHED)
        webkit_web_view_run_javascript(wv, CHROMELESS_JS, NULL, NULL, NULL);
}

static void activate(GApplication *app, gpointer data)
{
    GtkWidget *window = gtk_application_window_new(GTK_APPLICATION(app));
    main_window = GTK_WINDOW(window);
    gtk_window_set_title(GTK_WINDOW(window), "BOSS-MAN");
    gtk_window_maximize(GTK_WINDOW(window));
    gtk_window_set_default_size(GTK_WINDOW(window), 1184, 740);

    g_signal_connect(window, "key-press-event", G_CALLBACK(on_key_press), NULL);

    WebKitSettings *settings = webkit_settings_new();
    webkit_settings_set_enable_javascript(settings, TRUE);
    webkit_settings_set_media_playback_requires_user_gesture(settings, FALSE);
    webkit_settings_set_allow_universal_access_from_file_urls(settings, TRUE);
    webkit_settings_set_allow_file_access_from_file_urls(settings, TRUE);

    WebKitWebView *wv = WEBKIT_WEB_VIEW(webkit_web_view_new_with_settings(settings));
    g_signal_connect(wv, "load-changed", G_CALLBACK(on_load_changed), NULL);
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(wv));

    char exe[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (len > 0) exe[len] = '\0';
    char *dir = dirname(exe);
    char *html = g_build_filename(dir, "play", "server.html", NULL);
    char *url  = g_filename_to_uri(html, NULL, NULL);
    webkit_web_view_load_uri(wv, url);
    g_free(html);
    g_free(url);

    gtk_widget_show_all(window);
}

int main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new(
        "com.starplayrx.bossman", (GApplicationFlags)0);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
