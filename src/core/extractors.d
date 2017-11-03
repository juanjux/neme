module neme.core.extractors;

import neme.core.gapbuffer;
import neme.core.types;
import neme.core.predicates;

import std.algorithm.comparison : min;
import std.stdio;
import std.conv;

// XXX iterated and count should consider filtered?
public @safe
Subject[] lines(scope GapBuffer gb, GrpmIdx startPos, Direction dir,
        ArraySize count, Predicate predicate = &All)
{
    auto numLines = gb.numLines;
    auto realCount = min(count, numLines);

    Subject[] subjects;
    ulong iterated = 0;

    auto lineStartPos = gb.grpmPos2CPPos(startPos);
    auto lineno = gb.lineNumAtPos(lineStartPos);

    do {
        auto subject = gb.lineArraySubject(lineno).toSubject(gb);

        if (predicate(subject))
            subjects ~= subject;

        // Wrap around on first/last line and loop not finished
        if (dir == Direction.Front) {
            if (++lineno > numLines)
                lineno = 1;
        } else {
            if (--lineno < 1)
                lineno = numLines;
        }
    } while (++iterated < count);

    return subjects;
}
