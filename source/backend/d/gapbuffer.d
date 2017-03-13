module gapbuffer;

// TODO: import cleanup
import std.algorithm.comparison : max, min;
import std.array : join, replicate, appender, insertInPlace, minimallyInitializedArray;
import std.container.array : Array;
import std.conv;
import std.stdio;
import std.typecons: Flag;
import std.exception: mayPointTo, doesPointTo;

// TODO: text with the libArray too
// TODO: Make it work with unicode codepoints
// TODO: Make it a template AnyText

pragma(inline):
private bool overlaps(ulong destStart, ulong destEnd,
                        ulong sourceStart, ulong sourceEnd)
{
    writeln(destStart, ",", destEnd, ",", sourceStart, ",", sourceEnd);
    return (destStart > sourceStart && destStart < sourceEnd) ||
            (destEnd > sourceStart && destEnd < sourceEnd);
}

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
    ulong initialGapSize;

    // TODO: increase gap size to something bigger
    /// Constructor that takes a string as the inital contents
    public this(string text, ulong gapSize = 100)
    {
        initialGapSize = gapSize;
        // TODO: speed test the replicate vs a simple new char[initialGapSize]
        buffer = replicate(['-'], initialGapSize) ~ asArray(text);
        libArray = Array!char(asArray(text));
        gapStart = 0;
        gapEnd = initialGapSize;
    }

    /** Print the raw contents of the buffer and a guide line below with the 
     *  position of the start and end positions of the gap
     */
    public void debugContent()
    {
        writeln("gapstart: ", gapStart, " gapend: ", gapEnd, " len: ", buffer.length,
                " currentGapSize: ", currentGapSize, " initialGapSize: ", initialGapSize);
        writeln("BeforeGap: ");
        writeln(contentBeforeGap);
        writeln("AfterGap:");
        writeln(contentAfterGap);
        writeln("Text content:");
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


    // TODO: keep this calculated updating the total every time there
    // is an insertion or deletion (keept this as an invariant check for the class)
    pragma(inline):
    @property private long currentGapSize()
    {
        return buffer.length - contentBeforeGap.length - contentAfterGap.length;
    }

    pragma(inline):
    @property public ulong gapSize()
    {
        return initialGapSize;
    }

    pragma(inline):
    @property  public void gapSize(ulong newSize)
    {
        import std.exception: enforce;
        enforce(newSize > 1, "Minimum gap size must be greater than 1");
        initialGapSize = newSize;
        reallocate("", true);
    }

    public void cursorForward(long count)
    {
        if (buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        // TODO: test if this gives any real speed over always doing the dup
        long charsToCopy = min(count, buffer.length - gapEnd);
        long newGapStart = gapStart + charsToCopy;
        long newGapEnd = gapEnd + charsToCopy;

        if (overlaps(gapStart, newGapStart, gapEnd, newGapEnd)) {
            buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd].dup;
        } else {
            buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd];
        }

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

        // TODO: overlap detection to avoid using the tmp
        long charsToCopy = min(count, gapStart);
        long newGapStart = gapStart - charsToCopy;
        long newGapEnd = gapEnd - charsToCopy;

        // TODO: test if this gives any real speed over always doing the dup
        if (overlaps(newGapEnd, gapEnd, newGapStart, gapStart)) {
            buffer[newGapEnd .. gapEnd] = buffer[newGapStart..gapStart].dup;
        } else {
            buffer[newGapEnd .. gapEnd] = buffer[newGapStart..gapStart];
        }

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

    // TODO: support increasing the gap size on every reallocation
    /**
     * Adds text, moving the cursor to the end of the new text. Could cause
     * a reallocation of the buffer.
     * Params:
     *     text = text to add.
     */
    public void addText(string text)
    {
        auto arrayText = asArray(text);
        if (arrayText.length >= currentGapSize) {
            // doesnt fill in the gap, reallocate the buffer adding the text
            reallocate(text);
        } else {
            auto newGapStart = gapStart + arrayText.length;
            buffer[gapStart..newGapStart] = arrayText;
            gapStart = newGapStart;
        }
    }

    // Reallocates the buffer, creating a new gap of the configured size.
    // If the textToAdd parameter is used it will be added just before the start of
    // the new gap. This is useful to do less copy operations since usually you
    // want to reallocate the buffer because you want to insert a new text that
    // if to big for the gap.
    // Params:
    //  textToAdd: when reallocating, add this text before/after the gap (or cursor)
    //      depending on the textDir parameter.
    public void reallocate(string textToAdd="", bool forceRecreateGap=false)
    {
        if (textToAdd == null) {
            textToAdd = "";
        }

        auto charText = asArray(textToAdd);
        immutable oldContentAfterGapLen = contentAfterGap.length;
        auto newbuffer = buffer[0..contentBeforeGap.length] ~ 
                         charText ~
                         replicate(['-'], initialGapSize) ~
                         contentAfterGap;
        buffer = newbuffer;
        gapStart += charText.length;
        gapEnd = buffer.length - oldContentAfterGapLen;
    }
}