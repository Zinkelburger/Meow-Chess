#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include <string>
#include <vector>

#include "desktop_integration.h"
#include "file_open_channel.h"
#include "file_save_channel.h"
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FileOpenChannel* file_open_channel;
};

// The files among |arguments|: anything that is not a flag and names an
// existing regular file. Relative paths are made absolute here, while the
// working directory is still the one the file was named in.
static std::vector<std::string> file_arguments(gchar** arguments) {
  std::vector<std::string> paths;
  for (gchar** arg = arguments; arg != nullptr && *arg != nullptr; ++arg) {
    if ((*arg)[0] == '-' || (*arg)[0] == '\0') continue;
    if (!g_file_test(*arg, G_FILE_TEST_IS_REGULAR)) continue;
    g_autoptr(GFile) file = g_file_new_for_commandline_arg(*arg);
    g_autofree gchar* path = g_file_get_path(file);
    if (path != nullptr) paths.push_back(path);
  }
  return paths;
}

// Raises the existing window, if there is one. A second launch — from the
// menu, or a double-clicked .meow — reaches the running instance through
// GApplication and should bring it forward rather than open a second copy.
static gboolean present_existing_window(GtkApplication* application) {
  GList* windows = gtk_application_get_windows(application);
  if (windows == nullptr) return FALSE;
  gtk_window_present(GTK_WINDOW(windows->data));
  return TRUE;
}

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_widget_show(toplevel);
  desktop_integration_maybe_setup(GTK_WINDOW(toplevel));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (present_existing_window(GTK_APPLICATION(application))) return;

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Let GTK and the desktop provide their standard title bar and controls.
  gtk_window_set_title(window, "Meow Chess");

  gtk_window_set_default_size(window, 1280, 720);

  // X11 takes the window icon from here; Wayland from the desktop entry.
  // Found beside the executable, whatever the working directory.
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path =
        g_build_filename(exe_dir, "data", "flutter_assets", "assets", "icon",
                         "meow_chess.png", nullptr);
    gtk_window_set_icon_from_file(window, icon_path, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  self->file_open_channel->Attach(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)));
  attach_file_save_channel(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), window);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open — files a *second* launch forwarded to this,
// the running instance (a .meow double-clicked while the app is up).
static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  std::vector<std::string> paths;
  for (gint i = 0; i < n_files; ++i) {
    g_autofree gchar* path = g_file_get_path(files[i]);
    if (path != nullptr) paths.push_back(path);
  }
  self->file_open_channel->Open(paths);
  if (!present_existing_window(GTK_APPLICATION(application))) {
    g_application_activate(application);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  std::vector<std::string> paths = file_arguments(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // Another instance owns the app-id on the session bus: hand it our files
  // (or just raise it) and exit.
  if (g_application_get_is_remote(application)) {
    if (paths.empty()) {
      g_application_activate(application);
    } else {
      std::vector<GFile*> files;
      for (const std::string& path : paths) {
        files.push_back(g_file_new_for_path(path.c_str()));
      }
      g_application_open(application, files.data(),
                         static_cast<gint>(files.size()), "");
      for (GFile* file : files) g_object_unref(file);
    }
    *exit_status = 0;
    return TRUE;
  }

  self->file_open_channel->Open(paths);
  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  delete self->file_open_channel;
  self->file_open_channel = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->file_open_channel = new FileOpenChannel();
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // One instance per session in release builds: a later launch forwards its
  // files to the running one over the session bus (see local_command_line)
  // instead of opening a second window. Debug builds stay non-unique so
  // `flutter run` and integration tests never hand off to an open copy; set
  // MEOW_CHESS_NEW_INSTANCE=1 to get that in a release build too.
  GApplicationFlags flags = G_APPLICATION_HANDLES_OPEN;
#ifndef NDEBUG
  flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_NON_UNIQUE);
#endif
  if (g_strcmp0(g_getenv("MEOW_CHESS_NEW_INSTANCE"), "1") == 0) {
    flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_NON_UNIQUE);
  }

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}
