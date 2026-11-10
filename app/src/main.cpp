// Live Weather for Windows and macOS.
//
// Loads the KDE wallpaper's own QML (package/contents/ui/main.qml, shipped
// next to the app as "wallpaper/") on every screen, behind the desktop icons.
// The only Plasma bit in it is the WallpaperItem root, which is swapped for a
// plain Item with a `configuration` property as the file is loaded.
//
//   "Live Weather" --window    run in an ordinary window (for testing)
#include "autostart.h"
#include "config.h"
#include "desktop.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QMenu>
#include <QMessageBox>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QScreen>
#include <QSystemTrayIcon>
#include <QTimer>

namespace {

QString wallpaperDir()
{
    const QString env = qEnvironmentVariable("WEATHERWALL_PACKAGE");
    if (!env.isEmpty()) return env;
    QDir d(QCoreApplication::applicationDirPath());
#ifdef Q_OS_MACOS
    d.cd("../Resources");
#endif
    if (d.exists("wallpaper/contents/ui/main.qml")) return d.filePath("wallpaper");
    // running from a build folder inside the source tree
    QDir up(QCoreApplication::applicationDirPath());
    for (int i = 0; i < 6; i++) {
        if (up.exists("package/contents/ui/main.qml")) return up.filePath("package");
        if (!up.cdUp()) break;
    }
    return {};
}

class App : public QObject {
public:
    App(const QString &pkg, bool windowed) : m_pkg(pkg), m_windowed(windowed)
    {
        m_config = new Config(pkg + "/contents/config/main.xml", this);
        m_autostart = new Autostart(this);

        // the wallpaper QML, minus its Plasma root type
        const QString mainQml = pkg + "/contents/ui/main.qml";
        QFile f(mainQml);
        if (!f.open(QIODevice::ReadOnly)) qWarning() << "can't read" << mainQml;
        QString src = QString::fromUtf8(f.readAll());
        src.remove(QRegularExpression("^import org\\.kde\\.plasma\\.plasmoid\\s*$", QRegularExpression::MultilineOption));
        src.replace(QRegularExpression("^WallpaperItem \\{", QRegularExpression::MultilineOption),
                    "Item {\n    property QtObject configuration");
        m_wall = new QQmlComponent(&m_engine, this);
        // the original URL keeps relative paths (shaders/, ../photos) working
        m_wall->setData(src.toUtf8(), QUrl::fromLocalFile(mainQml));
        if (m_wall->isError()) {
            QMessageBox::critical(nullptr, "Live Weather", "The wallpaper failed to load:\n\n" + m_wall->errorString());
            QCoreApplication::exit(1);
            return;
        }

        if (m_windowed) {
            addScreen(QGuiApplication::primaryScreen());
        } else {
            for (QScreen *s : QGuiApplication::screens()) addScreen(s);
            connect(qApp, &QGuiApplication::screenAdded, this, &App::addScreen);
            connect(qApp, &QGuiApplication::screenRemoved, this, [this](QScreen *s) {
                if (QQuickWindow *w = m_windows.take(s)) w->deleteLater();
            });
        }
        makeTray();
        if (m_config->firstRun()) {
#ifndef Q_OS_WIN
            m_autostart->setEnabled(true);              // the Windows installer asks about this itself
#endif
            showSettings();
        }
    }

private:
    void addScreen(QScreen *screen)
    {
        auto *win = new QQuickWindow;
        win->setTitle("Live Weather");
        win->setColor(Qt::black);
        if (!m_windowed) {
            // (no WindowStaysOnBottomHint on macOS: the desktop level is set natively)
            win->setFlags(Qt::FramelessWindowHint | Qt::WindowDoesNotAcceptFocus
#ifndef Q_OS_MACOS
                          | Qt::WindowStaysOnBottomHint
#endif
                          | Qt::WindowTransparentForInput | Qt::WindowFlags(Desktop::windowFlags()));
            win->setScreen(screen);
            win->setGeometry(screen->geometry());
        } else {
            win->resize(1280, 720);
        }
        QObject *obj = m_wall->createWithInitialProperties(
            {{"configuration", QVariant::fromValue<QObject *>(m_config)}});
        auto *item = qobject_cast<QQuickItem *>(obj);
        if (!item) {
            qWarning() << m_wall->errorString();
            delete obj;
            delete win;
            return;
        }
        item->setParent(win);
        item->setParentItem(win->contentItem());
        item->setSize(win->size());
        connect(win, &QWindow::widthChanged, item, [item, win] { item->setSize(win->size()); });
        connect(win, &QWindow::heightChanged, item, [item, win] { item->setSize(win->size()); });
        if (m_windowed) {
            connect(win, &QWindow::visibleChanged, qApp, [](bool v) { if (!v) QCoreApplication::quit(); });
            win->show();
        } else {
            // plain show(), not showFullScreen(): on macOS that opens a full-screen Space
            win->show();
            Desktop::sendToBack(win, screen);
#ifdef Q_OS_MACOS
            // Qt can reset the window level when it shows or moves a window; keep it pinned
            auto *keep = new QTimer(win);
            connect(keep, &QTimer::timeout, win, [win, screen] { Desktop::sendToBack(win, screen); });
            keep->start(3000);
#endif
        }
        m_windows.insert(screen, win);
    }

    void makeTray()
    {
        m_tray = new QSystemTrayIcon(this);
#ifdef Q_OS_MACOS
        QIcon icon(":/icons/tray-mac.png");
        icon.setIsMask(true);                       // menu bar icons follow the light/dark theme
#else
        QIcon icon(":/icons/tray.png");
#endif
        m_tray->setIcon(icon);
        m_tray->setToolTip("Live Weather");
        auto *menu = new QMenu;
        menu->addAction("Settings…", this, &App::showSettings);
        menu->addSeparator();
        menu->addAction("Quit Live Weather", qApp, &QCoreApplication::quit);
        m_tray->setContextMenu(menu);
        connect(m_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason r) {
            if (r == QSystemTrayIcon::Trigger || r == QSystemTrayIcon::DoubleClick) showSettings();
        });
        m_tray->show();
    }

    void showSettings()
    {
        if (!m_settings) {
            QQmlComponent c(&m_engine, QUrl("qrc:/qml/Settings.qml"));
            QObject *o = c.createWithInitialProperties({{"config", QVariant::fromValue<QObject *>(m_config)},
                                                        {"autostart", QVariant::fromValue<QObject *>(m_autostart)}});
            m_settings = qobject_cast<QQuickWindow *>(o);
            if (!m_settings) { qWarning() << c.errorString(); delete o; return; }
            static_cast<QObject *>(m_settings)->setParent(this);
        }
        m_settings->show();
        m_settings->raise();
        m_settings->requestActivate();
    }

    QString m_pkg;
    bool m_windowed;
    QQmlEngine m_engine;
    Config *m_config = nullptr;
    Autostart *m_autostart = nullptr;
    QQmlComponent *m_wall = nullptr;
    QHash<QScreen *, QQuickWindow *> m_windows;
    QSystemTrayIcon *m_tray = nullptr;
    QQuickWindow *m_settings = nullptr;
};

}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setOrganizationName("matvaughn");
    app.setOrganizationDomain("matvaughn.com");
    app.setApplicationName("Live Weather");
    app.setQuitOnLastWindowClosed(false);
    app.setWindowIcon(QIcon(":/icons/tray.png"));
    QQuickStyle::setStyle("Fusion");                    // follows the system's light/dark colours everywhere

    const QString pkg = wallpaperDir();
    if (pkg.isEmpty()) {
        QMessageBox::critical(nullptr, "Live Weather", "Couldn't find the wallpaper files next to the app.");
        return 1;
    }
    App a(pkg, app.arguments().contains("--window"));
    return app.exec();
}
