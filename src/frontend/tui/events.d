module neme.frontend.tui.events;

import std.algorithm.comparison : max, min;
import std.experimental.logger;

import neme.core.gapbuffer;

class KeyboardHandlers
{
    // FIXME: accesor
    package GapBuffer* gb = void;
    FileLogger flog = void;

    this(ref FileLogger flog)
    {
        this.flog = flog;
    }

    void lineDown(ref long currentLine)
    {
        if (gb == null) return;
        currentLine = min(gb.numLines - 1, currentLine + 1);
        gb.cursorToLine(currentLine + 1);
    }

    void lineUp(ref long currentLine)
    {
        if (gb == null) return;
        currentLine = max(0, currentLine - 1);
        gb.cursorToLine(currentLine + 1);
    }

    void pageDown(ref long currentLine, long textAreaLines)
    {
        if (gb == null) return;
        currentLine = min(gb.numLines - 1, currentLine + textAreaLines);
        gb.cursorToLine(currentLine + textAreaLines);
    }

    void pageUp(ref long currentLine, long textAreaLines)
    {
        if (gb == null) return;
        currentLine = max(0, currentLine - textAreaLines);
        gb.cursorToLine(currentLine - textAreaLines);
    }
}
