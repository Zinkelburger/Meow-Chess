#ifndef RUNNER_FILE_SAVE_CHANNEL_H_
#define RUNNER_FILE_SAVE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void attach_file_save_channel(FlBinaryMessenger* messenger, GtkWindow* window);

#endif  // RUNNER_FILE_SAVE_CHANNEL_H_
