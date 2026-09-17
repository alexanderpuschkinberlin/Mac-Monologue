#include "writer.h"
#include <QMediaFormat>
#include <QUrl>
#include <QAbstractVideoBuffer>

namespace {
// QVideoFrame copies share timestamp metadata as well as pixels. Give recording
// frames independent metadata without copying their image planes or altering
// the live preview (or an already queued copy of a pause's final frame).
class FrameBuffer : public QAbstractVideoBuffer {
public:
    explicit FrameBuffer(const QVideoFrame &source) : m_source(source) {}
    ~FrameBuffer() override { unmap(); }
    QVideoFrameFormat format() const override { return m_source.surfaceFormat(); }
    MapData map(QVideoFrame::MapMode mode) override {
        MapData result;
        if(!m_source.map(mode)) return result;
        m_mapped=true;
        result.planeCount=m_source.planeCount();
        for(int i=0;i<result.planeCount;++i) {
            result.data[i]=m_source.bits(i);
            result.bytesPerLine[i]=m_source.bytesPerLine(i);
            result.dataSize[i]=m_source.mappedBytes(i);
        }
        return result;
    }
    void unmap() override { if(m_mapped) { m_source.unmap(); m_mapped=false; } }
private:
    QVideoFrame m_source;
    bool m_mapped=false;
};
}

void TakeClock::start(qint64 now) { m_start = now; m_completed = 0; m_paused = false; }
void TakeClock::pause(qint64 now) {
    if (!m_paused) { m_completed += std::max(qint64(0), now - m_start); m_paused = true; }
}
void TakeClock::resume(qint64 now) { if (m_paused) { m_start = now; m_paused = false; } }
qint64 TakeClock::duration(qint64 now) const { return m_completed + (m_paused ? 0 : std::max(qint64(0), now - m_start)); }
std::optional<qint64> TakeClock::position(qint64 time) const {
    if (m_paused || time < m_start) return {};
    return m_completed + time - m_start;
}

Writer::Writer(QObject *parent) : QObject(parent) {
    m_session.setRecorder(&m_recorder);
    m_flushTimeout.setSingleShot(true);
    m_flushTimeout.setInterval(10000);
    connect(&m_flushTimeout, &QTimer::timeout, this, [this] { fail("The encoder stopped responding. Partial files have been kept."); });
    connect(&m_recorder, &QMediaRecorder::errorOccurred, this, [this](auto, const QString &message) { fail(message); });
    connect(&m_recorder, &QMediaRecorder::recorderStateChanged, this, [this](auto state) {
        if (state == QMediaRecorder::StoppedState && m_stopping) {
            m_flushTimeout.stop();
            emit finished();
        }
    });
}
static QMediaFormat recordingFormat(bool audio) {
    QMediaFormat f(QMediaFormat::MPEG4);
    f.setVideoCodec(QMediaFormat::VideoCodec::H264);
    if (audio) f.setAudioCodec(QMediaFormat::AudioCodec::AAC);
    return f;
}
bool Writer::supported(bool audio) { return recordingFormat(audio).isSupported(QMediaFormat::Encode); }
bool Writer::start(const QString &path, const QVideoFrameFormat &format,
                   double fps, const QAudioFormat &audioFormat, qint64 now) {
    m_clock.start(now);
    m_frameDuration = qRound64(1000000.0 / fps);
    m_fps = fps;
    m_audioFormat = audioFormat;
    // Let the first frame initialize the encoder. Supplying a format hint can
    // leave Qt 6.11's canPushFrame cache false before its worker starts.
    m_video = new QVideoFrameInput(this);
    m_session.setVideoFrameInput(m_video);
    connect(m_video, &QVideoFrameInput::readyToSendVideoFrame, this, &Writer::drain);
    if (audioFormat.isValid()) {
        m_audio = new QAudioBufferInput(this);
        m_session.setAudioBufferInput(m_audio);
        connect(m_audio, &QAudioBufferInput::readyToSendAudioBuffer, this, &Writer::drain);
    }
    m_recorder.setMediaFormat(recordingFormat(audioFormat.isValid()));
    m_recorder.setVideoResolution(format.frameSize());
    m_recorder.setVideoFrameRate(fps);
    m_recorder.setQuality(QMediaRecorder::VeryHighQuality);
    m_recorder.setAudioBitRate(192000);
    m_recorder.setOutputLocation(QUrl::fromLocalFile(path));
    m_recorder.record();
    return !m_failed;
}
void Writer::pause(qint64 now) {
    if (!m_stopping) {
        // Hold the last camera frame through the interval's tail, just as the
        // live preview does between deliveries. Finish both streams together.
        if (m_tailFrame.isValid()) video(m_tailFrame, now - m_frameDuration);
        padAudioTo(m_clock.duration(now));
        m_clock.pause(now);
    }
}
void Writer::resume(qint64 now) { if (!m_stopping) m_clock.resume(now); }
void Writer::video(QVideoFrame frame, qint64 capturedAt) {
    if (m_stopping || m_failed || !frame.isValid()) return;
    const auto time = m_clock.position(capturedAt);
    if (!time) return;
    // Quantize to the output rate instead of rejecting short callback intervals:
    // real webcams deliver jittery batches, which must not halve the frame rate.
    const qint64 frameIndex = qRound64(*time * m_fps / 1000000.0);
    const qint64 timestamp = qRound64(frameIndex * 1000000.0 / m_fps);
    if (timestamp <= m_lastVideo) return;
    m_tailFrame = frame;
    frame = QVideoFrame(std::make_unique<FrameBuffer>(frame));
    frame.setStartTime(timestamp);
    frame.setEndTime(qRound64((frameIndex + 1) * 1000000.0 / m_fps));
    frame.setStreamFrameRate(m_fps);
    m_lastVideo = timestamp;
    // Bounded native-frame references; never build an unbounded 4K frame queue.
    if (m_frames.size() >= 6) { fail("Video encoding cannot keep up at this camera's maximum resolution. The take has been stopped and kept."); return; }
    m_frames.enqueue(frame);
    drain();
}
void Writer::audio(QByteArray data, qint64 capturedAt) {
    if (m_stopping || m_failed || !m_audio || m_clock.paused()) return;
    // A callback can straddle the start/resume boundary. Trim pre-take samples.
    if (capturedAt < m_clock.intervalStart()) {
        const auto skip = m_audioFormat.framesForDuration(m_clock.intervalStart() - capturedAt);
        data.remove(0, std::min(qsizetype(data.size()), qsizetype(skip * m_audioFormat.bytesPerFrame())));
        capturedAt += m_audioFormat.durationForFrames(skip);
        capturedAt = std::max(capturedAt, m_clock.intervalStart());
    }
    const auto time = m_clock.position(capturedAt);
    if (!time || data.isEmpty()) return;
    // Qt's FFmpeg audio encoder counts samples; it does not honor buffer PTS.
    // Materialize the timeline as PCM: silence for gaps, trim overlaps. This
    // preserves offsets and prevents missing callback tails accumulating over
    // repeated pauses. No paused samples ever enter this stream.
    const qint64 desiredFrame = m_audioFormat.framesForDuration(*time);
    if (desiredFrame < m_audioFramesWritten) {
        const auto overlap = (m_audioFramesWritten - desiredFrame) * m_audioFormat.bytesPerFrame();
        data.remove(0, std::min(qsizetype(data.size()), qsizetype(overlap)));
    } else padAudioTo(*time);
    if (!data.isEmpty()) appendAudio(data);
}
void Writer::padAudioTo(qint64 time) {
    if (!m_audio || m_failed) return;
    const qint64 missing = m_audioFormat.framesForDuration(time) - m_audioFramesWritten;
    if (missing <= 0) return;
    if (m_audioFormat.durationForFrames(missing) > 500000) {
        fail("Audio capture fell behind the recording. The interrupted take has been kept."); return;
    }
    appendAudio(QByteArray(missing * m_audioFormat.bytesPerFrame(),
                          m_audioFormat.sampleFormat() == QAudioFormat::UInt8 ? char(128) : char(0)));
}
void Writer::appendAudio(const QByteArray &data) {
    if (m_failed) return;
    QAudioBuffer buffer(data, m_audioFormat, m_audioFormat.durationForFrames(m_audioFramesWritten));
    m_audioFramesWritten += buffer.frameCount();
    m_queuedAudioUs += buffer.duration();
    if (m_queuedAudioUs > 500000) { fail("Audio encoding cannot keep up. The take has been stopped and kept."); return; }
    m_buffers.enqueue(buffer);
    drain();
}
void Writer::drain() {
    if (m_draining || m_failed) return;
    m_draining = true;
    while (!m_frames.isEmpty() && m_video->sendVideoFrame(m_frames.head())) m_frames.dequeue();
    while (!m_buffers.isEmpty() && m_audio->sendAudioBuffer(m_buffers.head())) {
        m_queuedAudioUs -= m_buffers.head().duration(); m_buffers.dequeue();
    }
    m_draining = false;
    if (m_stopping && m_frames.isEmpty() && m_buffers.isEmpty()) m_recorder.stop();
}
void Writer::finish() {
    if (m_stopping) return;
    m_stopping = true;
    m_flushTimeout.start();
    drain();
    if (m_recorder.recorderState() == QMediaRecorder::StoppedState) {
        m_flushTimeout.stop();
        QTimer::singleShot(0, this, &Writer::finished);
    }
}
void Writer::fail(const QString &message) {
    if (m_failed) return;
    m_failed = true;
    m_stopping = true;
    emit failed(message);
    m_frames.clear(); m_buffers.clear();
    m_recorder.stop();
    if (m_recorder.recorderState() == QMediaRecorder::StoppedState)
        QTimer::singleShot(0, this, &Writer::finished);
}
