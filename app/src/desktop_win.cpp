// Windows: the classic "WorkerW" trick. Asking Progman (message 0x052C) makes
// Explorer split the desktop into a window for the icons and an empty window
// behind them; a wallpaper parented to that window sits behind the icons.
// Windows 11 24H2 moved both inside Progman, so there we parent to Progman and
// slot in between the icons and its WorkerW.
#include "desktop.h"
#include <QScreen>
#include <QWindow>
#include <windows.h>

namespace {

struct Shell { HWND progman = nullptr, icons = nullptr, worker = nullptr; bool inside = false; };

Shell findShell()
{
    Shell sh;
    sh.progman = FindWindowW(L"Progman", nullptr);
    if (!sh.progman) return sh;
    DWORD_PTR res;
    SendMessageTimeoutW(sh.progman, 0x052C, 0xD, 0x1, SMTO_NORMAL, 1000, &res);
    SendMessageTimeoutW(sh.progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, &res);

    sh.icons = FindWindowExW(sh.progman, nullptr, L"SHELLDLL_DefView", nullptr);
    if (sh.icons) {                                   // 24H2 and later
        sh.inside = true;
        sh.worker = FindWindowExW(sh.progman, nullptr, L"WorkerW", nullptr);
        return sh;
    }
    // older: the icons live in a top-level WorkerW; the next WorkerW is empty
    EnumWindows([](HWND top, LPARAM p) -> BOOL {
        auto *s = reinterpret_cast<Shell *>(p);
        if (HWND dv = FindWindowExW(top, nullptr, L"SHELLDLL_DefView", nullptr)) {
            s->icons = dv;
            s->worker = FindWindowExW(nullptr, top, L"WorkerW", nullptr);
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&sh));
    return sh;
}

// The monitor's rectangle in physical pixels, matched by device name
RECT monitorRect(QScreen *screen)
{
    struct Find { std::wstring name; RECT r{}; bool found = false; } f{screen->name().toStdWString()};
    EnumDisplayMonitors(nullptr, nullptr, [](HMONITOR m, HDC, LPRECT, LPARAM p) -> BOOL {
        auto *f = reinterpret_cast<Find *>(p);
        MONITORINFOEXW mi{}; mi.cbSize = sizeof(mi);
        if (GetMonitorInfoW(m, &mi) && f->name == mi.szDevice) { f->r = mi.rcMonitor; f->found = true; return FALSE; }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&f));
    if (!f.found) {
        const QRect g = screen->geometry();
        POINT pt{g.x() + 1, g.y() + 1};
        MONITORINFO mi{}; mi.cbSize = sizeof(mi);
        GetMonitorInfoW(MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST), &mi);
        f.r = mi.rcMonitor;
    }
    return f.r;
}

}

int Desktop::windowFlags() { return Qt::Tool; }      // no taskbar button

bool Desktop::sendToBack(QWindow *window, QScreen *screen)
{
    HWND hwnd = reinterpret_cast<HWND>(window->winId());
    const RECT r = monitorRect(screen);
    const Shell sh = findShell();
    HWND host = sh.inside ? sh.progman : sh.worker;
    if (!host) {
        SetWindowPos(hwnd, HWND_BOTTOM, r.left, r.top, r.right - r.left, r.bottom - r.top, SWP_NOACTIVATE);
        return false;
    }
    if (sh.inside) {
        // Progman draws with layered windows on 24H2; ours has to be one too
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, GetWindowLongPtrW(hwnd, GWL_EXSTYLE) | WS_EX_LAYERED);
        SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
    }
    SetParent(hwnd, host);
    POINT tl{r.left, r.top};
    ScreenToClient(host, &tl);
    // under the icons (24H2), or simply inside the empty WorkerW (older)
    SetWindowPos(hwnd, sh.inside ? sh.icons : HWND_TOP, tl.x, tl.y, r.right - r.left, r.bottom - r.top,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    if (sh.inside && sh.worker)
        SetWindowPos(sh.worker, hwnd, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    return true;
}
