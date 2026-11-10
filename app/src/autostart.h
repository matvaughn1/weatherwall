#pragma once
// "Start at login" for the app, per platform.
#include <QObject>

class Autostart : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
public:
    using QObject::QObject;
    bool enabled() const;
    void setEnabled(bool on);
signals:
    void enabledChanged();
};
