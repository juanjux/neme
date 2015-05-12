#!/usr/bin/python3
# -*- coding: utf-8 -*-

"""
Neme: a NEw Modal Editor prototype

author: Juanjo Álvarez

Objectives of this project:
    - have fun writing it when I don't have anything better to do
    - get up to date with Python3 and Qt5 (and C++ later, after prototyping)
    - have my own editor that I can modify easily to satisfy my needs
    - rethink the modal operation for modern keyboards hjkl => jikl, chord
      as default to exit typing (ex-insert) mode, etc.
    - don't use anything needing to press a modifier (not even shift) for basic operations
    - avoid symbols that usually need shift in non-us keyboards (like '/' to search
      or ':' to enter commands).
    - but have the alt/options key as an option for shortcuts too
    - use the function keys too
"""

import sys, os, enum


# FIXME: remote millions of hardcodings, MVC, etc...
# (I shouldn't have uploaded this to github so soon...)

# FIXME: remove these *'s
from PyQt5.QtWidgets import *
from PyQt5.QtGui     import *
from PyQt5.QtCore    import Qt
from PyQt5.Qsci      import QsciScintilla as QSci, QsciLexerPython

# FIXME: make these configurable
ESCAPEFIRST     = Qt.Key_K
ESCAPESECOND    = Qt.Key_J
BACKSPACE_LINES = 5
RETURN_LINES    = 5
NUMSETKEYS = {Qt.Key_0: '0', Qt.Key_1: '1', Qt.Key_2: '2', Qt.Key_3: '3',
              Qt.Key_4: '4', Qt.Key_5: '5', Qt.Key_6: '6', Qt.Key_7: '7',
              Qt.Key_8: '8', Qt.Key_9: '9'}
WHITESPACE = {32, 10, 13, 9} 


class EditorMode(enum.Enum):
    Typing   = 1
    Movement = 2
    Command  = 3


class NemeTextWidget(QSci):
    ARROW_MARKER_NUM = 0

    def __init__(self, parent=None):
        super().__init__(parent)

        # number prefix storage
        self.numberList = []

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
        self.markerDefine(QSci.RightArrow, self.ARROW_MARKER_NUM)
        self.setMarkerBackgroundColor(QColor("#ee1111"), self.ARROW_MARKER_NUM)

        # Brace matching: enable for a brace immediately before or after
        # the current position
        #
        self.setBraceMatching(QSci.SloppyBraceMatch)

        # Current line visible with special background color
        self.setCaretLineVisible(True)
        self.setCaretLineBackgroundColor(QColor("#ffe4e4"))

        # Don't want to see the horizontal scrollbar at all
        # Use raw message to Scintilla here (all messages are documented
        # here: http://www.scintilla.org/ScintillaDoc.html)
        self.SendScintilla(QSci.SCI_SETHSCROLLBAR, 0)

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
        self.setMode(EditorMode.Movement)
        self.prevWasEscapeFirst = False # used for kj escape secuence


    def _findWORDPosition(self, findRight=True):
        """
        Find next WORD. With findRight=True it will
        instead find the end of the previous WORD
        """
        currentPos      = self.SendScintilla(QSci.SCI_GETCURRENTPOS)
        source          = bytearray(1)
        char            = -1
        foundWhiteSpace = False
        adder = 1 if findRight else -1

        while (findRight and char != 0) or (not findRight and currentPos != 0):
            char = self.SendScintilla(QSci.SCI_GETCHARAT, currentPos)
            if foundWhiteSpace and char not in WHITESPACE:
                # found the next word
                return currentPos

            if not foundWhiteSpace:
                foundWhiteSpace = char in WHITESPACE
            currentPos += adder 
        return -1


    def _findWORDExtremePosition(self, start = True):
        """
        Find the start or end of the current WORD
        """
        source = bytearray(1)
        currentPos = self.SendScintilla(QSci.SCI_GETCURRENTPOS)
        char = -1
        adder = -1 if start else 1

        while char != 0:
            char = self.SendScintilla(QSci.SCI_GETCHARAT, currentPos)
            if char in WHITESPACE:
                return currentPos - adder
            currentPos += adder
        return -1


    def _processNumberPrefix(self, key):
        "This should be called only when key has been validated to be a member of NUMSETKEYS"

        strnumkey = NUMSETKEYS.get(key)
        haveToClearList = False

        if strnumkey == '0' and not len(self.numberList):
            # store 0s only when not the first
            self.numberList.clear()
            haveToClearList = True
        else:
            self.numberList.append(strnumkey)

        print('DEBUG: number buffer: {}'.format(self.numberList))
        return haveToClearList


    def getNumberPrefix(self, limitByMaxLines = False):
        if not self.numberList:
            number = 1
        else:
            number = int(''.join([str(i) for i in self.numberList]))
        if limitByMaxLines:
            number = min(number, self.lines())
        return number


    def on_margin_clicked(self, nmargin, nline, modifiers):
        # Toggle marker for the line the margin was clicked on
        if self.markersAtLine(nline) != 0:
            self.markerDelete(nline, self.ARROW_MARKER_NUM)
        else:
            self.markerAdd(nline, self.ARROW_MARKER_NUM)


    def keyPressEvent(self, e):
        process         = False
        clearnumberList = True

        modifiers = QApplication.keyboardModifiers()

        # =============================================================
        # Typing Mode
        # =============================================================

        if self.mode == EditorMode.Typing:

            if modifiers == Qt.NoModifier: # NO MODIFIER
                if e.key() == Qt.Key_Escape:
                    self.setMode(EditorMode.Movement)
                elif e.key() == ESCAPEFIRST:
                    self.prevWasEscapeFirst = True
                    process = True

                elif e.key() == ESCAPESECOND:
                    if self.prevWasEscapeFirst:
                        # delete previous K and change to Movement
                        # FIXME: delete previous k
                        self.SendScintilla(QSci.SCI_DELETEBACK)
                        self.setMode(EditorMode.Movement)
                    else:
                        process = True
                    self.prevWasEscapeFirst = False
                else:
                    # just write
                    process = True

            elif modifiers == Qt.ShiftModifier: # SHIFT
                process = True

            elif modifiers == Qt.ControlModifier: # CONTROL
                # Ctrl + IK is PageUP/Down too like in normal mode
                if e.key() == Qt.Key_I:
                    self.SendScintilla(QSci.SCI_PAGEUP)
                elif e.key() == Qt.Key_K:
                    self.SendScintilla(QSci.SCI_PAGEDOWN)

            elif modifiers == Qt.AltModifier: # ALT
                # Alt + IKJL also moves the cursor in typing mode
                if e.key() == Qt.Key_I:
                    self.SendScintilla(QSci.SCI_LINEUP)
                elif e.key() == Qt.Key_K:
                    self.SendScintilla(QSci.SCI_LINEDOWN)
                elif e.key() == Qt.Key_J:
                    self.SendScintilla(QSci.SCI_CHARLEFT)
                elif e.key() == Qt.Key_L:
                    self.SendScintilla(QSci.SCI_CHARRIGHT)

        # =============================================================
        # Movement Mode
        # =============================================================

        elif self.mode == EditorMode.Movement:

            if modifiers == Qt.NoModifier: # NO MODIFIER
                if e.key() in NUMSETKEYS:
                    clearnumberList = self._processNumberPrefix(e.key())
                    if e.key() == Qt.Key_0 and clearnumberList:
                        # 0 with buffer empty = goto beginning of line
                        self.SendScintilla(QSci.SCI_HOME)
                        
                elif e.key() in {Qt.Key_T, Qt.Key_A}:
                    self.SendScintilla(QSci.SCI_CHARRIGHT)
                    self.setMode(EditorMode.Typing)
                elif e.key() == Qt.Key_Space:
                    self.setMode(EditorMode.Command)
                elif e.key() == Qt.Key_I: # line up
                    if modifiers == Qt.ControlModifier:
                        for _ in range(self.getNumberPrefix(True)):
                            self.SendScintilla(QSci.SCI_PAGEUP)
                    else:
                        for _ in range(self.getNumberPrefix(True)):
                            self.SendScintilla(QSci.SCI_LINEUP)
                elif e.key() == Qt.Key_Backspace: # n lines up
                    for _ in range(BACKSPACE_LINES * self.getNumberPrefix(True)):
                        self.SendScintilla(QSci.SCI_LINEUP, 5)
                elif e.key() == Qt.Key_K: # line down
                    if modifiers == Qt.ControlModifier:
                        for _ in range(self.getNumberPrefix(True)):
                            self.SendScintilla(QSci.SCI_PAGEDOWN)
                    else:
                        for _ in range(self.getNumberPrefix(True)):
                            self.SendScintilla(QSci.SCI_LINEDOWN)
                elif e.key() == Qt.Key_Return: # n lines up
                    # FIXME: MUST be a better way...
                    for _ in range(RETURN_LINES * self.getNumberPrefix(True)):
                        self.SendScintilla(QSci.SCI_LINEDOWN, 5)
                elif e.key() == Qt.Key_J: # char left
                    for _ in range(self.getNumberPrefix()):
                        self.SendScintilla(QSci.SCI_CHARLEFT)
                elif e.key() == Qt.Key_L: # char right
                    for _ in range(self.getNumberPrefix()):
                        self.SendScintilla(QSci.SCI_CHARRIGHT)
                elif e.key() == Qt.Key_W: # next beginning of word
                    for _ in range(self.getNumberPrefix()):
                        self.SendScintilla(QSci.SCI_WORDRIGHT)
                elif e.key() == Qt.Key_B: # prev beginning of word
                    for _ in range(self.getNumberPrefix()):
                        self.SendScintilla(QSci.SCI_WORDLEFT)
                elif e.key() == Qt.Key_E: # next end of word
                    for _ in range(self.getNumberPrefix()):
                        self.SendScintilla(QSci.SCI_WORDRIGHTEND)
                elif e.key() == Qt.Key_U: # undo
                    self.setReadOnly(0)
                    for _ in range(self.getNumberPrefix()):
                        self.undo()
                    self.setReadOnly(1)
                elif e.key() == Qt.Key_S: # first non-blank in line
                    self.SendScintilla(QSci.SCI_VCHOME)
                elif e.key() == Qt.Key_O: # insert empty line below current
                    self.beginUndoAction()
                    # FIXME: start at the right column after language indentation
                    for _ in range(self.getNumberPrefix()):
                        line, index = self.getCursorPosition()
                        self.insertAt('\n', line+1, 0)
                        self.setCursorPosition(line+1, 0)
                    self.setMode(EditorMode.Typing)
                    self.endUndoAction()
                else:
                    # probably single modifier
                    clearnumberList = False

            elif modifiers == Qt.ShiftModifier: # SHIFT
                if e.key() == Qt.Key_Dollar: # end of line
                    self.SendScintilla(QSci.SCI_LINEEND)
                elif e.key() == Qt.Key_A: # append after EOL
                    self.SendScintilla(QSci.SCI_LINEEND)
                    self.setMode(EditorMode.Typing)
                elif e.key() == Qt.Key_I: # insert at the start of the line
                    self.SendScintilla(QSci.SCI_VCHOME)
                    self.setMode(EditorMode.Typing)
                elif e.key() == Qt.Key_O: # insert empty line above current
                    # FIXME: start at the right column after language indentation
                    self.beginUndoAction()
                    for _ in range(self.getNumberPrefix()):
                        line, index = self.getCursorPosition()
                        self.insertAt('\n', line, 0)
                        self.setCursorPosition(line, 0)
                        self.setMode(EditorMode.Typing)
                    self.endUndoAction()
                elif e.key() == Qt.Key_J: # join line with line below
                    # FIXME: undoing this leaves the cursor at the end of the line
                    self.beginUndoAction()
                    for _ in range(self.getNumberPrefix(True)):
                        line, index = self.getCursorPosition()
                        nextLine    = self.text(line + 1).lstrip()
                        if not nextLine:
                            nextLine = '\n'

                        self.setReadOnly(0)
                        self.insertAt(' ' + nextLine, line, self.lineLength(line)-1)
                        self.SendScintilla(QSci.SCI_LINEDOWN)
                        self.SendScintilla(QSci.SCI_LINEDELETE)
                        self.SendScintilla(QSci.SCI_LINEDELETE)
                        self.SendScintilla(QSci.SCI_LINEUP)
                        self.setReadOnly(1)
                    self.endUndoAction()
                elif e.key() == Qt.Key_W: # next WORD
                    for _ in range(self.getNumberPrefix()):
                        nextWordPos = self._findWORDPosition()
                        if nextWordPos != -1:
                            self.SendScintilla(QSci.SCI_GOTOPOS, nextWordPos)
                elif e.key() == Qt.Key_E: # prev WORD end
                    for _ in range(self.getNumberPrefix()):
                        prevWordEndPos = self._findWORDPosition(findRight=False)
                        if prevWordEndPos != -1:
                            self.SendScintilla(QSci.SCI_GOTOPOS, prevWordEndPos)
                elif e.key() == Qt.Key_B: # prev WORD start
                    for _ in range(self.getNumberPrefix()):
                        prevWordEndPos = self._findWORDPosition(findRight=False)
                        if prevWordEndPos != -1:
                            self.SendScintilla(QSci.SCI_GOTOPOS, prevWordEndPos)
                            wordStart = self._findWORDExtremePosition(start = True)
                            self.SendScintilla(QSci.SCI_GOTOPOS, wordStart)


            elif modifiers == Qt.AltModifier: # ALT
                if e.key() == Qt.Key_E: # prev end of word
                    for _ in range(self.getNumberPrefix()):
                        self.SendScintilla(QSci.SCI_WORDLEFTEND)
                elif e.key() == Qt.Key_U: # redo
                    self.setReadOnly(0)
                    for _ in range(self.getNumberPrefix()):
                        self.redo()
                    self.setReadOnly(1)

            elif modifiers == Qt.ControlModifier:# CONTROL
                if e.key() == Qt.Key_I: # page up
                    for _ in range(self.getNumberPrefix(True)):
                        self.SendScintilla(QSci.SCI_PAGEUP)
                elif e.key() == Qt.Key_K: # page down
                    for _ in range(self.getNumberPrefix(True)):
                        self.SendScintilla(QSci.SCI_PAGEDOWN)

        # ==============================================================
        # Command Mode
        # ==============================================================

        elif self.mode == EditorMode.Command:

            if e.key() == Qt.Key_Escape:
                self.setMode(EditorMode.Movement)

            elif e.key() == Qt.Key_Return:
                self.processCommand()
                self.setMode(EditorMode.Movement)

        if self.prevWasEscapeFirst and e.key() != ESCAPEFIRST:
            self.prevWasEscapeFirst = False

        if clearnumberList:
            self.numberList.clear()

        if process:
            super().keyPressEvent(e)


    def setMode(self, newmode):
        if newmode == self.mode:
            return

        if newmode == EditorMode.Typing:
            self.SendScintilla(QSci.SCI_SETCARETSTYLE, 1)
            self.setReadOnly(0)

        elif newmode == EditorMode.Movement:
            self.SendScintilla(QSci.SCI_SETCARETSTYLE, 2)
            self.setReadOnly(0)
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
        self.scintilla.setText(
                open(os.path.abspath(__file__), encoding="utf8").read()
        )
        self.setCentralWidget(self.scintilla)
        self.setGeometry(300, 300, 350, 250)
        self.setWindowTitle('Neme Editor')
        self.show()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    neme = Neme()
    sys.exit(app.exec_())
