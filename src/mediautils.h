#pragma once
#include <QAudioFormat>
#include <QCameraDevice>
#include <QJsonObject>
#include <QString>

namespace media {
struct Format { QSize size; double minFps; double maxFps; int pixelFormat; };
int bestFormat(const QList<Format> &formats);
QCameraFormat bestCameraFormat(const QCameraDevice &device);
double targetFps(double minimum, double maximum);
double peak(const QByteArray &data, const QAudioFormat &format);
QString copyAtomically(const QString &source, const QString &destination);
QString normalizeMp4(const QString &path, double fps);
struct Probe { bool ok = false; QString error; QSize size; double duration = 0; bool audio = false; };
Probe probe(const QString &path);
}
