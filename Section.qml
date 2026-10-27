import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One section of the card: a glyph, a title and a line on what it is for,
// then whatever the section puts below (its `body`).
BorderSurface {
  id: section

  property string glyph: ""
  property string title: ""
  property string subtitle: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  default property alias body: body.data

  implicitHeight: column.implicitHeight + Style.spacing.lg * 2 + contentTopInset + contentBottomInset
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.controlSpec("normal", foreground, accent)

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: section.contentTopInset + Style.spacing.lg
    anchors.leftMargin: section.contentLeftInset + Style.spacing.controlPaddingX
    anchors.rightMargin: section.contentRightInset + Style.spacing.controlPaddingX
    spacing: Style.spacing.lg

    Row {
      width: parent.width
      spacing: Style.spacing.xxl

      Text {
        id: glyphText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: section.glyph
        color: section.accent
        font.family: section.fontFamily
        font.pixelSize: Style.font.display
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - glyphText.width - parent.spacing
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: section.title
          horizontalAlignment: Text.AlignLeft
          color: section.foreground
          font.family: section.fontFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: section.subtitle
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignLeft
          color: section.foreground
          opacity: 0.65
          font.family: section.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.spacing.md
    }
  }
}
