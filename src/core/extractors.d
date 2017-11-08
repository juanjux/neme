module neme.core.extractors;

import neme.core.gapbuffer;
import neme.core.predicates;
import neme.core.settings;
import neme.core.types;

import std.algorithm.comparison : min;
import std.conv;
import std.stdio;

public @safe
const(Subject)[] lines(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                       ArraySize count, Predicate predicate = &All)
{
    auto goingForward = dir == Direction.Front;
    auto numLines = gb.numLines;
    auto realCount = min(count, numLines);

    const(Subject)[] lines;
    ulong iterated = 0;

    auto lineStartPos = gb.grpmPos2CPPos(startPos);
    auto startLine = gb.lineNumAtPos(lineStartPos);
    auto lineno = startLine;

    bool limitFound() { return (goingForward && lineno > numLines) ||
                               (!goingForward && lineno < 1); }

    while (iterated < count && !limitFound)
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

// FIXME: iterate by graphemes
public @safe
const(Subject)[] words(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                    ArraySize count, Predicate predicate = &All)
{
    import std.algorithm.mutation: reverse;

    const(Subject)[] words;
    words.reserve(count);

    auto content = gb.content;
    auto contentLen = gb.contentGrpmLen;

    if (contentLen == 0)
        return words;

    auto curPos = startPos;
    auto wordStartPos = curPos;
    BufferType curWord = [];
    curWord.reserve(64);

    bool goingForward = dir == Direction.Front;
    bool prevWasWordChar = false;
    ulong iterated = 0;

    void maybeAddWord()
    {
        GrpmIdx realStart, realEnd;

        if (goingForward) {
            realStart = wordStartPos;
            realEnd = GrpmIdx(curPos - 1);
        } else {
            realStart = GrpmIdx(curPos + 1);
            realEnd = wordStartPos;
            // XXX check if this works for graphemes!
            curWord.reverse;
        }

        auto word = Subject(realStart, realEnd, curWord);

        if (predicate(word)) {
            words ~= word;
            ++iterated;
        }

        curWord.length = 0;
    }

    bool limitFound() { return (goingForward  && curPos >= contentLen) ||
                               (!goingForward && curPos < 0); }

    while (iterated < count) {

        auto curChar = content[curPos.to!long];
        auto isWordChar = curChar !in globalSettings.wordSeparators;

        if (isWordChar) {
            curWord ~= curChar;

            if (!prevWasWordChar) // start of new word
                wordStartPos = curPos;
        } else if (prevWasWordChar) { // end of the word
            maybeAddWord;
        }

        goingForward ? ++curPos : --curPos;

        if (limitFound()) {
            if (isWordChar)
                maybeAddWord;

            break;
        }

        prevWasWordChar = isWordChar;
    }

    return words;
}
