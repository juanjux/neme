module neme.frontend.tui.events;

import std.algorithm.comparison : max, min;
import std.conv;
import std.experimental.logger;

import neme.core.gapbuffer;
import neme.core.settings;
import extractors = neme.core.extractors;

enum Operations
{
    CHAR_LEFT,
    CHAR_RIGHT,
    LINE_UP,
    LINE_DOWN,
    PAGE_UP,
    PAGE_DOWN,
    LOAD_FILE,
    WORD_LEFT,
    UWORD_LEFT,
    WORD_RIGHT,
    UWORD_RIGHT,
    LINE_START,
    LINE_END,
    QUIT,
    UNKNOWN,
}

class OperationHandlers
{
    // FIXME: accesor
    package GapBuffer* gb = void;
    FileLogger flog = void;

    this(ref FileLogger flog)
    {
        this.flog = flog;
    }

    void lineDown(ref long currentLine, const GrpmCount savedColumn)
    {
        if (gb == null) return;
        currentLine = min(gb.numLines - 1, currentLine + 1);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedColumn - 1));
    }

    void lineUp(ref long currentLine, const GrpmCount savedColumn)
    {
        if (gb == null) return;
        currentLine = max(0, currentLine - 1);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedColumn - 1));
    }

    void pageDown(ref long currentLine, const long textAreaLines, const GrpmCount savedColumn)
    {
        if (gb == null) return;
        currentLine = min(gb.numLines - 1, currentLine + textAreaLines);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedColumn - 1));
    }

    void pageUp(ref long currentLine, const long textAreaLines, const GrpmCount savedColumn)
    {
        if (gb == null) return;
        currentLine = max(0, currentLine - textAreaLines);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedColumn - 1));
    }

    void wordLeft()
    {
        immutable cpos = gb.cursorPos;
        auto words = extractors.words(*gb, gb.cursorPos, Direction.Back, 1);
        if (words.length == 0)
            return;

        if (cpos == words[$-1].startPos) { 
            // didn't move because it was already at the end of a word
            words = extractors.words(*gb, gb.cursorPos, Direction.Back, 2);
        }
        gb.cursorPos = (words[$-1].startPos).GrpmIdx;
    }
    // TODO: uWordLeft

    void wordRight()
    {
        auto currentChar = (*gb)[gb.cursorPos.to!ulong].to!BufferElement;
        immutable count = currentChar in globalSettings.wordSeparators ? 1 : 2;
        auto words = extractors.words(*gb, gb.cursorPos, Direction.Front, count);
        gb.cursorPos = (words[$-1].startPos).GrpmIdx;
    }
    // TODO: uWordRight

    void lineStart()
    {
        gb.cursorPos = gb.lineStartPos(gb.currentLine);
    }

    void lineEnd()
    {
        gb.cursorPos = gb.lineEndPos(gb.currentLine);
    }
}
