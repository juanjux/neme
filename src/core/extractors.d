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
    auto numLines = gb.numLines;
    auto realCount = min(count, numLines);

    const(Subject)[] lines;
    ulong iterated = 0;

    auto lineStartPos = gb.grpmPos2CPPos(startPos);
    auto startLine = gb.lineNumAtPos(lineStartPos);
    auto lineno = startLine;

    do {
        auto line = gb.lineArraySubject(lineno).toSubject(gb);

        if (predicate(line)) {
            lines ~= line;
            ++iterated;
        }

        // Wrap around on first/last line and loop not finished
        if (dir == Direction.Front) {
            if (++lineno > numLines)
                lineno = 1;
        } else {
            if (--lineno < 1)
                lineno = max(numLines, 1);
        }
    } while (iterated < count && lineno != startLine);

    return lines;
}

// FIXME: slow mode (iterate by graphemes)
public @safe
const(Subject)[] words(in GapBuffer gb, GrpmIdx startPos, Direction dir,
                    ArraySize count, Predicate predicate = &All)
{

    auto curPos = startPos;
    const(Subject)[] words;
    auto content = gb.content;
    BufferType curWord = [];
    curWord.reserve(20);

    immutable wordSeps = globalSettings.wordSeparators;
    bool insideWord = false;
    auto wordStartPos = curPos;
    ulong iterated = 0;

    // XXX wrap around
    do {
        auto curChar = content[curPos.to!ulong];

        if (curChar !in wordSeps) {
            if (!insideWord) // new word starts
                wordStartPos = curPos;

            curWord ~= curChar;
            insideWord = true;
        } else {
            if (insideWord) { // word finished

                GrpmIdx realStart, realEnd;
                if (dir == Direction.Front) {
                    realStart = wordStartPos;
                    realEnd = GrpmIdx(curPos - 1);
                } else {
                    realStart = GrpmIdx(curPos - 1);
                    realEnd = wordStartPos;
                }

                auto word = Subject(realStart, realEnd, curWord.dup);

                if (predicate(word)) {
                    words ~= word;
                    ++iterated;
                }
                curWord.length = 0;
            } // else: inter-words space: noop

            insideWord = false;
        }

        // Wrap around
        if (dir == Direction.Front) {
            if (++curPos >= gb.contentGrpmLen)
                curPos = 0;
        } else {
            if (--curPos < 0)
                curPos = gb.contentGrpmLen - 1;
        }
    } while (iterated < count && curPos != startPos);

    return words;
}
