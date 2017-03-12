module gapbuffer;

import std.algorithm.comparison : max, min;
import std.array : join, replicate, appender;
import std.container.array : Array;
import std.conv;
import std.stdio;


// TODO: constructor with a file argument and no argument
// TODO: text with the libArray too
// TODO: Make it a template AnyText


/// Struct user as Gap Buffer
struct GapBuffer
{
    alias asArray = to!(char[]);

    // I'll be using both until I determine what is better for 
    // the editor buffer use case
private:
    char[] buffer = null;
    Array!char libArray;
    long gapStart;
    long gapEnd;
    ulong gapSize = 100;

    /// Constructor that takes a string as the inital contents
    public this(string text)
    {
        buffer = new char[gapSize] ~ asArray(text);
        libArray = Array!char(asArray(text));
        gapStart = 0;
        gapEnd = gapSize;
    }

    /** Print the raw contents of the buffer and a guide line below with the 
     *  position of the start and end positions of the gap
     */
    public void debugContent()
    {
        writeln("start: ", gapStart, " end: ",
                gapEnd, " len: ", buffer.length);
        writeln("Before: ");
        writeln(contentBeforeGap);
        writeln("After:");
        writeln(contentAfterGap);
        writeln("Processed test:");
        writeln(content);
        writeln("Full buffer: ");
        writeln(buffer.to!string);
        foreach (_; buffer[0 .. gapStart])
        {
            write(" ");
        }
        write("^");
        foreach (_; buffer[gapStart .. gapEnd - 2])
        {
            write("#");
        }
        write("^");
        writeln;
    }

    /** 
     * Retrieve the contents of the buffer.
     * Returns: The content of the buffer, as string.
     */
    pragma(inline):
    @property public string content()
    {
        return to!string(contentBeforeGap ~ contentAfterGap);
    }

    pragma(inline):
    @property private char[] contentBeforeGap()
    {
        return buffer[0 .. gapStart];
    }

    pragma(inline):
    @property private char[] contentAfterGap()
    {
        return buffer[gapEnd .. $];
    }

    pragma(inline):
    @property private long currentGapSize()
    {
        return buffer.length - contentBeforeGap.length - contentAfterGap.length;
    }

    public void cursorForward(long count)
    {
        // FIXME: log
        if (buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        long charsToCopy = min(count, buffer.length - gapEnd);
        long newGapStart = gapStart + charsToCopy;
        long newGapEnd = gapEnd + charsToCopy;
        buffer[gapStart .. newGapStart] = buffer[gapEnd .. newGapEnd];

        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    /** 
     * Moves the cursor backwards, copying the text left to the right to the 
     * right side of the buffer.
     * Params:
     *     count = the number of places to move to the left.
     */
    public void cursorBackward(long count)
    {
        // FIXME: log
        if (buffer.length == 0 || gapStart == 0)
            return;

        long charsToCopy = min(count, gapStart);
        long newGapStart = gapStart - charsToCopy;
        long newGapEnd = gapEnd - charsToCopy;
        buffer[newGapStart .. gapStart] = buffer[newGapEnd .. gapEnd];

        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    /**
     * Delete count chars to the left of the cursor position, moving it back (typically
     * the effect of the backspace key).
     *
     * Params: 
     *     count = the numbers of chars to delete.
     */
    public void deleteLeft(long count)
    {
        if (buffer.length == 0 || gapStart == 0)
            return;

        gapStart = max(gapStart - count, 0);
    }

    /** 
      * Delete count chars to the right of the cursor position, keeping it in place
      *  (typically the effect of the del key).
      *
      * Params:
      *     count = the number of chars to delete.
      */
    public void deleteRight(long count)
    {
        if (buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        gapEnd = min(gapEnd + count, buffer.length);
    }

    /**
     * Adds text, moving the cursor to the end of the new text. Could cause
     * a reallocation of the buffer.
     * Params:
     *     text = text to add.
     */
    public void addLeft(string text)
    {

    }

    /** 
     * Adds text to the right of the cursor without moving it. Could cause
     * a reallocation of the buffer.
     * Params:
     *     text = text to add.
     */
    public void addRight(string text)
    {

    }

    // Reallocates the buffer, increasing the gap size if gapSizeIncrease > 0
    // FIXME: make private
    public void reallocate(uint gapSizeIncrease)
    {
        immutable oldContentAfterGapLen = contentAfterGap.length;
        char[] newBuffer = 
            contentBeforeGap ~ new char[gapSize + gapSizeIncrease] ~ contentAfterGap;
        buffer = newBuffer;
        gapEnd = buffer.length - oldContentAfterGapLen;
    }
}