// macOS: a borderless window at the desktop level sits behind the icons, on
// every Space, and lets clicks through to the desktop.
#include "desktop.h"
#include <QScreen>
#include <QWindow>
#import <AppKit/AppKit.h>

int Desktop::windowFlags() { return 0; }   // not Qt::Tool: tool windows hide when the app isn't active

bool Desktop::sendToBack(QWindow *window, QScreen *screen)
{
    NSView *view = reinterpret_cast<NSView *>(window->winId());
    NSWindow *w = view.window;
    if (!w) return false;
    [w setLevel:kCGDesktopWindowLevel];
    [w setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces
                             | NSWindowCollectionBehaviorStationary
                             | NSWindowCollectionBehaviorIgnoresCycle];
    [w setIgnoresMouseEvents:YES];
    [w setHasShadow:NO];
    // cover the whole screen, menu bar area included
    for (NSScreen *s in [NSScreen screens]) {
        NSString *name = s.localizedName;
        if (name && QString::fromNSString(name) == screen->name()) { [w setFrame:s.frame display:YES]; break; }
    }
    return true;
}
