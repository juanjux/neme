#!/usr/bin/python3
# -*- coding: utf-8 -*-

"""
Neme: a NEw Modal Editor prototype

author: Juanjo Álvarez
"""

import sys, os, enum


# FIXME: remote millions of hardcodings, MVC, etc... 
# (I shouldn't have uploaded this to github so soon...)

# FIXME: remove these *'s
from PyQt5.QtWidgets import *
from PyQt5.QtGui     import *
from PyQt5.QtCore    import Qt
from PyQt5.Qsci      import QsciScintilla, QsciLexerPython

ESCAPEFIRST  = Qt.Key_K
ESCAPESECOND = Qt.Key_J

class EditorMode(enum.Enum):
    Typing  = 1
    Normal  = 2
    Command = 3


class NemeTextWidget(QsciScintilla):
    ARROW_MARKER_NUM = 0

    def __init__(self, parent=None):
        super().__init__(parent)

        # font
        font = QFont()
        font.setFamily('Courier')
        font.setFixedPitch(True)
        font.setPointSize(10)
        self.setFont(font)
        fontmetrics = QFontMetrics(font)

        # margins
        self.setMarginsFont(font)
        self.setMarginWidth(0, fontmetrics.width("0000") + 3)
        self.setMarginLineNumbers(0, True)
        self.setMarginsBackgroundColor(QColor("#cccccc"))
        self.setMarginSensitivity(1, True)
        self.marginClicked.connect(self.on_margin_clicked)
        self.markerDefine(QsciScintilla.RightArrow, self.ARROW_MARKER_NUM)
        self.setMarkerBackgroundColor(QColor("#ee1111"), self.ARROW_MARKER_NUM)

        # Brace matching: enable for a brace immediately before or after
        # the current position
        #
        self.setBraceMatching(QsciScintilla.SloppyBraceMatch)

        # Current line visible with special background color
        self.setCaretLineVisible(True)
        self.setCaretLineBackgroundColor(QColor("#ffe4e4"))

        # Don't want to see the horizontal scrollbar at all
        # Use raw message to Scintilla here (all messages are documented
        # here: http://www.scintilla.org/ScintillaDoc.html)
        self.SendScintilla(QsciScintilla.SCI_SETHSCROLLBAR, 0)

        # Set Python lexer
        # Set style for Python comments (style number 1) to a fixed-width
        # courier.
        #
        lexer = QsciLexerPython()
        lexer.setDefaultFont(font)
        self.setLexer(lexer)

        #not too small
        self.setMinimumSize(600, 450)
        
        self.mode = None
        self.changeMode(EditorMode.Normal)
        self.prevWasEscapeFirst = False # used for kj escape secuence


    def on_margin_clicked(self, nmargin, nline, modifiers):
        # Toggle marker for the line the margin was clicked on
        if self.markersAtLine(nline) != 0:
            self.markerDelete(nline, self.ARROW_MARKER_NUM)
        else:
            self.markerAdd(nline, self.ARROW_MARKER_NUM)


    def keyPressEvent(self, e):
        process = False
        modifiers = QApplication.keyboardModifiers()
        # Typing Mode =================================================

        if self.mode == EditorMode.Typing:
            if modifiers == Qt.AltModifier:
                # Alt + IKJL also moves the cursor in typing mode
                if e.key() == Qt.Key_I:
                    self.SendScintilla(QsciScintilla.SCI_LINEUP)

                elif e.key() == Qt.Key_K:
                    self.SendScintilla(QsciScintilla.SCI_LINEDOWN)

                elif e.key() == Qt.Key_J:
                    self.SendScintilla(QsciScintilla.SCI_CHARLEFT)

                elif e.key() == Qt.Key_L:
                    self.SendScintilla(QsciScintilla.SCI_CHARRIGHT)

            elif modifiers == Qt.ControlModifier:
                # Ctrl + IK is PageUP/Down too like in normal mode
                if e.key() == Qt.Key_I:
                    self.SendScintilla(QsciScintilla.SCI_PAGEUP)

                elif e.key() == Qt.Key_K:
                    self.SendScintilla(QsciScintilla.SCI_PAGEDOWN)
            else:
                # no modifiers
                if e.key() == Qt.Key_Escape:
                    self.changeMode(EditorMode.Normal)

                elif e.key() == ESCAPEFIRST:
                    self.prevWasEscapeFirst = True
                    process = True

                elif e.key() == ESCAPESECOND:
                    if self.prevWasEscapeFirst:
                        # delete previous K and change to Normal
                        # FIXME: delete previous k
                        self.SendScintilla(QsciScintilla.SCI_DELETEBACK)
                        self.changeMode(EditorMode.Normal)
                    else:
                        process = True
                    self.prevWasEscapeFirst = False
                else:
                    # just write
                    process = True


        # Normal Mode =================================================
        elif self.mode == EditorMode.Normal:
            # IKJL move the cursor, Ctrl-I and Ctrl-K are PageUp/PageDown
            if e.key() in {Qt.Key_T, Qt.Key_A}:
                self.changeMode(EditorMode.Typing)

            elif e.key() == Qt.Key_Escape:
                self.changeMode(EditorMode.Command)

            elif e.key() == Qt.Key_I:
                if modifiers == Qt.ControlModifier:
                    self.SendScintilla(QsciScintilla.SCI_PAGEUP)
                else:
                    self.SendScintilla(QsciScintilla.SCI_LINEUP)

            elif e.key() == Qt.Key_K:
                if modifiers == Qt.ControlModifier:
                    self.SendScintilla(QsciScintilla.SCI_PAGEDOWN)
                else:
                    self.SendScintilla(QsciScintilla.SCI_LINEDOWN)

            elif e.key() == Qt.Key_J:
                self.SendScintilla(QsciScintilla.SCI_CHARLEFT)

            elif e.key() == Qt.Key_L:
                self.SendScintilla(QsciScintilla.SCI_CHARRIGHT)

        # Command Mode =================================================
        elif self.mode == EditorMode.Command:
            if e.key() == Qt.Key_Escape:
                self.changeMode(EditorMode.Normal)

            elif e.key() == Qt.Key_Return:
                self.processCommand()
                self.changeMode(EditorMode.Normal)

        if self.prevWasEscapeFirst and e.key() != ESCAPEFIRST:
            self.prevWasEscapeFirst = False

        if process:
            super().keyPressEvent(e)
    

    # FIXME: property!
    def changeMode(self, newmode):
        print('In changemode {}'.format(newmode))
        if newmode == self.mode:
            print('XXX')
            return

        if newmode == EditorMode.Typing:
            print('XXX 1')
            self.setReadOnly(0)

        elif newmode == EditorMode.Normal:
            pass
            self.setReadOnly(1)

        elif newmode == EditorMode.Command:
            pass
            self.setReadOnly(1)

        self.mode = newmode
        print('NewMode: {}'.format(self.mode))


    def processCommand(self):
        # FIXME: implement
        pass


class Neme(QMainWindow):

    def __init__(self):
        super().__init__()
        self.initUI()


    def initUI(self):
        self.scintilla = NemeTextWidget()
        self.scintilla.setText(open(os.path.abspath(__file__)).read())
        self.setCentralWidget(self.scintilla)
        self.setGeometry(300, 300, 350, 250)
        self.setWindowTitle('Neme Editor')
        self.show()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    neme = Neme()
    sys.exit(app.exec_())
