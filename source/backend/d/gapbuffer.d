module gapbuffer;

import std.algorithm.comparison : max, min;
import std.array : join, replicate, appender, insertInPlace, minimallyInitializedArray;
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
        // TODO: speed test the replicate vs a simple new char[gapSize]
        buffer = replicate(['-'], gapSize) ~ asArray(text);
        libArray = Array!char(asArray(text));
        gapStart = 0;
        gapEnd = gapSize;
    }

    /** Print the raw contents of the buffer and a guide line below with the 
     *  position of the start and end positions of the gap
     */
    public void debugContent()
    {
        writeln("start: ", gapStart, " end: ", gapEnd, " len: ", buffer.length,
                " currentGapLen: ", currentGapSize);
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

    // Reallocates the buffer, creating a new gap of the original size or bigger
    // if gapSizeIncrease is greated than 0. If textToAdd is != than null and 
    // textToAdd.length > 0 it will be also be added just before the start of
    // the new gap.
    // FIXME: make private
    public void reallocate(uint gapSizeIncrease, string textToAdd)
    {
        if (textToAdd == null) {
            textToAdd = "";
        }

        // TODO: speed test with this too:
        // char[] newBuffer = 
        //     contentBeforeGap ~ new char[gapSize] ~ contentAfterGap;
        // buffer = newBuffer;

        char[] arrayToAdd;
        if (currentGapSize >= gapSize + gapSizeIncrease) 
        {
            // This was called because the text doesn't fill in the gap, yet our current
            // gat is greter than the requested one; just add the new text before the 
            // current gap when reallocating
            arrayToAdd = asArray(textToAdd);
        } else 
        {
            // curent gap smaller than the requested one, restore (or increase) the gap 
            // size and put the new text (if any) at the start
            gapSize += gapSizeIncrease;
            arrayToAdd = asArray(textToAdd) ~ replicate(['-'], gapSize - currentGapSize);
        }

        immutable oldContentAfterGapLen = contentAfterGap.length;
        buffer.insertInPlace(gapStart, arrayToAdd);
        gapEnd = buffer.length - oldContentAfterGapLen;
        gapStart += textToAdd.length;
    }

    /** 
     * Alias for reallocate(gapSizeIncrease, null)
     */
    pragma(inline):
    public void reallocate(uint gapSizeIncrease) 
    {
        reallocate(gapSizeIncrease, null);
    }

    /** 
     * Alias for reallocate(0, null)
     */
    pragma(inline):
    public void reallocate() 
    {
        reallocate(0, null);
    }

    /** 
     * Alias for reallocate(0, textToAdd)
     */
    pragma(inline):
    public void reallocate(string textToAdd)
    {
        reallocate(0, textToAdd);
    }
}