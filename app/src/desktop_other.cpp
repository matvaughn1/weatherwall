// Linux and others: use the KDE plugin instead; this is only for trying the
// app out in a window.
#include "desktop.h"
#include <Qt>

bool Desktop::sendToBack(QWindow *, QScreen *) { return false; }
int Desktop::windowFlags() { return 0; }
