#include "file_save_channel.h"

#include <cstring>

// One "save" call from Dart and the native dialog answering it. The dialog is
// shown without a nested main loop, so the Flutter engine keeps rendering and
// handling other channel traffic while it is open.
//
// Invariant: |call| is answered exactly once, by finish_save_request(), which
// also releases every reference this struct owns and frees it. Both ways a
// request can end lead there: the dialog's "response" signal, or the parent
// window being destroyed while the dialog is still open.
struct SaveRequest {
  FlMethodCall* call;            // Owned reference, dropped once answered.
  GtkFileChooserNative* dialog;  // Owned reference.
  GtkWindow* window;             // Borrowed; alive while the request is.
  gulong window_destroy_handler;
};

// Destroys and releases a dialog from the main loop rather than from inside
// its own "response" emission, so GTK never runs dispose on an object that is
// still delivering a signal.
static gboolean release_dialog(gpointer data) {
  GtkFileChooserNative* dialog = GTK_FILE_CHOOSER_NATIVE(data);
  gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
  g_object_unref(dialog);
  return G_SOURCE_REMOVE;
}

// Answers Dart with |path| (nullptr means cancelled) and frees |request|.
// |defer_dialog_release| is true while the dialog is emitting "response".
static void finish_save_request(SaveRequest* request, const gchar* path,
                                gboolean defer_dialog_release) {
  g_signal_handler_disconnect(request->window, request->window_destroy_handler);
  g_signal_handlers_disconnect_by_data(request->dialog, request);

  g_autoptr(FlValue) result =
      path == nullptr ? fl_value_new_null() : fl_value_new_string(path);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_success(request->call, result, &error)) {
    // The engine can already be gone during shutdown; nothing is listening.
    g_warning("Could not answer the save dialog request: %s", error->message);
  }
  g_object_unref(request->call);

  if (defer_dialog_release) {
    g_idle_add(release_dialog, request->dialog);
  } else {
    release_dialog(request->dialog);
  }
  delete request;
}

static void on_dialog_response(GtkNativeDialog* dialog, gint response_id,
                               gpointer user_data) {
  auto* request = static_cast<SaveRequest*>(user_data);
  g_autofree gchar* path = nullptr;
  if (response_id == GTK_RESPONSE_ACCEPT) {
    path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
  }
  finish_save_request(request, path, TRUE);
}

// The window is closing with the dialog still open: take the dialog down and
// report a cancellation, since no "response" will follow once it is hidden.
static void on_window_destroy(GtkWidget* window, gpointer user_data) {
  auto* request = static_cast<SaveRequest*>(user_data);
  gtk_native_dialog_hide(GTK_NATIVE_DIALOG(request->dialog));
  finish_save_request(request, nullptr, FALSE);
}

static void handle_save(FlMethodChannel* channel, FlMethodCall* call,
                        gpointer user_data) {
  if (strcmp(fl_method_call_get_name(call), "save") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* name = fl_method_call_get_args(call);
  if (fl_value_get_type(name) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(call, "bad-arguments",
                                 "A suggested filename is required", nullptr,
                                 nullptr);
    return;
  }
  GtkWindow* window = GTK_WINDOW(user_data);
  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      "Save File", window, GTK_FILE_CHOOSER_ACTION_SAVE, "_Save", "_Cancel");
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_current_name(chooser, fl_value_get_string(name));
  gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(dialog), TRUE);

  auto* request =
      new SaveRequest{FL_METHOD_CALL(g_object_ref(call)), dialog, window, 0};
  request->window_destroy_handler = g_signal_connect(
      window, "destroy", G_CALLBACK(on_window_destroy), request);
  g_signal_connect(dialog, "response", G_CALLBACK(on_dialog_response), request);
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
}

void attach_file_save_channel(FlBinaryMessenger* messenger, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Dropping this reference does not close the channel: the messenger keeps
  // its own reference to every channel with a registered handler, for as long
  // as the engine lives (app_test.dart checks the channel still answers).
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "meow_chess/file_save", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_save, window,
                                            nullptr);
}
