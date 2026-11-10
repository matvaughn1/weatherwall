#include "config.h"
#include <QFile>
#include <QSettings>
#include <QXmlStreamReader>

Config::Config(const QString &kcfgPath, QObject *parent) : QQmlPropertyMap(this, parent)
{
    QSettings s;
    m_firstRun = !s.contains("PlaceName");

    // defaults and types from the plugin's config schema
    QFile f(kcfgPath);
    if (f.open(QIODevice::ReadOnly)) {
        QXmlStreamReader x(&f);
        QString name;
        while (!x.atEnd()) {
            x.readNext();
            if (!x.isStartElement()) continue;
            if (x.name() == u"entry") {
                name = x.attributes().value("name").toString();
                m_types.insert(name, x.attributes().value("type").toString());
                insert(name, convert(name, QString()));
            } else if (x.name() == u"default" && !name.isEmpty()) {
                insert(name, convert(name, x.readElementText()));
            }
        }
    }
    // saved values on top
    for (const QString &key : s.allKeys())
        if (m_types.contains(key)) insert(key, convert(key, s.value(key)));
    // Your own photo and fetched photos need the Linux analysis tools
    insert("UseOwnPhoto", false);
    insert("OnlinePhotos", false);
}

QVariant Config::convert(const QString &key, const QVariant &v) const
{
    const QString t = m_types.value(key);
    const QString s = v.toString();
    if (t == "Bool") return v.typeId() == QMetaType::Bool ? v.toBool() : (s == "true" || s == "1");
    if (t == "Double") return s.toDouble();
    if (t == "Int") return s.toInt();
    return s;
}

QVariant Config::updateValue(const QString &key, const QVariant &input)
{
    const QVariant v = convert(key, input);
    QSettings().setValue(key, v);
    return v;
}
