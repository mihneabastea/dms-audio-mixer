import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "audioMixer"

    StringSetting {
        settingKey: "appMaxVolume"
        label: "Application max volume (%)"
        description: "Maximum application volume. Enter any whole number from 1 to 300."
        placeholder: "150"
        defaultValue: "150"
    }

    StringSetting {
        settingKey: "volumeScrollStep"
        label: "Scroll step (%)"
        description: "Volume change per scroll step. Supported values: 1, 2 or 5."
        placeholder: "2"
        defaultValue: "2"
    }
}
