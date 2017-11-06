module neme.core.extractors;

import neme.core.gapbuffer;
import neme.core.predicates;
import neme.core.settings;
import neme.core.types;

import std.algorithm.comparison : min;
import std.conv;
import std.stdio;

public @safe
const(Subject)[] lines(const scope GapBuffer gb, GrpmIdx startPos, Direction dir,
                       ArraySize count, Predicate predicate = &All)
{
    auto numLines = gb.numLines;
    auto realCount = min(count, numLines);

    const(Subject)[] subjects;
    ulong iterated = 0;

    auto lineStartPos = gb.grpmPos2CPPos(startPos);
    auto startLine = gb.lineNumAtPos(lineStartPos);
    auto lineno = startLine;

    do {
        auto subject = gb.lineArraySubject(lineno).toSubject(gb);

        if (predicate(subject)) {
            subjects ~= subject;
            ++iterated;
        }

        // Wrap around on first/last line and loop not finished
        if (dir == Direction.Front) {
            if (++lineno > numLines)
                lineno = 1;
        } else {
            if (--lineno < 1)
                lineno = numLines;
        }
    } while (iterated < count);

    return subjects;
}

public @safe
const(Subject)[] words(const scope GapBuffer gb, GrpmIdx startPos, Direction dir,
                    ArraySize count, Predicate predicate = &All)
{
}
