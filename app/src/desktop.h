#pragma once
// Puts a wallpaper window behind the desktop icons (platform specific).
class QWindow;
class QScreen;

namespace Desktop {
// Call after the window is shown. Returns false if it could only be put at
// the bottom of the normal window stack.
bool sendToBack(QWindow *window, QScreen *screen);
// Extra window flags this platform wants for a wallpaper window
int windowFlags();
}
