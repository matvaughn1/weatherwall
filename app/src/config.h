#pragma once
// The wallpaper's settings: the same keys and defaults as the KDE plugin
// (package/contents/config/main.xml), saved with QSettings. QML reads them as
// `configuration.Key` and the settings window writes them back.
#include <QQmlPropertyMap>
#include <QHash>

class Config : public QQmlPropertyMap {
    Q_OBJECT
public:
    explicit Config(const QString &kcfgPath, QObject *parent = nullptr);
    bool firstRun() const { return m_firstRun; }

protected:
    QVariant updateValue(const QString &key, const QVariant &input) override;

private:
    QVariant convert(const QString &key, const QVariant &v) const;
    QHash<QString, QString> m_types;
    bool m_firstRun = false;
};
