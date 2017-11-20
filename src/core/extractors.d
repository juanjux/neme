module neme.core.extractors;

import neme.core.gapbuffer;
import neme.core.predicates;
import neme.core.settings;
import neme.core.types;

import std.algorithm.comparison : min;
import std.array: array;
import std.container.dlist;
import std.conv;
import std.stdio;


/**
 * Generic extractor function that servers for many kinds of Subjects. Receives a
 * SeparatorChecker function that will check if we've found the boundary of the current
 * subject to add it to the list.
 **/
public @safe
const(Subject)[] extract(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                           ArraySize count, SeparatorChecker isSeparator,
                           Predicate predicate = &All)
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
        bool isWordChar = !isSeparator(curSubject, curGrpm);

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

public @safe
const(Subject)[] lines(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                       ArraySize count, Predicate predicate = &All)
{
    if (gb.length == 0) return [];

    const(Subject)[] lines;
    auto goingForward = dir == Direction.Front;
    ulong iterated = 0;

    auto lineStartPos = gb.grpmPos2CPPos(startPos);
    auto startLine = gb.lineNumAtPos(lineStartPos);
    auto lineno = startLine;
    auto limitFound = () => goingForward && lineno > gb.numLines || !goingForward && lineno < 1;

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

@safe
private bool isWordLimit(in DList!BufferElement loaded, in BufferType curGrpm)
{
    bool isWordChar = true;

    foreach(BufferElement cp; curGrpm) {
        if (cp in globalSettings.wordSeparators) {
            isWordChar = false;
            break;
        }
    }
    return !isWordChar;
}

public @safe
const(Subject)[] words(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                       ArraySize count, Predicate predicate = &All)
{
    return extract(gb, startPos, dir, count, &isWordLimit, predicate);
}
