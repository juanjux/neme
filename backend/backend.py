#!/usr/bin/env python3
import sys, os
from enum import Enum, unique
from collections import namedtuple

@unique
class Subject(Enum):
    Char      = 1
    Word      = 2
    Line      = 3
    Sentence  = 4
    Paragraph = 5
    Function  = 6
    Class     = 7
    FullFile  = 8

@unique
class Direction(Enum):
    Forward  = 1
    Backward = 2


Selection = namedtuple('Selection', ['start', 'end'])

class BufferInitializeException(Exception): pass

class Buffer:
    def __init__(self, filepath: str=None, text:str=None) -> None:
        if not filepath and not text:
            raise BufferInitializeException('Buffer must be instantiated with a filepath'
                                            'or a text')
        if filepath:
            with open(filepath, 'r') as f:
                self.text = f.read()
        else:
            self.text = text

        self.pos        = 0
        self.line       = 0
        self.column     = 0
        self.selections = [] # type: List[Selection]

        self.moveselect_method = {
            Subject.Char: self.ms_char,
            Subject.Word: self.ms_word,
            Subject.Line: self.ms_line,
            Subject.Sentence: self.ms_sentence,
            Subject.Paragraph: self.ms_paragraph,
            Subject.Function: self.ms_function,
            Subject.Class: self.ms_class,
            Subject.FullFile: self.ms_fullfile
        }

    def process_subject(self, count: int, subject: Subject, direction: Direction) -> None:
        # TODO: allow extending selections
        self.empty_selections()

        if subject == Subject.FullFile:
            count = 1

        for i in range(count):
            self.moveselect_method[subject](direction)


    def ms_char(self, direction: Direction) -> None:
        pass
    def ms_word(self, direction: Direction) -> None:
        pass
    def ms_line(self, direction: Direction) -> None:
        pass
    def ms_sentence(self, direction: Direction) -> None:
        pass
    def ms_paragraph(self, direction: Direction) -> None:
        pass
    def ms_function(self, direction: Direction) -> None:
        pass
    def ms_class(self, direction: Direction) -> None:
        pass

    def ms_fullfile(self, direction: Direction) -> None:
        if self.pos == len(self.text) and direction == Direction.Forward or\
           self.pos == 0 and direction == Direction.Backward:
                return

        if direction == Direction.Forward:
            if self.pos == len(self.text - 1):
                return

            self.selections.append(Selection(self.pos, len(self.text)))
            self.pos = len(self.text - 1)

        else:
            if self.pos == 0:
                return

            self.selections.append(Selection(0, self.pos))
            self.pos = 0

    def empty_selections(self):
        del self.selections[:]
        # TODO: emit


def main() -> None:
    if len(sys.argv) < 2:
        print('Need a file argument')
        exit(1)

    fpath = sys.argv[1]

    if not os.path.exists(fpath):
        print('Cannot find file')
        exit(2)

    buffer = Buffer(filepath=fpath)
    buffer.process_subject(2, Subject.Word, Direction.Forward)


if __name__ == '__main__':
    main()
