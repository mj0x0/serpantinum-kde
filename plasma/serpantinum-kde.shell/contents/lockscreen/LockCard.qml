// The wing card chrome from v2: a soft drop, a lifted surface, a hairline border.
import QtQuick

Item {
    id: card
    required property Item lock
    property real cornerRadius: lock.r(16)
    default property alias content: inner.data

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: card.lock.s(2)
        anchors.bottomMargin: card.lock.s(-2)
        radius: card.cornerRadius
        color: Qt.rgba(0, 0, 0, 0.22)
    }
    Rectangle {
        anchors.fill: parent
        radius: card.cornerRadius
        color: Qt.lighter(card.lock.surface0, 1.28)
        border.width: 1
        border.color: Qt.rgba(card.lock.text.r, card.lock.text.g, card.lock.text.b, 0.06)
    }
    Item {
        id: inner
        anchors.fill: parent
        clip: true
    }
}
