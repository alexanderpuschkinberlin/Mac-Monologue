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
    property int discards: 0
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
    function discardCurrent() { discards++; state = "ready"; changed() }
    function save() {}
    function openInOmacut() {}
    function retry() {}
}
)",QUrl());
        QScopedPointer<QObject> backend(fake.create()); QVERIFY2(backend,qPrintable(fake.errorString()));
        QTemporaryDir themeDir;
        const auto response=themeDir.filePath("rounding.json"), command=themeDir.filePath("hyprctl");
        auto write=[](const QString &path,const QByteArray &data) { QFile f(path); return f.open(QIODevice::WriteOnly) && f.write(data)==data.size(); };
        QVERIFY(write(command,"#!/bin/sh\ncat '" + response.toUtf8() + "'\n"));
        QVERIFY(QFile::setPermissions(command,QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner));
        QVERIFY(write(response,"{\"int\":0}"));
        Theme theme(themeDir.path(),nullptr,command);
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
        auto *restart=window->findChild<QObject*>("restartDialog"); QVERIFY(restart);
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(restart->property("opened").toBool());
        QCOMPARE(backend->property("discards").toInt(),0);
        auto *confirm=window->findChild<QQuickItem*>("restartConfirm"); QVERIFY(confirm);
        auto *cancel=window->findChild<QQuickItem*>("restartCancel"); QVERIFY(cancel);
        QVERIFY(confirm->hasActiveFocus());
        QTest::keyClick(window,Qt::Key_Tab); QVERIFY(cancel->hasActiveFocus());
        QTest::keyClick(window,Qt::Key_Backtab); QVERIFY(confirm->hasActiveFocus());
        QTest::keyClick(window,Qt::Key_Left); QVERIFY(cancel->hasActiveFocus());
        QTest::keyClick(window,Qt::Key_Right); QVERIFY(confirm->hasActiveFocus());
        QTest::keyClick(window,Qt::Key_Left);
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_VERIFY(!restart->property("visible").toBool());
        QCOMPARE(backend->property("discards").toInt(),0);
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(restart->property("opened").toBool());
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(!restart->property("visible").toBool());
        QCOMPARE(backend->property("state").toString(),QString("recording"));
        for(const auto &state:{"recording","paused","finished"}) {
            backend->setProperty("state",state);
            QTest::keyClick(window,Qt::Key_Escape);
            QTRY_VERIFY(restart->property("opened").toBool());
            QVERIFY(confirm->hasActiveFocus());
            QTest::keyClick(window,Qt::Key_Return);
            QTRY_VERIFY(!restart->property("visible").toBool());
            QCOMPARE(backend->property("state").toString(),QString("ready"));
        }
        QCOMPARE(backend->property("discards").toInt(),3);
        QTest::keyClick(window,Qt::Key_Escape); QVERIFY(!restart->property("visible").toBool());
        QTest::keyClick(window,Qt::Key_Space);
        QCOMPARE(backend->property("state").toString(),QString("recording"));
        QTest::keyClick(window,Qt::Key_Return,Qt::ControlModifier); QCOMPARE(backend->property("state").toString(),QString("finished"));
        window->resize(640,460); QTest::qWait(100);
        auto frame=window->grabWindow(); QVERIFY(!frame.isNull());
        frame.save("/tmp/monologue-ui-minimum.png");
        window->resize(960,700); backend->setProperty("state","ready"); QTest::qWait(100);
        window->grabWindow().save("/tmp/monologue-ui-ready.png");
        backend->setProperty("state","paused");
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(restart->property("opened").toBool());
        auto *dialogBackground=restart->property("background").value<QObject*>(); QVERIFY(dialogBackground);
        auto *buttonBackground=confirm->property("background").value<QObject*>(); QVERIFY(buttonBackground);
        QCOMPARE(dialogBackground->property("radius").toInt(),0);
        QCOMPARE(buttonBackground->property("radius").toInt(),0);
        QTest::qWait(50); window->grabWindow().save("/tmp/monologue-discard-square.png");
        QVERIFY(write(response,"{\"int\":6}"));
        QTRY_COMPARE(dialogBackground->property("radius").toInt(),6);
        QCOMPARE(buttonBackground->property("radius").toInt(),6);
        QTest::qWait(50); window->grabWindow().save("/tmp/monologue-discard-rounded.png");
        QVERIFY(write(response,"{\"int\":0}"));
        QTRY_COMPARE(dialogBackground->property("radius").toInt(),0);
        QCOMPARE(buttonBackground->property("radius").toInt(),0);
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
