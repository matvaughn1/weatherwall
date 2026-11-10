// macOS: a borderless window at the desktop level sits behind the icons, on
// every Space, and lets clicks through to the desktop. Called again every few
// seconds, because Qt can put the window level back when it shows or moves it.
#include "desktop.h"
#include <QScreen>
#include <QWindow>
#import <AppKit/AppKit.h>

int Desktop::windowFlags() { return 0; }   // not Qt::Tool: tool windows hide when the app isn't active

// The NSScreen matching a QScreen (Qt: top-left origin; Cocoa: bottom-left)
static NSScreen *nsScreenFor(QScreen *screen, NSWindow *w)
{
    const QRect g = screen->geometry();
    const CGFloat primaryH = NSScreen.screens.firstObject.frame.size.height;
    for (NSScreen *s in NSScreen.screens) {
        const NSRect f = s.frame;
        if (qRound(f.origin.x) == g.x() && qRound(f.size.width) == g.width()
            && qRound(primaryH - f.origin.y - f.size.height) == g.y())
            return s;
    }
    return w.screen ?: NSScreen.mainScreen;
}

bool Desktop::sendToBack(QWindow *window, QScreen *screen)
{
    NSView *view = reinterpret_cast<NSView *>(window->winId());
    NSWindow *w = view.window;
    if (!w) return false;
    if (w.level != kCGDesktopWindowLevel) [w setLevel:kCGDesktopWindowLevel];
    const NSWindowCollectionBehavior want = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle
        | NSWindowCollectionBehaviorFullScreenNone;
    if (w.collectionBehavior != want) [w setCollectionBehavior:want];
    if (!w.ignoresMouseEvents) [w setIgnoresMouseEvents:YES];
    [w setHasShadow:NO];
    // cover the whole screen, menu bar area included
    NSScreen *s = nsScreenFor(screen, w);
    if (!NSEqualRects(w.frame, s.frame)) [w setFrame:s.frame display:YES];
    [w orderBack:nil];
    return true;
}
