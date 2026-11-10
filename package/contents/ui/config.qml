import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

Kirigami.FormLayout {
    id: page

    property real cfg_Latitude
    property real cfg_Longitude
    property string cfg_PlaceName
    property alias cfg_Fahrenheit: fahrenheit.checked
    property alias cfg_ShowInfo: showInfo.checked
    property alias cfg_RefreshMinutes: refresh.value
    property string cfg_PreviewCondition
    property string cfg_PreviewTime
    property string cfg_PreviewHoliday
    property alias cfg_ShowPatio: showPatio.checked
    property string cfg_SceneMode
    property alias cfg_OnlinePhotos: onlinePhotos.checked
    property alias cfg_LiveSky: liveSky.checked
    property string cfg_PatioStyle
    property string cfg_LightsPower
    property string cfg_LightsColour
    property string cfg_Decorations
    property string cfg_PhotoChange
    property string cfg_Places
    property alias cfg_UseOwnPhoto: useOwn.checked
    property string cfg_OwnPhoto

    RowLayout {
        Kirigami.FormData.label: i18n("Find place:")
        QQC2.TextField {
            id: search
            placeholderText: i18n("City name")
            onAccepted: page.lookup()
        }
        QQC2.Button { text: i18n("Search"); onClicked: page.lookup() }
    }
    QQC2.ComboBox {
        id: results
        visible: count > 0
        textRole: "label"
        model: ListModel { id: resultModel }
        onActivated: {
            const r = resultModel.get(currentIndex);
            page.cfg_Latitude = r.lat;
            page.cfg_Longitude = r.lon;
            page.cfg_PlaceName = r.name;
        }
    }
    QQC2.Label {
        Kirigami.FormData.label: i18n("Location:")
        text: page.cfg_PlaceName + "  (" + page.cfg_Latitude.toFixed(3) + ", " + page.cfg_Longitude.toFixed(3) + ")"
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

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox { id: fahrenheit; Kirigami.FormData.label: i18n("Units:"); text: i18n("Fahrenheit") }
    QQC2.CheckBox { id: showInfo; Kirigami.FormData.label: i18n("Readout:"); text: i18n("Show temperature and conditions") }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Scene:")
        readonly property var keys: ["photos", "drawn"]
        model: [i18n("Real photos with live weather"), i18n("Drawn village and patio")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_SceneMode))
        onActivated: page.cfg_SceneMode = keys[currentIndex]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Change the view:")
        readonly property var keys: ["twice", "daily", "weather"]
        model: [i18n("At sunrise and sunset (weather changes the same view)"),
                i18n("Once a day (same view all day, relit at night)"),
                i18n("Whenever the weather changes")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_PhotoChange))
        onActivated: page.cfg_PhotoChange = keys[currentIndex]
    }
    QQC2.CheckBox {
        id: useOwn
        Kirigami.FormData.label: i18n("Your own photo:")
        text: i18n("Always show my photo (it still reacts to the weather)")
    }
    RowLayout {
        enabled: useOwn.checked
        QQC2.Button {
            text: i18n("Choose photo…")
            icon.name: "document-open"
            enabled: !runner.busy
            onClicked: picker.open()
        }
        QQC2.BusyIndicator { visible: runner.busy; running: visible; implicitHeight: Kirigami.Units.gridUnit * 1.5 }
        QQC2.Label {
            text: runner.busy ? i18n("Analysing the photo (about 20 seconds)…")
                : runner.error ? runner.error
                : page.cfg_OwnPhoto ? page.cfg_OwnPhoto.split("/").pop().split("__").pop() : i18n("None chosen")
            elide: Text.ElideMiddle
            Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        }
    }
    FileDialog {
        id: picker
        title: i18n("Choose a photo")
        nameFilters: [i18n("Images (*.jpg *.jpeg *.png *.webp)")]
        onAccepted: runner.analyse(decodeURIComponent(selectedFile.toString().replace("file://", "")))
    }
    // Runs the analysis (depth + scene labels) via the helper command
    P5Support.DataSource {
        id: runner
        engine: "executable"
        property bool busy: false
        property string error: ""
        function analyse(path) {
            busy = true; error = "";
            connectSource("\"$HOME/.local/bin/weatherwall-add-photo\" '" + path.replace(/'/g, "'\\''") + "'");
        }
        onNewData: (source, data) => {
            disconnectSource(source);
            busy = false;
            const out = (data.stdout || "").trim().split("\n").pop();
            if (data["exit code"] === 0 && out.indexOf("/") === 0) page.cfg_OwnPhoto = out;
            else error = i18n("Couldn't analyse that photo");
        }
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Places:")
        readonly property var keys: ["mix", "towns", "nature"]
        model: [i18n("A mix"), i18n("Towns and back yards"), i18n("Nature (mountains, lakes, forests)")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_Places))
        onActivated: page.cfg_Places = keys[currentIndex]
    }
    QQC2.CheckBox { id: onlinePhotos; text: i18n("Include photos fetched online (tools/fetch_online.py)") }
    QQC2.CheckBox { id: liveSky; text: i18n("Swap a photo's sunny sky for the live clouds when it's overcast") }
    QQC2.CheckBox { id: showPatio; Kirigami.FormData.label: i18n("Foreground:"); text: i18n("Patio string lights") }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Show lights on:")
        enabled: showPatio.checked
        readonly property var keys: ["auto", "lights", "full"]
        model: [i18n("Town and back yard views only"), i18n("Every view (wild ones too)"),
                i18n("Every view, with the patio railing and eave")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_PatioStyle))
        onActivated: page.cfg_PatioStyle = keys[currentIndex]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("String lights:")
        enabled: showPatio.checked
        readonly property var keys: ["auto", "on", "off"]
        model: [i18n("Auto (on after dusk)"), i18n("Always on"), i18n("Off")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_LightsPower))
        onActivated: page.cfg_LightsPower = keys[currentIndex]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Light colour:")
        enabled: showPatio.checked
        readonly property var keys: ["auto", "multi", "random", "warm", "white", "red", "orange", "yellow",
                                     "green", "blue", "purple", "pink"]
        model: [i18n("Auto (warm white, holiday colours on holidays)"), i18n("Multicolour"),
                i18n("Random (new colours with each new view)"), i18n("Warm white"), i18n("Cool white"),
                i18n("Red"), i18n("Orange"), i18n("Yellow"), i18n("Green"), i18n("Blue"), i18n("Purple"), i18n("Pink")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_LightsColour))
        onActivated: page.cfg_LightsColour = keys[currentIndex]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Decorations:")
        readonly property var keys: ["always", "auto", "off"]
        model: [i18n("Always (the next holiday's between holidays)"), i18n("Only around holidays"), i18n("Off")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_Decorations))
        onActivated: page.cfg_Decorations = keys[currentIndex]
    }
    QQC2.SpinBox { id: refresh; Kirigami.FormData.label: i18n("Refresh every (min):"); from: 5; to: 120 }

    Item { Kirigami.FormData.isSection: true }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Preview weather:")
        readonly property var keys: ["auto", "clear", "partly", "cloudy", "fog", "rain", "snow", "storm"]
        model: [i18n("Live (auto)"), i18n("Clear"), i18n("Partly cloudy"), i18n("Overcast"),
                i18n("Fog"), i18n("Rain"), i18n("Snow"), i18n("Thunderstorm")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_PreviewCondition))
        onActivated: page.cfg_PreviewCondition = keys[currentIndex]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Preview time:")
        readonly property var keys: ["auto", "day", "dusk", "night"]
        model: [i18n("Live (auto)"), i18n("Day"), i18n("Sunset"), i18n("Night")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_PreviewTime))
        onActivated: page.cfg_PreviewTime = keys[currentIndex]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Preview holiday:")
        readonly property var keys: ["auto", "none", "christmas", "newyear", "halloween", "oktoberfest",
                                     "thanksgiving", "july4", "valentine", "stpatrick", "easter"]
        model: [i18n("Live (auto)"), i18n("None"), i18n("Christmas"), i18n("New Year's Eve"), i18n("Halloween"),
                i18n("Oktoberfest"), i18n("Thanksgiving"), i18n("4th of July"), i18n("Valentine's Day"),
                i18n("St. Patrick's Day"), i18n("Easter")]
        currentIndex: Math.max(0, keys.indexOf(page.cfg_PreviewHoliday))
        onActivated: page.cfg_PreviewHoliday = keys[currentIndex]
    }
}
