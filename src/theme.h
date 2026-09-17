#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QTimer>

class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString foreground READ foreground NOTIFY changed)
public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr);
    QString accent() const { return m_accent; }
    QString foreground() const;
    static QString readAccent(const QString &path);
    static QString contrastingColor(const QString &color);
signals:
    void changed();
private:
    void reload();
    QString m_directory;
    QString m_accent = "#FFD60A";
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
