module neme.core.gapbuffer;

// TODO: move these to local imports when only used once
public import neme.core.types;

import core.memory: GC;
import std.algorithm: uniq, each, sort, filter, each, copy, count;
import std.algorithm.comparison : max, min;
import std.algorithm.searching: canFind;
import std.array : appender, insertInPlace, join, minimallyInitializedArray;
import std.container.array : Array;
import std.conv;
import std.exception: assertNotThrown, assertThrown, enforce;
import std.range.primitives: popFrontExactly;
import std.range: take, drop, array, tail;
import std.stdio;
import std.traits;
import std.typecons: Typedef, Flag, Yes, No, tuple, Tuple;
import std.uni: byCodePoint, byGrapheme;
import std.utf: byDchar;

// TODO: Subject/Selector/predicate system. A subject is a copy of a region of the buffer.
// Predicates are functions that take text and return a modified version. There will be
// several methods:

// - getSubject(Type, Selector, Params): Where:
//  - Type is the kind of subject (chars, words, lines, paragraphs, functions, etc)
//  that will be selected.
//  - Selector is the way the subjects will be selected among others, and it will be
//  another function. Examples are: indexing, that will select subjects based on their
//  position inside the buffer or relative to the cursor position, regexp that will select
//  subjects that match a certain regexp, etc.
// - Params: parameters for the selector (index for the indexing, string for the
// regexp, etc).
//
// GetSubject would retrieve the text from the subjects as an InputRange. Then another
// method would map() the selected Predicate over the InputRage and return an
// OutputRange. That OutputRange will replace the original text of the subjects in
// the buffer.
//
// TODO: scope all the things
// TODO: add a demo mode (you type but the buffer representation is shown in
//       real time as you type or move the cursor)
// TODO: Unify doc comment style

/* Important:
 * - line numbers are 1-based, cursor positions are 0-based.
 * - The gap goes from gapStart (included) to gapEnd (not included). This is,
 * gapEnd is the position of the first character OUTSIDE the gap.

/**
 Terminology in this module:

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
 is updated every time text is added to the buffer or the array is reallocated
 (currently no check is done when deleting characters for performance reasons).
*/

/**
 * Struct user as Gap Buffer. It uses dchar (UTF32) characters internally for easier and
 * probably faster dealing with unicode chars since 1 dchar = 1 unicode char and slices
 * are just direct indexes without having to use libraries to get the indices of code
 * points.
 */

// This seems to work pretty well for common use cases, can be changed
// with the property configuredGapSize
enum DefaultGapSize = 32 * 1024;


@safe pure
BufferType asArray(StrT = string)(StrT str)
    if(is(StrT == string) || is(StrT == wstring) || is(StrT == dstring)
       || is(BufferType) || is(wchar[]) || is(char[]))
{
    return str.to!dstring.to!BufferType;
}


// TODO: unittest
package pure @safe @nogc
bool overlaps(ulong destStart, ulong destEnd, ulong sourceStart, ulong sourceEnd)
{
    return !(
        ((destStart < sourceStart && destEnd  < sourceEnd) &&
            (destStart < sourceEnd && destEnd < sourceStart)) ||
        ((destStart > sourceStart && destEnd  > sourceEnd) &&
            (destStart > sourceEnd && destEnd > sourceStart))
    );
}

package pure nothrow @safe @nogc
bool hasNewLine(BufferType)(BufferType text)
{
    import std.string: indexOf;
    return indexOf(text, '\n') != -1;
}


public @safe
GapBuffer gapbuffer(STR)(STR s, ArraySize gapSize = DefaultGapSize)
if (isSomeString!STR)
{
    return GapBuffer(asArray(s), gapSize);
}


public @safe
GapBuffer gapbuffer()
{
    return GapBuffer("", DefaultGapSize);
}

struct GapBuffer
{
    // The internal buffer holding the text and the gap
    package BufferType buffer = null;

    /// Counter of reallocations done since the struct was created to make room for
    /// text bigger than currentGapSize().
    package ulong reallocCount;

    /// Counter the times the gap have been extended.
    private ulong gapExtensionCount;

    // Gap location info vars
    package ArrayIdx gapStart;
    package ArrayIdx gapEnd;
    private ArraySize _configuredGapSize;

    // Catching some indexes and lengths to avoid having to iterate
    // by grapheme over unicode stuff when the "slow" multi-codepoint
    // mode is enabled
    package GrpmCount contentBeforeGapGrpmLen;
    package GrpmCount contentAfterGapGrpmLen;

    // If we have combining unicode chars (several code points for a single
    // grapheme) some methods switch to a slower unicode-striding implementation.
    // The detection and update of this boolean is done checkCombinedGraphemes().
    package bool hasCombiningGraphemes;
    /// This will use the fast array-based version of all text operations even if the buffer
    /// contains multi code point graphemes. Enabling this will make multi cp graphemes
    /// to don't display correctly.
    package bool _forceFastMode;

    // Map holding the (absolute and without accounting for the gap, ArrayIdx)
    // position of all newline characters. The key is the line
    // number and the value is an array with the newline offset
    package ArrayIdx[ArrayIdx] _newLines;

    // Average line length in the file, in code points, including the newline character.
    // Used to optimize currentLine. Updated on indexNewLines(buffer)
    package ArraySize _averageLineLenCP = 90;

    package pure nothrow @safe @nogc
    bool insideGap(ArrayIdx pos) const
    {
        return (pos >= gapStart && pos < gapEnd);
    }

    package @property @safe
    bool forceFastMode() const
    {
        return _forceFastMode;
    }
    package @property @safe
    void forceFastMode(bool force)
    {
        _forceFastMode = force;

        if (!force)
            // Dont remove Yes.forceCheck, could cause a recursive loop
            // (I deduced this logically, it didn't happen to me)
            checkCombinedGraphemes(content, Yes.forceCheck);
    }

    /// Normal constructor for a BufferType
    public @safe
    this(const BufferType textarray, ArraySize gapSize = DefaultGapSize)
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
    package @safe
    void checkCombinedGraphemes(const(BufferType) text, Flag!"forceCheck" forceCheck = No.forceCheck)
    {
        // Only a small text: only do the check if we didn't
        // had combined chars before (to avoid setting it to "false"
        // when it already had combined chars but the new text doesn't)

        if (!forceFastMode && (forceCheck || !hasCombiningGraphemes)) {
            foreach(gpm; text.byGrapheme) {
                // Short circuit the loop as soon as a multi CP grapheme is found
                if (gpm.length > 1) {
                    hasCombiningGraphemes = true;
                    return;
                }
            }

            hasCombiningGraphemes = false;
        }
    }
    package @safe
    void checkCombinedGraphemes()
    {
        checkCombinedGraphemes(content, Yes.forceCheck);
    }


    /// Returns the number of graphemes in the text.
    public @safe
    inout(GrpmCount) countGraphemes(const BufferType  slice) inout const
    {
        // fast path
        if (_forceFastMode || !hasCombiningGraphemes)
            return slice.length.GrpmCount;

        return slice.byGrapheme.count.GrpmCount;
    }


    // Starting from an ArrayIdx, count the number of codeunits that numGraphemes letters
    // take in the given direction.
    // TODO: check that this doesnt go over the gap
    package @safe
    ArrayIdx idxDiffUntilGrapheme(ArrayIdx idx, GrpmCount numGraphemes, Direction dir) const
    {
        // fast path
        if (_forceFastMode || !hasCombiningGraphemes)
            return numGraphemes.to!ArrayIdx;

        if (numGraphemes == 0u)
            return ArrayIdx(0);

        ArrayIdx charCount;
        if (dir == Direction.Front) {
            charCount = buffer[idx..$].byGrapheme.take(numGraphemes.to!long).byCodePoint.count;
        } else { // Direction.Back
            charCount = buffer[0..idx].byGrapheme.tail(numGraphemes.to!long).byCodePoint.count;
        }
        return charCount;
    }

    /// Convert a content (without accounting for the gapbuffer) position in graphemes to
    /// a position in code points. This / will be the same for buffers without multi code
    /// point characters (fast / mode).
    public @safe
    ArrayIdx grpmPos2CPPos(GrpmIdx pos) const
    {
        ArrayIdx retpos;

        if (_forceFastMode || !hasCombiningGraphemes) {
            retpos = pos.to!long;
        } else {
            auto gpIdx = min(contentGrpmLen - 1, pos.to!long);
            retpos = content.byGrapheme.take(gpIdx.to!long).byCodePoint.count.ArrayIdx;
        }
        return min(retpos, contentCPLen);
    }

    public @safe
    GrpmIdx CPPos2GrpmPos(ArrayIdx pos) const
    {
        GrpmIdx retpos;

        if (_forceFastMode || !hasCombiningGraphemes) {
            retpos = pos.to!long;
        } else {
            auto topIdx = min(contentCPLen, pos + 1);
            retpos = content[0..topIdx].byGrapheme.count - 1;
        }
        return retpos.to!GrpmIdx;
    }

    // Convert a position relative to the content (by grapheme and not accounting for the
    // gapbuffer), in graphemes, to an absolute position in the buffer (by code point and
    // accounting for the gapbuffer), in codepoints.
    package @safe
    ArrayIdx contentPos2ArrayPos(GrpmIdx pos) const
    {
        auto cpPos = grpmPos2CPPos(pos);

        if (cpPos >= gapStart)
            cpPos += currentGapSize;

        return min(cpPos, buffer.length);
    }

    // Convert an absolute array position (by code point and including the gap) to
    // a position in the content (by grapheme and without the gap)
    package @safe
    GrpmIdx arrayPos2ContentPos(ArrayIdx pos) const
    {
        ArrayIdx noGapPos;

        if (pos >= gapEnd) {// after the gap
            noGapPos = pos - currentGapSize;
        } else if (insideGap(pos)) {
            // Between the gap, give the previous valid position if the gap doesnt
            // starts at 0 or the next one if it does
            noGapPos = gapStart == 0 ? 0 : gapStart - 1;
        } else { // before the gap
            noGapPos = pos;
        }

        noGapPos = max(0, noGapPos);

        if (_forceFastMode || !hasCombiningGraphemes)
            return GrpmIdx(min(contentCPLen - 1, noGapPos));

        // slow path
        auto topIdx = min(contentCPLen, noGapPos);
        auto numGraphemes = countGraphemes(content[0 .. topIdx]);
        return GrpmIdx(numGraphemes);
    }

    // Create a new gap (empty array) with the configured size
    package nothrow @safe
    BufferType createNewGap(ArraySize gapSize=0) const
    {
        // if a new gapsize was specified use that, else use the configured default
        ImArraySize newGapSize = gapSize? gapSize: _configuredGapSize;
        debug
        {
            import std.array: replicate;
            return replicate(['-'.to!BufferElement], newGapSize);
        }
        else
        {
            return new BufferType(newGapSize);
        }
    }


    /** Print the raw contents of the buffer and a guide line below with the
     *  position of the start and end positions of the gap
     */
    package @safe
    void debugContent() const
    {
        import std.array: replace;

        writeln("gapstart: ", gapStart, " gapend: ", gapEnd, " len: ", buffer.length,
                " currentGapSize: ", currentGapSize, " configuredGapSize: ", _configuredGapSize,
                " contentGrpmLen: ", contentGrpmLen.to!long, " contentCPLen: ",
                content.byCodePoint.count);
        writeln("BeforeGap:|", contentBeforeGap.replace("\n", "/"),"|");
        writeln("AfterGap:|", contentAfterGap.replace("\n", "/"), "|");
        writeln("Text content:|", content.replace("\n", "/"), "|");
        writeln("Full buffer:");
        writeln(buffer.replace("\n", "/"));
        foreach (_; buffer[0 .. gapStart].byGrapheme)
        {
            write(" ");
        }
        write("^");
        if (gapEnd - 2 > gapStart) {
            foreach (_; buffer[gapStart .. gapEnd - 2].byGrapheme)
            {
                write("#");
            }
            write("^");
        }
        writeln;
    }

    public pure nothrow @property @safe
    bool empty() const
    {
        return contentCPLen == 0;
    }

    /**
     * Retrieve the textual content of the buffer until the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    public pure nothrow @property @safe @nogc
    const(BufferType) contentBeforeGap() const
    {
        return buffer[0..gapStart];
    }

    /**
     * Retrieve the textual content of the buffer after the gap/cursor.
     * The returned const array will be a direct reference to the
     * contents inside the buffer.
     */
    public pure nothrow @property @safe @nogc
    const(BufferType) contentAfterGap() const
    {
        return buffer[gapEnd .. $];
    }

    /**
     * Retrieve all the contents of the buffer. Unlike contentBeforeGap
     * and contentAfterGap the returned array will be newly instantiated, so
     * this method will be slower than the other two. PLEASE NOTE that if you
     * index the array returned by this function you'll be indexing by code point;
     * use indexing over the gapbuffer instance directly (gb[x]) to index by grapheme.
     *
     * Returns: The content of the buffer, as BufferElement.
     */
    public pure nothrow @property @safe
    const(BufferType) content() const
    {
        // Implementation note: I tried with a content cache, that would return
        // the the pre-appended content if not modified; but it wasn't significatively
        // faster and made const-correctness much harder so I disabled it.
        //return (contentBeforeGap ~ contentAfterGap).to!BufferType;
        return contentBeforeGap ~ contentAfterGap;
    }


    // Current gap size. The returned size is the number of chartype elements
    // (NOT bytes).
    public pure nothrow @property @safe @nogc
    ArraySize currentGapSize() const
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
    public pure nothrow @property @safe @nogc
    ArraySize configuredGapSize() const
    {
        return _configuredGapSize;
    }

    /**
     * Asigning to this property will change the gap size that will be used
     * at creation and reallocation time and will cause a reallocation to
     * generate a buffer with the new gap.
     */
    public @property @safe
    void configuredGapSize(ArraySize newSize)
    {
        enforce(newSize > 1, "Minimum gap size must be greater than 1");
        _configuredGapSize = newSize;

        // If the newSize if bigger than the current gap, reallocate
        if (newSize > currentGapSize)
            reallocate;
    }

    /// Return the number of code points. This number can be
    /// different / from the number of graphemes (visual characters) elements
    /// if the text contain multi-cp graphemes.
    public pure nothrow @property @safe
    ArraySize contentCPLen() const
    {
        return buffer.length - currentGapSize;
    }

    /// Return the number of visual chars (graphemes). This number can be
    /// different / from the number of chartype elements or even unicode code
    /// points.
    public pure nothrow @property @safe
    GrpmCount contentGrpmLen() const
    {
        return GrpmCount(contentBeforeGapGrpmLen + contentAfterGapGrpmLen);
    }
    public alias length = contentGrpmLen;

    /**
     * Returns the cursor position. Starts at 0.
     */
    public pure nothrow @property @safe
    GrpmIdx cursorPos() const
    {
        return max(0.GrpmIdx,
                min(GrpmIdx(contentBeforeGapGrpmLen),
                    GrpmIdx(contentGrpmLen - 1)
                )
        );
    }

    /+
     ╔══════════════════════════════════════════════════════════════════════════════
     ║ ⚑ Cursor operations
     ╚══════════════════════════════════════════════════════════════════════════════
    +/
    /**
     * Sets the cursor position. The position is relative to
     * the text and ignores the gap. Cursor positions start at 0.
     */
    public @property @safe
    void cursorPos(GrpmIdx pos)
    {
        pos = min(pos, GrpmIdx(contentGrpmLen - 1));

        if (pos < cursorPos) {
            cursorBackward(GrpmCount(cursorPos - pos));
        } else {
            cursorForward(GrpmCount(pos - cursorPos));
        }
    }

    /**
     * Moves the cursor forward, moving text to the left side of the gap.
     * Params:
     *     count = the number of places to move to the right.
     */
    public @safe
    ImGrpmIdx cursorForward(GrpmCount count)
    {
        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return cursorPos;

        ImGrpmCount actualToMoveGrpm = min(count, contentAfterGapGrpmLen);
        immutable ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapEnd, actualToMoveGrpm,
                Direction.Front);

        ImArrayIdx newGapStart = gapStart + idxDiff;
        ImArrayIdx newGapEnd   = gapEnd   + idxDiff;

        if (overlaps(gapStart, newGapStart, gapEnd, newGapEnd)) {
            buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd].dup;
        } else {
            // slices dont overlap so no need to create a temporary
            buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd];
        }

        gapStart = newGapStart;
        gapEnd   = newGapEnd;

        contentBeforeGapGrpmLen += actualToMoveGrpm.to!long;
        contentAfterGapGrpmLen  -= actualToMoveGrpm.to!long;
        return cursorPos;
    }

    /**
     * Moves the cursor backwards, moving text to the right side of the gap.
     * Params:
     *     count = the number of places to move to the left.
     */
    public @safe
    ImGrpmIdx cursorBackward(GrpmCount count)
    body
    {
        if (count <= 0 || buffer.length == 0 || gapStart == 0 || count == 0.GrpmCount)
            return cursorPos;

        ImGrpmCount actualToMoveGrpm = min(count, contentBeforeGapGrpmLen);
        immutable ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapStart, actualToMoveGrpm,
                Direction.Back);

        ImArrayIdx newGapStart = gapStart - idxDiff;
        ImArrayIdx newGapEnd = gapEnd - idxDiff;

        if (overlaps(newGapEnd, gapEnd, newGapStart, gapStart)) {
            buffer[newGapEnd..gapEnd] = buffer[newGapStart..gapStart].dup;
        } else {
            // slices dont overlap so no need to create a temporary
            buffer[newGapEnd..gapEnd] = buffer[newGapStart..gapStart];
        }


        gapStart = newGapStart;
        gapEnd  = newGapEnd;

        contentBeforeGapGrpmLen -= actualToMoveGrpm.to!long;
        contentAfterGapGrpmLen  += actualToMoveGrpm.to!long;

        return cursorPos;
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
    ImGrpmIdx deleteLeft(GrpmCount count)
    {
        if (buffer.length == 0 || gapStart == 0 || count == 0.GrpmCount)
            return cursorPos;

        ImGrpmCount actualToDelGrpm = min(count, contentBeforeGapGrpmLen);
        ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapStart, actualToDelGrpm,
                Direction.Back);

        gapStart = max(gapStart - idxDiff, 0);
        contentBeforeGapGrpmLen -= actualToDelGrpm.to!long;

        //if (buffer[gapStart..oldGapStart].hasNewLine)
        indexNewLines;

        return cursorPos;
    }

    // Note: ditto.
    /**
      * Delete count chars to the right of the cursor position, moving the end of the gap
      * to the right, keeping the cursor at the same position (typically the effect of the
      * del key).
      *
      * Params:
      *     count = the number of chars to delete.
      */
    public @safe
    ImGrpmIdx deleteRight(GrpmCount count)
    {
        if (buffer.length == 0 || gapEnd == buffer.length || count == 0.GrpmCount)
            return cursorPos;

        ImGrpmCount actualToDelGrpm = min(count, contentAfterGapGrpmLen);
        ImArrayIdx idxDiff = idxDiffUntilGrapheme(gapEnd, actualToDelGrpm,
                Direction.Front);

        gapEnd = min(gapEnd + idxDiff, buffer.length);
        contentAfterGapGrpmLen -= actualToDelGrpm.to!long;

        //if (buffer[oldGapEnd..gapEnd].hasNewLine)
        indexNewLines;

        return cursorPos;
    }

    /*
     * Delete the text between the specified grapheme positions.
     * Returns:
     *     The cursor position at the end.
     */
    public @safe
    ImGrpmIdx deleteBetween(GrpmIdx start, GrpmIdx end)
    {
        if (end > contentGrpmLen || start < 0)
            return cursorPos;

        cursorPos = start;
        deleteRight(GrpmCount(end - start));
        // deleteRight already calls indexNewLines if needed

        return cursorPos;
    }

    /**
     * Adds text, moving the cursor to the end of the new text. Could cause
     * a reallocation of the buffer.
     * Params:
     *     text = text to add.
     */
    public @safe
    ImGrpmIdx addText(const BufferType text)
    {
        if (text.length == 0)
            return cursorPos;

        bool reallocated;

        if (text.length >= currentGapSize) {
            // doesnt fill in the gap, reallocate the buffer adding the text
            reallocate(text);
            reallocated = true;
        } else {
            checkCombinedGraphemes(text);
            ImArrayIdx newGapStart = gapStart + text.length;
            text.copy(buffer[gapStart..newGapStart]);
            gapStart = newGapStart;
            GrpmIdx graphemesAdded;

            // fast path
            if (_forceFastMode || !hasCombiningGraphemes) {
                graphemesAdded = text.length;
            } else {
                graphemesAdded = countGraphemes(text);
            }

            contentBeforeGapGrpmLen += graphemesAdded.to!long;
            indexNewLines;
        }

        return cursorPos;
    }

    public @safe
    ImGrpmIdx addText(StrT=string)(StrT text)
        if (isSomeString!StrT)
    {
        return addText(asArray(text));
    }

    /**
     * Adds text at the specific position. This will move the cursor.
     * Returns:
     *  The new cursor position
     */
    public @safe
    ImGrpmIdx addAtPosition(ImGrpmIdx start, const BufferType text)
    {
        cursorPos = start;
        addText(text);
        return cursorPos;
    }

    // Note: this is slow on the slow path so it should only be used on things
    // that are slow anyway like clear() or reallocate(). Other stuff that modifies
    // the text (addText, delete*, cursor*) update the indexes directly.
    package @safe
    void updateGrpmLens()
    {
        if (_forceFastMode || !hasCombiningGraphemes) {
            // fast path
            contentBeforeGapGrpmLen = contentBeforeGap.length;
            contentAfterGapGrpmLen  = contentAfterGap.length;
        } else {
            // slow path
            contentBeforeGapGrpmLen = countGraphemes(contentBeforeGap);
            contentAfterGapGrpmLen  = countGraphemes(contentAfterGap);
        }
    }

    /**
     * Removes all pre-existing text from the buffer. You can also pass a
     * string to add new text after the previous ones has cleared (for example,
     * for the typical pasting with all the text preselected). This is
     * more efficient than clearing and then calling addText with the new
     * text
     */
    public @safe
    ImGrpmIdx clear(const BufferType text, bool moveToEndEnd=true)
    {
        immutable bool noRealloc = buffer.length >= (text.length + _configuredGapSize);

        if (moveToEndEnd) {
            if (noRealloc) {
                buffer[0..text.length] = text;
                gapStart = text.length;
                gapEnd = buffer.length;
            } else {
                buffer = text ~ createNewGap;
                gapStart = text.length;
                gapEnd = gapStart + _configuredGapSize;
            }
            gapEnd = buffer.length;
        } else {
            if (noRealloc) {
                gapStart = 0;
                gapEnd = buffer.length - text.length;
                buffer[gapEnd..$] = text;
            } else {
                buffer = createNewGap ~ text;
                gapStart = 0;
                gapEnd = _configuredGapSize;
            }
        }

        checkCombinedGraphemes;
        updateGrpmLens;
        indexNewLines;

        return cursorPos;
    }
    public @safe
    ImGrpmIdx clear()
    {
        return clear(null, false);
    }
    public @safe
    ImGrpmIdx clear(StrT=string)(StrT text="", bool moveToEndEnd=true)
    if (isSomeString!StrT)
    {
        return clear(asArray(text), moveToEndEnd);
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
    void reallocate(const BufferType textToAdd)
    {
        immutable ImArraySize oldContentAfterGapSize = contentAfterGap.length;

        // Check if the actual size of the gap is smaller than configuredSize
        // to extend the gap (and how much)
        BufferType gapExtension;
        if (currentGapSize >= _configuredGapSize) {
            // no need to extend the gap
            gapExtension.length = 0;
        } else {
            gapExtension = createNewGap(_configuredGapSize - currentGapSize);
            gapExtensionCount += 1;
        }

        buffer.insertInPlace(gapStart, textToAdd, gapExtension);
        gapStart += textToAdd.length;
        gapEnd = buffer.length - oldContentAfterGapSize;
        ++reallocCount;

        checkCombinedGraphemes;
        updateGrpmLens;
        indexNewLines;
    }
    package @safe
    void reallocate()
    {
        reallocate(null);
    }
    package @safe
    void reallocate(StrT=string)(StrT textToAdd)
    if (isSomeString!StrT)
    {
        reallocate(asArray(textToAdd));
    }

    /+
     ╔══════════════════════════════════════════════════════════════════════════════
     ║ ⚑ By Line information / operations
     ╚══════════════════════════════════════════════════════════════════════════════
    +/
    // Implementation note: in exploratory/ there is a parallel (and uglier) version of this but for
    // normal files it was 25x slower than this serial version. For 100MB files it was about
    // the same speed and from there it was faster; could be recovered if in the future I add a
    // "big file mode".

    public @trusted
    void indexNewLines()
    {
        ArrayIdx nlIndex;
        // For calculating the average line length, to optimize currentLine():
        ArraySize linesLengthSum;
        ArrayIdx prevOffset;
        bool afterGap;

        foreach(ref offset, cp; buffer) {
            if (insideGap(offset)) {
                // ignore the gap
                offset = gapEnd - 1;
                continue;
            }

            if(!afterGap && offset >= gapEnd)
                afterGap = true;

            // offset without the gap (by-content):
            ArrayIdx noGapOffset = offset;

            if (cp == '\n') {
                if (afterGap)
                    noGapOffset = offset - currentGapSize;

                // Store in the map [newLine#] : newlineOffset
                _newLines[nlIndex] = noGapOffset;
                ++nlIndex;

                // Add the current line length (numchars from the prevOffset to this \n)
                linesLengthSum += noGapOffset - prevOffset + 1;
                prevOffset = noGapOffset;
            }
        }

        if (nlIndex == 0) {
            _averageLineLenCP = contentCPLen;
        } else {
            _averageLineLenCP = numLines > 0 ? linesLengthSum / nlIndex : contentCPLen;
        }
    }

    public @safe @property
    ArrayIdx numLines() const
    {
        if (contentGrpmLen == 0)
            return 0.ArrayIdx;

        if (content[$-1] == '\n')
            return _newLines.length;

        return _newLines.length + 1;
    }

    package @safe
    const(ArraySubject) lineArraySubject(ArrayIdx linenum) const
    {
        if (linenum < 1 || linenum > numLines) {
            return ArraySubject(0.ArrayIdx, 0.ArrayIdx, "".to!BufferType);
        }
        else if (_newLines.length == 0) {
            return ArraySubject(0.ArrayIdx, content.length.ArrayIdx, content);
        }
        else if (linenum == 1) {
            return ArraySubject(0.ArrayIdx, _newLines[0], content[0.._newLines[0]]);
        }

        auto startPos = _newLines[linenum - 2] + 1;
        auto endPos   = _newLines[min(linenum - 1, _newLines.length - 1)];
        return ArraySubject(startPos, endPos, content[startPos..endPos]);
    }

    public @safe
    const(BufferType) lineAt(ArrayIdx linenum) const
    {
        return this[lineStartPos(linenum)..lineEndPos(linenum)];
    }

    /// Get the start position of the specified line. Doesn't move the cursor.
    public @safe
    GrpmIdx lineStartPos(ArrayIdx linenum) const
    {
        if (linenum <= 1 || !contentCPLen || !numLines || !_newLines.length)
            return 0.GrpmIdx;

        ArrayIdx newLineIdx = min(linenum - 1, _newLines.length);
        return (_newLines[newLineIdx - 1] + 1).GrpmIdx;
    }

    /// Get the end position of the specified line. Doesn't move the cursor.
    public @safe
    GrpmIdx lineEndPos(ArrayIdx linenum) const
    {
        if (linenum < 1 || !contentCPLen || !numLines) {
            return 0.GrpmIdx;
        }

        if (_newLines.length <= linenum)
            // last line
            return (contentGrpmLen - 1).GrpmIdx;

        // Next line position minus one
        return (lineStartPos(linenum + 1) - 1).GrpmIdx;
    }

    public @safe @property
    long currentCol() const
    {
        // Special case: if the cursor is on a \n, col is always 1
        if (this[cursorPos.to!ulong] == "\n")
            return 1;

        return cursorPos - lineStartPos(currentLine) + 1;
    }

    // FIXME: unittest
    public @safe
    GrpmIdx lineLength(ArrayIdx linenum) const
    {
        return (lineEndPos(linenum) - lineStartPos(linenum)).GrpmIdx;
    }

    /// Move the cursor to the start of the specified line
    public @safe
    GrpmIdx cursorToLine(ArrayIdx linenum)
    {
        cursorPos(lineStartPos(linenum));
        return cursorPos;
    }

    /// Delete the specified line. Moves the cursor.
    public @safe
    void deleteLine(ArrayIdx linenum)
    {
        // Nonsensical line
        if (linenum < 1 || linenum > _newLines.length + 1) {
            return;
        }

        // Single line, delete all
        if (linenum == 1 && _newLines.length == 0) {
            cursorPos(0.GrpmIdx);
            deleteRight(contentGrpmLen);
            return;
        }

        auto delStart = lineStartPos(linenum);
        auto delEnd = (lineEndPos(linenum) + 1).GrpmIdx;
        deleteBetween(delStart, delEnd);
        indexNewLines;
    }

    /// Delete the specified lines. Moves the cursor.
    public @safe
    void deleteLines(ArrayIdx[] linenums)
    {
        auto deleted = 0;
        immutable deleteDecr = (ArrayIdx x) { deleteLine(x - deleted); ++deleted; };

        linenums
            .sort
            .uniq
            .filter!(a => a <= numLines && a > 0)
            .each!(deleteDecr);
    }

    // FIXME: this is a logic mess
    /**
     * Returns the current line inside the buffer (0-based index).
     * Doesn't move the cursor.
     */
    public @safe
    ArrayIdx lineNumAtPos(ArrayIdx pos) const
    {
        if (pos == 0 || _newLines.length < 2 || _averageLineLenCP == 0)
            return 1;

        if (pos >= contentCPLen)
            return numLines;

        ArrayIdx aprox = min(_newLines.length - 1, pos / _averageLineLenCP);

        while (true) {
            if (aprox >_newLines.length || aprox < 0)
                return aprox + 1;

            immutable guessNewlinePos = _newLines[aprox];
            if (guessNewlinePos == pos)
                return aprox + 1; // Lucky shot

            if (guessNewlinePos > pos) {
                // Current position is after the guessed newline

                if (aprox == 0)
                    return 1; // it was the first, so found

                // Check the position of the previous newline to see if our pos is between them
                if (_newLines[aprox - 1] < pos)
                    return aprox + 1;

                // Not found, continue searching back
                --aprox;
            }

            else if (guessNewlinePos < pos) {
                // Current position is before the guessed newline

                // Check the position of the next newline to see if our pos is between them
                if (aprox + 1 == _newLines.length || _newLines[aprox + 1] > pos)
                    return aprox + 2;

                // Not found, continue searching front
                ++aprox;
            }
            else {
                assert(false, "Bug in currentLine");
            }
        }
    }

    public @safe @property
    ArrayIdx currentLine() const
    {
        return lineNumAtPos(gapStart);
    }

    /+
     ╔══════════════════════════════════════════════════════════════════════════════
     ║ ⚑ Operator[] overloads
     ╚══════════════════════════════════════════════════════════════════════════════
    +/

    /**
     * $ (length) operator
     */
    public alias opDollar = contentGrpmLen;

    /**
     * [] (slice) operator, currently only supported as rvalue
     */

    /// OpIndex: BufferType b = gapbuffer[3]; /// Please note that this returns a BufferType and NOT a single
    /// BufferElement because the returned character could take several code points/units.
    public @safe
    const(BufferType) opIndex(GrpmIdx pos) const
    {
        // fast path
        if (_forceFastMode || !hasCombiningGraphemes)
            return [content[pos.to!long]];

        return content.byGrapheme.drop(pos.to!long).take(1).byCodePoint.array.to!(BufferType);
    }
    public @safe
    const(BufferType) opIndex(long pos) const
    {
        return opIndex(pos.GrpmIdx);
    }

    /**
     * index operator read: auto x = gapBuffer[0..3]
     */
    public @safe
    const(BufferType) opSlice(GrpmIdx start, GrpmIdx end) const
    {
        // fast path
        if (_forceFastMode || !hasCombiningGraphemes) {
            return content[start.to!long..end.to!long];
        }

        // slow path
        return content.byGrapheme.drop(start.to!long)
                      .take(end.to!long - start.to!long)
                      .byCodePoint.array.to!(BufferType);
    }
    public @safe
    const(BufferType) opSlice(long start, long end) const
    {
        return opSlice(start.GrpmIdx, end.GrpmIdx);
    }

    /**
     * index operator read: auto x = gapBuffer[]
     */
    public pure nothrow @safe
    const(BufferType) opSlice() const
    {
        return content;
    }
}
