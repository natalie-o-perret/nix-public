import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

Popup {
    id: root

    property var items: []
    property bool keyboardNavigation: false
    property var returnFocus: null
    property int selectedIndex: -1

    function activate(index) {
        if (index < 0 || index >= items.length)
            return;
        const item = items[index];
        if (item.type === "separator" || item.enabled === false)
            return;
        close();
        Qt.callLater(item.action);
    }
    function firstEnabledIndex() {
        for (let i = 0; i < items.length; ++i) {
            if (items[i].type !== "separator" && items[i].enabled !== false)
                return i;
        }
        return -1;
    }
    function moveSelection(direction) {
        if (items.length === 0)
            return;
        let next = selectedIndex;
        for (let i = 0; i < items.length; ++i) {
            next = (next + direction + items.length) % items.length;
            if (items[next].type !== "separator" && items[next].enabled !== false) {
                selectedIndex = next;
                menuFlick.contentY = Math.max(0, Math.min(menuFlick.contentHeight - menuFlick.height, next * 34 - menuFlick.height / 2));
                return;
            }
        }
    }
    function showAt(parentItem, localX, localY, menuItems, fromKeyboard) {
        parent = parentItem;
        items = menuItems || [];
        keyboardNavigation = !!fromKeyboard;
        selectedIndex = keyboardNavigation ? firstEnabledIndex() : -1;
        x = Math.max(8, Math.min(parentItem.width - width - 8, localX));
        y = Math.max(8, Math.min(parentItem.height - height - 8, localY));
        open();
    }

    closePolicy: Popup.CloseOnEscape
    dim: false
    focus: true
    height: Math.min((parent ? parent.height : 600) - 16, menuColumn.implicitHeight + Theme.spacingS * 2)
    modal: false
    padding: 0
    width: 272

    background: Rectangle {
        color: "transparent"
    }
    contentItem: Rectangle {
        Accessible.name: "File actions"
        Accessible.role: Accessible.PopupMenu
        border.color: Theme.outlineMedium
        border.width: 1
        color: Theme.floatingSurface
        radius: Theme.cornerRadius

        Item {
            id: keyHandler

            anchors.fill: parent
            focus: root.keyboardNavigation

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Down:
                    root.keyboardNavigation = true;
                    root.moveSelection(1);
                    event.accepted = true;
                    break;
                case Qt.Key_Up:
                    root.keyboardNavigation = true;
                    root.moveSelection(-1);
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    root.activate(root.selectedIndex);
                    event.accepted = true;
                    break;
                case Qt.Key_Escape:
                    root.close();
                    event.accepted = true;
                    break;
                }
            }
        }
        Flickable {
            id: menuFlick

            anchors.fill: parent
            anchors.margins: Theme.spacingS
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            contentHeight: menuColumn.implicitHeight
            contentWidth: width

            Column {
                id: menuColumn

                spacing: 1
                width: menuFlick.width

                Repeater {
                    model: root.items

                    Item {
                        id: row

                        required property int index
                        required property var modelData

                        height: modelData.type === "separator" ? 9 : 34
                        width: menuColumn.width

                        Rectangle {
                            Accessible.role: Accessible.Separator
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.outlineMedium
                            height: 1
                            visible: row.modelData.type === "separator"
                        }
                        Rectangle {
                            id: actionSurface

                            Accessible.description: row.modelData.shortcut || ""
                            Accessible.focusable: enabled
                            Accessible.focused: root.selectedIndex === row.index
                            Accessible.ignored: !visible
                            Accessible.name: row.modelData.text || ""
                            Accessible.role: Accessible.MenuItem
                            anchors.fill: parent
                            color: {
                                if (row.modelData.enabled === false)
                                    return "transparent";
                                if (root.keyboardNavigation && root.selectedIndex === row.index)
                                    return row.modelData.dangerous ? Theme.errorHover : Theme.primaryHover;
                                if (actionArea.containsMouse)
                                    return row.modelData.dangerous ? Theme.errorHover : Theme.surfaceVariant;
                                return "transparent";
                            }
                            enabled: row.modelData.enabled !== false
                            opacity: row.modelData.enabled === false ? 0.42 : 1
                            radius: Theme.cornerRadius
                            visible: row.modelData.type !== "separator"

                            Accessible.onPressAction: root.activate(row.index)

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.right: shortcutLabel.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                DankIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: row.modelData.dangerous ? Theme.error : Theme.surfaceText
                                    name: row.modelData.icon || ""
                                    size: 17
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: row.modelData.dangerous ? Theme.error : Theme.surfaceText
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeSmall
                                    text: row.modelData.text || ""
                                    width: parent.width - 25
                                }
                            }
                            StyledText {
                                id: shortcutLabel

                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.surfaceTextMedium
                                font.pixelSize: Theme.fontSizeSmall
                                text: row.modelData.shortcut || ""
                            }
                            MouseArea {
                                id: actionArea

                                anchors.fill: parent
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: row.modelData.enabled !== false
                                hoverEnabled: true

                                onClicked: root.activate(row.index)
                                onEntered: {
                                    root.keyboardNavigation = false;
                                    root.selectedIndex = row.index;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onClosed: {
        closePolicy = Popup.CloseOnEscape;
        keyboardNavigation = false;
        selectedIndex = -1;
        if (returnFocus)
            Qt.callLater(() => returnFocus.forceActiveFocus());
    }
    onOpened: {
        outsideClickDelay.restart();
        if (keyboardNavigation)
            Qt.callLater(() => keyHandler.forceActiveFocus());
    }

    Timer {
        id: outsideClickDelay

        interval: 80

        onTriggered: root.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside
    }
}
