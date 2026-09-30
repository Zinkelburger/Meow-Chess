#ifndef RUNNER_DESKTOP_INTEGRATION_H_
#define RUNNER_DESKTOP_INTEGRATION_H_

#include <gtk/gtk.h>

// Offers (once) to set the app up on this desktop: an app-menu entry with its
// icon, the .meow file type, and the app as the default for .meow files.
// Everything goes into the user's XDG data and config directories, so no
// password is asked for. If accepted, the entry is refreshed on later
// launches so it follows the app folder if it moves. No-op inside Flatpak and
// for installed packages, which ship all of this themselves, and in debug
// builds, so a developer's build never becomes the .meow handler.
void desktop_integration_maybe_setup(GtkWindow* parent_window);

#endif  // RUNNER_DESKTOP_INTEGRATION_H_
