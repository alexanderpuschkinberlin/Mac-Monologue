#include <QtTest>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickItem>
#include <QQuickStyle>
#include <QTemporaryDir>
#include "theme.h"

class UiTests : public QObject {
    Q_OBJECT
private slots:
    void keyboardAndLayout() {
        QStringList warnings;
        QQmlApplicationEngine engine;
        connect(&engine,&QQmlEngine::warnings,&engine,[&](const QList<QQmlError> &errors){ for(auto &e:errors) warnings.append(e.toString()); });
        QQmlComponent fake(&engine);
        fake.setData(R"(
import QtQml
QtObject {
    property string state: "ready"
    property string message: ""
    property string formatLabel: "3840 × 2160 · 30 fps recording"
    property var cameras: [{label: "Test camera"}]
    property var microphones: [{label: "Test microphone"}]
    property int cameraIndex: 0
    property int microphoneIndex: 0
    property bool ready: state === "ready"
    property bool audioEnabled: true
    property bool takeActive: state === "recording" || state === "paused"
    property bool dialogOpen: false
    property real duration: 84
    property real level: -9
    property real peakLevel: -6
    property bool clipping: false
    property string meterText: "−9 dBFS"
    property url clip: ""
    property string clipName: "Monologue-2026-09-17.mp4"
    property var recordings: []
    property int toggles: 0
    signal changed()
    signal safeToClose()
    signal overwriteRequested(string path)
    function setPreview(sink) {}
    function toggleRecording() { toggles++; state = state === "ready" || state === "paused" ? "recording" : "paused"; changed() }
    function finish() { state = "finished"; changed() }
    function refreshRecordings() {}
    function selectCamera(i) {}
    function selectMicrophone(i) {}
    function newRecording() { state = "ready"; changed() }
    function save() {}
    function openInOmacut() {}
    function retry() {}
}
)",QUrl());
        QScopedPointer<QObject> backend(fake.create()); QVERIFY2(backend,qPrintable(fake.errorString()));
        QTemporaryDir themeDir; Theme theme(themeDir.path());
        engine.rootContext()->setContextProperty("backend",backend.data());
        engine.rootContext()->setContextProperty("theme",&theme);
        engine.load(QUrl("qrc:/Main.qml")); QVERIFY(!engine.rootObjects().isEmpty());
        auto *window=qobject_cast<QQuickWindow*>(engine.rootObjects().first()); QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window)); window->requestActivate(); QTest::qWait(100);
        QTest::keyClick(window,Qt::Key_Space); QCOMPARE(backend->property("state").toString(),QString("recording"));
        QTest::keyClick(window,Qt::Key_Space); QCOMPARE(backend->property("state").toString(),QString("paused"));
        QTest::keyClick(window,Qt::Key_Space); QCOMPARE(backend->property("state").toString(),QString("recording"));
        QKeyEvent repeat(QEvent::KeyPress,Qt::Key_Space,Qt::NoModifier," ",true); QCoreApplication::sendEvent(window,&repeat);
        QCOMPARE(backend->property("toggles").toInt(),3);
        backend->setProperty("dialogOpen",true); QTest::keyClick(window,Qt::Key_Space); QCOMPARE(backend->property("toggles").toInt(),3);
        backend->setProperty("dialogOpen",false);
        QTest::keyClick(window,Qt::Key_Return,Qt::ControlModifier); QCOMPARE(backend->property("state").toString(),QString("finished"));
        window->resize(640,460); QTest::qWait(100);
        auto frame=window->grabWindow(); QVERIFY(!frame.isNull());
        frame.save("/tmp/monologue-ui-minimum.png");
        window->resize(960,700); backend->setProperty("state","ready"); QTest::qWait(100);
        window->grabWindow().save("/tmp/monologue-ui-ready.png");
        delete window;
        QVERIFY2(warnings.isEmpty(),qPrintable(warnings.join('\n')));
    }
};
int main(int argc,char**argv) {
    qputenv("QT_MEDIA_BACKEND","ffmpeg");
    QGuiApplication app(argc,argv); QQuickStyle::setStyle("Material");
    UiTests tests; return QTest::qExec(&tests,argc,argv);
}
#include "ui_tests.moc"
