version(0)
{
    /*
     * This is a repository of code that was discarded after benchmarking it against other solutions
     */

    pragma(inline):
    @safe
    pure bool overlaps(ulong destStart, ulong destEnd,
                               ulong sourceStart, ulong sourceEnd)
    {
        return !(
            ((destStart < sourceStart && destEnd  < sourceEnd) &&
                (destStart < sourceEnd && destEnd < sourceStart)) ||
            ((destStart > sourceStart && destEnd  > sourceEnd) &&
                (destStart > sourceEnd && destEnd > sourceStart))
        );
    }

    @safe unittest
    {
        assert(!overlaps(1, 2, 3, 4));
        assert(!overlaps(1, 1, 2, 2));
        assert(!overlaps(0, 1, 2, 2));
        assert(overlaps(0, 4, 2, 3));
        assert(overlaps(0, 3, 2, 4));
        assert(overlaps(0, 1, 1, 3));
        assert(overlaps(0, 0, 0, 0));
        assert(overlaps(2, 6, 1, 5));
    }

    // Method of GapBuffer
    public void cursorForward_smartDup(ulong count)
    {
        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        // TODO: test if this gives any real speed over always doing the dup
        ulong charsToCopy = min(count, buffer.length - gapEnd);
        ulong newGapStart = gapStart + charsToCopy;
        ulong newGapEnd = gapEnd + charsToCopy;

        if (overlaps(gapStart, newGapStart, gapEnd, newGapEnd)) {
            // ARRAYOP: COPY
            buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd].dup;
        } else {
            // ARRAYOP: COPY
            buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd];
        }

        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    // Method of GapBuffer
    public void cursorForward_alwaysdup(ulong count)
    {
        if (count <= 0 || buffer.length == 0 || gapEnd + 1 == buffer.length)
            return;

        // TODO: test if this gives any real speed over always doing the dup
        ulong charsToCopy = min(count, buffer.length - gapEnd);
        ulong newGapStart = gapStart + charsToCopy;
        ulong newGapEnd = gapEnd + charsToCopy;

        buffer[gapStart..newGapStart] = buffer[gapEnd..newGapEnd].dup;

        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    // Method of GapBuffer
    public void cursorBackward_smartdup(ulong count)
    {
        if (count <= 0 || buffer.length == 0 || gapStart == 0)
            return;

        immutable ulong charsToCopy = min(count, gapStart);
        ulong newGapStart = gapStart - charsToCopy;
        ulong newGapEnd = gapEnd - charsToCopy;

        // TODO: test if this gives any real speed over always doing the dup
        if (overlaps(newGapEnd, gapEnd, newGapStart, gapStart)) {
            // ARRAYOP: COPY
            buffer[newGapEnd .. gapEnd] = buffer[newGapStart..gapStart].dup;
        } else {
            // ARRAYOP: COPY
            buffer[newGapEnd .. gapEnd] = buffer[newGapStart..gapStart];
        }

        gapStart = newGapStart;
        gapEnd = newGapEnd;
    }

    // Method of GapBuffer
    public void reallocate_appender(StringT textToAdd="")
    {
        // FIXME: make this private
        if (textToAdd == null) {
            textToAdd = "";
        }

        immutable charText = asArray(textToAdd);
        immutable oldContentAfterGapLen = contentAfterGap.length;
        // TODO: benchmark vs insertInPlace
        // ARRAYOP: SLICE + CONCATENATION

        auto app = appender!(CharT[])();
        app.reserve(contentBeforeGap.length + charText.length + _configuredGapSize +
                contentAfterGap.length + 8);
        app.put(buffer[0..contentBeforeGap.length]);
        app.put(charText);
        app.put(createNewGap());
        app.put(contentAfterGap);
        buffer = app.data;

        gapStart += charText.length;
        gapEnd = buffer.length - oldContentAfterGapLen;
        reallocCount += 1;
    }

    // Method of GapBuffer
    public void reallocate_concatenation(StringT textToAdd="")
    {
        // FIXME: make this private
        if (textToAdd == null) {
            textToAdd = "";
        }

        immutable charText = asArray(textToAdd);
        immutable oldContentAfterGapLen = contentAfterGap.length;
        // TODO: benchmark vs insertInPlace
        // ARRAYOP: SLICE + CONCATENATION

        // FIXME: change contentBeforeGap.length for gapStart, search for other instances
        gapExtensionCount += 1;
        buffer = buffer[0..gapStart] ~
                         charText ~
                         createNewGap() ~
                         contentAfterGap;

        gapStart += charText.length;
        gapEnd = buffer.length - oldContentAfterGapLen;
        reallocCount += 1;
    }
}
