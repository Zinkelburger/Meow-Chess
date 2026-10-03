#include "file_open_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shlobj.h>

#include "utils.h"

namespace {

constexpr char kChannelName[] = "meow_chess/file_open";

flutter::EncodableValue PathsToValue(const std::vector<std::string>& paths) {
  flutter::EncodableList list;
  for (const std::string& path : paths) {
    list.push_back(flutter::EncodableValue(path));
  }
  return flutter::EncodableValue(list);
}

}  // namespace

void FileOpenChannel::Attach(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "reveal") {
          const auto* path = call.arguments()
              ? std::get_if<std::string>(call.arguments()) : nullptr;
          if (!path || path->empty()) {
            result->Error("invalid_path", "A file path is required.");
            return;
          }
          const auto wide_path = Utf16FromUtf8(*path);
          PIDLIST_ABSOLUTE item = nullptr;
          HRESULT status = SHParseDisplayName(wide_path.c_str(), nullptr,
                                               &item, 0, nullptr);
          if (SUCCEEDED(status)) {
            status = SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
          }
          CoTaskMemFree(item);
          if (FAILED(status)) {
            result->Error("reveal_failed", "Could not show the file in File Explorer.");
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() != "ready") {
          result->NotImplemented();
          return;
        }
        dart_ready_ = true;
        flutter::EncodableValue pending = PathsToValue(pending_);
        pending_.clear();
        result->Success(pending);
      });
}

void FileOpenChannel::Open(const std::vector<std::string>& paths) {
  if (paths.empty()) return;
  if (!dart_ready_ || !channel_) {
    pending_.insert(pending_.end(), paths.begin(), paths.end());
    return;
  }
  channel_->InvokeMethod(
      "open", std::make_unique<flutter::EncodableValue>(PathsToValue(paths)));
}
