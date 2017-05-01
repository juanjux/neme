module neme.core.gapbuffer;

import std.algorithm.comparison : max, min;
import std.algorithm: copy, count;
import std.array : appender, insertInPlace, join, minimallyInitializedArray;
import std.container.array : Array;
import std.conv;
import std.exception: assertNotThrown, assertThrown, enforce;
import std.range: take, drop, array, tail;
import std.range.primitives: popFrontExactly;
import std.stdio;
import std.traits;
import std.uni: byGrapheme, byCodePoint;
import std.utf: byDchar;

debug {
    import std.array: replicate;
}

/**
 IMPORTANT terminology in this module:

 CUnit = the internal array type, NOT grapheme or visual character
 CPoint = Code point. Usually, but not always, same as a letter. On dchar
          1 CPoint = 1 CUnit but on UTF16 and UTF8 a CPoint can be more than 1
          CUnit.
 Letter = Grapheme, a visual character, using letter because is shorter and less
          alien-sounding for any normal person.

 Also, function parameters are RawIdx when they refer to base array positions
 (code points) and GrphIdx when the indexes are given in graphemes.

 Some functions have a "fast path" that operate by chars and a "slow path" that
 operate by graphemes. The path is selected by the hasCombiningChars member that
 is updated every time text is added to the buffer to the array is reallocated
 (currently no check is done when deleting characters for performance reasons).
*/

// The detection can be done with text.byCodePoint.count == test.byGrapheme.count

// TODO: Split the fast and slow implementations, use the Proxy generator

// TODO: Benchmark emulating several different text editing sessions,
// use the benchmark to avoid regresions in performance and test stuff

// TODO: unicode mode optimization: update on changes (cursor movement, delete, add, realloc):
// grpmCursorPos, rawCursorPos
// contentBeforeGap.grpmLength
// contentAfterGap.grpmLength
// graphemesLength (gb.length)

// TODO: Add invariants to check the stuff above

// TODO: Grapheme to GP, CodeUnit to CU, CUIdx, GPIdx

// TODO: use RawIdx and GraphIdx

// TODO: add tests with combining chars

// TODO: check that I'm using const correctly

// TODO: add a demo mode (you type but the buffer representation is shown in
//       real time as you type or move the cursor)

// TODO: line number cache in the data structure

// TODO: explicit attributes, safe, nothrow, pure, @nogc, etc

// TODO: add a "fastclear()": if buffer.length > newText, without reallocation. This will
// overwrite the start with the new text and then extend the gap from the end of
// the new text to the end of the buffer

// TODO: Try to do it @nogc, use Array from stdlib, use other strings, "fast", etc?

// TODO: change the fast/slow methods to private when traits can access private members
// (if not, the Proxify mixin wont work)

/**
 * Struct user as Gap Buffer. It uses dchar (UTF32) characters internally for easier and
 * probably faster dealing with unicode chars since 1 dchar = 1 unicode char and slices are just direct indexes
 * without having to use libraries to get the indices of code points.
 */

private dchar[] asArray(StrT = string)(StrT str)
    if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring)
       || is(dchar[]) || is(wchar[]) || is(char[]))
{
    return to!(dchar[])(str);
}

/// Convenience function to get a GapBuffer from any string type
public GapBuffer gapbuffer(Str = string)(Str text="".to!Str, ulong gapSize=100)
{
    return GapBuffer(asArray(text), gapSize);
}

// For array positions
alias RawIdx = ulong;
// For grapheme positions
alias GrphIdx = ulong;

debug
{
    // unittest support functions
    // TODO: use them in the grapheme support methods in GapBuffer?

    RawIdx firstGraphemesSize(S)(S txt, GrphIdx n)
    {
        return txt.byGrapheme.take(n).byCodePoint.to!S.length;
    }

    RawIdx lastGraphemesSize(S)(S txt, GrphIdx count)
    {
        return txt.byGrapheme.tail(count).byCodePoint.to!S.length;
    }

    RawIdx graphemesSizeFrom(S)(S txt, GrphIdx from)
    {
        return txt.byGrapheme.take(from).byCodePoint.to!S.length;
    }

    S graphemeSlice(S, T = string)(S txt, GrphIdx from, T to)
    {
        RawIdx startRawIdx = txt.firstGraphemesSize(from);
        RawIdx endRawIdx;

        static if (is(T == string)) {
            if (to == "$")
                endRawIdx = txt.length;
            else
                assert(false, "String to argument for graphemeSlice must be $");
        } else {
            endRawIdx = txt.firstGraphemesSize(to);
        }
        return txt[startRawIdx..endRawIdx];
    }
}


struct GapBuffer
{
public:
    /// Counter of reallocations done sync the struct was created to make room for
    /// text bigger than currentGapSize().
    ulong reallocCount;
    /// Counter the times the gap have been extended.
    ulong gapExtensionCount;

package:
    enum Direction { Front, Back }
    dchar[] buffer = null;
    ulong gapStart;
    ulong gapEnd;
    ulong _configuredGapSize;
    bool hasCombiningChars = false;
    int XXXdeleteMe;

    // TODO: increase gap size to something bigger
    public this(dchar[] textarray, ulong gapSize = 100)
    {
        enforce(gapSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = gapSize;
        clear(textarray, false);
    }

        @system unittest
        {
            /// test null
            gapbuffer("", 0).assertThrown;
            gapbuffer("", 1).assertThrown;
        }
        @system unittest
        {
            GapBuffer gb;
            assertNotThrown(gb = gapbuffer("", 1000_000));
        }
        ///
        @system unittest
        {
            auto gb = gapbuffer("", 2);
            assert(gb.buffer != null);
            assert(gb.buffer.length == 2);
        }
        @system unittest
       {
            auto gb = gapbuffer("", 2);
            assert(gb.buffer.length == 2);
            assert(gb.content.to!string == "");
            assert(gb.content.length == 0);
            assert(gb.contentAfterGap.length == 0);
            assert(gb.reallocCount == 0);
        }
        ///
        @system unittest
        {
            dstring text = "Some initial text";
            dstring combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 2);
                assert(gb.content.to!dstring == txt);
                assert(gb.contentBeforeGap.length == 0);
                assert(gb.contentAfterGap.to!dstring == txt);
                assert(gb.reallocCount == 0);
            }
        }

    private void checkForMultibyteChars(T)(T text)
    {
        // TODO: short circuit the exit as soon as one is found
        hasCombiningChars = text.byCodePoint.count != text.byGrapheme.count;

        if (hasCombiningChars)
            rebind("slow");
        else
            rebind("fast");
    }

    public ulong fast_countGraphemes(const dchar[] slice) const
    {
        assert(!hasCombiningChars);
        return slice.length;
    }
    public ulong slow_countGraphemes(const dchar[] slice) const
    {
        writeln("XXX hasCombiningChars in slowCount: ", hasCombiningChars);
        writeln("XXX XXXdeleteMe: ", XXXdeleteMe);
        assert(hasCombiningChars);
        return slice.byGrapheme.count;
    }
    ulong delegate(const dchar[]) const countGraphemes;

    void rebind(string s)
    {
        writeln("XXX hasCombiningChars on rebind: ", hasCombiningChars);
        if (s == "slow")
            countGraphemes = &slow_countGraphemes;
        else
            countGraphemes = &fast_countGraphemes;
    }


    //public ulong countGraphemes(const dchar[] slice) const
    //{
        //// fast path
        //if (!hasCombiningChars)
            //return slice.length;
        //// slow path
        //return slice.byGrapheme.count;
    //}

        unittest
        {
            // 17 dchars, 17 graphemes
            auto str_a = "some ascii string"d;
            // 20 dchars, 17 graphemes
            auto str_c = "ññññ r̈a⃑⊥ b⃑ string"d;

            auto gba = gapbuffer(str_a);
            assert(!gba.hasCombiningChars);
            gba.cursorPos = 9999;

            auto gbc = gapbuffer(str_c);
            assert(gbc.hasCombiningChars);
            gbc.cursorPos = 9999;

            assert(gba.countGraphemes(gba.buffer[0..4]) == 4);
            assert(gbc.countGraphemes(gbc.buffer[0..4]) == 4);

            assert(gba.countGraphemes(gba.buffer[0..17]) == 17);
            assert(gbc.countGraphemes(gbc.buffer[0..20]) == 17);
        }


    // TODO: check that this doesnt go over the gap
    private RawIdx idxDiffUntilGrapheme(RawIdx idx, ulong numGraphemes, Direction dir)
    {
        if (!hasCombiningChars)
            return numGraphemes;

        // slow path
        if (numGraphemes == 0)
            return 0;

        RawIdx charCount;
        if (dir == Direction.Front) {
            charCount = buffer[idx..$].byGrapheme.take(numGraphemes).byCodePoint.count;
        } else { // Direction.Back
            charCount = buffer[0..idx].byGrapheme.tail(numGraphemes).byCodePoint.count;
        }
        return charCount;
    }

        unittest
        {
            dstring text = "Some initial text";
            dstring combtext = "r̈a⃑⊥ b⃑67890";

            auto gb = gapbuffer(text);
            auto gbc = gapbuffer(combtext);

            alias front = gb.Direction.Front;
            assert(gb.idxDiffUntilGrapheme(gb.gapEnd, 4, front) == 4);
            assert(gb.idxDiffUntilGrapheme(gb.gapEnd, gb.graphemesLength, front) == text.length);

            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd, gbc.graphemesLength, front) == combtext.length);
            assert(gbc.idxDiffUntilGrapheme(gbc.buffer.length - 4, 4, front) == 4);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd,     1, front) == 2);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 2, 1, front) == 2);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 4, 1, front) == 1);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 5, 1, front) == 1);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 6, 1, front) == 2);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 8, 1, front) == 1);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 9, 1, front) == 1);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 10, 1, front) == 1);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 11, 1, front) == 1);
            assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 12, 1, front) == 1);
        }

    dchar[] createNewGap(ulong gapSize=0)
    {
        // if a new gapsize was specified use that, else use the configured default
        ulong newGapSize = gapSize? gapSize: configuredGapSize;
        debug
        {
            return replicate(['-'.to!dchar], newGapSize);
        }
        else
        {
            return new dchar[](newGapSize);
        }
    }


    /** Print the raw contents of the buffer and a guide line below with the
     *  position of the start and end positions of the gap
     */
    public void debugContent()
    {
        writeln("gapstart: ", gapStart, " gapend: ", gapEnd, " len: ", buffer.length,
                " currentGapSize: ", currentGapSize, " configuredGapSize: ", configuredGapSize,
                " graphemesLength: ", graphemesLength);
        writeln("BeforeGap:|", contentBeforeGap,"|");
        writeln("AfterGap:|", contentAfterGap, "|");
        writeln("Text content:|", content, "|");
        writeln("Full buffer:");
        writeln(buffer);
        foreach (_; buffer[0 .. gapStart].byGrapheme)
        {
            write(" ");
        }
        write("^");
        foreach (_; buffer[gapStart .. gapEnd - 2].byGrapheme)
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
    @property public const(dchar[]) content() const
    {
        return contentBeforeGap ~ contentAfterGap;
    }

    /**
     * Retrieve the textual content of the buffer until the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    @property public const(dchar[]) contentBeforeGap() const
    {
        writeln("XXX hasCombiningChars in contentBeforeGap: ", hasCombiningChars);
        return buffer[0..gapStart];
    }

    /**
     * Retrieve the textual content of the buffer after the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    @property public const(dchar[]) contentAfterGap() const
    {
        return buffer[gapEnd .. $];
    }

        ///
        @system unittest
        {
            // Check that the slice returned by contentBeforeGap/AfterGap points to the same
            // memory positions as the original with not copying involved
            dstring text = "Some initial text";
            dstring combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 5);
                gb.cursorForward(3);
                auto before = gb.contentBeforeGap;
                assert(&before[0] == &gb.buffer[0]);
                assert(&before[$-1] == &gb.buffer[gb.gapStart-1]);

                auto after = gb.contentAfterGap;
                assert(&after[0] == &gb.buffer[gb.gapEnd]);
                assert(&after[$-1] == &gb.buffer[$-1]);
            }
        }

        ///
        @system unittest
        {
            string text = "initial text";

            auto gb = gapbuffer(text);
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
            auto gb = gapbuffer(text);
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


    // Current gap size. The returned size is the number of chartype elements
    // (NOT bytes).
    @property private ulong currentGapSize() const
    {
        return gapEnd - gapStart;
    }

    /**
     * This property will hold the value of the currently configured gap size.
     * Please note that this is the initial value at creation of reallocation
     * time but it can grow or shrink during the operation of the buffer.
     * Returns:
     *     The configured gap size.
     */
    @property public ulong configuredGapSize() const
    {
        return _configuredGapSize;
    }

    /**
     * Asigning to this property will change the gap size that will be used
     * at creation and reallocation time and will cause a reallocation to
     * generate a buffer with the new gap.
     */
    @property  public void configuredGapSize(ulong newSize)
    {
        enforce(newSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = newSize;
        reallocate();
    }
        @system unittest
        {
            dstring text = "Some initial text";
            dstring combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer("", 50);
                assert(gb.configuredGapSize == 50);
                assert(gb.currentGapSize == gb.configuredGapSize);
                gb.addText(txt);

                // New text if written on the gap so its size should be reduced
                assert(gb.currentGapSize == gb.configuredGapSize - asArray(txt).length);
                assert(gb.reallocCount == 0);
            }
        }
        @system unittest
        {
            dstring text =     "1234567890abcde";
            dstring combtext = "r̈a⃑⊥ b⃑67890abcde";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 50);
                // Deleting should recover space from the gap
                auto prevCurSize = gb.currentGapSize;
                gb.deleteRight(10);

                assert(gb.currentGapSize == prevCurSize + txt.firstGraphemesSize(10));
                assert(gb.content.to!dstring == "abcde");
                assert(gb.reallocCount == 0);
            }
        }
        @system unittest
        {
            dstring text     = "12345";
            dstring combtext = "r̈a⃑⊥ b⃑";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt);
                gb.deleteRight(5);
                assert(gb.graphemesLength == 0);
            }
        }
        @system unittest
        {
            // Same to the left, if we move the cursor to the left of the text to delete
            dstring text     = "1234567890abc";
            dstring combtext = "r̈a⃑⊥ b⃑67890abc";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 50);
                auto prevCurSize = gb.currentGapSize;
                gb.cursorForward(10);
                writeln("XXX 1: ", txt);
                writeln("XXX 1 hasCombiningChars: ", gb.hasCombiningChars);
                gb.XXXdeleteMe = 20;
                gb.deleteLeft(10);
                writeln("XXX 2");
                assert(gb.currentGapSize == prevCurSize + txt.firstGraphemesSize(10));
                assert(gb.content.to!string == "abc");
                assert(gb.reallocCount == 0);
            }
        }
        ///
        @system unittest
        {
            // Reassign to configuredGapSize. Should reallocate.
            dstring text     = "1234567890abc";
            dstring combtext = "r̈a⃑⊥ b⃑67890abc";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 50);
                gb.cursorForward(5);
                assert(gb.contentBeforeGap == txt.graphemeSlice(0, 5));
                assert(gb.contentAfterGap == "67890abc");
                auto prevBufferLen = gb.buffer.length;

                gb.configuredGapSize = 100;
                assert(gb.reallocCount == 1);
                assert(gb.buffer.length == prevBufferLen + 50);
                assert(gb.currentGapSize == 100);
                assert(gb.content.to!dstring == txt);
                assert(gb.contentBeforeGap == txt.graphemeSlice(0, 5));
                assert(gb.contentAfterGap == "67890abc");
            }
        }

    /// Returns the full size of the internal buffer including the gap in bytes
    /// For example for a gapbuffer(string, dchar) with the content
    /// "1234" contentSize would return 16 (4 dchars * 4 bytes each) but
    /// contentSize would return 4 (dchars)
    @property public ulong bufferByteSize() const
    {
        return buffer.sizeof;
    }

    /// Returns the size, in bytes, of the textual part of the buffer without the gap
    /// For example for a gapbuffer(string, dchar) with the content
    /// "1234" contentSize would return 16 (4 dchars * 4 bytes each) but
    /// contentSize would return 4 (dchars)
    @property private ulong contentByteSize() const
    {
        return (contentBeforeGap.length + contentAfterGap.length).sizeof;
    }

    /// Return the number of visual chars (graphemes). This number can be
    //different / from the number of chartype elements or even unicode code
    //points.
    @property public ulong graphemesLength() const
    {
        if(hasCombiningChars) {
            return contentBeforeGap.byGrapheme.count +
                   contentAfterGap.byGrapheme.count;
        }
        // fast path
        return contentBeforeGap.length + contentAfterGap.length;
    }
    public alias length = graphemesLength;

    /**
     * Returns the cursor position (the gapStart)
     */
    @property public ulong cursorPos() const
    {
        // fast path
        if (!hasCombiningChars)
            return gapStart;

        return countGraphemes(contentBeforeGap);
    }

    public void cursorForward(GrphIdx count)
    {
        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        auto graphemesToCopy = min(count, countGraphemes(contentAfterGap));
        auto idxDiff = idxDiffUntilGrapheme(gapEnd, graphemesToCopy, Direction.Front);
        auto newGapStart = gapStart + idxDiff;
        auto newGapEnd = gapEnd + idxDiff;

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
    public void cursorBackward(GrphIdx count)
    {
        if (count <= 0 || buffer.length == 0 || gapStart == 0)
            return;

        auto graphemesToCopy = min(count, countGraphemes(contentBeforeGap));
        auto idxDiff = idxDiffUntilGrapheme(gapStart, graphemesToCopy, Direction.Back);
        auto newGapStart = gapStart - idxDiff;
        auto newGapEnd = gapEnd - idxDiff;

        buffer[newGapStart..gapStart].copy(buffer[newGapEnd..gapEnd]);
        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

        ///
        @system unittest
        {
            dstring text     = "1234567890";
            dstring combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt);

                assert(gb.cursorPos == 0);

                gb.cursorForward(5);
                assert(gb.cursorPos == 5);
                assert(gb.contentBeforeGap == txt.graphemeSlice(0, 5));
                assert(gb.contentAfterGap == "67890");

                gb.cursorForward(10_000);
                gb.cursorBackward(4);
                assert(gb.cursorPos == gb.length - 4);
                assert(gb.contentBeforeGap == txt.graphemeSlice(0, 6));
                assert(gb.contentAfterGap == "7890");

                immutable prevCurPos = gb.cursorPos;
                gb.cursorForward(0);
                assert(gb.cursorPos == prevCurPos);
            }
        }
    /**
     * Sets the cursor position. The position is relative to
     * the text and ignores the gap
     */
    @property public void cursorPos(ulong pos)
    {
        if (cursorPos > pos) {
            cursorBackward(cursorPos - pos);
        } else {
            cursorForward(pos - cursorPos);
        }
    }

        ///
        @system unittest
        {
            string text     = "1234567890";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb  = gapbuffer(txt);
                assert(gb.graphemesLength == 10);
                assert(gb.cursorPos == 0);
                assert(gb.contentAfterGap.to!string == txt);

                gb.cursorPos = 5;
                assert(gb.graphemesLength == 10);
                assert(gb.cursorPos == 5);
                assert(gb.contentBeforeGap.to!string == txt.graphemeSlice(0, 5).text);
                assert(gb.contentAfterGap == "67890");

                gb.cursorPos(0);
                assert(gb.cursorPos == 0);
                assert(gb.contentAfterGap.to!string == txt);
            }
        }


    // Note: this wont call checkForMultibyteChars because it would have to check
    // the full text and it could be slow, so for example on a text with the slow
    // path enabled because it has combining chars deleting all the combining
    // chars with this method wont switch to the fast path like adding text do.
    // If you need that, call checkForMultibyteChars manually or wait for reallocation.
    /**
     * Delete count chars to the left of the cursor position, moving the gap (and the cursor) back
     * (typically the effect of the backspace key).
     *
     * Params:
     *     count = the numbers of chars to delete.
     */
    public void deleteLeft(GrphIdx count)
    {
        if (buffer.length == 0 || gapStart == 0)
            return;

        auto graphemesToDel = min(count, countGraphemes(contentBeforeGap));
        auto idxDiff = idxDiffUntilGrapheme(gapStart, graphemesToDel, Direction.Back);
        gapStart = max(gapStart - idxDiff, 0);
    }

    // Note: this wont call checkForMultibyteChars because it would have to check
    // the full text and it could be slow, so for example on a text with the slow
    // path enabled because it has combining chars deleting all the combining
    // chars with this method wont switch to the fast path like adding text do.
    // If you need that, call checkForMultibyteChars manually or wait for reallocation.
    /**
      * Delete count chars to the right of the cursor position, moving the end of the gap to the right,
      * keeping the cursor at the same position
      *  (typically the effect of the del key).
      *
      * Params:
      *     count = the number of chars to delete.
      */
    public void deleteRight(GrphIdx count)
    {
        if (buffer.length == 0 || gapEnd == buffer.length)
            return;

        auto graphemesToDel = min(count, countGraphemes(contentAfterGap));
        auto idxDiff = idxDiffUntilGrapheme(gapEnd, graphemesToDel, Direction.Front);
        gapEnd = min(gapEnd + idxDiff, buffer.length);
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
            checkForMultibyteChars(text);
            auto newGapStart = gapStart + text.length;
            text.copy(buffer[gapStart..newGapStart]);
            gapStart = newGapStart;
        }
    }

    public void addText(StrT=string)(StrT text)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        addText(asArray(text));
    }

        @system unittest
        {
            string text     = "1234567890";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer("", 100);

                immutable prevGapStart = gb.gapStart;
                immutable prevGapEnd = gb.gapEnd;

                gb.addText(txt);
                assert(gb.content.to!string == txt);
                assert(gb.contentAfterGap == "");
                assert(gb.contentBeforeGap.to!string == txt);
                assert(gb.reallocCount == 0);
                assert(gb.gapStart == prevGapStart + asArray(txt).length);
                assert(gb.gapEnd == prevGapEnd);
            }
        }
        @system unittest
        {
            // Same test with a tiny gapsize to force reallocation

            string text     = "1234567890";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer("", 10);
                immutable prevGapStart = gb.gapStart;
                immutable prevGapEnd = gb.gapEnd;

                // text is bigger than gap size so it should reallocate
                gb.addText(txt);
                assert(gb.reallocCount == 1);
                assert(gb.content.to!string == txt);
                assert(gb.gapStart == prevGapStart + asArray(txt).length);
                assert(gb.gapEnd == prevGapEnd + asArray(txt).length);
            }
        }
        @system unittest
        {
            auto gb = gapbuffer("", 10);

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
        checkForMultibyteChars(text);
    }

    public void clear(StrT=string)(StrT text="", bool moveToEndEnd=true)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        clear(asArray(text), moveToEndEnd);
    }

        /// clear without text
        @system unittest
        {
            string text = "some added text";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 10);
                gb.clear();

                assert(gb.buffer.length == gb.configuredGapSize);
                assert(gb.content.to!string == "");
                assert(gb.content.length == 0);
                assert(gb.gapStart == 0);
                assert(gb.gapEnd == gb.configuredGapSize);
            }
        }

        /// clear with some text, moving to the end
        @system unittest
        {
            string text     = "1234567890";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt, 10);
                auto newText = "some replacing stuff";
                gb.clear(newText, true);

                assert(gb.buffer.length == (gb.configuredGapSize + newText.length));
                assert(gb.content.length == newText.length);
                assert(gb.content.to!string == newText);
                assert(gb.cursorPos == newText.length);
                assert(gb.gapStart == newText.length);
                assert(gb.gapEnd == gb.buffer.length);
            }
        }

        /// clear with some text, moving to the start
        @system unittest
        {
            auto gb = gapbuffer("Some initial text", 10);
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
        auto oldContentAfterGapSize = contentAfterGap.length;

        // Check if the actual size of the gap is smaller than configuredSize
        // to extend the gap (and how much)
        dchar[] gapExtension;
        if (currentGapSize >= _configuredGapSize) {
            // no need to extend the gap
            gapExtension.length = 0;
        } else {
            gapExtension = createNewGap(configuredGapSize - currentGapSize);
            gapExtensionCount += 1;
        }

        buffer.insertInPlace(gapStart, textToAdd, gapExtension);
        gapStart += textToAdd.length;
        gapEnd = buffer.length - oldContentAfterGapSize;
        reallocCount += 1;

        checkForMultibyteChars(buffer);
    }

    private void reallocate(StrT=string)(StrT textToAdd)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        reallocate(asArray(textToAdd));
    }
        @system unittest
        {
            string text     = "1234567890";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt);
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
        }
        @system unittest
        {
            string text     = "1234567890";
            string combtext = "r̈a⃑⊥ b⃑67890";

            foreach(txt; [text, combtext])
            {
                auto gb = gapbuffer(txt);
                gb.cursorForward(4);

                immutable prevGapSize = gb.currentGapSize;
                immutable prevBufferLen = gb.buffer.length;
                immutable prevGapStart = gb.gapStart;
                immutable prevGapEnd = gb.gapEnd;

                string newtext = " and some new text ";
                gb.reallocate(newtext);
                assert(gb.reallocCount == 1);
                assert(gb.buffer.length == prevBufferLen + asArray(newtext).length);
                assert(gb.currentGapSize == prevGapSize);
                assert(gb.content.to!string ==
                       txt.graphemeSlice(0, 4) ~ newtext ~ txt.graphemeSlice(4, "$"));
                assert(gb.gapStart == prevGapStart + asArray(newtext).length);
                assert(gb.gapEnd == prevGapEnd + asArray(newtext).length);
            }
        }

    //====================================================================
    //
    // Interface implementations and operators overloads
    //
    //====================================================================

    /**
     * $ (length) operator
     */
    public alias opDollar = graphemesLength;

    /// OpIndex: dchar[] b = gapbuffer[3];
    /// Please note that this returns a dchar[] and NOT a single
    //  dchar because the returned character could take several code points/units.
    public const(dchar[]) opIndex(GrphIdx pos) const
    {
        // fast path
        if (!hasCombiningChars) {
            return [content[pos]];
        }

        // slow path
        return content.byGrapheme.drop(pos).take(1).byCodePoint.array.to!(dchar[]);
    }
        @system unittest
        {
            auto gb = gapbuffer("polompos");
            assert(gb[0] == "p");
            assert(gb[$-1] == "s");

            dstring combtext = "r̈a⃑⊥ b⃑67890";
            auto gbc = gapbuffer(combtext);
            assert(gbc[0] == "r̈");
            assert(gbc[1] == "a⃑");
            assert(gbc[2] == "⊥");
            assert(gbc[3] == " ");
            assert(gbc[4] == "b⃑");
            assert(gbc[5] == "6");
            assert(gbc[6] == "7");
            assert(gbc[7] == "8");
            assert(gbc[8] == "9");
            assert(gbc[9] == "0");
        }

    /**
     * index operator read: auto x = gapBuffer[0..3]
     */
    public const(dchar[]) opSlice(GrphIdx start, GrphIdx end) const
    {
        // fast path
        if (!hasCombiningChars) {
            return content[start..end];
        }

        // slow path
        return content.byGrapheme.drop(start).take(end-start).byCodePoint.array.to!(dchar[]);
    }
        @system unittest
        {
            auto gb = gapbuffer("polompos");
            assert(gb[0..2] == "po");
            assert(gb[0..$] == "polompos");

            dstring combtext = "r̈a⃑⊥ b⃑67890";
            auto gbc = gapbuffer(combtext);
            assert(gbc[0..$] == combtext);
            assert(gbc[0..2] == "r̈a⃑");
            assert(gbc[3..5] == " b⃑");
            assert(gbc[5..$] == "67890");
        }


    /**
     * index operator read: auto x = gapBuffer[]
     */
    public const(dchar[]) opSlice() const
    {
        return content;
    }

        @system unittest
        {
            auto gb = gapbuffer("polompos");
            assert(gb[] == "polompos");
            assert(gb.content == "polompos");

            dstring combtext = "r̈a⃑⊥ b⃑67890";
            auto gbc = gapbuffer(combtext);
            assert(gbc[] == combtext);
            assert(gbc[] == gbc.content);
        }

    /**
     * index operator assignment: gapBuffer[] = "some string" (replaces all);
     */
    public ref GapBuffer opIndexAssign(dchar[] value)
    {
        clear(value);
        return this;
    }

    public ref GapBuffer opIndexAssign(StrT=string)(StrT value)
        if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring))
    {
        return opIndexAssign(asArray(value));
    }

        @system unittest
        {
            auto gb = gapbuffer("polompos");
            gb[] = "pokompos";
            assert(gb.content == "pokompos");

            dstring combtext = "r̈a⃑⊥ b⃑67890";
            auto gbc = gapbuffer(combtext);
            gbc[] = "123r̈a⃑⊥ b⃑";
            assert(gbc.content == "123r̈a⃑⊥ b⃑");
            assert(gbc[0..$] == "123r̈a⃑⊥ b⃑");
        }
}

// This must be outside of the template-struct. If tests inside the GapBuffer
// runs several times is because of this
@system unittest
{
    string text   = "init with text ñáñáñá";
    wstring wtext = "init with text ñáñáñá";
    dstring dtext = "init with text ñáñáñá";
    auto gb8 = gapbuffer(text);
    auto gb16 = gapbuffer(wtext);
    auto gb32 = gapbuffer(dtext);

    assert(gb8.graphemesLength == gb32.graphemesLength);
    assert(gb8.graphemesLength == gb16.graphemesLength);
    assert(gb8.content == gb32.content);
    assert(gb8.content == gb16.content);
    assert(gb8.content.to!string.length == 27);
    assert(gb8.content.to!wstring.length == 21);
    assert(gb8.content.to!dstring.length == gb32.content.to!dstring.length);
}
