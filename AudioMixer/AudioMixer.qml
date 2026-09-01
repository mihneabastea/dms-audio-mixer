import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.settings
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    property var popoutService: null
    property int currentTab: 0

    readonly property int defaultMaxVolumePercent: 150
    readonly property int minimumMaxVolumePercent: 1
    readonly property int maximumMaxVolumePercent: 300
    readonly property int volumeScrollStep: {
        const configured = Number(pluginData?.volumeScrollStep ?? 2)
        return [1, 2, 5].indexOf(configured) !== -1 ? configured : 2
    }

    readonly property int appMaxVolumePercent: {
        const configured = Number(pluginData?.appMaxVolume ?? defaultMaxVolumePercent)
        if (!isFinite(configured))
            return defaultMaxVolumePercent
        return Math.max(minimumMaxVolumePercent,
                        Math.min(maximumMaxVolumePercent, Math.round(configured)))
    }

    Settings {
        id: mixerSettings
        category: "AudioMixer"
        property string hiddenOutputKeysJson: "[]"
    }

    // Increment this whenever hidden state changes so QML bindings re-evaluate
    // even though the persisted value is JSON.
    property int hiddenRevision: 0

    readonly property var allOutputs: sortOutputs(Pipewire.nodes.values.filter(node =>
        node && node.audio && node.isSink && !node.isStream
    ))

    readonly property var appStreams: Pipewire.nodes.values.filter(node =>
        node && node.audio && node.isStream && node.isSink
    ).slice().sort((a, b) => appName(a).localeCompare(appName(b), undefined, {
        sensitivity: "base"
    }))

    readonly property var outputs: {
        hiddenRevision
        return allOutputs.filter(node => !isOutputHidden(node))
    }

    readonly property var hiddenOutputs: {
        hiddenRevision
        return allOutputs.filter(node => isOutputHidden(node))
    }

    popoutWidth: 520
    popoutHeight: Math.max(380, Math.min(650, 155 + (currentTab === 0
        ? outputs.length * 88 + (hiddenOutputs.length > 0 ? 48 : 0)
        : appStreams.length * 112)))

    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(node =>
            node && (node.isSink || node.isStream)
        ).concat(Pipewire.linkGroups.values)
    }

    function outputKey(node) {
        if (!node)
            return ""
        return node.name || outputName(node)
    }

    function hiddenKeys() {
        try {
            const parsed = JSON.parse(mixerSettings.hiddenOutputKeysJson)
            return Array.isArray(parsed) ? parsed : []
        } catch (e) {
            return []
        }
    }

    function isOutputHidden(node) {
        hiddenRevision
        return hiddenKeys().indexOf(outputKey(node)) !== -1
    }

    function hideOutput(node) {
        const key = outputKey(node)
        if (!key)
            return

        const keys = hiddenKeys()
        if (keys.indexOf(key) !== -1)
            return

        keys.push(key)
        mixerSettings.hiddenOutputKeysJson = JSON.stringify(keys)
        hiddenRevision++
    }

    function restoreOutput(node) {
        const key = outputKey(node)
        const keys = hiddenKeys().filter(k => k !== key)
        mixerSettings.hiddenOutputKeysJson = JSON.stringify(keys)
        hiddenRevision++
    }

    function isDefaultSink(node) {
        return AudioService.sink && node && AudioService.sink.name === node.name
    }

    function sortOutputs(nodes) {
        return nodes.slice().sort((a, b) => {
            const aDefault = isDefaultSink(a)
            const bDefault = isDefaultSink(b)
            if (aDefault !== bDefault)
                return aDefault ? -1 : 1
            return outputName(a).localeCompare(outputName(b), undefined, {
                sensitivity: "base"
            })
        })
    }

    function outputName(node) {
        if (!node)
            return "Unknown output"

        const alias = AudioService.getDeviceAlias(node.name)
        if (alias)
            return alias

        const props = node.properties || {}
        return props["node.description"]
            || node.description
            || props["device.description"]
            || node.nickname
            || node.name
            || "Unknown output"
    }

    function appName(node) {
        if (!node)
            return "Unknown application"

        const props = node.properties || {}
        return props["application.name"]
            || props["application.process.binary"]
            || props["media.name"]
            || props["node.description"]
            || node.description
            || node.nickname
            || node.name
            || "Unknown application"
    }

    function appIconSource(node) {
        if (!node)
            return ""

        const props = node.properties || {}

        // PipeWire's explicitly recommended application icon.
        const explicitIcon = props["application.icon-name"] || ""
        if (explicitIcon)
            return Paths.resolveIconPath(String(explicitIcon))

        // Generic metadata candidates. Nothing here is app-specific.
        const candidates = [
            props["application.id"],
            props["application.process.binary"],
            props["application.name"],
            props["node.name"],
            node.name,
            appName(node)
        ]

        const seen = {}

        for (let i = 0; i < candidates.length; i++) {
            const raw = candidates[i]
            if (!raw)
                continue

            const candidate = String(raw).trim()
            if (!candidate || seen[candidate])
                continue

            seen[candidate] = true

            const desktopEntry = DesktopEntries.heuristicLookup(candidate)
            if (desktopEntry && desktopEntry.icon) {
                const resolved = Paths.getAppIcon(candidate, desktopEntry)
                if (resolved)
                    return resolved
            }
        }

        return ""
    }

    function appFallbackLetter(node) {
        const name = appName(node).trim()
        return name.length > 0 ? name.charAt(0).toUpperCase() : "?"
    }

    function appSubtitle(node) {
        if (!node)
            return ""

        const props = node.properties || {}
        const app = props["application.name"] || props["application.process.binary"] || ""
        const media = props["media.name"] || props["node.description"] || ""
        return media && media !== app ? media : ""
    }

    function currentStreamTarget(stream) {
        if (!stream)
            return null

        const groups = Pipewire.linkGroups.values
        for (let i = 0; i < groups.length; ++i) {
            const group = groups[i]
            if (group && group.source === stream && group.target && !group.target.isStream)
                return group.target
        }

        return null
    }

    function outputIndexForStream(stream) {
        const target = currentStreamTarget(stream)
        if (!target)
            return -1

        for (let i = 0; i < outputs.length; ++i) {
            if (outputs[i] === target || outputs[i].name === target.name)
                return i
        }

        return -1
    }

    function deviceMaxVolumePercent(node) {
        const configured = Number(AudioService.getMaxVolumePercent(node))
        return isFinite(configured) ? Math.max(100, configured) : 100
    }

    function volumePercent(node) {
        return node && node.audio ? node.audio.volume * 100 : 0
    }

    function wheelStep(wheel) {
        const delta = wheel.angleDelta.y !== 0
            ? wheel.angleDelta.y
            : wheel.pixelDelta.y
        return delta === 0 ? 0 : (delta > 0 ? volumeScrollStep : -volumeScrollStep)
    }

    function routeStream(stream, sink) {
        if (!stream || !sink)
            return

        // WirePlumber's moving-stream policy watches target.object metadata.
        // Use node.name because it remains usable even if PipeWire numeric IDs change.
        Proc.runCommand(
            "audioMixer.route." + stream.id,
            [
                "pw-metadata",
                "-n", "default",
                String(stream.id),
                "target.object",
                sink.name,
                "Spa:String"
            ],
            (stdout, exitCode) => {
                if (exitCode !== 0)
                    console.warn("AudioMixer: failed to route stream", stream.id, "to", sink.name)
            }
        )
    }

    function setNodeVolume(node, percent, maxPercent) {
        if (!node || !node.audio)
            return

        const maxVol = isFinite(maxPercent) ? maxPercent : 100
        const clamped = Math.max(0, Math.min(maxVol, Math.round(percent)))
        node.audio.volume = clamped / 100
    }

    function toggleMute(node) {
        if (!node || !node.audio)
            return
        node.audio.muted = !node.audio.muted
    }

    function setDefault(node) {
        if (!node)
            return
        AudioService.setSink(node)
    }

    horizontalBarPill: Component {
        StyledRect {
            implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
            width: implicitWidth
            implicitHeight: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: "graphic_eq"
                    size: Theme.iconSizeSmall
                    color: Theme.primary
                }

                StyledText {
                    text: "Mixer"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                }
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            implicitWidth: parent.widgetThickness
            width: parent.widgetThickness
            implicitHeight: verticalContent.implicitHeight + Theme.spacingM * 2
            height: implicitHeight
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: verticalContent
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "graphic_eq"
                    size: Theme.iconSizeSmall
                    color: Theme.primary
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Mix"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: mixerPopout
            headerText: "Audio Mixer"
            detailsText: ""
            showCloseButton: true

            property bool hiddenExpanded: false

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Compact pill-style tabs inspired by DMS Audio.
                StyledRect {
                    width: parent.width
                    height: 42
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 3

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Math.max(0, Theme.cornerRadius - 2)
                            color: root.currentTab === 0
                                ? Theme.primary
                                : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: "Devices"
                                color: root.currentTab === 0
                                    ? Theme.onPrimary
                                    : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentTab = 0
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Math.max(0, Theme.cornerRadius - 2)
                            color: root.currentTab === 1
                                ? Theme.primary
                                : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: "Applications"
                                color: root.currentTab === 1
                                    ? Theme.onPrimary
                                    : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentTab = 1
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: root.popoutHeight - 125

                    // ---------------- DEVICES ----------------
                    Flickable {
                        anchors.fill: parent
                        visible: root.currentTab === 0
                        contentWidth: width
                        contentHeight: deviceColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        Column {
                            id: deviceColumn
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                visible: root.outputs.length === 0
                                text: "No output devices."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Repeater {
                                model: root.outputs

                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    height: 88
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainer

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.topMargin: Theme.spacingS
                                        anchors.bottomMargin: Theme.spacingS
                                        spacing: Theme.spacingXS

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingS

                                            DankIcon {
                                                name: root.isDefaultSink(modelData)
                                                    ? "volume_up"
                                                    : "speaker"
                                                size: Theme.iconSizeSmall
                                                color: Theme.primary
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: root.outputName(modelData)
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                                elide: Text.ElideRight
                                            }

                                            DankIcon {
                                                name: modelData.audio && modelData.audio.muted
                                                    ? "volume_off"
                                                    : "volume_up"
                                                size: Theme.iconSizeSmall
                                                color: modelData.audio && modelData.audio.muted
                                                    ? Theme.error
                                                    : Theme.surfaceVariantText

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -8
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleMute(modelData)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.text: modelData.audio && modelData.audio.muted
                                                        ? "Unmute device"
                                                        : "Mute device"
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingS

                                            Slider {
                                                id: deviceSlider
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 24
                                                from: 0
                                                to: root.deviceMaxVolumePercent(modelData)
                                                value: root.volumePercent(modelData)
                                                stepSize: 1
                                                enabled: !!modelData.audio

                                                background: Rectangle {
                                                    x: deviceSlider.leftPadding
                                                    y: deviceSlider.topPadding + deviceSlider.availableHeight / 2 - height / 2
                                                    width: deviceSlider.availableWidth
                                                    height: 4
                                                    radius: 2
                                                    color: Theme.surfaceContainerHighest

                                                    Rectangle {
                                                        width: deviceSlider.visualPosition * parent.width
                                                        height: parent.height
                                                        radius: parent.radius
                                                        color: Theme.primary
                                                    }
                                                }

                                                handle: Rectangle {
                                                    x: deviceSlider.leftPadding + deviceSlider.visualPosition * (deviceSlider.availableWidth - width)
                                                    y: deviceSlider.topPadding + deviceSlider.availableHeight / 2 - height / 2
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.primary
                                                }

                                                onMoved: root.setNodeVolume(
                                                    modelData,
                                                    value,
                                                    root.deviceMaxVolumePercent(modelData)
                                                )

                                                MouseArea {
                                                    anchors.fill: parent
                                                    acceptedButtons: Qt.NoButton
                                                    hoverEnabled: true

                                                    onWheel: function(wheel) {
                                                        const step = root.wheelStep(wheel)
                                                        if (step === 0)
                                                            return
                                                        const next = Math.max(
                                                            deviceSlider.from,
                                                            Math.min(deviceSlider.to, deviceSlider.value + step)
                                                        )

                                                        deviceSlider.value = next
                                                        root.setNodeVolume(
                                                            modelData,
                                                            next,
                                                            root.deviceMaxVolumePercent(modelData)
                                                        )
                                                        wheel.accepted = true
                                                    }
                                                }
                                            }

                                            StyledText {
                                                Layout.preferredWidth: 42
                                                horizontalAlignment: Text.AlignRight
                                                text: modelData.audio
                                                    ? Math.round(modelData.audio.volume * 100) + "%"
                                                    : "—"
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                            }

                                            DankIcon {
                                                name: root.isDefaultSink(modelData)
                                                    ? "check_circle"
                                                    : "radio_button_unchecked"
                                                size: Theme.iconSizeSmall
                                                color: root.isDefaultSink(modelData)
                                                    ? Theme.primary
                                                    : Theme.surfaceVariantText

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -8
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (!root.isDefaultSink(modelData))
                                                            root.setDefault(modelData)
                                                    }
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.text: root.isDefaultSink(modelData)
                                                        ? "Default output"
                                                        : "Set as default output"
                                                }
                                            }

                                            DankIcon {
                                                name: "visibility_off"
                                                size: Theme.iconSizeSmall
                                                color: Theme.surfaceVariantText

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -8
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.hideOutput(modelData)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.text: "Hide device"
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 1
                                        color: Theme.outlineVariant
                                        opacity: 0.55
                                        visible: false
                                    }
                                }
                            }

                            // Hidden device submenu at bottom of Devices.
                            Item {
                                width: parent.width
                                height: root.hiddenOutputs.length > 0 ? 48 : 0
                                visible: root.hiddenOutputs.length > 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingS
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: "visibility_off"
                                        size: Theme.iconSizeSmall
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Hidden devices (" + root.hiddenOutputs.length + ")"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    DankIcon {
                                        name: mixerPopout.hiddenExpanded
                                            ? "expand_more"
                                            : "chevron_right"
                                        size: Theme.iconSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mixerPopout.hiddenExpanded = !mixerPopout.hiddenExpanded
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 0
                                visible: mixerPopout.hiddenExpanded && root.hiddenOutputs.length > 0

                                Repeater {
                                    model: root.hiddenOutputs

                                    delegate: Item {
                                        required property var modelData
                                        width: parent.width
                                        height: 56

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingS
                                            anchors.rightMargin: Theme.spacingS
                                            spacing: Theme.spacingS

                                            DankIcon {
                                                name: "speaker"
                                                size: Theme.iconSizeSmall
                                                color: Theme.surfaceVariantText
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: root.outputName(modelData)
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall
                                                elide: Text.ElideRight
                                            }

                                            DankIcon {
                                                name: "visibility"
                                                size: Theme.iconSizeSmall
                                                color: Theme.primary

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -8
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.restoreOutput(modelData)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.text: "Restore device"
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: Theme.outlineVariant
                                            opacity: 0.4
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------------- APPLICATIONS ----------------
                    Flickable {
                        anchors.fill: parent
                        visible: root.currentTab === 1
                        contentWidth: width
                        contentHeight: appColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        Column {
                            id: appColumn
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                visible: root.appStreams.length === 0
                                text: "No application is currently playing audio."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Repeater {
                                model: root.appStreams

                                delegate: Rectangle {
                                    id: appDelegate
                                    required property var modelData
                                    width: parent.width
                                    height: 112
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainer

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.topMargin: Theme.spacingS
                                        anchors.bottomMargin: Theme.spacingS
                                        spacing: Theme.spacingXS

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingS

                                            Item {
                                                Layout.preferredWidth: Theme.iconSizeSmall
                                                Layout.preferredHeight: Theme.iconSizeSmall

                                                IconImage {
                                                    id: appIconImage
                                                    anchors.fill: parent
                                                    source: root.appIconSource(modelData)
                                                    smooth: true
                                                    mipmap: true
                                                    asynchronous: true
                                                    visible: status === Image.Ready
                                                }

                                                StyledText {
                                                    anchors.centerIn: parent
                                                    visible: !appIconImage.visible
                                                    text: root.appFallbackLetter(modelData)
                                                    color: Theme.primary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: root.appName(modelData)
                                                    color: Theme.surfaceText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.Medium
                                                    wrapMode: Text.NoWrap
                                                    maximumLineCount: 1
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    visible: text.length > 0
                                                    text: root.appSubtitle(modelData)
                                                    color: Theme.surfaceVariantText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    wrapMode: Text.NoWrap
                                                    maximumLineCount: 1
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Item {
                                                id: outputSelector
                                                Layout.preferredWidth: 155
                                                Layout.preferredHeight: 32

                                                readonly property int currentIndex: root.outputIndexForStream(modelData)
                                                readonly property string currentLabel: currentIndex >= 0
                                                    ? root.outputName(root.outputs[currentIndex])
                                                    : "Output"

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: Theme.cornerRadius
                                                    color: outputButton.containsMouse
                                                        ? Theme.surfaceContainerHighest
                                                        : Theme.surfaceContainerHigh
                                                    border.width: 1
                                                    border.color: outputPopup.opened
                                                        ? Theme.primary
                                                        : Theme.outlineVariant

                                                    StyledText {
                                                        anchors.left: parent.left
                                                        anchors.right: selectorIcon.left
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        anchors.leftMargin: Theme.spacingS
                                                        anchors.rightMargin: Theme.spacingXS
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: outputSelector.currentLabel
                                                        color: Theme.surfaceText
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        elide: Text.ElideRight
                                                    }

                                                    DankIcon {
                                                        id: selectorIcon
                                                        anchors.right: parent.right
                                                        anchors.rightMargin: Theme.spacingXS
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        name: "expand_more"
                                                        size: Theme.iconSizeSmall
                                                        color: Theme.surfaceVariantText
                                                        rotation: outputPopup.opened ? 180 : 0
                                                    }
                                                }

                                                MouseArea {
                                                    id: outputButton
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: root.outputs.length > 0
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: outputPopup.opened
                                                        ? outputPopup.close()
                                                        : outputPopup.open()
                                                    ToolTip.visible: containsMouse && !outputPopup.opened
                                                    ToolTip.text: outputSelector.currentIndex >= 0
                                                        ? outputSelector.currentLabel
                                                        : "Output"
                                                }

                                                Popup {
                                                    id: outputPopup
                                                    x: 0
                                                    y: outputSelector.height + Theme.spacingXS
                                                    width: outputSelector.width
                                                    height: Math.min(240, root.outputs.length * 40 + 8)
                                                    padding: 4
                                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                                    background: Rectangle {
                                                        color: Theme.surfaceContainerHigh
                                                        radius: Theme.cornerRadius
                                                        border.width: 1
                                                        border.color: Theme.outlineVariant
                                                    }

                                                    contentItem: ListView {
                                                        clip: true
                                                        boundsBehavior: Flickable.StopAtBounds
                                                        model: root.outputs

                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            required property int index
                                                            width: ListView.view.width
                                                            height: 40
                                                            radius: Math.max(0, Theme.cornerRadius - 2)
                                                            color: optionMouse.containsMouse
                                                                ? Theme.surfaceContainerHighest
                                                                : (index === outputSelector.currentIndex
                                                                    ? Theme.surfaceContainerHighest
                                                                    : "transparent")

                                                            StyledText {
                                                                anchors.left: parent.left
                                                                anchors.right: optionCheck.left
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                anchors.leftMargin: Theme.spacingS
                                                                anchors.rightMargin: Theme.spacingXS
                                                                text: root.outputName(modelData)
                                                                color: index === outputSelector.currentIndex
                                                                    ? Theme.primary
                                                                    : Theme.surfaceText
                                                                font.pixelSize: Theme.fontSizeSmall
                                                                elide: Text.ElideRight
                                                            }

                                                            DankIcon {
                                                                id: optionCheck
                                                                anchors.right: parent.right
                                                                anchors.rightMargin: Theme.spacingS
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                visible: index === outputSelector.currentIndex
                                                                name: "check"
                                                                size: Theme.iconSizeSmall
                                                                color: Theme.primary
                                                            }

                                                            MouseArea {
                                                                id: optionMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    root.routeStream(appDelegate.modelData, root.outputs[index])
                                                                    outputPopup.close()
                                                                }
                                                                ToolTip.visible: containsMouse
                                                                ToolTip.text: root.outputName(modelData)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingS

                                            Slider {
                                                id: appSlider
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 24
                                                from: 0
                                                to: root.appMaxVolumePercent
                                                value: root.volumePercent(modelData)
                                                stepSize: 1
                                                enabled: !!modelData.audio

                                                background: Rectangle {
                                                    x: appSlider.leftPadding
                                                    y: appSlider.topPadding + appSlider.availableHeight / 2 - height / 2
                                                    width: appSlider.availableWidth
                                                    height: 4
                                                    radius: 2
                                                    color: Theme.surfaceContainerHighest

                                                    Rectangle {
                                                        width: appSlider.visualPosition * parent.width
                                                        height: parent.height
                                                        radius: parent.radius
                                                        color: Theme.primary
                                                    }
                                                }

                                                handle: Rectangle {
                                                    x: appSlider.leftPadding + appSlider.visualPosition * (appSlider.availableWidth - width)
                                                    y: appSlider.topPadding + appSlider.availableHeight / 2 - height / 2
                                                    width: 14
                                                    height: 14
                                                    radius: 7
                                                    color: Theme.primary
                                                }

                                                onMoved: root.setNodeVolume(modelData, value, root.appMaxVolumePercent)

                                                MouseArea {
                                                    anchors.fill: parent
                                                    acceptedButtons: Qt.NoButton
                                                    hoverEnabled: true

                                                    onWheel: function(wheel) {
                                                        const step = root.wheelStep(wheel)
                                                        if (step === 0)
                                                            return
                                                        const next = Math.max(
                                                            appSlider.from,
                                                            Math.min(appSlider.to, appSlider.value + step)
                                                        )

                                                        appSlider.value = next
                                                        root.setNodeVolume(modelData, next, root.appMaxVolumePercent)
                                                        wheel.accepted = true
                                                    }
                                                }
                                            }

                                            StyledText {
                                                Layout.preferredWidth: 42
                                                horizontalAlignment: Text.AlignRight
                                                text: modelData.audio
                                                    ? Math.round(modelData.audio.volume * 100) + "%"
                                                    : "—"
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                            }

                                            DankIcon {
                                                name: modelData.audio && modelData.audio.muted
                                                    ? "volume_off"
                                                    : "volume_up"
                                                size: Theme.iconSizeSmall
                                                color: modelData.audio && modelData.audio.muted
                                                    ? Theme.error
                                                    : Theme.surfaceVariantText

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -8
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleMute(modelData)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.text: modelData.audio && modelData.audio.muted
                                                        ? "Unmute application"
                                                        : "Mute application"
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 1
                                        color: Theme.outlineVariant
                                        opacity: 0.55
                                        visible: false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
