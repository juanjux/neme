module neme.frontend.tui.events;

// FIXME XXX: rename to operations.d

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
    JUMPTO_CHAR_RIGHT,
    JUMPTO_CHAR_LEFT,
    SEARCH_FRONT, // XXX implement
    SEARCH_BACK, // XXX implement
    JUMP_WORD_UNDERCURSOR_FRONT, // XXX implement
    JUMP_WORD_UNDERCURSOR_BACK, // XXX implement
    JUMP_MATCHING_BLOCKCHAR, // XXX implement (like '%' in Vim)
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

    void lineDown(ref long currentLine, const GrpmCount savedCol)
    {
        if (gb == null) return;
        currentLine = min(gb.numLines - 1, currentLine + 1);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedCol - 1));
    }

    void lineUp(ref long currentLine, const GrpmCount savedCol)
    {
        if (gb == null) return;
        currentLine = max(0, currentLine - 1);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedCol - 1));
    }

    void pageDown(ref long currentLine, const long textAreaLines, const GrpmCount savedCol)
    {
        if (gb == null) return;
        currentLine = min(gb.numLines - 1, currentLine + textAreaLines);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedCol - 1));
    }

    void pageUp(ref long currentLine, const long textAreaLines, const GrpmCount savedCol)
    {
        if (gb == null) return;
        currentLine = max(0, currentLine - textAreaLines);
        gb.cursorToLine(currentLine + 1);
        gb.lineCursorForward(GrpmCount(savedCol - 1));
    }

    // TODO: Factorize these two into one taking the extractor
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

    void uWordLeft()
    {
        immutable cpos = gb.cursorPos;
        auto words = extractors.uWords(*gb, gb.cursorPos, Direction.Back, 1);
        if (words.length == 0)
            return;

        if (cpos == words[$-1].startPos) {
            // didn't move because it was already at the end of a word
            words = extractors.uWords(*gb, gb.cursorPos, Direction.Back, 2);
        }
        gb.cursorPos = (words[$-1].startPos).GrpmIdx;
    }

    void wordRight()
    {
        auto currentChar = (*gb)[gb.cursorPos.to!ulong].to!BufferElement;
        immutable count = currentChar in globalSettings.wordSeparators ? 1 : 2;
        const words = extractors.words(*gb, gb.cursorPos, Direction.Front, count);
        gb.cursorPos = (words[$-1].startPos).GrpmIdx;
    }

    void uWordRight()
    {
        import std.uni: isWhite;

        auto currentChar = (*gb)[gb.cursorPos.to!ulong].to!BufferElement;
        immutable count = isWhite(currentChar) ? 1 : 2;
        const words = extractors.uWords(*gb, gb.cursorPos, Direction.Front, count);
        gb.cursorPos = (words[$-1].startPos).GrpmIdx;
    }

    void lineStart()
    {
        gb.cursorPos = gb.lineStartPos(gb.currentLine);
    }

    void lineEnd()
    {
        gb.cursorPos = gb.lineEndPos(gb.currentLine);
    }

    // Return value indicates if column must be updated
    bool jumpToCharRight(long currentLine, const GrpmCount savedCol,
            BufferElement t)
    {
        if ((*gb)[gb.cursorPos] == "\n") // empty line
            return false;

        auto lines = extractors.lines(*gb, GrpmIdx(gb.cursorPos+1),
                Direction.Front, 1);

        if (lines.length == 0)
            return false;

        auto line = lines[0];
        auto searchStart = savedCol.to!long - 1;

        if (searchStart < 0 || searchStart >= line.text.length)
            return false;

        foreach(i, c; line.text[searchStart..$]) {
            if (c == t && i > 0) {
                gb.cursorPos = GrpmIdx(gb.cursorPos + i);
                break;
            }
        }

        return true;
    }

    // Return value indicates if column must be updated
    bool jumpToCharLeft(long currentLine, const GrpmCount savedCol,
            BufferElement t)
    {
        if (savedCol <= 1)
            return false;

        auto lines = extractors.lines(*gb, GrpmIdx(gb.cursorPos+1),
                Direction.Front, 1);

        if ((lines.length == 0) ||
                // empty line
                (lines.length == 1 && (*gb)[gb.cursorPos] == "\n")) {
            return false;
        }

        auto line = lines[0];
        auto searchStart = savedCol.to!long - 1;

        if (searchStart < 0 || searchStart >= line.text.length)
            return false;

        foreach_reverse(i, c; line.text[0..searchStart]) {
            auto idx = savedCol - i;
            if (c == t && idx > 0) {
                gb.cursorPos = GrpmIdx(gb.cursorPos - idx + 1);
                break;
            }
        }

        return true;
    }
}
