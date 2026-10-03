#include "file_save_channel.h"

#include <cstring>

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
  g_autoptr(GtkFileChooserNative) dialog = gtk_file_chooser_native_new(
      "Save File", GTK_WINDOW(user_data), GTK_FILE_CHOOSER_ACTION_SAVE,
      "_Save", "_Cancel");
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_current_name(chooser, fl_value_get_string(name));
  gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(dialog), TRUE);

  g_autofree gchar* path = nullptr;
  if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    path = gtk_file_chooser_get_filename(chooser);
  }
  g_autoptr(FlValue) result =
      path == nullptr ? fl_value_new_null() : fl_value_new_string(path);
  fl_method_call_respond_success(call, result, nullptr);
}

void attach_file_save_channel(FlBinaryMessenger* messenger, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "meow_chess/file_save", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_save, window, nullptr);
}
