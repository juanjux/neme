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

/**
 IMPORTANT terminology in this module:

 CUnit = the internal array type, NOT grapheme or visual character
 CPoint = Code point. Usually, but not always, same as a letter. On dchar
          1 CPoint = 1 CUnit but on UTF16 and UTF8 a CPoint can be more than 1
          CUnit.
 Letter = Grapheme, a visual character, using letter because is shorter and less
          alien-sounding for any normal person.

 Function parameters are ArrayIdx/Size when they refer to base array positions
 (code points) and GrpmIdx/Count when the indexes are given in graphemes.

 Some functions have a "fast path" that operate by chars and a "slow path" that
 operate by graphemes. The path is selected by the hasCombiningGraphemes member that
 is updated every time text is added to the buffer to the array is reallocated
 (currently no check is done when deleting characters for performance reasons).
*/

// TODO: Benchmark emulating several different text editing sessions,
// use the benchmark to avoid regresions in performance and test stuff

// TODO: unicode mode optimization: update on changes (cursor movement, delete, add, realloc):
// grpmCursorPos
// contentBeforeGap.grpmLength
// contentAfterGap.grpmLength
// contentLength (gb.length)

// TODO: Add invariants to check the stuff above

// TODO: add a demo mode (you type but the buffer representation is shown in
//       real time as you type or move the cursor)

// TODO: line number cache in the data structure

// TODO: add a "fastclear()": if buffer.length > newText, without reallocation. This will
// overwrite the start with the new text and then extend the gap from the end of
// the new text to the end of the buffer

// TODO: Try to do it @nogc, use Array from stdlib, use other strings, "fast", etc?

// TODO: content() (probably) reallocates every time, think of a way to avoid that

// TODO: Unify doc comment style

/**
 * Struct user as Gap Buffer. It uses dchar (UTF32) characters internally for easier and
 * probably faster dealing with unicode chars since 1 dchar = 1 unicode char and slices are just direct indexes
 * without having to use libraries to get the indices of code points.
 */

// TODO: increase
enum DefaultGapSize = 100;

enum Direction { Front, Back }

// For array positions / sizes
alias ArrayIdx = ulong;
alias ImArrayIdx = immutable ulong;

alias ArraySize = ulong;
alias ImArraySize = immutable ulong;

// For grapheme positions / sizes
alias GrpmIdx = ulong;
alias ImGrpmIdx = immutable ulong;

alias GrpmCount = ulong;
alias ImGrpmCount = immutable ulong;


@safe pure pragma(inline)
dchar[] asArray(StrT = string)(StrT str)
    if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring)
       || is(dchar[]) || is(wchar[]) || is(char[]))
{
    return to!(dchar[])(str);
}


public @safe pragma(inline)
GapBuffer gapbuffer(STR)(STR s, ArraySize gapSize = DefaultGapSize)
if (isSomeString!STR)
{
    return GapBuffer(asArray(s), gapSize);
}


public @safe pragma(inline)
GapBuffer gapbuffer()
{
    return GapBuffer("", DefaultGapSize);
}


struct GapBuffer
{
    // The internal buffer holding the text and the gap
    package dchar[] buffer = null;

    /// Counter of reallocations done since the struct was created to make room for
    /// text bigger than currentGapSize().
    package ulong reallocCount;

    /// Counter the times the gap have been extended.
    private ulong gapExtensionCount;

    // Gap location info vars
    package ulong gapStart;
    package ulong gapEnd;
    private ulong _configuredGapSize;

    // If we have combining unicode chars (several code points for a single
    // grapheme) some methods switch to a slower unicode-striding implementation.
    // The detection and update of this boolean is done checkCombinedGraphemes().
    package bool hasCombiningGraphemes = false;
    /// This will use the fast array-based version of all text operations even if the buffer
    /// contains multi code point graphemes. Enabling this will make multi cp graphemes
    /// to don't display correctly.
    public bool forceFastMode = false;

    /// Normal constructor for a dchar[]
    public @safe
    this(const dchar[] textarray, ArraySize gapSize = DefaultGapSize)
    {
        enforce(gapSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = gapSize;
        clear(textarray, false);
    }

    /// Overloaded constructor for string types
    public @safe
    this(Str=string)(Str text, ArraySize gapSize = DefaultGapSize)
    if (isSomeString!Str)
    {
        this(asArray(text), gapSize);
    }

    // If we have combining unicode chars (several code points for a single
    // grapheme) some methods switch to a slower unicode-striding implementation.
    // NOTE: this sets the global state of hasCombiningGraphemes so when checking
    // a block of text smaller than the total only call it if hasCombiningGraphemes
    // if false:
    // if (!hasCombiningGraphemes) checkCombinedGraphemes()
    package @safe pragma(inline)
    void checkCombinedGraphemes(const(dchar[]) text=null)
    {
        // TODO: short circuit the exit as soon as one difference is found
        if (text is null) {
            // check all the text (for full loads and reallocations)
            hasCombiningGraphemes = content.byCodePoint.count != content.byGrapheme.count;
        } else if (!hasCombiningGraphemes) {
            // only a small text: only do the check if we didn't
            // had combined chars before (to avoid setting it to "false"
            // when it already had combined chars but the new text doesn't)
            hasCombiningGraphemes = text.byCodePoint.count != text.byGrapheme.count;
        }
    }

    // Returns the number of graphemes in the text.
    public @safe const pragma(inline) inout
    inout(GrpmCount) countGraphemes(const dchar[]  slice)
    {
        // fast path
        if (forceFastMode || !hasCombiningGraphemes)
            return slice.length;

        return slice.byGrapheme.count;
    }

    // Starting from an ArrayIdx, count the number of codeunits that numGraphemes letters
    // take in the given direction.
    // TODO: check that this doesnt go over the gap
    package @safe const pragma(inline)
    ArrayIdx idxDiffUntilGrapheme(ArrayIdx idx, GrpmCount numGraphemes, Direction dir)
    {
        // fast path
        if (forceFastMode || !hasCombiningGraphemes)
            return numGraphemes;

        if (numGraphemes == 0)
            return 0;

        ArrayIdx charCount;
        if (dir == Direction.Front) {
            charCount = buffer[idx..$].byGrapheme.take(numGraphemes).byCodePoint.count;
        } else { // Direction.Back
            charCount = buffer[0..idx].byGrapheme.tail(numGraphemes).byCodePoint.count;
        }
        return charCount;
    }

    // Create a new gap (empty array) with the configured size
    package @safe nothrow pragma(inline)
    dchar[] createNewGap(ArraySize gapSize=0)
    {
        // if a new gapsize was specified use that, else use the configured default
        ImArraySize newGapSize = gapSize? gapSize: configuredGapSize;
        debug
        {
            import std.array: replicate;
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
    public @safe
    void debugContent()
    {
        writeln("gapstart: ", gapStart, " gapend: ", gapEnd, " len: ", buffer.length,
                " currentGapSize: ", currentGapSize, " configuredGapSize: ", configuredGapSize,
                " contentLength: ", contentLength);
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
     * Retrieve the textual content of the buffer until the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    public @property @safe nothrow @nogc const pragma(inline)
    const(dchar[]) contentBeforeGap()
    {
        return buffer[0..gapStart];
    }

    /**
     * Retrieve the textual content of the buffer after the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    public @property @safe nothrow @nogc const pragma(inline)
    const(dchar[]) contentAfterGap()
    {
        return buffer[gapEnd .. $];
    }

    /**
     * Retrieve all the contents of the buffer. Unlike contentBeforeGap
     * and contentAfterGap the returned array will be newly instantiated, so
     * this method will be slower than the other two.
     *
     * Returns: The content of the buffer, as dchar.
     */
    public @property @safe nothrow const pragma(inline)
    const(dchar[]) content()
    {
        return contentBeforeGap ~ contentAfterGap;
    }

    // Current gap size. The returned size is the number of chartype elements
    // (NOT bytes).
    public @property @safe nothrow @nogc const pragma(inline)
    ArraySize currentGapSize()
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
    public @property @safe nothrow pure @nogc const pragma(inline)
    ArraySize configuredGapSize()
    {
        return _configuredGapSize;
    }

    /**
     * Asigning to this property will change the gap size that will be used
     * at creation and reallocation time and will cause a reallocation to
     * generate a buffer with the new gap.
     */
    public @property @safe pragma(inline)
    void configuredGapSize(ArraySize newSize)
    {
        enforce(newSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = newSize;
        reallocate();
    }
    /// Return the number of visual chars (graphemes). This number can be
    /// different / from the number of chartype elements or even unicode code
    /// points.
    public @property @safe const pragma(inline)
    GrpmCount contentLength()
    {
        // XXX use indexes
        return countGraphemes(contentBeforeGap) + countGraphemes(contentAfterGap);
    }
    public alias length = contentLength;

    /**
     * Returns the cursor position (the gapStart)
     */
    public @property @safe const pragma(inline)
    GrpmIdx cursorPos()
    {
        // fast path
        if (forceFastMode || !hasCombiningGraphemes)
            return gapStart;

        // XXX use indexes
        return countGraphemes(contentBeforeGap);
    }

    /**
     * Sets the cursor position. The position is relative to
     * the text and ignores the gap
     */
    public @property @safe pragma(inline)
    void cursorPos(GrpmIdx pos)
    {
        if (cursorPos > pos) {
            cursorBackward(cursorPos - pos);
        } else {
            cursorForward(pos - cursorPos);
        }
    }

    /**
     * Moves the cursor forward, moving text to the left side of the gap.
     * Params:
     *     count = the number of places to move to the right.
     */
    public @safe
    void cursorForward(GrpmCount count)
    {
        // XXX: update indexes
        // XXX: use indexes (contentAfterGapGrpmLen)

        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        ImGrpmCount graphemesToCopy = min(count, countGraphemes(contentAfterGap));
        ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapEnd, graphemesToCopy, Direction.Front);
        ImArrayIdx newGapStart = gapStart + idxDiff;
        ImArrayIdx newGapEnd = gapEnd + idxDiff;

        buffer[gapEnd..newGapEnd].copy(buffer[gapStart..newGapStart]);
        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    /**
     * Moves the cursor backwards, moving text to the right side of the gap.
     * Params:
     *     count = the number of places to move to the left.
     */
    public @safe
    void cursorBackward(GrpmCount count)
    {
        // XXX: update indexes
        // XXX: use indexes (contentBeforeGapGrpmLen)

        if (count <= 0 || buffer.length == 0 || gapStart == 0)
            return;

        ImGrpmCount graphemesToCopy = min(count, countGraphemes(contentBeforeGap));
        ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapStart, graphemesToCopy, Direction.Back);
        ImArrayIdx newGapStart = gapStart - idxDiff;
        ImArrayIdx newGapEnd = gapEnd - idxDiff;

        buffer[newGapStart..gapStart].copy(buffer[newGapEnd..gapEnd]);
        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    // Note: this wont call checkCombinedGraphemes because it would have to check
    // the full text and it could be slow, so for example on a text with the slow
    // path enabled because it has combining chars deleting all the combining
    // chars with this method wont switch to the fast path like adding text do.
    // If you need that, call checkCombinedGraphemes manually or wait for reallocation.

    /**
     * Delete count chars to the left of the cursor position, moving the gap (and the cursor) back
     * (typically the effect of the backspace key).
     *
     * Params:
     *     count = the numbers of chars to delete.
     */
    public @safe
    void deleteLeft(GrpmCount count)
    {
        // XXX: update indexes
        // XXX: use indexes (contentBeforeGapGrpmLen)

        if (buffer.length == 0 || gapStart == 0)
            return;

        ImGrpmCount graphemesToDel = min(count, countGraphemes(contentBeforeGap));
        ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapStart, graphemesToDel, Direction.Back);
        gapStart = max(gapStart - idxDiff, 0);
    }

    // Note: ditto.
    /**
      * Delete count chars to the right of the cursor position, moving the end of the gap to the right,
      * keeping the cursor at the same position
      *  (typically the effect of the del key).
      *
      * Params:
      *     count = the number of chars to delete.
      */
    public @safe
    void deleteRight(GrpmCount count)
    {
        // XXX: update indexes
        // XXX: use indexes (contentAfterGapGrpmLen)

        if (buffer.length == 0 || gapEnd == buffer.length)
            return;

        ImGrpmCount graphemesToDel = min(count, countGraphemes(contentAfterGap));
        ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapEnd, graphemesToDel, Direction.Front);
        gapEnd = min(gapEnd + idxDiff, buffer.length);
    }

    /**
     * Adds text, moving the cursor to the end of the new text. Could cause
     * a reallocation of the buffer.
     * Params:
     *     text = text to add.
     */
    public @safe
    void addText(const dchar[] text)
    {
        // XXX: update indexes

        if (text.length >= currentGapSize) {
            // doesnt fill in the gap, reallocate the buffer adding the text
            reallocate(text);
        } else {
            checkCombinedGraphemes(text);
            ImArrayIdx newGapStart = gapStart + text.length;
            text.copy(buffer[gapStart..newGapStart]);
            gapStart = newGapStart;
        }
    }

    public @safe pragma(inline)
    void addText(StrT=string)(StrT text)
        if (isSomeString!StrT)
    {
        addText(asArray(text));
    }

    /**
     * Removes all pre-existing text from the buffer. You can also pass a
     * string to add new text after the previous ones has cleared (for example,
     * for the typical pasting with all the text preselected). This is
     * more efficient than clearing and then calling addText with the new
     * text
     */
    public @safe
    void clear(const dchar[] text=null, bool moveToEndEnd=true)
    {
        // XXX: update indexes
        if (moveToEndEnd) {
            buffer = text ~ createNewGap();
            gapStart = text.length;
            gapEnd = buffer.length;
        } else {
            buffer = createNewGap() ~ text;
            gapStart = 0;
            gapEnd = _configuredGapSize;
        }
        checkCombinedGraphemes();
    }

    public @safe pragma(inline)
    void clear(StrT=string)(StrT text="", bool moveToEndEnd=true)
    if (isSomeString!StrT)
    {
        clear(asArray(text), moveToEndEnd);
    }


    // Reallocates the buffer, creating a new gap of the configured size.
    // If the textToAdd parameter is used it will be added just before the start of
    // the new gap. This is useful to do less copy operations since usually you
    // want to reallocate the buffer because you want to insert a new text that
    // if to big for the gap.
    // Params:
    //  textToAdd: when reallocating, add this text before/after the gap (or cursor)
    //      depending on the textDir parameter.
    package @trusted
    void reallocate(const dchar[] textToAdd=null)
    {
        // XXX: update indexes

        ImArraySize oldContentAfterGapSize = contentAfterGap.length;

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

        checkCombinedGraphemes();
    }

    package @safe pragma(inline)
    void reallocate(StrT=string)(StrT textToAdd)
    if (isSomeString!StrT)
    {
        reallocate(asArray(textToAdd));
    }

    //====================================================================
    //
    // Interface implementations and operators overloads
    //
    //====================================================================

    /**
     * $ (length) operator
     */
    public alias opDollar = contentLength;

    /// OpIndex: dchar[] b = gapbuffer[3];
    /// Please note that this returns a dchar[] and NOT a single
    /// dchar because the returned character could take several code points/units.
    public @safe pragma(inline)
    const(dchar[]) opIndex(GrpmIdx pos) const
    {
        // fast path
        if (forceFastMode || !hasCombiningGraphemes)
            return [content[pos]];

        return content.byGrapheme.drop(pos).take(1).byCodePoint.array.to!(dchar[]);
    }

    /**
     * index operator read: auto x = gapBuffer[0..3]
     */
    public @safe pragma(inline)
    const(dchar[]) opSlice(GrpmIdx start, GrpmIdx end) const
    {
        // fast path
        if (forceFastMode || !hasCombiningGraphemes) {
            return content[start..end];
        }

        // slow path
        return content.byGrapheme.drop(start).take(end-start).byCodePoint.array.to!(dchar[]);
    }

    /**
     * index operator read: auto x = gapBuffer[]
     */
    public @safe nothrow pragma(inline)
    const(dchar[]) opSlice() const
    {
        return content;
    }
}
