// Kumori — Precision Overcast SDDM theme (Qt6 / SDDM greeter API).
// Dark register: Slate surfaces, one Glacier accent, Geist Mono for fixed text.
// Sizes scale with screen height (s) so the form isn't tiny on HiDPI panels.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#131a26" // slate-900

    // HiDPI scale: 1.0 at 1080p, 2.0 at 2160p, etc. (SDDM sizes root to the screen)
    readonly property real s: Math.max(1.0, height / 1080.0)
    function px(v) { return Math.round(v * s) }

    // Precision Overcast palette
    readonly property color cSurface:   "#1f2937" // slate-800
    readonly property color cRaised:    "#2a3445"
    readonly property color cText:      "#e2e7ee"
    readonly property color cTextDim:   "#a8b3c4"
    readonly property color cAccent:    "#4a7d9b" // glacier-500 (fills)
    readonly property color cAccentLt:  "#8eb5cc" // glacier-300 (text/links)
    readonly property color cOutline:   "#3e4a60"
    readonly property color cError:     "#b47362" // aurora-rust

    readonly property string fontSans: "Schibsted Grotesk"
    readonly property string fontMono: "Geist Mono"

    function doLogin() {
        errorLabel.text = ""
        sddm.login(username.text, password.text, sessionModel.lastIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorLabel.text = "Authentication failed."
            password.text = ""
            password.forceActiveFocus()
        }
    }

    // Wallpaper (the Kumori overcast seascape) — rendered hidden, then blurred.
    Image {
        id: wallpaper
        anchors.fill: parent
        source: "file:///usr/share/backgrounds/kumori/kumori.jpg"
        fillMode: Image.PreserveAspectCrop
        // Decode at screen size. The source is 4752x3168 (~60MB uncompressed);
        // without this the greeter pushes all of it through the blur chain.
        sourceSize.width: root.width
        sourceSize.height: root.height
        cache: true
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 48
    }
    // Scrim: keep the dark register and ensure text/clock stay legible
    Rectangle {
        anchors.fill: parent
        color: "#131a26"
        opacity: 0.4
    }

    // Clock
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.px(120)
        spacing: root.px(4)
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cText
            font.family: root.fontSans
            font.pixelSize: root.px(72)
            font.weight: Font.DemiBold
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: dateLabel
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cTextDim
            font.family: root.fontMono
            font.pixelSize: root.px(15)
            text: Qt.formatDate(new Date(), "dddd, MMMM d").toUpperCase()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            clock.text = Qt.formatTime(new Date(), "HH:mm")
            dateLabel.text = Qt.formatDate(new Date(), "dddd, MMMM d").toUpperCase()
        }
    }

    // Login card
    Rectangle {
        anchors.centerIn: parent
        width: root.px(360)
        height: col.implicitHeight + root.px(48)
        radius: root.px(12)
        color: root.cSurface
        border.color: root.cOutline
        border.width: 1
        opacity: 0.97

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: root.px(24)
            spacing: root.px(14)

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "KUMORI"
                color: root.cAccentLt
                font.family: root.fontMono
                font.pixelSize: root.px(14)
                font.letterSpacing: 2
            }

            TextField {
                id: username
                Layout.fillWidth: true
                Layout.preferredHeight: root.px(40)
                placeholderText: "Username"
                placeholderTextColor: root.cTextDim
                text: userModel.lastUser
                color: root.cText
                font.family: root.fontSans
                font.pixelSize: root.px(15)
                leftPadding: root.px(12)
                rightPadding: root.px(12)
                selectByMouse: true
                background: Rectangle {
                    radius: root.px(4)
                    color: root.cRaised
                    border.color: username.activeFocus ? root.cAccent : root.cOutline
                    border.width: 1
                }
                onAccepted: password.forceActiveFocus()
            }

            TextField {
                id: password
                Layout.fillWidth: true
                Layout.preferredHeight: root.px(40)
                placeholderText: "Password"
                placeholderTextColor: root.cTextDim
                echoMode: TextInput.Password
                color: root.cText
                font.family: root.fontSans
                font.pixelSize: root.px(15)
                leftPadding: root.px(12)
                rightPadding: root.px(12)
                selectByMouse: true
                background: Rectangle {
                    radius: root.px(4)
                    color: root.cRaised
                    border.color: password.activeFocus ? root.cAccent : root.cOutline
                    border.width: 1
                }
                onAccepted: root.doLogin()
            }

            Button {
                id: loginButton
                Layout.fillWidth: true
                Layout.preferredHeight: root.px(40)
                text: "Sign in"
                font.family: root.fontSans
                font.pixelSize: root.px(15)
                onClicked: root.doLogin()
                background: Rectangle {
                    radius: root.px(4)
                    color: loginButton.down ? "#2d5773" : root.cAccent
                }
                contentItem: Text {
                    text: loginButton.text
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: loginButton.font
                }
            }

            Text {
                id: errorLabel
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: root.px(14)
                color: root.cError
                font.family: root.fontMono
                font.pixelSize: root.px(12)
                text: ""
            }
        }
    }

    // Outlined pill button: clearly interactive (border + hover fill + glow).
    component PowerButton: Button {
        id: pb
        hoverEnabled: true
        leftPadding: root.px(14)
        rightPadding: root.px(14)
        topPadding: root.px(7)
        bottomPadding: root.px(7)
        font.family: root.fontMono
        font.pixelSize: root.px(13)
        background: Rectangle {
            radius: root.px(4)
            color: pb.hovered ? root.cRaised : "transparent"
            border.color: pb.hovered ? root.cAccent : root.cOutline
            border.width: 1
        }
        contentItem: Text {
            text: pb.text
            color: pb.hovered ? root.cAccentLt : root.cTextDim
            font: pb.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        // Pointing-hand cursor without intercepting the Button's own clicks.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    // Power controls
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.px(24)
        spacing: root.px(12)
        PowerButton { text: "Restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        PowerButton { text: "Shut down"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    // Session indicator (niri is the only session — informational, not a button)
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: root.px(24)
        text: "session: niri"
        color: root.cTextDim
        font.family: root.fontMono
        font.pixelSize: root.px(13)
        opacity: 0.7
    }

    Component.onCompleted: {
        if (username.text.length > 0)
            password.forceActiveFocus()
        else
            username.forceActiveFocus()
    }
}
