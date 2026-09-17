// Theme watching follows Omacut (MIT, David Heinemeier Hansson).
#include "theme.h"
#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <cmath>

Theme::Theme(const QString &directory, QObject *parent) : QObject(parent),
    m_directory(directory.isEmpty() ? QDir::homePath() + "/.local/state/omarchy/current" : directory) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);
    reload();
}

QString Theme::readAccent(const QString &path) {
    QFile file(path);
    if (file.open(QIODevice::ReadOnly)) {
        const QRegularExpression expression(R"re(^\s*accent\s*=\s*["'](#[0-9a-fA-F]{6})["']\s*(?:#.*)?$)re",
                                            QRegularExpression::MultilineOption);
        const auto match = expression.match(QString::fromUtf8(file.readAll()));
        if (match.hasMatch()) return match.captured(1);
    }
    return "#FFD60A";
}

QString Theme::contrastingColor(const QString &color) {
    const QColor c(color);
    auto linear = [](double v) { return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4); };
    const double luminance = .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
    return luminance > .179 ? "black" : "white";
}
QString Theme::foreground() const { return contrastingColor(m_accent); }

void Theme::reload() {
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty()) m_watcher.removePaths(paths);
    // Watch the parent too: the current or theme symlink can be replaced, and
    // installing Omarchy later should work without restarting this application.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/") ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, QFileInfo(ancestor).absolutePath(), m_directory,
                           m_directory + "/theme", m_directory + "/theme/colors.toml"};
    candidates.removeDuplicates();
    for (const auto &path : candidates)
        if (QFileInfo::exists(path)) m_watcher.addPath(path);
    const auto accent = readAccent(m_directory + "/theme/colors.toml");
    if (accent != m_accent) { m_accent = accent; emit changed(); }
}
