import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtMultimedia

ApplicationWindow {
    id: win
    width: 960; height: 700
    minimumWidth: 640; minimumHeight: 460
    visible: true
    title: "monologue"
    color: "#0e0e10"
    Material.theme: Material.Dark
    Material.accent: theme.accent
    readonly property color accent: theme.accent
    readonly property color accentForeground: theme.foreground
    readonly property int cornerRadius: theme.radius
    readonly property bool finished: backend.state === "finished" || backend.state === "saving"
    readonly property bool busy: backend.state === "finalizing" || backend.state === "saving"
    readonly property bool overlayOpen: closeDialog.visible || recordingsDialog.visible || discardDialog.visible || restartDialog.visible || helpDialog.visible || backend.dialogOpen
    property bool quitting: false
    property string discardId: ""
    property var playbackOutput: null
    function time(seconds) {
        var s = Math.max(0, Math.floor(seconds))
        return (s >= 3600 ? Math.floor(s/3600) + ":" : "") + String(Math.floor(s/60)%60).padStart(2,"0") + ":" + String(s%60).padStart(2,"0")
    }
    function togglePlayback() {
        if (playbackOutput === null) playbackOutput = playbackAudio.createObject(win)
        if (player.playbackState === MediaPlayer.PlayingState) player.pause()
        else { if(player.position >= player.duration - 50) player.position = 0; player.play() }
    }
    function space() { if (finished) togglePlayback(); else backend.toggleRecording() }
    function closeSafely() {
        if (busy || backend.dialogOpen) return
        if (backend.takeActive) closeDialog.open()
        else { quitting = true; win.close() }
    }
    onClosing: close => {
        if (!quitting && (backend.takeActive || busy || backend.dialogOpen)) { close.accepted = false; closeSafely() }
    }
    Connections {
        target: backend
        function onSafeToClose() { win.quitting = true; win.close() }
        function onOverwriteRequested(path) { overwriteDialog.targetPath = path; overwriteDialog.open() }
        function onChanged() { if (!win.finished) player.stop() }
    }
    Component.onCompleted: backend.setPreview(liveVideo.videoSink)

    // Controls handle Space themselves. A window shortcut only takes it when
    // focus is on the preview/background; no double action from focused buttons.
    readonly property bool controlFocused: activeFocusItem && (activeFocusItem instanceof AbstractButton || activeFocusItem instanceof ComboBox || activeFocusItem instanceof Slider || activeFocusItem instanceof TextInput)
    Shortcut {
        sequence: "Space"; context: Qt.WindowShortcut; autoRepeat: false
        enabled: !win.overlayOpen && !cameraChoice.popup.visible && !microphoneChoice.popup.visible && !win.controlFocused && !win.busy
        onActivated: win.space()
    }
    Shortcut { sequence: "Ctrl+Return"; context: Qt.WindowShortcut; autoRepeat: false; enabled: backend.takeActive && !win.busy && !win.overlayOpen; onActivated: backend.finish() }
    Shortcut { sequence: "Ctrl+Enter"; context: Qt.WindowShortcut; autoRepeat: false; enabled: backend.takeActive && !win.busy && !win.overlayOpen; onActivated: backend.finish() }
    Shortcut { sequence: "Ctrl+S"; context: Qt.WindowShortcut; autoRepeat: false; enabled: win.finished && !win.busy && !win.overlayOpen; onActivated: { player.pause(); backend.save() } }
    Shortcut {
        sequence: "Escape"; context: Qt.WindowShortcut; autoRepeat: false
        enabled: (backend.takeActive || win.finished) && !win.busy && !win.overlayOpen && !cameraChoice.popup.visible && !microphoneChoice.popup.visible
        onActivated: { player.pause(); restartDialog.open() }
    }
    Shortcut { sequence: "Q"; context: Qt.WindowShortcut; autoRepeat: false; enabled: !win.overlayOpen; onActivated: win.closeSafely() }
    Shortcut { sequence: "?"; context: Qt.WindowShortcut; enabled: !win.overlayOpen; onActivated: helpDialog.open() }

    component ActionButton: Button {
        id: button
        property bool primary: false
        padding: 14; topPadding: 10; bottomPadding: 10
        font.pixelSize: 13; font.weight: Font.DemiBold
        focusPolicy: Qt.TabFocus
        implicitHeight: 42
        contentItem: Text { text: button.text; font: button.font; color: button.primary ? win.accentForeground : "#eeeef0"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: button.enabled ? 1 : .4 }
        background: Rectangle {
            radius: win.cornerRadius; color: button.primary ? win.accent : button.hovered ? "#3a3a3e" : "#2c2c2f"
            opacity: button.enabled ? 1 : .4
            border.width: button.activeFocus ? 2 : 0; border.color: button.primary ? win.accentForeground : win.accent
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }
    component ThemedDialog: Dialog {
        id: dialog
        focus: true
        Material.roundedScale: win.cornerRadius
        Material.elevation: 0
        background: Rectangle { color: "#202023"; radius: win.cornerRadius; border.color: "#39393e" }
        Overlay.modal: Rectangle { color: "#99000000" }
        header: Label {
            text: dialog.title; color: "#eeeef0"; font.pixelSize: 22
            padding: 24; bottomPadding: 0; elide: Text.ElideRight
        }
        footer: DialogButtonBox {
            Material.roundedScale: win.cornerRadius
            background: Item { }
            visible: count > 0
            delegate: ActionButton { }
        }
        onClosed: liveVideo.forceActiveFocus()
    }
    component SourceChoice: ComboBox {
        id: choice
        textRole: "label"
        focusPolicy: Qt.TabFocus
        implicitHeight: 42
        font.pixelSize: 13
        Material.accent: win.accent
        background: Rectangle { color: "#202023"; radius: win.cornerRadius; border.width: 1; border.color: choice.activeFocus ? win.accent : "#39393e"; opacity: choice.enabled ? 1 : .5 }
        popup.background: Rectangle { color: "#202023"; radius: win.cornerRadius; border.color: "#39393e" }
        ToolTip {
            visible: choice.hovered && choice.currentText !== ""
            text: choice.currentText
            background: Rectangle { color: "#303037"; radius: win.cornerRadius }
        }
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 12
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                Label { text: win.finished ? "Recording" : "Camera"; color: "#9999a1"; font.pixelSize: 11 }
                SourceChoice {
                    id: cameraChoice; visible: !win.finished
                    Layout.fillWidth: true
                    model: backend.cameras; currentIndex: backend.cameraIndex
                    enabled: !backend.takeActive && !win.busy
                    onActivated: index => { backend.selectCamera(index); liveVideo.forceActiveFocus() }
                    Accessible.name: "Camera"
                }
                Label { visible: win.finished; text: backend.clipName; Layout.fillWidth: true; elide: Text.ElideMiddle; font.pixelSize: 13 }
            }
            ColumnLayout {
                visible: !win.finished; Layout.fillWidth: true; spacing: 3
                Label { text: "Microphone"; color: "#9999a1"; font.pixelSize: 11 }
                SourceChoice {
                    id: microphoneChoice; Layout.fillWidth: true
                    model: backend.microphones; currentIndex: backend.microphoneIndex
                    enabled: !backend.takeActive && !win.busy
                    onActivated: index => { backend.selectMicrophone(index); liveVideo.forceActiveFocus() }
                    Accessible.name: "Microphone"
                }
            }
            ActionButton {
                visible: win.finished; text: "New recording"; enabled: !win.busy && !backend.dialogOpen
                onClicked: { player.stop(); backend.newRecording(); liveVideo.forceActiveFocus() }
            }
            ToolButton {
                text: "☰"; Accessible.name: "Recordings"; enabled: !backend.takeActive && !win.busy && !backend.dialogOpen
                onClicked: { player.pause(); backend.refreshRecordings(); recordingsDialog.open() }
                ToolTip.visible: hovered; ToolTip.text: "Recordings (" + backend.recordings.length + ")"
            }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 120
            color: "black"; radius: win.cornerRadius; clip: true
            VideoOutput { id: liveVideo; anchors.fill: parent; visible: !win.finished; fillMode: VideoOutput.PreserveAspectFit; focus: true }
            VideoOutput { id: clipVideo; anchors.fill: parent; visible: win.finished; fillMode: VideoOutput.PreserveAspectFit }
            MouseArea { anchors.fill: parent; onClicked: { liveVideo.forceActiveFocus(); if (win.finished) win.togglePlayback() } }
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 14
                height: 30; width: stateLabel.implicitWidth + 32; radius: win.cornerRadius; color: "#dd17171b"
                Row {
                    anchors.centerIn: parent; spacing: 7
                    Rectangle { width: 7; height: 7; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: backend.state === "recording" ? "#f06c6c" : backend.state === "paused" ? "#e2c77c" : "#a3bd9c" }
                    Label { id: stateLabel; text: win.finished ? "Preview" : backend.state === "recording" ? "Recording" : backend.state === "paused" ? "Paused" : backend.ready ? "Ready" : win.busy ? "Finishing" : backend.state === "unavailable" ? "Unavailable" : "Connecting"; font.pixelSize: 11; font.family: "monospace" }
                }
            }
            Rectangle {
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 14
                visible: backend.formatLabel !== ""
                height: 30; width: formatText.implicitWidth + 20; radius: win.cornerRadius; color: "#dd17171b"
                Label { id: formatText; anchors.centerIn: parent; text: backend.formatLabel; font.pixelSize: 11; font.family: "monospace" }
            }
            Column {
                anchors.centerIn: parent; width: Math.min(400, parent.width-40); spacing: 16
                visible: backend.state === "unavailable" || backend.state === "starting" || win.busy
                Label {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; font.pixelSize: 15
                    text: win.busy ? (backend.state === "saving" ? "Saving your clip…" : "Finishing your clip…") : backend.state === "starting" ? "Connecting your camera and microphone…" : backend.message
                }
                ActionButton { anchors.horizontalCenter: parent.horizontalCenter; visible: backend.state === "unavailable"; text: "Retry"; onClicked: backend.retry() }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            ActionButton {
                id: recordButton
                text: win.finished ? (player.playbackState === MediaPlayer.PlayingState ? "Ⅱ" : "▶") : backend.state === "recording" ? "Ⅱ  Pause" : backend.state === "paused" ? "●  Resume" : "●  Record"
                primary: !win.finished && backend.state !== "recording"
                enabled: !win.busy && !backend.dialogOpen && (win.finished || backend.ready || backend.takeActive)
                Accessible.name: win.finished ? "Play or pause clip" : text
                onClicked: { win.space(); liveVideo.forceActiveFocus() }
            }
            Label { text: win.time(win.finished ? player.position/1000 : backend.duration); font.family: "monospace"; font.pixelSize: win.width < 760 ? 14 : 18 }
            ActionButton { visible: backend.takeActive; enabled: !win.busy; text: "■  Finish"; onClicked: { backend.finish(); liveVideo.forceActiveFocus() } }
            Slider {
                id: seek; visible: win.finished; Layout.fillWidth: true; from: 0; to: player.duration
                value: player.position; enabled: !win.busy
                background: Rectangle {
                    x: seek.leftPadding; y: seek.topPadding + seek.availableHeight / 2 - height / 2
                    width: seek.availableWidth; height: 4; radius: Math.min(2, win.cornerRadius); color: "#39393e"
                    Rectangle { width: seek.visualPosition * parent.width; height: parent.height; radius: parent.radius; color: win.accent }
                }
                handle: Rectangle {
                    x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                    y: seek.topPadding + seek.availableHeight / 2 - height / 2
                    width: 14; height: 20; radius: Math.min(7, win.cornerRadius); color: win.accent
                    border.width: seek.activeFocus ? 2 : 0; border.color: win.accentForeground
                }
                onMoved: player.position = value
                Accessible.name: "Clip position"
            }
            Item { visible: !win.finished; Layout.fillWidth: true }
            ColumnLayout {
                visible: !win.finished; spacing: 3
                Layout.preferredWidth: win.width < 760 ? 176 : 224
                Layout.maximumWidth: win.width < 760 ? 176 : 224
                Row {
                    spacing: 3
                    Repeater {
                        model: 24
                        Rectangle {
                            required property int index
                            readonly property double threshold: -60 + index * 60 / 24
                            width: win.width < 760 ? 4 : 6; height: 17; radius: 1
                            color: backend.audioEnabled && (backend.level >= threshold || Math.abs(backend.peakLevel - threshold) < 2.5) ? (threshold >= -3 ? "#f06c6c" : threshold >= -12 ? "#e2c77c" : "#9fc89b") : "#303037"
                        }
                    }
                    Rectangle { width: 5; height: 17; radius: Math.min(1, win.cornerRadius); color: backend.clipping ? "#f06c6c" : "#303037" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "−60"; color: "#777780"; font.pixelSize: 9 }
                    Item { Layout.fillWidth: true }
                    Label { text: backend.meterText; color: backend.clipping ? "#f06c6c" : "#aaaab1"; font.pixelSize: 10; font.family: "monospace" }
                    Item { Layout.fillWidth: true }
                    Label { text: "0"; color: "#777780"; font.pixelSize: 9 }
                }
                Accessible.role: Accessible.Indicator
                Accessible.name: "Microphone level: " + backend.meterText
            }
            ActionButton { visible: win.finished; text: "Save…"; enabled: !win.busy && !backend.dialogOpen; onClicked: { player.pause(); backend.save() } }
            ActionButton { visible: win.finished; text: "Open in Omacut"; primary: true; enabled: !win.busy && !backend.dialogOpen; onClicked: { player.pause(); backend.openInOmacut() } }
        }
        Label {
            Layout.fillWidth: true; visible: backend.message !== "" && backend.state !== "unavailable" && !win.busy
            text: backend.message; color: win.accent; font.pixelSize: 12; wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true; elide: Text.ElideRight; color: "#96969f"; font.pixelSize: 11
                text: win.finished ? "Kept in Recordings until you discard it" : backend.state === "paused" ? "Space to resume · Preview and mic are live" : backend.state === "recording" ? "Space to pause · Ctrl+Enter to finish" : "Space to record · Sources remembered automatically"
            }
            ActionButton { text: "?"; padding: 0; implicitHeight: 24; implicitWidth: 24; onClicked: helpDialog.open(); Accessible.name: "Keyboard shortcuts" }
        }
    }
    MediaPlayer {
        id: player; source: win.finished ? backend.clip : ""
        videoOutput: clipVideo
        audioOutput: win.playbackOutput
    }
    Component { id: playbackAudio; AudioOutput {} }
    ThemedDialog {
        id: closeDialog; anchors.centerIn: parent; modal: true; title: "Finish this recording?"
        closePolicy: Popup.CloseOnEscape
        ColumnLayout {
            spacing: 16
            Label { text: "Finish and keep the clip before closing, or keep recording."; wrapMode: Text.WordWrap; Layout.maximumWidth: 420 }
            RowLayout {
                ActionButton { text: "Keep recording"; onClicked: closeDialog.close() }
                ActionButton { text: "Discard"; onClicked: { closeDialog.close(); backend.discardAndClose() } }
                ActionButton { text: "Finish and keep"; primary: true; onClicked: { closeDialog.close(); backend.finishAndClose() } }
            }
        }
    }
    ThemedDialog {
        id: recordingsDialog; anchors.centerIn: parent; modal: true
        title: "Recordings"; width: Math.min(win.width-40,700); height: Math.min(win.height-60,490)
        standardButtons: Dialog.Close
        ColumnLayout {
            anchors.fill: parent
            Label { text: "Originals stay here until you discard them."; color: "#aaaab1"; font.pixelSize: 12 }
            Label { visible: backend.recordings.length === 0; text: "Your finished and interrupted takes will appear here."; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
                model: backend.recordings
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width; height: 92; color: "#202023"; radius: 8
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 3
                        Label { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideMiddle; font.pixelSize: 12 }
                        RowLayout {
                            Label { text: modelData.status + " · " + modelData.size; color: "#aaaab1"; font.pixelSize: 11; Layout.fillWidth: true }
                            ActionButton { text: "Open"; onClicked: { recordingsDialog.close(); backend.openRecording(modelData.id) } }
                            ActionButton { text: "Files"; onClicked: backend.showFiles(modelData.id) }
                            ActionButton { text: "Discard"; onClicked: { win.discardId=modelData.id; discardDialog.open() } }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
    ThemedDialog {
        id: discardDialog; anchors.centerIn: parent; modal: true; title: "Discard this recording?"
        width: Math.min(win.width-40,460)
        standardButtons: Dialog.Cancel | Dialog.Discard
        Label { width: parent.width; text: "This deletes the original from Recordings. Any Omacut window using it will lose its source. Saved copies are kept."; wrapMode: Text.WordWrap }
        onDiscarded: { player.stop(); backend.discardRecording(win.discardId) }
    }
    ThemedDialog {
        id: restartDialog; objectName: "restartDialog"
        anchors.centerIn: parent; modal: true; title: "Discard this clip and start over?"
        width: Math.min(win.width-40,460)
        closePolicy: Popup.CloseOnEscape
        enter: Transition { }
        exit: Transition { }
        onOpened: restartConfirm.forceActiveFocus()
        footer: DialogButtonBox {
            Material.roundedScale: win.cornerRadius
            background: Item { }
            ActionButton {
                id: restartCancel; objectName: "restartCancel"; text: "Cancel"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                KeyNavigation.tab: restartConfirm; KeyNavigation.backtab: restartConfirm
                KeyNavigation.left: restartConfirm; KeyNavigation.right: restartConfirm
            }
            ActionButton {
                id: restartConfirm; objectName: "restartConfirm"; text: "Confirm"; primary: true
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                KeyNavigation.tab: restartCancel; KeyNavigation.backtab: restartCancel
                KeyNavigation.left: restartCancel; KeyNavigation.right: restartCancel
            }
        }
        Label { width: parent.width; text: "This deletes the current clip. Saved copies are kept."; wrapMode: Text.WordWrap }
        onAccepted: { player.stop(); backend.discardCurrent() }
    }
    ThemedDialog {
        id: overwriteDialog; anchors.centerIn: parent; modal: true; title: "Replace the existing MP4?"
        property string targetPath: ""
        width: Math.min(win.width-40,460)
        standardButtons: Dialog.Yes | Dialog.No
        Label { width: parent.width; text: overwriteDialog.targetPath + " already exists."; wrapMode: Text.WrapAnywhere }
        onAccepted: backend.confirmOverwrite(true)
        onRejected: backend.confirmOverwrite(false)
    }
    ThemedDialog {
        id: helpDialog; anchors.centerIn: parent; modal: true; title: "Keyboard shortcuts"; standardButtons: Dialog.Close
        Label { text: "Space     Record / pause / resume; play a finished clip\nCtrl+Enter     Finish this take\nCtrl+S     Save the finished clip\nEsc     Discard this clip and start over (asks first)\nQ     Quit\n?     Show shortcuts\n\nTab between controls; Space activates a focused control."; lineHeight: 1.5; font.pixelSize: 13 }
    }
}
