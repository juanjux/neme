module neme;

import std.array: join;
import std.algorithm.comparison: max, min;
import std.algorithm.mutation: fill;
import std.container.array: Array;
import std.conv;
import std.stdio;

struct GapBuffer
{
    // I'll be using both until I determine what is better for 
    // the editor buffer use case
    private:
        char[] buffer = null;
        Array!char libArray;
        long gapStart;
        long gapEnd;
        ulong gapSize = 100;

    this(string text)
    {
        char[] initialGap;
        initialGap.length = gapSize;

        // char[] initialGap;
        // initialGap.fill!(char[], char)(' ');
        buffer = initialGap ~ text.to!(char[]);
        libArray = Array!char(text.to!(char[]));
        gapStart = 0;
        gapEnd = gapSize;
    }

    void debugContent() const
    {
        writeln("start: ", gapStart, " end: ", gapEnd);
        writeln("Before: ");
        writeln(contentBeforeGap);
        writeln("After:");
        writeln(contentAfterGap);
        writeln("Full: ");
        writeln(buffer.to!string);
        foreach(_; buffer[0..gapStart]) {
            write(" ");
        }
        write("^");
        foreach(_; buffer[gapStart..gapEnd-2]) {
            write("#");
        }
        write("^");
        writeln;
    }

    @property 
    string content() const 
    {
        return buffer.to!string;
    }

    @property
    string contentBeforeGap() const
    {
        return buffer[0..gapStart].to!string;
    }

    @property
    string contentAfterGap() const
    {
        return buffer[gapEnd..$].to!string;
    }

    void cursorForward(long count) 
    {
        // FIXME: log
        if (buffer.length == 0 || gapEnd + 1 == buffer.length) {
            return;
        }

        long charsToCopy = min(count, buffer.length - gapEnd);
        long newGapStart = gapStart + charsToCopy;
        long newGapEnd   = gapEnd + charsToCopy;
        buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd];

        gapStart = newGapStart;
        gapEnd   = newGapEnd;
    }

    void cursorBackward(long count) 
    {
        // FIXME: log
        if (buffer.length == 0  || gapStart == 0) {
            return;
        }

        long charsToCopy = min(count, gapStart);
        long newGapStart = gapStart - charsToCopy;
        long newGapEnd   = gapEnd - charsToCopy;
        buffer[newGapStart..gapStart] = buffer[newGapEnd..gapEnd];

        gapStart = newGapStart;
        gapEnd   = newGapEnd;
    }
}

void main()
{
    auto text = "Lorem ipsum blabla";
    auto gBuffer = GapBuffer(text);

    writeln("\n\n=== Start ===");
    gBuffer.debugContent();

    writeln("\n=== Cursor forward 4 ===");
    gBuffer.cursorForward(4);
    gBuffer.debugContent();

    writeln("\n=== Cursor backward 2 ===");
    gBuffer.cursorBackward(2);
    gBuffer.debugContent();

    writeln("=== Cursor backward 1000 ===");
    gBuffer.cursorBackward(10000);
    gBuffer.debugContent();

    writeln("\n=== Cursor forward 6 ===");
    gBuffer.cursorForward(6);
    gBuffer.debugContent();

    writeln("\n=== Cursor forward 1000 ===");
    gBuffer.cursorForward(10000);
    gBuffer.debugContent();

    writeln("\n=== Cursor backward 8 ===");
    gBuffer.cursorBackward(8);
    gBuffer.debugContent();
}