#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <unistd.h>
#include <limits.h>
#include <libgen.h>

static void activate(GApplication *app, gpointer data)
{
    GtkWidget *window = gtk_application_window_new(GTK_APPLICATION(app));
    gtk_window_set_title(GTK_WINDOW(window), "BOSS-MAN");
    gtk_window_maximize(GTK_WINDOW(window));
    gtk_window_set_default_size(GTK_WINDOW(window), 1184, 740);

    WebKitSettings *settings = webkit_settings_new();
    webkit_settings_set_enable_javascript(settings, TRUE);
    webkit_settings_set_media_playback_requires_user_gesture(settings, FALSE);
    webkit_settings_set_allow_universal_access_from_file_urls(settings, TRUE);
    webkit_settings_set_allow_file_access_from_file_urls(settings, TRUE);

    WebKitWebView *wv = WEBKIT_WEB_VIEW(webkit_web_view_new_with_settings(settings));
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(wv));

    char exe[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (len > 0) exe[len] = '\0';
    char *dir = dirname(exe);
    char *html = g_build_filename(dir, "play", "local.html", NULL);
    char *url  = g_filename_to_uri(html, NULL, NULL);
    webkit_web_view_load_uri(wv, url);
    g_free(html);
    g_free(url);

    gtk_widget_show_all(window);
}

int main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new(
        "com.starplayrx.bossman", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
