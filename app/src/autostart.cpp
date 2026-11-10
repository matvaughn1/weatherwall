#include "autostart.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <QStandardPaths>

#if defined(Q_OS_WIN)
static const char *RUN_KEY = "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";

bool Autostart::enabled() const
{
    return QSettings(RUN_KEY, QSettings::NativeFormat).contains("Live Weather");
}

void Autostart::setEnabled(bool on)
{
    QSettings run(RUN_KEY, QSettings::NativeFormat);
    if (on) run.setValue("Live Weather", "\"" + QDir::toNativeSeparators(QCoreApplication::applicationFilePath()) + "\"");
    else run.remove("Live Weather");
    emit enabledChanged();
}

#elif defined(Q_OS_MACOS)
static QString agentPath()
{
    return QDir::homePath() + "/Library/LaunchAgents/com.matvaughn.weatherwall.plist";
}

bool Autostart::enabled() const { return QFile::exists(agentPath()); }

void Autostart::setEnabled(bool on)
{
    if (on) {
        QDir().mkpath(QFileInfo(agentPath()).path());
        QFile f(agentPath());
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            const QString exe = QCoreApplication::applicationFilePath().toHtmlEscaped();
            f.write(QString(R"(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.matvaughn.weatherwall</string>
  <key>ProgramArguments</key><array><string>%1</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
)").arg(exe).toUtf8());
        }
    } else {
        QFile::remove(agentPath());
    }
    emit enabledChanged();
}

#else
static QString desktopPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/autostart/live-weather.desktop";
}

bool Autostart::enabled() const { return QFile::exists(desktopPath()); }

void Autostart::setEnabled(bool on)
{
    if (on) {
        QDir().mkpath(QFileInfo(desktopPath()).path());
        QFile f(desktopPath());
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            f.write(QString("[Desktop Entry]\nType=Application\nName=Live Weather\nExec=\"%1\"\n")
                        .arg(QCoreApplication::applicationFilePath()).toUtf8());
    } else {
        QFile::remove(desktopPath());
    }
    emit enabledChanged();
}
#endif
