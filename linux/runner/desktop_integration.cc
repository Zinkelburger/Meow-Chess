#include "desktop_integration.h"

#include <string.h>

// A portable build (the release zip) is just a folder: nothing tells the
// desktop it exists. Accepting the offer installs what a package would have:
//
//  * a desktop entry, so the app is in the menu and, on Wayland, the window
//    gets its icon (compositors find it by matching the app-id to an entry);
//  * the icon;
//  * the .meow MIME type — unlike .pgn, no desktop knows .meow on its own;
//  * the app as the default handler for that type, in mimeapps.list.

static const char kMimeType[] = "application/x-meow-chess";
static const char kDesktopId[] = APPLICATION_ID ".desktop";
static const char kMimePackage[] = APPLICATION_ID ".xml";
static const char kIconFile[] = APPLICATION_ID ".png";

static gchar* state_file_path() {
  return g_build_filename(g_get_user_data_dir(), APPLICATION_ID,
                          "desktop-integration-choice", nullptr);
}

static void write_choice(const gchar* choice) {
  g_autofree gchar* path = state_file_path();
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0755);
  g_file_set_contents(path, choice, -1, nullptr);
}

static gchar* read_choice() {
  g_autofree gchar* path = state_file_path();
  gchar* choice = nullptr;
  if (!g_file_get_contents(path, &choice, nullptr, nullptr)) return nullptr;
  return choice;
}

// True when a package (.deb, .rpm) installed the desktop entry system-wide;
// then there is nothing for the app to set up.
static gboolean installed_system_wide() {
  for (const gchar* const* dir = g_get_system_data_dirs(); *dir != nullptr;
       ++dir) {
    g_autofree gchar* entry =
        g_build_filename(*dir, "applications", kDesktopId, nullptr);
    if (g_file_test(entry, G_FILE_TEST_EXISTS)) return TRUE;
  }
  return FALSE;
}

// Returns TRUE when |path| was written (it was missing or different).
static gboolean write_file_if_changed(const gchar* path, const gchar* data,
                                      gssize length) {
  if (length < 0) length = strlen(data);
  gsize old_length = 0;
  g_autofree gchar* old_data = nullptr;
  if (g_file_get_contents(path, &old_data, &old_length, nullptr) &&
      old_length == (gsize)length && memcmp(old_data, data, old_length) == 0) {
    return FALSE;
  }
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0755);
  return g_file_set_contents(path, data, length, nullptr);
}

// Copies |source| to |dest| when the contents differ.
static gboolean copy_file_if_changed(const gchar* source, const gchar* dest) {
  g_autofree gchar* data = nullptr;
  gsize length = 0;
  if (!g_file_get_contents(source, &data, &length, nullptr)) {
    g_warning("Desktop setup: missing %s", source);
    return FALSE;
  }
  return write_file_if_changed(dest, data, length);
}

// Best effort: the helpers come with every desktop that reads these files,
// and the files themselves are already correct without them.
static void run_helper(const gchar* program, const gchar* argument) {
  gchar* argv[] = {const_cast<gchar*>(program),
                   const_cast<gchar*>(argument), nullptr};
  g_spawn_async(nullptr, argv, nullptr,
                static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH |
                                         G_SPAWN_STDOUT_TO_DEV_NULL |
                                         G_SPAWN_STDERR_TO_DEV_NULL),
                nullptr, nullptr, nullptr, nullptr);
}

// |value| as one quoted argument of a desktop entry's Exec key, or nullptr
// when it holds a character that cannot be written there. Shell quoting is
// not valid in Exec: the spec wants double quotes with " ` $ \ escaped and %
// doubled, and the key-file layer then removes one level of backslashes.
// Matches exec_argument in tools/install_linux_launcher.py.
static gchar* desktop_exec_quote(const gchar* value) {
  if (strpbrk(value, "\n\r\t=") != nullptr) return nullptr;
  GString* quoted = g_string_new("\"");
  for (const gchar* c = value; *c != '\0'; ++c) {
    switch (*c) {
      case '%':
        g_string_append(quoted, "%%");
        break;
      case '\\':
        g_string_append(quoted, "\\\\\\\\");
        break;
      case '"':
      case '`':
      case '$':
        g_string_append(quoted, "\\\\");
        g_string_append_c(quoted, *c);
        break;
      default:
        g_string_append_c(quoted, *c);
    }
  }
  g_string_append_c(quoted, '"');
  return g_string_free(quoted, FALSE);
}

static void install_desktop_files() {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return;
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  const gchar* data_home = g_get_user_data_dir();

  g_autofree gchar* icon_src =
      g_build_filename(exe_dir, "data", "flutter_assets", "assets", "icon",
                       "meow_chess.png", nullptr);
  g_autofree gchar* icon_dest =
      g_build_filename(data_home, "icons", "hicolor", "256x256", "apps",
                       kIconFile, nullptr);
  if (copy_file_if_changed(icon_src, icon_dest)) {
    g_autofree gchar* icons_dir =
        g_build_filename(data_home, "icons", "hicolor", nullptr);
    run_helper("gtk-update-icon-cache", icons_dir);
  }

  g_autofree gchar* mime_src =
      g_build_filename(exe_dir, "data", kMimePackage, nullptr);
  g_autofree gchar* mime_dir = g_build_filename(data_home, "mime", nullptr);
  g_autofree gchar* mime_dest =
      g_build_filename(mime_dir, "packages", kMimePackage, nullptr);
  if (copy_file_if_changed(mime_src, mime_dest)) {
    run_helper("update-mime-database", mime_dir);
  }

  // Absolute Exec path, refreshed every launch so the entry keeps working
  // if the user moves the unzipped app folder. %f is the file the desktop
  // was asked to open with us.
  g_autofree gchar* exec_quoted = desktop_exec_quote(exe_path);
  if (exec_quoted == nullptr) return;
  g_autofree gchar* desktop_data = g_strdup_printf(
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=Meow Chess\n"
      "Comment=Run Swiss and quad chess tournaments\n"
      "Exec=%s %%f\n"
      "Icon=" APPLICATION_ID "\n"
      "StartupWMClass=" APPLICATION_ID "\n"
      "Categories=Game;BoardGame;\n"
      "Keywords=chess;tournament;swiss;quad;pairings;\n"
      "MimeType=%s;\n",
      exec_quoted, kMimeType);
  g_autofree gchar* applications_dir =
      g_build_filename(data_home, "applications", nullptr);
  g_autofree gchar* desktop_dest =
      g_build_filename(applications_dir, kDesktopId, nullptr);
  if (write_file_if_changed(desktop_dest, desktop_data, -1)) {
    run_helper("update-desktop-database", applications_dir);
  }
}

// Prepends |entry| to the ';'-separated list in |group|/|key| unless present.
static void key_file_add_to_list(GKeyFile* key_file, const gchar* group,
                                 const gchar* key, const gchar* entry) {
  g_autofree gchar* current =
      g_key_file_get_string(key_file, group, key, nullptr);
  if (current != nullptr) {
    g_auto(GStrv) parts = g_strsplit(current, ";", -1);
    for (gchar** part = parts; *part != nullptr; ++part) {
      if (g_strcmp0(*part, entry) == 0) return;
    }
  }
  g_autofree gchar* updated =
      (current == nullptr || *current == '\0')
          ? g_strdup_printf("%s;", entry)
          : g_strdup_printf("%s;%s", entry, current);
  g_key_file_set_string(key_file, group, key, updated);
}

// Makes this app the default for .meow in the user's mimeapps.list — the file
// `xdg-mime default` edits, written directly so xdg-utils is not required.
// Done once, on accepting the offer: re-asserting it on every launch would
// silently undo a default the user later changed.
static void set_default_handler() {
  g_autofree gchar* path =
      g_build_filename(g_get_user_config_dir(), "mimeapps.list", nullptr);
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_key_file_load_from_file(key_file, path, G_KEY_FILE_KEEP_COMMENTS, nullptr);

  g_key_file_set_string(key_file, "Default Applications", kMimeType,
                        kDesktopId);
  key_file_add_to_list(key_file, "Added Associations", kMimeType, kDesktopId);

  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0755);
  g_autoptr(GError) error = nullptr;
  if (!g_key_file_save_to_file(key_file, path, &error)) {
    g_warning("Could not update %s: %s", path, error->message);
  }
}

static void on_prompt_response(GtkDialog* dialog, gint response_id,
                               gpointer user_data) {
  if (response_id == GTK_RESPONSE_ACCEPT) {
    write_choice("yes");
    install_desktop_files();
    set_default_handler();
  } else if (response_id == GTK_RESPONSE_REJECT) {
    write_choice("no");
  }
  // Closing the dialog without choosing leaves no state, so we ask again
  // on the next launch.
  gtk_widget_destroy(GTK_WIDGET(dialog));
}

void desktop_integration_maybe_setup(GtkWindow* parent_window) {
#ifndef NDEBUG
  return;
#endif
  if (g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS)) return;
  if (installed_system_wide()) return;

  // MEOW_CHESS_DESKTOP_SETUP=1 answers "Set Up" and =0 "No Thanks" without
  // asking, for scripted installs.
  const gchar* preset = g_getenv("MEOW_CHESS_DESKTOP_SETUP");
  if (g_strcmp0(preset, "0") == 0) return;
  if (g_strcmp0(preset, "1") == 0) {
    write_choice("yes");
    install_desktop_files();
    set_default_handler();
    return;
  }

  g_autofree gchar* choice = read_choice();
  if (choice != nullptr) {
    if (g_str_has_prefix(choice, "yes")) install_desktop_files();
    return;
  }

  GtkWidget* dialog = gtk_message_dialog_new(
      parent_window, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
      "Set up Meow Chess on this computer?");
  gtk_message_dialog_format_secondary_text(
      GTK_MESSAGE_DIALOG(dialog),
      "Adds Meow Chess to your app menu and opens .meow tournament files "
      "with it when you double-click them. This only changes files in your "
      "home folder; you can change the default later in your desktop's "
      "settings.");
  gtk_dialog_add_button(GTK_DIALOG(dialog), "No Thanks", GTK_RESPONSE_REJECT);
  gtk_dialog_add_button(GTK_DIALOG(dialog), "Set Up", GTK_RESPONSE_ACCEPT);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
  g_signal_connect(dialog, "response", G_CALLBACK(on_prompt_response),
                   nullptr);
  gtk_widget_show_all(dialog);
}
