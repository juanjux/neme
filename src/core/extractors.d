module neme.core.extractors;

import neme.core.gapbuffer;
import neme.core.predicates;
import neme.core.settings;
import neme.core.types;

import std.algorithm.comparison : min;
import std.array: array;
import std.container.dlist;
import std.conv;
import std.traits;
import std.stdio;
import std.array;


/**
 * Generic extractor function that servers for many kinds of Subjects. The isBoundary
 * compile time parameter is a callable that will check if we've found the boundary of the
 * current subject to add it to the list.
 * That function or delegate should have the signature:
 *
 * bool isBoundary(DList!BufferElement, BufferType)
 **/
public @safe
const(Subject)[] extract(alias isBoundary)
    (in GapBuffer gb, GrpmIdx startPos, Direction dir, ArraySize count,
     Predicate predicate = &All)
if (isCallable!isBoundary)
{
    auto contentLen = gb.contentGrpmLen;
    if (contentLen == 0) return [];

    const(Subject)[] subjects; subjects.reserve(count);
    auto pos = startPos;
    auto subjectStartPos = pos;
    auto curSubject = DList!BufferElement();
    bool goingForward = (dir == Direction.Front);
    ulong iterated = 0;

    void maybeAdd() {
        GrpmIdx realStart, realEnd;

        if (goingForward) {
            realStart = subjectStartPos;
            realEnd = GrpmIdx(pos - 1);
        } else {
            realStart = GrpmIdx(pos + 1);
            realEnd = subjectStartPos;
        }

        auto subject = Subject(realStart, realEnd, curSubject.array);
        if (predicate(subject)) {
            subjects ~= subject;
            ++iterated;
        }

        curSubject.clear();
    }

    auto limitFound = () => goingForward && pos >= contentLen || !goingForward && pos < 0;

    while (iterated < count) {
        const(BufferType) curGrpm = gb[pos.to!long];
        bool isWordChar = !isBoundary(curSubject, curGrpm);

        if (isWordChar) {
            if (curSubject.empty) // start of new word
                subjectStartPos = pos;

            goingForward ? curSubject.insertBack(curGrpm) : curSubject.insertFront(curGrpm);
        } else if (!curSubject.empty)  // end of the word
            maybeAdd;

        goingForward ? ++pos : --pos;

        if (limitFound()) {
            if (isWordChar) maybeAdd;
            break;
        }
    }

    return subjects;
}

// Lines extractor doesn't use the generic extractor because the GapBuffer already
// can provide precise line information with lineNumAtPos and lineArraysubject
public @safe
const(Subject)[] lines(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                       ArraySize count, Predicate predicate = &All)
{
    if (gb.length == 0) return [];

    const(Subject)[] lines;
    immutable goingForward = dir == Direction.Front;
    ulong iterated;

    auto lineStartPos = gb.grpmPos2CPPos(startPos);
    auto lineno = gb.lineNumAtPos(lineStartPos);
    auto limitFound = () => (goingForward && lineno > gb.numLines) || (!goingForward && lineno < 1);

    while (iterated < count && !limitFound())
    {
        auto line = gb.lineArraySubject(lineno).toSubject(gb);

        if (predicate(line)) {
            lines ~= line;
            ++iterated;
        }

        goingForward ? ++lineno : --lineno;
    }

    return lines;
}

public @safe
const(Subject)[] words(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                       ArraySize count, Predicate predicate = &All)
{
    bool isBoundary(in DList!BufferElement loaded, in BufferType curGrpm)
    {
        bool isWordChar = true;

        foreach(BufferElement cp; curGrpm) {
            // FIXME: any sequence of wordSeparators started by a wordSeparator char is also a word
            // until the first non separator or whitespace character
            if (cp in globalSettings.wordSeparators) {
                isWordChar = false;
                break;
            }
        }
        return !isWordChar;
    }

    return extract!isBoundary(gb, startPos, dir, count, predicate);
}

// Same as the Vim concept of words with 'W', only considering whitespace
// characters as separators
public @safe
const(Subject)[] uWords(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                        ArraySize count, Predicate predicate = &All)
{
    import std.uni: isWhite;

    bool isBoundary(in DList!BufferElement loaded, in BufferType curGrpm)
    {
        bool isWordChar = true;

        foreach(BufferElement cp; curGrpm) {
            if (isWhite(cp)) {
                isWordChar = false;
                break;
            }
        }
        return !isWordChar;
    }

    return extract!isBoundary(gb, startPos, dir, count, predicate);
}



public @safe
const(Subject)[] paragraphs(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                            ArraySize count, Predicate predicate = &All)
{
    import std.string: strip;

    bool isBoundary(in DList!BufferElement loaded, in BufferType curGrpm)
    {
        if (dir == Direction.Front) {
            return !loaded.empty && (loaded.back == '\n' && curGrpm[0] == '\n');
        }
        return !loaded.empty && (loaded.front == '\n' && curGrpm[0] == '\n');
    }

    // Clean up \n at the start and end of paragraphs
    auto parags = extract!isBoundary(gb, startPos, dir, count, predicate);
    const(Subject)[] endParags;
    endParags.reserve(parags.length);

    auto maxLen = gb.length;

    foreach(ref p; parags) {
        // Strip newlines and fix backward motion positions
        GrpmIdx start, end;

        if (p.startPos == 0)
            start = 0;
        else if (dir == Direction.Back)
            start = min((p.startPos + 1).GrpmIdx, gb.length);
        else
            start = p.startPos.to!long;

        if (p.endPos >= maxLen)
            end = maxLen;
        else if (dir == Direction.Back)
            end = min((p.endPos + 1).GrpmIdx, gb.length);
        else
            end = p.endPos.to!long;

        endParags ~= Subject(start, end, p.text.strip);
    }

    return endParags;
}
