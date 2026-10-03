#include "file_open_channel.h"

namespace {

struct RevealRequest {
  FlMethodCall* call;
  gchar* uri;
  gchar* parent_uri;
};

void finish_reveal(RevealRequest* request, bool selected) {
  g_autoptr(GError) error = nullptr;
  // Some desktops do not implement FileManager1. Open the containing folder
  // using the default handler in that case, never the event file itself.
  if (selected || g_app_info_launch_default_for_uri(request->parent_uri,
                                                   nullptr, &error)) {
    fl_method_call_respond_success(request->call, nullptr, nullptr);
  } else {
    fl_method_call_respond_error(request->call, "reveal_failed", error->message,
                                 nullptr, nullptr);
  }
  g_object_unref(request->call);
  g_free(request->uri);
  g_free(request->parent_uri);
  delete request;
}

void reveal_file(FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_STRING ||
      !g_path_is_absolute(fl_value_get_string(args))) {
    fl_method_call_respond_error(call, "invalid_path",
                                 "An absolute file path is required.",
                                 nullptr, nullptr);
    return;
  }
  const gchar* path = fl_value_get_string(args);
  if (!g_file_test(path, G_FILE_TEST_EXISTS)) {
    fl_method_call_respond_error(call, "reveal_failed",
                                 "The file could not be found.", nullptr, nullptr);
    return;
  }
  g_autoptr(GFile) file = g_file_new_for_path(path);
  g_autoptr(GFile) parent = g_file_get_parent(file);
  auto* request = new RevealRequest{
      FL_METHOD_CALL(g_object_ref(call)), g_file_get_uri(file),
      g_file_get_uri(parent != nullptr ? parent : file)};
  g_bus_get(G_BUS_TYPE_SESSION, nullptr,
      [](GObject*, GAsyncResult* result, gpointer data) {
        auto* request = static_cast<RevealRequest*>(data);
        g_autoptr(GError) error = nullptr;
        g_autoptr(GDBusConnection) bus = g_bus_get_finish(result, &error);
        if (bus == nullptr) {
          finish_reveal(request, false);
          return;
        }
        const gchar* uris[] = {request->uri, nullptr};
        g_dbus_connection_call(
            bus, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
            "org.freedesktop.FileManager1", "ShowItems",
            g_variant_new("(^ass)", uris, ""), nullptr,
            G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
            [](GObject* source, GAsyncResult* result, gpointer data) {
              g_autoptr(GError) error = nullptr;
              g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
                  G_DBUS_CONNECTION(source), result, &error);
              finish_reveal(static_cast<RevealRequest*>(data), reply != nullptr);
            }, request);
      }, request);
}

}  // namespace

static const char kChannelName[] = "meow_chess/file_open";

static FlValue* paths_to_value(const std::vector<std::string>& paths) {
  FlValue* list = fl_value_new_list();
  for (const std::string& path : paths) {
    fl_value_append_take(list, fl_value_new_string(path.c_str()));
  }
  return list;
}

FileOpenChannel::FileOpenChannel() {}

FileOpenChannel::~FileOpenChannel() {
  g_clear_object(&channel_);
}

void FileOpenChannel::Attach(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, kChannelName,
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                            nullptr);
}

void FileOpenChannel::Open(const std::vector<std::string>& paths) {
  if (paths.empty()) return;
  if (!dart_ready_ || channel_ == nullptr) {
    pending_.insert(pending_.end(), paths.begin(), paths.end());
    return;
  }
  g_autoptr(FlValue) args = paths_to_value(paths);
  fl_method_channel_invoke_method(channel_, "open", args, nullptr, nullptr,
                                  nullptr);
}

// static
void FileOpenChannel::OnMethodCall(FlMethodChannel* channel,
                                   FlMethodCall* method_call,
                                   gpointer user_data) {
  auto* self = static_cast<FileOpenChannel*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(GError) error = nullptr;

  if (g_strcmp0(method, "reveal") == 0) {
    reveal_file(method_call);
    return;
  }

  if (g_strcmp0(method, "ready") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, &error);
    return;
  }

  self->dart_ready_ = true;
  g_autoptr(FlValue) result = paths_to_value(self->pending_);
  self->pending_.clear();
  fl_method_call_respond_success(method_call, result, &error);
  if (error != nullptr) {
    g_warning("file_open: failed to answer ready: %s", error->message);
  }
}
