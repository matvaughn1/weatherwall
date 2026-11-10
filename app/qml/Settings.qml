// Settings window for the Windows/macOS app. Mirrors the KDE settings page
// (package/contents/ui/config.qml) without the Linux-only photo tools.
// Changes apply straight away.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    required property QtObject config
    required property QtObject autostart
    title: qsTr("Live Weather Settings")
    width: 620; height: 720
    minimumWidth: 520

    // A labelled drop-down bound to one setting
    component Choice: ComboBox {
        required property string key
        property var keys: []
        Layout.fillWidth: true
        currentIndex: Math.max(0, keys.indexOf(win.config[key]))
        onActivated: win.config[key] = keys[currentIndex]
    }
    component Heading: Label {
        Layout.columnSpan: 2
        Layout.topMargin: 14
        font.bold: true
        font.pixelSize: 15
    }
    component Name: Label { Layout.alignment: Qt.AlignRight | Qt.AlignVCenter; opacity: 0.85 }

    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth

        GridLayout {
            width: scroll.availableWidth - 40
            x: 20; y: 12
            columns: 2
            columnSpacing: 12
            rowSpacing: 8

            Heading { text: qsTr("Location") }
            Name { text: qsTr("Find place:") }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: qsTr("City name")
                    onAccepted: win.lookup()
                }
                Button { text: qsTr("Search"); onClicked: win.lookup() }
            }
            Item { visible: results.visible; width: 1; height: 1 }
            ComboBox {
                id: results
                Layout.fillWidth: true
                visible: count > 0
                textRole: "label"
                model: ListModel { id: resultModel }
                onActivated: {
                    const r = resultModel.get(currentIndex);
                    win.config.Latitude = r.lat;
                    win.config.Longitude = r.lon;
                    win.config.PlaceName = r.name;
                }
            }
            Name { text: qsTr("Location:") }
            Label {
                text: win.config.PlaceName + "  (" + Number(win.config.Latitude).toFixed(3) + ", "
                      + Number(win.config.Longitude).toFixed(3) + ")"
            }
            Name { text: qsTr("Units:") }
            CheckBox {
                text: qsTr("Fahrenheit")
                checked: win.config.Fahrenheit
                onToggled: win.config.Fahrenheit = checked
            }
            Name { text: qsTr("Readout:") }
            CheckBox {
                text: qsTr("Show temperature and conditions")
                checked: win.config.ShowInfo
                onToggled: win.config.ShowInfo = checked
            }
            Name { text: qsTr("Refresh every (min):") }
            SpinBox {
                from: 5; to: 120
                value: win.config.RefreshMinutes
                onValueModified: win.config.RefreshMinutes = value
            }

            Heading { text: qsTr("Scene") }
            Name { text: qsTr("Scene:") }
            Choice {
                key: "SceneMode"; keys: ["photos", "drawn"]
                model: [qsTr("Real photos with live weather"), qsTr("Drawn village and patio")]
            }
            Name { text: qsTr("Change the view:") }
            Choice {
                key: "PhotoChange"; keys: ["twice", "daily", "weather"]
                model: [qsTr("At sunrise and sunset"), qsTr("Once a day (relit at night)"), qsTr("Whenever the weather changes")]
            }
            Name { text: qsTr("Places:") }
            Choice {
                key: "Places"; keys: ["mix", "towns", "nature"]
                model: [qsTr("A mix"), qsTr("Towns and back yards"), qsTr("Nature (mountains, lakes, forests)")]
            }
            Item { width: 1; height: 1 }
            CheckBox {
                text: qsTr("Swap a photo's sunny sky for the live clouds when it's overcast")
                checked: win.config.LiveSky
                onToggled: win.config.LiveSky = checked
            }
            Name { text: qsTr("Decorations:") }
            Choice {
                key: "Decorations"; keys: ["always", "auto", "off"]
                model: [qsTr("Always (the next holiday's between holidays)"), qsTr("Only around holidays"), qsTr("Off")]
            }

            Heading { text: qsTr("String lights") }
            Name { text: qsTr("Foreground:") }
            CheckBox {
                text: qsTr("Patio string lights")
                checked: win.config.ShowPatio
                onToggled: win.config.ShowPatio = checked
            }
            Name { text: qsTr("Show lights on:") }
            Choice {
                enabled: win.config.ShowPatio
                key: "PatioStyle"; keys: ["auto", "lights", "full"]
                model: [qsTr("Town and back yard views only"), qsTr("Every view (wild ones too)"),
                        qsTr("Every view, with the patio railing and eave")]
            }
            Name { text: qsTr("String lights:") }
            Choice {
                enabled: win.config.ShowPatio
                key: "LightsPower"; keys: ["auto", "on", "off"]
                model: [qsTr("Auto (on after dusk)"), qsTr("Always on"), qsTr("Off")]
            }
            Name { text: qsTr("Light colour:") }
            Choice {
                enabled: win.config.ShowPatio
                key: "LightsColour"
                keys: ["auto", "multi", "random", "warm", "white", "red", "orange", "yellow", "green", "blue", "purple", "pink"]
                model: [qsTr("Auto (warm white, holiday colours on holidays)"), qsTr("Multicolour"),
                        qsTr("Random (new colours with each new view)"), qsTr("Warm white"), qsTr("Cool white"),
                        qsTr("Red"), qsTr("Orange"), qsTr("Yellow"), qsTr("Green"), qsTr("Blue"), qsTr("Purple"), qsTr("Pink")]
            }

            Heading { text: qsTr("Preview") }
            Name { text: qsTr("Weather:") }
            Choice {
                key: "PreviewCondition"; keys: ["auto", "clear", "partly", "cloudy", "fog", "rain", "snow", "storm"]
                model: [qsTr("Live (auto)"), qsTr("Clear"), qsTr("Partly cloudy"), qsTr("Overcast"),
                        qsTr("Fog"), qsTr("Rain"), qsTr("Snow"), qsTr("Thunderstorm")]
            }
            Name { text: qsTr("Time:") }
            Choice {
                key: "PreviewTime"; keys: ["auto", "day", "dusk", "night"]
                model: [qsTr("Live (auto)"), qsTr("Day"), qsTr("Sunset"), qsTr("Night")]
            }
            Name { text: qsTr("Holiday:") }
            Choice {
                key: "PreviewHoliday"
                keys: ["auto", "none", "christmas", "newyear", "halloween", "oktoberfest", "thanksgiving", "july4",
                       "valentine", "stpatrick", "easter"]
                model: [qsTr("Live (auto)"), qsTr("None"), qsTr("Christmas"), qsTr("New Year's Eve"), qsTr("Halloween"),
                        qsTr("Oktoberfest"), qsTr("Thanksgiving"), qsTr("4th of July"), qsTr("Valentine's Day"),
                        qsTr("St. Patrick's Day"), qsTr("Easter")]
            }

            Heading { text: qsTr("App") }
            Name { text: qsTr("Startup:") }
            CheckBox {
                text: qsTr("Start Live Weather when I log in")
                checked: win.autostart.enabled
                onToggled: win.autostart.enabled = checked
            }
            Item { width: 1; height: 1 }
            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 16
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: qsTr("Live Weather keeps running in the tray (menu bar on Mac). Weather from Open-Meteo; photos are public domain, see CREDITS.md.")
            }
        }
    }

    function lookup() {
        if (!search.text.trim()) return;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
            resultModel.clear();
            const j = JSON.parse(xhr.responseText);
            for (const r of (j.results || [])) {
                resultModel.append({
                    label: [r.name, r.admin1, r.country_code].filter(x => x).join(", "),
                    name: r.name, lat: r.latitude, lon: r.longitude
                });
            }
            if (resultModel.count > 0) {
                results.currentIndex = 0;
                results.activated(0);
            }
        };
        xhr.open("GET", "https://geocoding-api.open-meteo.com/v1/search?count=8&name="
                 + encodeURIComponent(search.text.trim()));
        xhr.send();
    }
}
