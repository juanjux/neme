module gapbuffer;

import std.algorithm: copy;
import std.algorithm.comparison : max, min;
import std.array : appender, insertInPlace, join, minimallyInitializedArray;
import std.container.array : Array;
import std.conv;
import std.exception: assertNotThrown, assertThrown, enforce;
import std.stdio;
import std.traits;

debug {
    import std.array: replicate;
}

// FIXME: Make it work with unicode codepoints:
//        std.utf.count to get the length,
//        std.uni.normalize(NFC) to make sure code points are not composed from several
// TODO: ref parameters/ returns?
// TODO: Implement the range interface(s)
// TODO: attributes, safe, nothrow, pure, etc
// TODO: add a demo mode (you type but the buffer representation is shown in
//       real time as you type or move the cursor)
// TODO: Shortcuts for deletion, insertion and replacement methods that doesn't move the cursor until
//       after the operation is done (if needed) avoiding unnecesary copying
// TODO: .clear() (just extend the gap to both extremes of the array)
// TODO: line number cache in the data structure
// TODO: benchmark against implementations in other languages!
// TODO: test with utf8 chars


/// Struct user as Gap Buffer
struct GapBuffer (StringT = string)
    if (
        // StringT is used for parameters and return values that we want to be immutable so isSomeString
        // doesnt server since it allows for mutables
        (is(StringT == string) || is(StringT == wstring) || is(StringT == dstring))
    )
{
public:
    /// Counter of reallocations done sync the struct was created to make room for
    /// text bigger than currentGapSize().
    ulong reallocCount;
    /// Counter the times the gap have been extended.
    ulong gapExtensionCount;

private:
    alias asArray = to!(dchar[]);

    dchar[] buffer = null;
    ulong gapStart;
    ulong gapEnd;
    ulong _configuredGapSize;

    // TODO: increase gap size to something bigger
    /// Constructor that takes a StringT as the inital contents
    public this(StringT text, ulong gapSize = 100)
    {
        enforce(gapSize > 1, "Minimum gap size must be greater than 1");

        if (text == null) {
            text = "";
        }

        _configuredGapSize = gapSize;
        // ARRAYOP: CONCATENATION
        buffer = createNewGap ~ asArray(text);
        //libArray = Array!dchar(asArray(text));
        gapStart = 0;
        gapEnd = _configuredGapSize;
    }
        @system unittest
        {
            /// test null
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
            StringT text = "init with text";
            scope gb = GapBuffer(text, 2);
            assert(gb.content == text);
            assert(gb.contentBeforeGap.length == 0);
            assert(gb.contentAfterCursor == text);
            assert(gb.reallocCount == 0);
        }

    pragma(inline)
    dchar[] createNewGap(ulong gapSize=0)
    {
        ulong actualGapSize = gapSize? gapSize: configuredGapSize;

        debug
        {
            return replicate(['-'.to!dchar], actualGapSize);
        }
        else
        {
            return new dchar[actualGapSize];
        }
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
        writeln(contentAfterCursor);
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
     * Returns: The content of the buffer, as StringT.
     */
    pragma(inline)
    @property public StringT content()
    {
        return to!StringT(contentBeforeGap ~ contentAfterGap);
    }

    pragma(inline)
    @property private dchar[] contentBeforeGap()
    {
        return buffer[0..gapStart];
    }

    /**
     * Returns the contents from the start of the file until the current
     * cursor position.
     * Returns:
     *     Text as StringT
     */
    pragma(inline)
    @property public StringT contentBeforeCursor()
    {
        return to!StringT(contentBeforeGap);
    }

    pragma(inline)
    @property private dchar[] contentAfterGap()
    {
        return buffer[gapEnd .. $];
    }

    /**
     * Returns the contents from the cursor position until the end of the file
     * Returns:
     *     Text as StringT
     */
    pragma(inline)
    @property public StringT contentAfterCursor()
    {
        return to!StringT(contentAfterGap);
    }

        ///
        @system unittest
        {
            StringT text = "initial text";
            scope gb = GapBuffer(text);
            gb.cursorForward(7);
            assert(gb.content == text);
            assert(gb.contentBeforeCursor == "initial");
            assert(gb.contentAfterCursor == " text");
            gb.addText(" inserted stuff");
            assert(gb.reallocCount == 0);
            assert(gb.content == "initial inserted stuff text");
            assert(gb.contentBeforeCursor == "initial inserted stuff");
            assert(gb.contentAfterCursor == " text");
        }

    @system unittest
    {
        StringT text = "¡Hola mundo! Aquí estamos en España!";
        scope gb = GapBuffer(text);
        assert(gb.content == text);
        gb.cursorForward(1);
        gb.debugContent;
        gb.cursorForward(4);
        gb.debugContent;
        //assert(gb.content == text);
        //assert(gb.contentBeforeCursor == "initial");
        //assert(gb.contentAfterCursor == " text");
        //gb.addText(" inserted stuff");
        //assert(gb.reallocCount == 0);
        //assert(gb.content == "initial inserted stuff text");
        //assert(gb.contentBeforeCursor == "initial inserted stuff");
        //assert(gb.contentAfterCursor == " text");

    }


    pragma(inline)
    @property private ulong currentGapSize()
    {
        return buffer.length - contentBeforeGap.length - contentAfterGap.length;
    }

    /**
     * This property will hold the value of the currently configured gap size.
     * Please note that this is the initial value at creation of reallocation
     * time but it can grow or shrink during the operation of the buffer.
     * Returns:
     *     The configured gap size.
     */
    pragma(inline)
    @property public ulong configuredGapSize()
    {
        return _configuredGapSize;
    }

    /**
     * Asigning to this property will change the gap size that will be used
     * at creation and reallocation time and will cause a reallocation to
     * generate a buffer with the new gap.
     */
    pragma(inline)
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
            StringT newtext = "Some text to delete";
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
            assert(gb.contentAfterCursor == "text");
            auto prevBufferLen = gb.buffer.length;

            gb.configuredGapSize = 100;
            assert(gb.reallocCount == 1);
            assert(gb.buffer.length == prevBufferLen + 50);
            assert(gb.currentGapSize == 100);
            assert(gb.content == "Some text");
            assert(gb.contentBeforeCursor == "Some ");
            assert(gb.contentAfterCursor == "text");
        }

    pragma(inline)
    @property public ulong contentLength()
    {
        // "this.content" does a conversion so this is faster than
        // this.content.length
        return contentBeforeGap.length + contentAfterGap.length;
    }

    /**
     * Returns the cursor position (the gapStart)
     */
    pragma(inline)
    @property public ulong cursorPos() const
    {
        return gapStart;
    }

    /**
     * Sets the cursor position. The position is relative to
     * the text and ignores the gap
     */
    pragma(inline)
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
            StringT text = "1234567890";
            scope gb = GapBuffer(text);
            assert(gb.contentLength == 10);
            assert(gb.cursorPos == 0);
            assert(gb.contentAfterCursor == text);

            gb.cursorPos = 5;
            assert(gb.contentLength == 10);
            assert(gb.cursorPos == 5);
            assert(gb.contentBeforeCursor == "12345");
            assert(gb.contentAfterCursor == "67890");

            gb.cursorPos(10000).assertThrown;
            gb.cursorPos(-10000).assertThrown;

            gb.cursorPos(0);
            assert(gb.cursorPos == 0);
            assert(gb.contentAfterCursor == text);
        }

    public void cursorForward(ulong count)
    {

        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        // TODO: test if this gives any real speed over always doing the dup
        ulong charsToCopy = min(count, buffer.length - gapEnd);
        ulong newGapStart = gapStart + charsToCopy;
        ulong newGapEnd = gapEnd + charsToCopy;

        buffer[gapEnd..newGapEnd].copy(buffer[gapStart..newGapStart]);
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

        buffer[newGapStart..gapStart].copy(buffer[newGapEnd..gapEnd]);
        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

        ///
        unittest
        {
            StringT text = "Some initial text";
            scope gb = GapBuffer(text);
            scope gb2 = GapBuffer(text);
            scope gb3 = GapBuffer(text);
            assert(gb.cursorPos == 0);

            gb.cursorForward(5);
            assert(gb.cursorPos == 5);
            assert(gb.contentBeforeCursor == "Some ");
            assert(gb.contentAfterCursor == "initial text");

            gb.cursorForward(10_000);
            assert(gb.cursorPos == text.length);

            gb.cursorBackward(4);
            assert(gb.cursorPos == gb.content.length - 4);
            assert(gb.contentBeforeCursor == "Some initial ");
            assert(gb.contentAfterCursor == "text");

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
    public void addText(StringT text)
    {
        immutable arrayText = asArray(text);
        if (arrayText.length >= currentGapSize) {
            // doesnt fill in the gap, reallocate the buffer adding the text
            reallocate(text);
        } else {
            auto newGapStart = gapStart + arrayText.length;
            arrayText.copy(buffer[gapStart..newGapStart]);
            gapStart = newGapStart;
        }
    }
        @system unittest
        {
            scope gb = GapBuffer("", 100);
            StringT text = "some added text";
            auto prevGapStart = gb.gapStart;
            auto prevGapEnd = gb.gapEnd;

            gb.addText(text);
            assert(gb.content == "some added text");
            assert(gb.contentAfterCursor == "");
            assert(gb.contentBeforeCursor == "some added text");
            assert(gb.reallocCount == 0);
            assert(gb.gapStart == prevGapStart + text.length);
            assert(gb.gapEnd == prevGapEnd);
        }
        @system unittest
        {
            scope gb = GapBuffer("", 10);
            auto prevGapStart = gb.gapStart;
            auto prevGapEnd = gb.gapEnd;

            // text is bigger than gap size so it should reallocate
            StringT text = "some added text";
            gb.addText(text);
            assert(gb.reallocCount == 1);
            assert(gb.content == text);
            assert(gb.gapStart == prevGapStart + text.length);
            assert(gb.gapEnd == prevGapEnd + text.length);
        }
        @system unittest
        {
            scope gb = GapBuffer("", 10);
            auto prevGapStart = gb.gapStart;
            auto prevGapEnd = gb.gapEnd;
            auto prevBufferSize = gb.buffer.length;

            assertNotThrown(gb.addText(null));
            assert(prevBufferSize == gb.buffer.length);
            assert(prevGapStart == gb.gapStart);
            assert(prevGapEnd == gb.gapEnd);
        }

    // Reallocates the buffer, creating a new gap of the configured size.
    // If the textToAdd parameter is used it will be added just before the start of
    // the new gap. This is useful to do less copy operations since usually you
    // want to reallocate the buffer because you want to insert a new text that
    // if to big for the gap.
    // Params:
    //  textToAdd: when reallocating, add this text before/after the gap (or cursor)
    //      depending on the textDir parameter.

    public void reallocate(StringT textToAdd="")
    {
        // FIXME: make this private
        if (textToAdd == null) {
            textToAdd = "";
        }

        immutable charText = asArray(textToAdd);
        immutable oldContentAfterGapLen = contentAfterGap.length;

        // Check if the actual size of the gap is smaller than configuredSize
        // to extend the gap (and how much)
        dchar[] gapExtension;
        if (currentGapSize >= _configuredGapSize) {
            // no need to extend the gap
            gapExtension.length = 0;
            //writeln(currentGapSize, _configuredGapSize);
        } else {
            gapExtension = createNewGap(configuredGapSize - currentGapSize);
            gapExtensionCount += 1;
        }

        buffer.insertInPlace(gapStart, charText, gapExtension);
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

            StringT newtext = " and some new text";
            gb.reallocate(" and some new text");
            assert(gb.reallocCount == 1);
            assert(gb.buffer.length == prevBufferLen + newtext.length);
            assert(gb.currentGapSize == prevGapSize);
            assert(gb.content == "Some and some new text text");
            assert(gb.gapStart == prevGapStart + newtext.length);
            assert(gb.gapEnd == prevGapEnd + newtext.length);
        }
}
