module gapbuffer;

import std.algorithm.comparison : max, min;
import std.array : appender, insertInPlace, join, minimallyInitializedArray, replicate;
import std.container.array : Array;
import std.conv;
import std.exception: assertNotThrown, assertThrown, enforce;
import std.stdio;
import std.traits;
import std.typecons: Flag;

// TODO: remove the casts in the tests and elsewhere, use a generic AnyStr argument and force
// the conversion to dchar[] or dstring inside the methods
// TODO: benchmark vs UTF8 (char[] and normal string, taking in account the code points)
// TODO: Implement the range interface(s)
// TODO: text with the libArray too
// FIXME: Make it work with unicode codepoints:
//  std.utf.count to get the length,
//  std.uni.normalize(NFC) to make sure code points are not composed from several
// TODO: Make it a template AnyText
// TODO: Methods to move the cursor to the start or end, maybe with optimized copy
// TODO: attributes, safe, nothrow, pure, etc
// TODO: support optionally increasing the gap size on every reallocation
// TODO: add a demo mode (you type but the buffer representation is shown in
//       real time as you type or move the cursor)
// TODO: add public contentBeforeCursor, contentAfterCursor, contentAtPosition that call
// contentBefore/AfterGap but converting to dstring (or other immutable type) (maybe unneded
// after implemeting the range interfaces).

pragma(inline):
pure private bool overlaps(ulong destStart, ulong destEnd,
                        ulong sourceStart, ulong sourceEnd)
{
    return (destStart > sourceStart && destStart < sourceEnd) ||
            (destEnd > sourceStart && destEnd < sourceEnd);
}

unittest
{
    assert(!overlaps(1, 2, 3, 4));
    assert(!overlaps(1, 1, 2, 2));
    assert(!overlaps(0, 1, 2, 2));
    assert(overlaps(0, 4, 2, 3));
    assert(overlaps(0, 3, 2, 4));
    assert(overlaps(0, 1, 1, 3));
    assert(overlaps(0, 0, 0, 0));
}

/// Struct user as Gap Buffer
struct GapBuffer (CharT)
    if (isSomeChar!CharT)
{
    // I'll be using both until I determine what is better for
    // the editor buffer use case
public:
    ulong reallocCount;

private:
    alias asArray = to!(dchar[]);
    dchar[] buffer = null;
    Array!dchar libArray;
    ulong gapStart;
    ulong gapEnd;
    ulong _configuredGapSize;

    // TODO: increase gap size to something bigger
    /// Constructor that takes a string as the inital contents
    public this(string text, ulong gapSize = 100)
    {
        enforce(gapSize > 1, "Minimum gap size must be greater than 1");

        if (text == null) {
            text = "";
        }

        _configuredGapSize = gapSize;
        // TODO: speed test the replicate vs a simple new dchar[configuredGapSize]
        buffer = replicate(['-'.to!dchar], configuredGapSize) ~ asArray(text);
        //libArray = Array!dchar(asArray(text));
        gapStart = 0;
        gapEnd = _configuredGapSize;
    }
        @system unittest
        {
            /// test null
            scope GapBuffer gb;
            GapBuffer("", 0).assertThrown;
            GapBuffer("", 1).assertThrown;
        }
        @system unittest
        {
            scope GapBuffer gb;
            assertNotThrown(gb = GapBuffer("", 1000_000));
        }
        ///
        @system unittest
        {
            scope gb = GapBuffer("", 2);
            assert(gb.buffer != null);
            assert(gb.buffer.length == 2);
        }
        @system unittest
        {
            scope gb = GapBuffer(null, 2);
            assert(gb.buffer.length == 2);
            assert(gb.content == "");
            assert(gb.content.length == 0);
            assert(gb.contentAfterGap.length == 0);
            assert(gb.reallocCount == 0);
        }
        ///
        @system unittest
        {
            string text = "init with text";
            scope gb = GapBuffer(text, 2);
            assert(gb.content == text);
            assert(gb.contentBeforeCursor.length == 0);
            assert(gb.contentAfterGap.to!string == text);
            assert(gb.reallocCount == 0);
        }

    /** Print the raw contents of the buffer and a guide line below with the
     *  position of the start and end positions of the gap
     */
    public void debugContent()
    {
        writeln("gapstart: ", gapStart, " gapend: ", gapEnd, " len: ", buffer.length,
                " currentGapSize: ", currentGapSize, " configuredGapSize: ", configuredGapSize);
        writeln("BeforeGap: ");
        writeln(contentBeforeCursor);
        writeln("AfterGap:");
        writeln(contentAfterGap);
        writeln("Text content:");
        writeln(content);
        writeln("Full buffer: ");
        writeln(buffer);
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
        return to!string(contentBeforeCursor ~ contentAfterGap);
    }
    pragma(inline):
    @property private dchar[] contentBeforeCursor()
    {
        return buffer[0..gapStart];
    }

    pragma(inline):
    @property private dchar[] contentAfterGap()
    {
        return buffer[gapEnd .. $];
    }
        ///
        @system unittest
        {
            string text = "initial text";
            scope gb = GapBuffer(text);
            gb.cursorForward(7);
            assert(gb.content == text);
            assert(gb.contentBeforeCursor == "initial");
            assert(gb.contentAfterGap == " text");
            gb.addText(" inserted stuff");
            assert(gb.reallocCount == 0);
            assert(gb.content == "initial inserted stuff text");
            assert(gb.contentBeforeCursor == "initial inserted stuff");
            assert(gb.contentAfterGap == " text");
        }


    // TODO: keep this calculated updating the total every time there
    // is an insertion or deletion (keept this as an invariant check for the class)
    pragma(inline):
    @property private ulong currentGapSize()
    {
        return buffer.length - contentBeforeCursor.length - contentAfterGap.length;
    }
    // FIXME: rename to configuredGapSize
    pragma(inline):
    @property public ulong configuredGapSize()
    {
        return _configuredGapSize;
    }

    // FIXME: document that this will cause a reallocation
    pragma(inline):
    @property  public void configuredGapSize(ulong newSize)
    {
        enforce(newSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = newSize;
        reallocate("");
    }
        @system unittest
        {
            scope gb = GapBuffer("", 50);
            assert(gb.configuredGapSize == 50);
            assert(gb.currentGapSize == gb.configuredGapSize);
            auto newtext = "Some text to delete";
            gb.addText(newtext);

            // New text if written on the gap so its size should be reduced
            assert(gb.currentGapSize == gb.configuredGapSize - newtext.length);
            assert(gb.reallocCount == 0);
        }
        @system unittest
        {
            scope gb = GapBuffer("Some text to delete", 50);
            // Deleting should recover space from the gap
            auto prevCurSize = gb.currentGapSize;
            gb.deleteRight(10);
            assert(gb.currentGapSize == prevCurSize + 10);
            assert(gb.content == "to delete");
            assert(gb.reallocCount == 0);
        }
        @system unittest
        {
            // Same to the left, if we move the cursor to the left of the text to delete
            scope gb = GapBuffer("Some text to delete", 50);
            auto prevCurSize = gb.currentGapSize;
            gb.cursorForward(10);
            gb.deleteLeft(10);
            assert(gb.currentGapSize == prevCurSize + 10);
            assert(gb.content == "to delete");
            assert(gb.reallocCount == 0);
            // TODO: assign to configuredGapSize to force a reallocation
        }
        ///
        @system unittest
        {
            // Reassign to configuredGapSize. Should reallocate.
            scope gb = GapBuffer("Some text", 50);
            gb.cursorForward(5);
            assert(gb.contentBeforeCursor == "Some ");
            assert(gb.contentAfterGap == "text");
            auto prevBufferLen = gb.buffer.length;

            gb.configuredGapSize = 100;
            assert(gb.reallocCount == 1);
            assert(gb.buffer.length == prevBufferLen + 50);
            assert(gb.currentGapSize == 100);
            assert(gb.content == "Some text");
            assert(gb.contentBeforeCursor == "Some ");
            assert(gb.contentAfterGap == "text");
        }

    pragma(inline):
    @property public ulong contentLength()
    {
        // this.content does a conversion so this is faster than
        // this.content.length
        return contentBeforeCursor.length + contentAfterGap.length;
    }

    /**
     * Returns the cursor position (the gapStart)
     */
    pragma(inline):
    @property public ulong cursorPos() const
    {
        return gapStart;
    }

    /**
     * Sets the cursor position. The position is relative to
     * the text and ignores the gap
     */
    pragma(inline):
    @property public void cursorPos(ulong pos)
    {
        enforce(pos >= 0 && pos < contentLength);
        if (cursorPos > pos) {
            cursorBackward(cursorPos - pos);
        } else {
            cursorForward(pos - cursorPos);
        }
    }

        ///
        unittest
        {
            auto text = "1234567890";
            scope gb = GapBuffer(text);
            assert(gb.contentLength == 10);
            assert(gb.cursorPos == 0);
            assert(gb.contentAfterGap.to!string == text);

            gb.cursorPos = 5;
            assert(gb.contentLength == 10);
            assert(gb.cursorPos == 5);
            assert(gb.contentBeforeCursor == "12345");
            assert(gb.contentAfterGap.to!string == "67890");

            gb.cursorPos(10000).assertThrown;
            gb.cursorPos(-10000).assertThrown;

            gb.cursorPos(0);
            assert(gb.cursorPos == 0);
            assert(gb.contentAfterGap.to!string == text);
        }


    public void cursorForward(ulong count)
    {
        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        // TODO: test if this gives any real speed over always doing the dup
        immutable ulong charsToCopy = min(count, buffer.length - gapEnd);
        ulong newGapStart = gapStart + charsToCopy;
        ulong newGapEnd = gapEnd + charsToCopy;

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
    public void cursorBackward(ulong count)
    {
        if (count <= 0 || buffer.length == 0 || gapStart == 0)
            return;

        immutable ulong charsToCopy = min(count, gapStart);
        ulong newGapStart = gapStart - charsToCopy;
        ulong newGapEnd = gapEnd - charsToCopy;

        // TODO: test if this gives any real speed over always doing the dup
        if (overlaps(newGapEnd, gapEnd, newGapStart, gapStart)) {
            buffer[newGapEnd .. gapEnd] = buffer[newGapStart..gapStart].dup;
        } else {
            buffer[newGapEnd .. gapEnd] = buffer[newGapStart..gapStart];
        }

        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

        ///
        unittest
        {
            auto text = "Some initial text";
            scope gb = GapBuffer(text);
            assert(gb.cursorPos == 0);

            gb.cursorForward(5);
            assert(gb.cursorPos == 5);
            assert(gb.contentBeforeCursor == "Some ");
            assert(gb.contentAfterGap == "initial text");

            gb.cursorForward(10_000);
            assert(gb.cursorPos == text.length);

            gb.cursorBackward(4);
            assert(gb.cursorPos == gb.content.length - 4);
            assert(gb.contentBeforeCursor == "Some initial ");
            assert(gb.contentAfterGap == "text");

            auto prevCurPos = gb.cursorPos;
            gb.cursorForward(0);
            assert(gb.cursorPos == prevCurPos);
        }

    /**
     * Delete count chars to the left of the cursor position, moving it back (typically
     * the effect of the backspace key).
     *
     * Params:
     *     count = the numbers of chars to delete.
     */
    public void deleteLeft(ulong count)
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
    public void deleteRight(ulong count)
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
    public void addText(string text)
    {
        immutable arrayText = asArray(text);
        if (arrayText.length >= currentGapSize) {
            // doesnt fill in the gap, reallocate the buffer adding the text
            reallocate(text);
        } else {
            auto newGapStart = gapStart + arrayText.length;
            buffer[gapStart..newGapStart] = arrayText;
            gapStart = newGapStart;
        }
    }
        @system unittest
        {
            scope gb = GapBuffer("", 100);
            gb.addText("some added text");
            assert(gb.content == "some added text");
            assert(gb.contentAfterGap == "");
            assert(gb.contentBeforeCursor == "some added text");
            assert(gb.reallocCount == 0);
        }
        @system unittest
        {
            scope gb = GapBuffer("", 10);
            // text is bigger than gap size so it should reallocate
            gb.addText("some added text");
            assert(gb.reallocCount == 1);
            assert(gb.content == "some added text");
        }
        @system unittest
        {
            scope gb = GapBuffer("", 10);
            auto prevBufferSize = gb.buffer.length;
            assertNotThrown(gb.addText(null));
            assert(prevBufferSize == gb.buffer.length);
        }
        // TODO: check gapStart and gapEnd

    // Reallocates the buffer, creating a new gap of the configured size.
    // If the textToAdd parameter is used it will be added just before the start of
    // the new gap. This is useful to do less copy operations since usually you
    // want to reallocate the buffer because you want to insert a new text that
    // if to big for the gap.
    // Params:
    //  textToAdd: when reallocating, add this text before/after the gap (or cursor)
    //      depending on the textDir parameter.

    public void reallocate(string textToAdd="")
    {
        if (textToAdd == null) {
            textToAdd = "";
        }

        immutable charText = asArray(textToAdd);
        immutable oldContentAfterGapLen = contentAfterGap.length;
        // TODO: benchmark vs insertInPlace
        buffer = buffer[0..contentBeforeCursor.length] ~
                         charText ~
                         replicate(['-'.to!dchar], _configuredGapSize) ~
                         contentAfterGap;
        gapStart += charText.length;
        gapEnd = buffer.length - oldContentAfterGapLen;
        reallocCount += 1;
    }
        @system unittest
        {
            scope gb = GapBuffer("Some text");
            gb.cursorForward(5);
            auto prevGapSize = gb.currentGapSize;
            auto prevGapStart = gb.gapStart;
            auto prevGapEnd = gb.gapEnd;

            gb.reallocate("");
            assert(gb.reallocCount == 1);
            assert(gb.currentGapSize == prevGapSize);
            assert(prevGapStart == gb.gapStart);
            assert(prevGapEnd == gb.gapEnd);
        }
        @system unittest
        {
            scope gb = GapBuffer("Some text");
            gb.cursorForward(4);

            auto prevGapSize = gb.currentGapSize;
            auto prevBufferLen = gb.buffer.length;
            auto prevGapStart = gb.gapStart;
            auto prevGapEnd = gb.gapEnd;

            auto newtext = " and some new text";
            gb.reallocate(" and some new text");
            assert(gb.reallocCount == 1);
            assert(gb.buffer.length == prevBufferLen + newtext.length);
            assert(gb.currentGapSize == prevGapSize);
            assert(gb.content == "Some and some new text text");
            assert(gb.gapStart == prevGapStart + newtext.length);
            assert(gb.gapEnd == prevGapEnd + newtext.length);
        }
}
