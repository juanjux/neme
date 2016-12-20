#!/usr/bin/env python3
import unittest
import backend
from blist import blist

class TestBuffer(unittest.TestCase):
    # Columns should always be pos in line + 1

    #col: 1                        26                       51 # maxcol = 52
    t1 = "0 some random text  and  25 and some more  text   50" # maxpos = 51 || len = 52
    t2 = "0 some random test with  25\n new line and more\nlines after\n62" # maxpos = 61 "" len = 62
    t3 = "123456789"
    tnull = " "

    def setUp(self):
        self.buf1    = backend.Buffer(text = self.t1)
        self.buf2    = backend.Buffer(text = self.t2)
        self.buf3    = backend.Buffer(text = self.t3)
        self.bufnull = backend.Buffer(text = self.tnull)

    def test_text(self):
        self.assertEqual(self.buf1.text, self.t1)
        self.assertEqual(self.bufnull.text, " ")

        newstr = "polompos pok"
        self.buf1.text = newstr
        self.assertEqual(self.buf1.text, newstr)

    def test_pos(self):
        # TODO: test negros con negativos o cosas raras
        self.assertEqual(self.buf1.pos, 0)
        self.assertEqual(self.bufnull.pos, 0)

        self.buf1.pos = 0
        self.assertEqual(self.buf1.line, 1)
        self.assertEqual(self.buf1.column, 1)

        self.buf3.pos = 5
        self.assertEqual(self.buf3.line, 1)
        self.assertEqual(self.buf3.column, 6)

        self.buf1.pos = 99999999
        self.assertEqual(self.buf1.line, 1)
        self.assertEqual(self.buf1.column, len(self.t1))

        self.buf2.pos = 25
        self.assertEqual(self.buf2.line, 1)
        self.assertEqual(self.buf2.column, 26)

        self.buf2.pos = 27
        self.assertEqual(self.buf2.line, 1)
        self.assertEqual(self.buf2.column, 28)

        self.buf2.pos = 99999999
        self.assertEqual(self.buf2.line, 4)
        self.assertEqual(self.buf2.column, 2)

        self.bufnull.pos = 99999999
        self.assertEqual(self.bufnull.line, 1)
        self.assertEqual(self.bufnull.column, 1)



    # def test_ms_fullfile(self) -> None:
        # b = backend.Buffer(t1)
        # self.assertEqual(
