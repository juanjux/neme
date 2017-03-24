module gapbuffer;

import std.algorithm.comparison : max, min;
import std.algorithm: copy;
import std.array : appender, insertInPlace, join, minimallyInitializedArray;
import std.container.array : Array;
import std.conv;
import std.exception: assertNotThrown, assertThrown, enforce;
import std.stdio;
import std.traits;
import std.uni: normalize, NFC;
import std.utf;

debug {
    import std.array: replicate;
}

// TODO: implement opApply and opApplyReverse

// TODO: implement other range interfaces

// TODO: unittest that normalize and asArray is working (with composed chars)

// TODO: add a demo mode (you type but the buffer representation is shown in
//       real time as you type or move the cursor)

// TODO: line number cache in the data structure

// TODO: benchmark against implementations in other languages

// TODO: explicit attributes, safe, nothrow, pure, etc

// TODO: add a "fastclear()": if buffer.length > newText, without reallocation. This will
// overwrite the start with the new text and then extend the gap from the end of
// the new text to the end of the buffer


/**
 * Struct user as Gap Buffer. It uses dchar (UTF32) characters internally for easier and
 * probably faster dealing with unicode chars since 1 dchar = 1 unicode char and slices are just direct indexes
 * without having to use libraries to get the indices of code points.
 * Params:
 * The template parameter StringT is only used for the text passed to the constructor since internally dchar
 * will be used
 * XXX remove the StringT param, the user just have to convert to dchar
 */
struct GapBuffer(StringT=string)
    if(is(StringT == string) || is(StringT == wstring) || is(StringT == dstring))
{
public:
    /// Counter of reallocations done sync the struct was created to make room for
    /// text bigger than currentGapSize().
    ulong reallocCount;
    /// Counter the times the gap have been extended.
    ulong gapExtensionCount;


private:
    dchar[] buffer = null;
    ulong gapStart;
    ulong gapEnd;
    ulong _configuredGapSize;

    // TODO: increase gap size to something bigger
    /// Constructor that takes a StringT as the inital contents
    public this(StringT text, ulong gapSize = 100)
    {
        enforce(gapSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = gapSize;

        clear(text, false);
    }

        @system unittest
        {
            /// test null
            GapBuffer("", 0).assertThrown;
            GapBuffer("", 1).assertThrown;
        }
        @system unittest
        {
            GapBuffer gb;
            assertNotThrown(gb = GapBuffer("", 1000_000));
        }
        ///
        @system unittest
        {
            auto gb = GapBuffer("", 2);
            assert(gb.buffer != null);
            assert(gb.buffer.length == 2);
        }
        @system unittest
       {
            auto gb = GapBuffer("", 2);
            assert(gb.buffer.length == 2);
            assert(gb.content.to!string == "");
            assert(gb.content.length == 0);
            assert(gb.contentAfterGap.length == 0);
            assert(gb.reallocCount == 0);
        }
        ///
        @system unittest
        {
            string text = "init with text";
            auto gb = GapBuffer(text.to!StringT, 2);
            assert(gb.content.to!string == text);
            assert(gb.contentBeforeGap.length == 0);
            assert(gb.contentAfterGap.to!string == text);
            assert(gb.reallocCount == 0);
        }


    pragma(inline)
    private dchar[] asArray(StrT = string)(StrT str)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        return normalize!NFC(to!(dchar[])(str));
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
            return new dchar[](actualGapSize);
        }
    }


    /** Print the raw contents of the buffer and a guide line below with the
     *  position of the start and end positions of the gap
     */
    public void debugContent()
    {
        writeln("gapstart: ", gapStart, " gapend: ", gapEnd, " len: ", buffer.length,
                " currentGapSize: ", currentGapSize, " configuredGapSize: ", configuredGapSize);
        writeln("BeforeGap:|", contentBeforeGap,"|");
        writeln("AfterGap:|", contentAfterGap, "|");
        writeln("Text content:|", content, "|");
        writeln("Full buffer:");
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
     * Retrieve all the contents of the buffer. Unlike contentBeforeGap
     * and contentAfterGap the returned array will be newly instantiated, so
     * this method will be slower than the other two.
     *
     * Returns: The content of the buffer, as dchar.
     */
    pragma(inline)
    @property public const(dchar[]) content() const
    {
        return contentBeforeGap ~ contentAfterGap;
    }

    /**
     * Retrieve the textual content of the buffer until the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    pragma(inline)
    @property public const(dchar[]) contentBeforeGap() const
    {
        return buffer[0..gapStart];
    }

    /**
     * Retrieve the textual content of the buffer after the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    pragma(inline)
    @property public const(dchar[]) contentAfterGap() const
    {
        return buffer[gapEnd .. $];
    }

        ///
        @system unittest
        {
            // Check that the slice returned by contentBeforeGap/AfterGap points to the same
            // memory positions as the original with not copying involved
            auto gb = GapBuffer("polompos", 5);
            gb.cursorForward(3);
            auto before = gb.contentBeforeGap;
            assert(&before[0] == &gb.buffer[0]);
            assert(&before[$-1] == &gb.buffer[gb.gapStart-1]);

            auto after = gb.contentAfterGap;
            assert(&after[0] == &gb.buffer[gb.gapEnd]);
            assert(&after[$-1] == &gb.buffer[$-1]);
        }

        ///
        @system unittest
        {
            string text = "initial text";
            auto gb = GapBuffer(text.to!StringT);
            gb.cursorForward(7);
            assert(gb.content.to!string == text);
            assert(gb.contentBeforeGap == "initial");
            assert(gb.contentAfterGap == " text");
            gb.addText(" inserted stuff");
            assert(gb.reallocCount == 0);
            assert(gb.content.to!string == "initial inserted stuff text");
            assert(gb.contentBeforeGap == "initial inserted stuff");
            assert(gb.contentAfterGap == " text");
        }

        @system unittest
        {
            string text = "¡Hola mundo en España!";
            auto gb = GapBuffer(text.to!StringT);
            assert(gb.content.to!string == text);
            assert(to!dstring(gb.content).length == 22);
            assert(to!string(gb.content).length == 24);

            gb.cursorForward(1);
            assert(gb.contentBeforeGap == "¡");

            gb.cursorForward(4);
            assert(gb.contentBeforeGap == "¡Hola");
            assert(gb.content.to!string == text);
            assert(gb.contentAfterGap == " mundo en España!");

            gb.addText(" más cosas");
            assert(gb.reallocCount == 0);
            assert(gb.content.to!string == "¡Hola más cosas mundo en España!");
            assert(gb.contentBeforeGap == "¡Hola más cosas");
            assert(gb.contentAfterGap == " mundo en España!");
        }


    pragma(inline)
    @property private ulong currentGapSize() const
    {
        //return buffer.length - contentBeforeGap.length - contentAfterGap.length;
        return gapEnd - gapStart;
    }

    /**
     * This property will hold the value of the currently configured gap size.
     * Please note that this is the initial value at creation of reallocation
     * time but it can grow or shrink during the operation of the buffer.
     * Returns:
     *     The configured gap size.
     */
    pragma(inline)
    @property public ulong configuredGapSize() const
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
        reallocate();
    }
        @system unittest
        {
            auto gb = GapBuffer("", 50);
            assert(gb.configuredGapSize == 50);
            assert(gb.currentGapSize == gb.configuredGapSize);
            string newtext = "Some text to delete";
            gb.addText(newtext);

            // New text if written on the gap so its size should be reduced
            assert(gb.currentGapSize == gb.configuredGapSize - newtext.length);
            assert(gb.reallocCount == 0);
        }
        @system unittest
        {
            auto gb = GapBuffer("Some text to delete", 50);
            // Deleting should recover space from the gap
            immutable prevCurSize = gb.currentGapSize;
            gb.deleteRight(10);
            assert(gb.currentGapSize == prevCurSize + 10);
            assert(gb.content.to!string == "to delete");
            assert(gb.reallocCount == 0);
        }
        @system unittest
        {
            auto gb = GapBuffer!string("123");
            gb.deleteRight(3);
            assert(gb.contentLength == 0);
        }
        @system unittest
        {
            // Same to the left, if we move the cursor to the left of the text to delete
            auto gb = GapBuffer("Some text to delete", 50);
            immutable prevCurSize = gb.currentGapSize;
            gb.cursorForward(10);
            gb.deleteLeft(10);
            assert(gb.currentGapSize == prevCurSize + 10);
            assert(gb.content.to!string == "to delete");
            assert(gb.reallocCount == 0);
        }
        ///
        @system unittest
        {
            // Reassign to configuredGapSize. Should reallocate.
            auto gb = GapBuffer("Some text", 50);
            gb.cursorForward(5);
            assert(gb.contentBeforeGap == "Some ");
            assert(gb.contentAfterGap == "text");
            immutable prevBufferLen = gb.buffer.length;

            gb.configuredGapSize = 100;
            assert(gb.reallocCount == 1);
            assert(gb.buffer.length == prevBufferLen + 50);
            assert(gb.currentGapSize == 100);
            assert(gb.content.to!string == "Some text");
            assert(gb.contentBeforeGap == "Some ");
            assert(gb.contentAfterGap == "text");
        }

    /// "this.content" does a conversion so this is faster than
    /// this.content.length
    pragma(inline)
    @property public ulong contentLength() const
    {
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
        enforce(pos >= 0 && pos < contentLength + 1);
        if (cursorPos > pos) {
            cursorBackward(cursorPos - pos);
        } else {
            cursorForward(pos - cursorPos);
        }
    }

        ///
        @system unittest
        {
            string text = "1234567890";
            auto gb = GapBuffer(text.to!StringT);
            assert(gb.contentLength == 10);
            assert(gb.cursorPos == 0);
            assert(gb.contentAfterGap.to!string == text);

            gb.cursorPos = 5;
            assert(gb.contentLength == 10);
            assert(gb.cursorPos == 5);
            assert(gb.contentBeforeGap == "12345");
            assert(gb.contentAfterGap == "67890");

            gb.cursorPos(10_000).assertThrown;
            gb.cursorPos(-10_000).assertThrown;

            gb.cursorPos(0);
            assert(gb.cursorPos == 0);
            assert(gb.contentAfterGap.to!string == text);
        }

    public void cursorForward(ulong count)
    {

        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        immutable charsToCopy = min(count, buffer.length - gapEnd);
        immutable newGapStart = gapStart + charsToCopy;
        immutable newGapEnd = gapEnd + charsToCopy;

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

        immutable charsToCopy = min(count, gapStart);
        immutable newGapStart = gapStart - charsToCopy;
        immutable newGapEnd = gapEnd - charsToCopy;

        buffer[newGapStart..gapStart].copy(buffer[newGapEnd..gapEnd]);
        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

        ///
        @system unittest
        {
            string text = "Some initial text";
            auto gb = GapBuffer(text.to!StringT);
            auto gb2 = GapBuffer(text.to!StringT);
            auto gb3 = GapBuffer(text.to!StringT);
            assert(gb.cursorPos == 0);

            gb.cursorForward(5);
            assert(gb.cursorPos == 5);
            assert(gb.contentBeforeGap == "Some ");
            assert(gb.contentAfterGap == "initial text");

            gb.cursorForward(10_000);
            assert(gb.cursorPos == text.length);

            gb.cursorBackward(4);
            assert(gb.cursorPos == gb.content.length - 4);
            assert(gb.contentBeforeGap == "Some initial ");
            assert(gb.contentAfterGap == "text");

            immutable prevCurPos = gb.cursorPos;
            gb.cursorForward(0);

            assert(gb.cursorPos == prevCurPos);
        }

    /**
     * Delete count chars to the left of the cursor position, moving the gap (and the cursor) back
     * (typically the effect of the backspace key).
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
      * Delete count chars to the right of the cursor position, moving the end of the gap to the right,
      * keeping the cursor at the same position
      *  (typically the effect of the del key).
      *
      * Params:
      *     count = the number of chars to delete.
      */
    public void deleteRight(ulong count)
    {
        if (buffer.length == 0 || gapEnd == buffer.length)
            return;

        gapEnd = min(gapEnd + count, buffer.length);
    }

    /**
     * Adds text, moving the cursor to the end of the new text. Could cause
     * a reallocation of the buffer.
     * Params:
     *     text = text to add.
     */
    public void addText(dchar[] text)
    {
        if (text.length >= currentGapSize) {
            // doesnt fill in the gap, reallocate the buffer adding the text
            reallocate(text);
        } else {
            auto newGapStart = gapStart + text.length;
            text.copy(buffer[gapStart..newGapStart]);
            gapStart = newGapStart;
        }
    }

    pragma(inline)
    public void addText(StrT=string)(StrT text)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        addText(asArray(text));
    }
        @system unittest
        {
            auto gb = GapBuffer("", 100);
            string text = "some added text";
            immutable prevGapStart = gb.gapStart;
            immutable prevGapEnd = gb.gapEnd;

            gb.addText(text);
            assert(gb.content.to!string == "some added text");
            assert(gb.contentAfterGap == "");
            assert(gb.contentBeforeGap == "some added text");
            assert(gb.reallocCount == 0);
            assert(gb.gapStart == prevGapStart + text.length);
            assert(gb.gapEnd == prevGapEnd);
        }
        @system unittest
        {
            auto gb = GapBuffer("", 10);
            immutable prevGapStart = gb.gapStart;
            immutable prevGapEnd = gb.gapEnd;

            // text is bigger than gap size so it should reallocate
            string text = "some added text";
            gb.addText(text);
            assert(gb.reallocCount == 1);
            assert(gb.content.to!string == text);
            assert(gb.gapStart == prevGapStart + text.length);
            assert(gb.gapEnd == prevGapEnd + text.length);
        }
        @system unittest
        {
            auto gb = GapBuffer("", 10);
            immutable prevGapStart = gb.gapStart;
            immutable prevGapEnd = gb.gapEnd;
            immutable prevBufferSize = gb.buffer.length;

            assertNotThrown(gb.addText(""));
            assert(prevBufferSize == gb.buffer.length);
            assert(prevGapStart == gb.gapStart);
            assert(prevGapEnd == gb.gapEnd);
        }


    /**
     * Removes all pre-existing text from the buffer. You can also pass a
     * string to add new text after the previous ones has cleared (for example,
     * for the typical pasting with all the text preselected). This is
     * more efficient than clearing and then calling addText with the new
     * text
     */
    public void clear(dchar[] text=null, bool moveToEndEnd=true)
    {
        if (moveToEndEnd) {
            buffer = text ~ createNewGap();
            gapStart = text.length;
            gapEnd = buffer.length;
        } else {
            buffer = createNewGap() ~ text;
            gapStart = 0;
            gapEnd = _configuredGapSize;
        }
    }

    pragma(inline)
    public void clear(StrT=string)(StrT text="", bool moveToEndEnd=true)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        clear(asArray(text), moveToEndEnd);
    }

        /// clear without text
        @system unittest
        {
            auto gb = GapBuffer("Some initial text", 10);
            gb.clear();

            assert(gb.buffer.length == gb.configuredGapSize);
            assert(gb.content.to!string == "");
            assert(gb.content.length == 0);
            assert(gb.gapStart == 0);
            assert(gb.gapEnd == gb.configuredGapSize);
        }

        /// clear with some text, moving to the end
        @system unittest
        {
            auto gb = GapBuffer("Some initial text", 10);
            auto newText = "some replacing stuff";
            gb.clear(newText, true);

            assert(gb.buffer.length == (gb.configuredGapSize + newText.length));
            assert(gb.content.length == newText.length);
            assert(gb.content.to!string == newText);
            assert(gb.cursorPos == newText.length);
            assert(gb.gapStart == newText.length);
            assert(gb.gapEnd == gb.buffer.length);
        }

        /// clear with some text, moving to the start
        @system unittest
        {
            auto gb = GapBuffer("Some initial text", 10);
            auto newText = "some replacing stuff";
            gb.clear(newText, false);

            assert(gb.buffer.length == (gb.configuredGapSize + newText.length));
            assert(gb.content.length == newText.length);
            assert(gb.content.to!string == newText);
            assert(gb.cursorPos == 0);
            assert(gb.gapStart == 0);
            // check that the text was written from the start and not using addtext
            assert(gb.gapEnd == gb.configuredGapSize);
        }

    // Reallocates the buffer, creating a new gap of the configured size.
    // If the textToAdd parameter is used it will be added just before the start of
    // the new gap. This is useful to do less copy operations since usually you
    // want to reallocate the buffer because you want to insert a new text that
    // if to big for the gap.
    // Params:
    //  textToAdd: when reallocating, add this text before/after the gap (or cursor)
    //      depending on the textDir parameter.

    private void reallocate(dchar[] textToAdd=null)
    {
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

        buffer.insertInPlace(gapStart, textToAdd, gapExtension);
        gapStart += textToAdd.length;
        gapEnd = buffer.length - oldContentAfterGapLen;
        reallocCount += 1;
    }

    pragma(inline)
    private void reallocate(StrT=string)(StrT textToAdd)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        reallocate(asArray(textToAdd));
    }
        @system unittest
        {
            auto gb = GapBuffer("Some text");
            gb.cursorForward(5);
            immutable prevGapSize = gb.currentGapSize;
            immutable prevGapStart = gb.gapStart;
            immutable prevGapEnd = gb.gapEnd;

            gb.reallocate();
            assert(gb.reallocCount == 1);
            assert(gb.currentGapSize == prevGapSize);
            assert(prevGapStart == gb.gapStart);
            assert(prevGapEnd == gb.gapEnd);
        }
        @system unittest
        {
            auto gb = GapBuffer("Some text");
            gb.cursorForward(4);

            immutable prevGapSize = gb.currentGapSize;
            immutable prevBufferLen = gb.buffer.length;
            immutable prevGapStart = gb.gapStart;
            immutable prevGapEnd = gb.gapEnd;

            string newtext = " and some new text";
            gb.reallocate(" and some new text");
            assert(gb.reallocCount == 1);
            assert(gb.buffer.length == prevBufferLen + newtext.length);
            assert(gb.currentGapSize == prevGapSize);
            assert(gb.content.to!string == "Some and some new text text");
            assert(gb.gapStart == prevGapStart + newtext.length);
            assert(gb.gapEnd == prevGapEnd + newtext.length);
        }

    // Convert an index to the content to a real index in the buffer
    pragma(inline)
    private const(ulong) contentIdx2BufferIdx(ulong idx) const
    {
        if (idx >= gapStart) {
            return idx + currentGapSize;
        }
        // else: before the gap, direct translation
        return idx;
    }

        @system unittest
        {
            auto gapSize = 10;
            auto initialText = "Some initial content";
            auto gb = GapBuffer!string(initialText, gapSize);
            // new text is always at the end so all operations will need gapSize
            assert(gb.contentIdx2BufferIdx(0) == 0 + gapSize);
            assert(gb.contentIdx2BufferIdx(5) == 5 + gapSize);
            assert(gb.contentIdx2BufferIdx(initialText.length) == initialText.length + gapSize);

            // move the cursor back to the first word
            gb.cursorPos = 4;
            assert(gb.contentBeforeGap == "Some");
            assert(gb.contentIdx2BufferIdx(0) == 0);
            assert(gb.contentIdx2BufferIdx(3) == 3);
            assert(gb.contentIdx2BufferIdx(4) == 4 + gapSize);
        }

    // Index ([]) overloading methods
    alias opDollar = contentLength;

    /**
     * index operator assignment: gapBuffer[2] = 'x';
     */
    pragma(inline)
    public dchar opIndexAssign(dchar value, ulong idx)
    {
        buffer[contentIdx2BufferIdx(idx)] = value;
        return value;
    }

        @system unittest
        {
            auto gb = GapBuffer!string("012345");
            gb[0] = 'a';
            gb[5] = 'z';
            assert(gb.content[0] == 'a');
            assert(gb.content[5] == 'z');
        }

    /**
     * index operator read: auto x = gapBuffer[0..3]
     */
    pragma(inline)
    public const(dchar[]) opSlice(ulong start, ulong end) const
    {
        return content[start..end];
    }
    @system unittest
    {
        auto gb = GapBuffer!string("polompos");
        assert(gb[0..2] == "po");
        assert(gb[0..$] == "polompos");
    }


    /**
     * index operator read: auto x = gapBuffer[]
     */
    pragma(inline)
    public const(dchar[]) opSlice() const
    {
        return opSlice(0, contentLength);
    }

        @system unittest
        {
            auto gb = GapBuffer!string("polompos");
            assert(gb[] == "polompos");
            assert(gb.content == "polompos");
        }

    /**
     * index operator assignment: gapBuffer[] = "some string" (replaces all);
     */
    pragma(inline)
    public ref GapBuffer opIndexAssign(dchar[] value)
    {
        clear(value);
        return this;
    }

    pragma(inline)
    public ref GapBuffer opIndexAssign(StrT=string)(StrT value)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        return opIndexAssign(asArray(value));
    }

        @system unittest
        {
            auto gb = GapBuffer!string("polompos");
            gb[] = "pokompos";
            assert(gb.content == "pokompos");
        }

    // input range interface methods
    pragma(inline)
    @property public bool empty() const
    {
        return !contentAfterGap.length;
    }

        @system unittest
        {
            auto gb = GapBuffer();
            assert(gb.empty);
            gb.addText("polompos");
            gb.cursorPos = 0;
            assert(!gb.empty);

            auto gb2 = GapBuffer!string("pokompos");
            gb2.cursorPos = gb2.contentLength;
            assert(gb2.empty);
        }

    /**
     * Implements the front range interface. For the GapBuffer
     * the front() is considered to be the cursor position, NOT
     * the first textual content
     */
    @property public ref dchar front()
    {
        assert(contentLength > 0,
                "Attempt to fetch the front with the cursor at the end of the gapbuffer");
        assert(contentAfterGap.length > 0,
                "Attempt to fetch the front with the cursor at the end of the gapbuffer");
        return buffer[gapEnd];
    }
        @system unittest
        {
            auto gb = GapBuffer!string("Polompos");
            assert(gb.front == 'P');
            gb.cursorForward(1);
            assert(gb.front == 'o');
            gb.cursorForward(1000);
            // gb.front; // AssertionError
            gb.addText(" pok");
            gb.cursorBackward(1);
            assert(gb.front == 'k');
            gb.cursorPos = 0;
            assert(gb.front == 'P');
        }


    /**
     * Implements the popFront range interface. This will delete the character to the
     * right of the cursor. This will not delete any character to the left of the cursor.
     */
    @property public void popFront()
    {
        assert(contentLength > 0,
                "Attempt to popFront with the cursor at the end of the gapbuffer");
        deleteRight(1);
    }

        @system unittest
        {
            auto gb = GapBuffer!string("Polompos");
            auto clen = gb.contentLength;

            assert(gb.front == 'P');
            gb.popFront;
            clen--;
            assert(gb.front == 'o');
            assert(clen == gb.contentLength);

            gb.popFront;
            clen--;
            assert(gb.front == 'l');
            assert(clen == gb.contentLength);

            gb.cursorForward(1);
            gb.popFront;
            clen--;
            assert(gb.front == 'm');
            assert(clen == gb.contentLength);
        }

        /// test the InputRange interface
        @system unittest
        {
            auto text = "Some initial text";
            auto gb = GapBuffer!string(text);

            auto idx = 0;
            // Using a normal for because foreach would call opApply that we also implement
            for(auto r = gb; !r.empty; r.popFront) {
                auto e = r.front;
                assert(e == text[idx]);
                idx++;
            }
        }
}

// This must be outside of the template-struct. If tests inside the GapBuffer
// runs several times is because of this
@system unittest
{
    string text = "init with text ñáñáñá";
    wstring wtext = "init with text ñáñáñá";
    dstring dtext = "init with text ñáñáñá";
    auto gb8 = GapBuffer!string(text);
    auto gb16 = GapBuffer!wstring(wtext);
    auto gb32 = GapBuffer!dstring(dtext);

    assert(gb8.contentLength == gb32.contentLength);
    assert(gb8.contentLength == gb16.contentLength);
    assert(gb8.content == gb32.content);
    assert(gb8.content == gb16.content);
    assert(gb8.content.to!string.length == 27);
    assert(gb8.content.to!wstring.length == 21);
    assert(gb8.content.to!dstring.length == gb32.content.to!dstring.length);
}
