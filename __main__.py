#!/usr/bin/python3
# -*- coding: utf-8 -*-

"""
Neme: a NEw Modal Editor prototype

author: Juanjo Álvarez
"""

import sys, os
from PyQt5.QtWidgets import QMainWindow, QTextEdit, QAction, QApplication
from PyQt5.QtGui import QIcon
from PyQt5.Qsci import QsciScintilla


class Neme(QMainWindow):

    def __init__(self):
        super().__init__()

        self.initUI()


    def initUI(self):
        self.scintilla = QsciScintilla()
        #self.scintilla = QTextEdit()
        self.setCentralWidget(self.scintilla)

        self.setGeometry(300, 300, 350, 250)
        self.setWindowTitle('Neme Editor')
        self.show()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    neme = Neme()
    sys.exit(app.exec_())
