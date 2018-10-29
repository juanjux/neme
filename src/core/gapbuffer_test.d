module neme.core.gapbuffer_test;

import neme.core.gapbuffer;
import std.exception: assertNotThrown, assertThrown;
import std.conv;
import std.uni: byGrapheme, byCodePoint;
import std.range: take, tail;
import std.stdio: writeln;
import std.typecons;
import std.algorithm: count;

// TODO: add fuzzy testing
// TODO add test names, or use unithreaded
// @("Like this")
debug
{
    // unittest support functions
    // TODO: use them in the grapheme support methods in GapBuffer?

    ArrayIdx firstGraphemesSize(S)(S txt, GrpmIdx n)
    {
        return txt.byGrapheme.take(n.to!long).byCodePoint.to!S.length;
    }

    ArrayIdx lastGraphemesSize(S)(S txt, GrpmIdx count)
    {
        return txt.byGrapheme.tail(count.to!long).byCodePoint.to!S.length;
    }

    ArrayIdx graphemesSizeFrom(S)(S txt, GrpmIdx from)
    {
        return txt.byGrapheme.take(from.to!long).byCodePoint.to!S.length;
    }

    S graphemeSlice(S, T = string)(S txt, GrpmIdx from, T to)
    {
        ArrayIdx startArrayIdx = txt.firstGraphemesSize(from);
        ArrayIdx endArrayIdx;

        static if (is(T == string)) {
            if (to == "$")
                endArrayIdx = txt.length;
            else
                assert(false, "String to argument for graphemeSlice must be $");
        } else {
            endArrayIdx = txt.firstGraphemesSize(to);
        }
        return txt[startArrayIdx..endArrayIdx];
    }
}

// this

@safe unittest
{
    // test null
    gapbuffer("", 0).assertThrown;
    gapbuffer("", 1).assertThrown;
}
@safe unittest
{
    assertNotThrown(gapbuffer("", 1000_000));
}
@safe unittest
{
    auto gb = gapbuffer("", 2);
    assert(gb.buffer != null);
    assert(gb.buffer.length == 2);
}
@safe unittest
{
    auto gb = gapbuffer("", 2);
    assert(gb.buffer.length == 2);
    assert(gb.content.to!string == "");
    assert(gb.content.length == 0);
    assert(gb.contentAfterGap.length == 0);
    assert(gb.reallocCount == 0);
}
@safe unittest
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

// CheckCombiningGraphemes
@safe unittest
{
    // Checks the "stickyness" of hasCombinedGraphemes
    dstring text = "Some initial text";
    dstring combtext = "r̈a⃑⊥ b⃑67890";

    auto gb = gapbuffer("", 2);
    gb.checkCombinedGraphemes(text);
    assert(!gb.hasCombiningGraphemes);

    gb.checkCombinedGraphemes(combtext);
    assert(gb.hasCombiningGraphemes);

    gb.checkCombinedGraphemes(text);
    assert(gb.hasCombiningGraphemes);

    // Eval all the text
    gb.checkCombinedGraphemes;
    assert(!gb.hasCombiningGraphemes);

    gb.clear;
    assert(!gb.hasCombiningGraphemes);

    gb.clear(text);
    assert(!gb.hasCombiningGraphemes);

    gb.clear;
    assert(!gb.hasCombiningGraphemes);

    gb.addText(text);
    assert(!gb.hasCombiningGraphemes);

    gb.checkCombinedGraphemes;
    assert(!gb.hasCombiningGraphemes);
}

/// countGraphemes
@safe unittest
{
    // 17 dchars, 17 graphemes
    auto str_a = "some ascii string"d;
    // 20 dchars, 17 graphemes
    auto str_c = "ññññ r̈a⃑⊥ b⃑ string"d;

    auto gba = gapbuffer(str_a);
    assert(!gba.hasCombiningGraphemes);
    gba.cursorPos = 9999.GrpmIdx;

    auto gbc = gapbuffer(str_c);
    assert(gbc.hasCombiningGraphemes);
    gbc.cursorPos = 9999.GrpmIdx;

    auto gbc2 = gapbuffer(str_c);
    gbc2.forceFastMode = true;
    assert(gbc.hasCombiningGraphemes);

    assert(gba.countGraphemes(gba.buffer[0..4]) == 4);
    assert(gbc.countGraphemes(gbc.buffer[0..4]) == 4);
    assert(gbc2.countGraphemes(gbc.buffer[0..4]) == 4);

    assert(gba.countGraphemes(gba.buffer[0..17]) == 17);
    assert(gbc.countGraphemes(gbc.buffer[0..20]) == 17);
    assert(gbc2.countGraphemes(gbc2.buffer[0..20]) == 20);
}

/// contentPos2ArrayPos
@safe unittest
{
    auto str_a = "some ascii string"d;

    void checkAtRawPosition(ref GapBuffer gb, GrpmIdx pos, BufferElement c, ulong len = 1)
    {
        auto idx = gb.contentPos2ArrayPos(pos);
        assert(gb.buffer[idx.. idx + len] == c.to!dstring);
    }

    auto gba = gapbuffer(str_a, 10);
    checkAtRawPosition(gba, 0.GrpmIdx, 's');
    checkAtRawPosition(gba, 3.GrpmIdx, 'e');
    checkAtRawPosition(gba, 7.GrpmIdx, 'c');
    checkAtRawPosition(gba, 13.GrpmIdx, 'r');
    checkAtRawPosition(gba, 16.GrpmIdx, 'g');

    assert(gba.contentPos2ArrayPos(17.GrpmIdx) == 27);
    assert(gba.contentPos2ArrayPos(100.GrpmIdx) == 27);

    auto str_c = "abcd a⃑ b⃑ string"d;

    gba = gapbuffer(str_c, 10);

    checkAtRawPosition(gba, 0.GrpmIdx, 'a');
    checkAtRawPosition(gba, 1.GrpmIdx, 'b');
    checkAtRawPosition(gba, 2.GrpmIdx, 'c');
    checkAtRawPosition(gba, 3.GrpmIdx, 'd');
    checkAtRawPosition(gba, 4.GrpmIdx, ' ');

    assert(gba.contentPos2ArrayPos(5.GrpmIdx) == 15);
    assert(gba.contentPos2ArrayPos(6.GrpmIdx) == 17);
    assert(gba.contentPos2ArrayPos(7.GrpmIdx) == 18);
    assert(gba.contentPos2ArrayPos(8.GrpmIdx) == 20);
    assert(gba.contentPos2ArrayPos(9.GrpmIdx) == 21);
}

/// arrayPos2ContentPos
@safe unittest
{
    auto str = "some ascii string"d;
    auto gb = gapbuffer(str, 10);

     //inside the gap:
    assert(gb.arrayPos2ContentPos(0) == 0);

     //after the gap:
    assert(gb.arrayPos2ContentPos(10) == 0);
    assert(gb.arrayPos2ContentPos(11) == 1);
    assert(gb.arrayPos2ContentPos(17) == 7);
    assert(gb.arrayPos2ContentPos(26) == 16);
    assert(gb.arrayPos2ContentPos(26) == 16);
    assert(gb.arrayPos2ContentPos(27) == 16);
    assert(gb.arrayPos2ContentPos(9999) == 16);

    gb.cursorForward(5.GrpmCount);

    // before the gap:
    assert(gb.arrayPos2ContentPos(0) == 0);
    assert(gb.arrayPos2ContentPos(4) == 4);

    // inside the gap:
    assert(gb.arrayPos2ContentPos(5) == 4);
    assert(gb.arrayPos2ContentPos(11) == 4);
    assert(gb.arrayPos2ContentPos(14) == 4);

    // after the gap:
    assert(gb.arrayPos2ContentPos(15) == 5);
    assert(gb.arrayPos2ContentPos(20) == 10);
    assert(gb.arrayPos2ContentPos(26) == 16);
    assert(gb.arrayPos2ContentPos(27) == 16);
    assert(gb.arrayPos2ContentPos(9999) == 16);
}
@safe unittest
{
    auto str = "abcd a⃑ b⃑ string"d;
    auto gb = gapbuffer(str, 10);

    // inside the gap:
    assert(gb.arrayPos2ContentPos(0) == 0);
    assert(gb.arrayPos2ContentPos(10) == 0);

    // after the gap:
    assert(gb.arrayPos2ContentPos(11) == 1);
    assert(gb.arrayPos2ContentPos(15) == 5);

    // first multi cp char
    assert(gb.arrayPos2ContentPos(16) == 6);
    assert(gb.arrayPos2ContentPos(17) == 6);

    assert(gb.arrayPos2ContentPos(18) == 7);

    // second multi cp char
    assert(gb.arrayPos2ContentPos(19) == 8);
    assert(gb.arrayPos2ContentPos(20) == 8);

    // rest
    assert(gb.arrayPos2ContentPos(21) == 9);
    assert(gb.arrayPos2ContentPos(22) == 10);
    assert(gb.arrayPos2ContentPos(23) == 11);
    assert(gb.arrayPos2ContentPos(24) == 12);
    assert(gb.arrayPos2ContentPos(25) == 13);
    assert(gb.arrayPos2ContentPos(26) == 14);
    assert(gb.arrayPos2ContentPos(27) == 15);
    assert(gb.arrayPos2ContentPos(9999) == 15);

    gb.cursorForward(5.GrpmCount);

    // before the gap
    assert(gb.arrayPos2ContentPos(0) == 0);
    assert(gb.arrayPos2ContentPos(4) == 4);

    // inside the gap:
    assert(gb.arrayPos2ContentPos(5) == 4);
    assert(gb.arrayPos2ContentPos(11) == 4);
    assert(gb.arrayPos2ContentPos(14) == 4);

    // after the gap:
    assert(gb.arrayPos2ContentPos(15) == 5);

    // first multi cp char
    assert(gb.arrayPos2ContentPos(16) == 6);
    assert(gb.arrayPos2ContentPos(17) == 6);

    assert(gb.arrayPos2ContentPos(18) == 7);

    // second multi cp char
    assert(gb.arrayPos2ContentPos(19) == 8);
    assert(gb.arrayPos2ContentPos(20) == 8);
}

// Unicode-optimizing indexes
// contentBeforeGapGrpmLen;
// contentAfterGapGrpmLen;
@safe unittest
{
    dstring combtext = "r̈a⃑⊥ b⃑67890"; // 10 graphemes, 13 len
    immutable combtextGrpmLen = combtext.byGrapheme.count;

    auto gb = gapbuffer(combtext, 10);
    assert(gb.hasCombiningGraphemes);
    assert(gb.cursorPos == 0);
    assert(gb.contentBeforeGapGrpmLen == 0);
    assert(gb.contentAfterGapGrpmLen == combtextGrpmLen);

    gb.cursorForward(1.GrpmCount);
    assert(gb.cursorPos == 1);
    assert(gb.cursorPos == gb.cursorPos);
    assert(gb.contentBeforeGapGrpmLen == 1);
    assert(gb.contentAfterGapGrpmLen == combtextGrpmLen - 1);


    gb.cursorForward(1000.GrpmCount);
    assert(gb.cursorPos == combtextGrpmLen - 1);
    assert(gb.cursorPos == gb.contentGrpmLen - 1);
    assert(gb.contentBeforeGapGrpmLen == combtextGrpmLen);
    assert(gb.contentAfterGapGrpmLen == 0);

    gb.cursorBackward(1.GrpmCount);
    assert(gb.cursorPos == combtextGrpmLen - 1);
    assert(gb.cursorPos == gb.contentGrpmLen - 1);
    assert(gb.contentBeforeGapGrpmLen == combtextGrpmLen - 1);
    assert(gb.contentAfterGapGrpmLen == 1);

    gb.cursorBackward(GrpmCount(1000));
    assert(gb.cursorPos == 0);
    assert(gb.contentBeforeGapGrpmLen == 0);
    assert(gb.contentAfterGapGrpmLen == combtextGrpmLen);

    gb.cursorPos = GrpmCount(0);
    assert(gb.cursorPos == 0);
    assert(gb.contentBeforeGapGrpmLen == 0);
    assert(gb.contentAfterGapGrpmLen == combtextGrpmLen);
}


// idxDiffUntilGrapheme

@safe unittest
{
    dstring text = "Some initial text"; // 17 len & graphemes
    dstring combtext = "r̈a⃑⊥ b⃑67890"; // 10 graphemes, 13 len

    auto gb  = gapbuffer(text, 10);
    auto gbc = gapbuffer(combtext, 10);

    alias front = Direction.Front;
    assert(gb.idxDiffUntilGrapheme(gb.gapEnd, 4.GrpmCount, front) == 4);
    assert(gb.idxDiffUntilGrapheme(gb.gapEnd, gb.contentGrpmLen, front) == text.length);

    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd, gbc.contentGrpmLen, front) == combtext.length);
    assert(gbc.idxDiffUntilGrapheme(gbc.buffer.length - 4, 4.GrpmCount, front) == 4);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd, 1.GrpmCount, front) == 2);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 2, 1.GrpmCount, front) == 2);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 4, 1.GrpmCount, front) == 1);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 5, 1.GrpmCount, front) == 1);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 6, 1.GrpmCount, front) == 2);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 8, 1.GrpmCount, front) == 1);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 9, 1.GrpmCount, front) == 1);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 10, 1.GrpmCount, front) == 1);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 11, 1.GrpmCount, front) == 1);
    assert(gbc.idxDiffUntilGrapheme(gbc.gapEnd + 12, 1.GrpmCount, front) == 1);
}


// content / contentAfterGap / contentBeforeGap

@safe unittest
{
    // Check that the slice returned by contentBeforeGap/AfterGap points to the same
    // memory positions as the original with not copying involved
    dstring text = "Some initial text";
    dstring combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 5);
        gb.cursorForward(3.GrpmCount);
        auto before = gb.contentBeforeGap;
        assert(&before[0] == &gb.buffer[0]);
        assert(&before[$-1] == &gb.buffer[gb.gapStart-1]);

        auto after = gb.contentAfterGap;
        assert(&after[0] == &gb.buffer[gb.gapEnd]);
        assert(&after[$-1] == &gb.buffer[$-1]);
    }
}

@safe unittest
{
    string text = "initial text";

    auto gb = gapbuffer(text);
    gb.cursorForward(7.GrpmCount);
    assert(gb.content.to!string == text);
    assert(gb.contentBeforeGap == "initial");
    assert(gb.contentAfterGap == " text");
    gb.addText(" inserted stuff");
    assert(gb.reallocCount == 0);
    assert(gb.content.to!string == "initial inserted stuff text");
    assert(gb.contentBeforeGap == "initial inserted stuff");
    assert(gb.contentAfterGap == " text");
}

@safe unittest
{
    string text = "¡Hola mundo en España!";
    auto gb = gapbuffer(text);
    assert(gb.content.to!string == text);
    assert(to!dstring(gb.content).length == 22);
    assert(to!string(gb.content).length == 24);

    gb.cursorForward(1.GrpmCount);
    assert(gb.contentBeforeGap == "¡");

    gb.cursorForward(4.GrpmCount);
    assert(gb.contentBeforeGap == "¡Hola");
    assert(gb.content.to!string == text);
    assert(gb.contentAfterGap == " mundo en España!");

    gb.addText(" más cosas");
    assert(gb.reallocCount == 0);
    assert(gb.content.to!string == "¡Hola más cosas mundo en España!");
    assert(gb.contentBeforeGap == "¡Hola más cosas");
    assert(gb.contentAfterGap == " mundo en España!");
}

// contentGrpmLen

@safe unittest
{
    dstring text = "Some initial text";
    dstring combtext = "r̈a⃑⊥ b⃑67890";

    auto gb = gapbuffer(text, 50);
    auto cgb = gapbuffer(combtext, 50);

    assert(gb.contentGrpmLen == 17);
    assert(cgb.contentGrpmLen == 10);
}

// currentGapSize / configuredGapSize

@safe unittest
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
@safe unittest
{
    dstring text =     "1234567890abcde";
    dstring combtext = "r̈a⃑⊥ b⃑67890abcde";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 50);
        // Deleting should recover space from the gap
        immutable prevCurSize = gb.currentGapSize;
        gb.deleteRight(10.GrpmCount);

        assert(gb.currentGapSize == prevCurSize + txt.firstGraphemesSize(10.GrpmCount));
        assert(gb.content.to!dstring == "abcde");
        assert(gb.reallocCount == 0);
    }
}

// deleteRight
@safe unittest
{
    dstring text     = "12345";
    dstring combtext = "r̈a⃑⊥ b⃑";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt);
        gb.deleteRight(5.GrpmCount);
        assert(gb.contentGrpmLen == 0);
    }

    auto gb = gapbuffer(text);
    gb.deleteRight(2.GrpmCount);
    assert(gb.content.to!string == "345");
    gb.deleteRight(3.GrpmCount);
    assert(gb.content.to!string == "");
}

// deleteLeft
@safe unittest
{
    // Same to the left, if we move the cursor to the left of the text to delete
    dstring text     = "1234567890abc";
    dstring combtext = "r̈a⃑⊥ b⃑67890abc";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 50);
        immutable prevCurSize = gb.currentGapSize;
        gb.cursorForward(10.GrpmCount);
        gb.deleteLeft(10.GrpmCount);
        assert(gb.currentGapSize == prevCurSize + txt.firstGraphemesSize(10.GrpmCount));
        assert(gb.content.to!string == "abc");
        assert(gb.reallocCount == 0);
        gb.cursorForward(3.GrpmCount);
        gb.deleteLeft(3.GrpmCount);
        assert(gb.content.to!string == "");
    }
}
@safe unittest
{
    // Reassign to configuredGapSize. Should reallocate.
    dstring text     = "1234567890abc";
    dstring combtext = "r̈a⃑⊥ b⃑67890abc";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 50);
        gb.cursorForward(5.GrpmCount);
        assert(gb.contentBeforeGap == txt.graphemeSlice(0.GrpmIdx, 5.GrpmIdx));
        assert(gb.contentAfterGap == "67890abc");
        immutable prevBufferLen = gb.buffer.length;

        gb.configuredGapSize = 100;
        assert(gb.reallocCount == 1);
        assert(gb.buffer.length == prevBufferLen + 50);
        assert(gb.currentGapSize == 100);
        assert(gb.content.to!dstring == txt);
        assert(gb.contentBeforeGap == txt.graphemeSlice(0.GrpmIdx, 5.GrpmIdx));
        assert(gb.contentAfterGap == "67890abc");
    }
}

// cursorForward / cursorBackward

@safe unittest
{
    dstring text     = "1234567890";
    dstring combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt);

        assert(gb.cursorPos == 0);

        gb.cursorForward(5.GrpmCount);
        assert(gb.cursorPos == 5);
        assert(gb.contentBeforeGap == txt.graphemeSlice(0.GrpmIdx, 5.GrpmIdx));
        assert(gb.contentAfterGap == "67890");

        gb.cursorForward(10_000.GrpmCount);
        gb.cursorBackward(4.GrpmCount);
        assert(gb.cursorPos == gb.length - 4);
        assert(gb.contentBeforeGap == txt.graphemeSlice(0.GrpmIdx, 6.GrpmIdx));
        assert(gb.contentAfterGap == "7890");

        immutable prevCurPos = gb.cursorPos;
        gb.cursorForward(0.GrpmCount);
        assert(gb.cursorPos == prevCurPos);
    }
}

// cursorPos

@safe unittest
{
    string text     = "1234567890";
    string combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb  = gapbuffer(txt);
        assert(gb.contentGrpmLen == 10);
        assert(gb.cursorPos == 0);
        assert(gb.contentAfterGap.to!string == txt);

        gb.cursorPos = 6.GrpmIdx;
        assert(gb.contentGrpmLen == 10);
        assert(gb.cursorPos == 6);
        assert(gb.contentBeforeGap.to!string == txt.graphemeSlice(0.GrpmIdx, 6.GrpmIdx).text);
        assert(gb.contentAfterGap == "7890");

        gb.cursorPos(0.GrpmCount);
        assert(gb.cursorPos == 0);
        assert(gb.contentAfterGap.to!string == txt);
    }
}

// deleteLeft / deleteRight / addText

@safe unittest
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

@safe unittest
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

@safe unittest
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

// deleteBetween
@safe unittest
{
    string text     = "1234567890";
    string combtext = "r̈a⃑⊥ b⃑67890";

    auto pgb = gapbuffer(text, 10);
    pgb.deleteBetween(0.GrpmIdx, 2.GrpmIdx);
    assert(pgb.content.to!string == "34567890");

    pgb.deleteBetween(2.GrpmIdx, 4.GrpmIdx);
    assert(pgb.content.to!string == "347890");

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 10);
        auto oldMinusTwo = gb[2.GrpmIdx..$];
        gb.deleteBetween(0.GrpmIdx, 2.GrpmIdx);
        assert(gb.content == oldMinusTwo);

        gb = gapbuffer(txt, 10);
        auto oldMinutLastTwo = gb[0.GrpmIdx..8.GrpmIdx];
        gb.deleteBetween(8.GrpmIdx, 10.GrpmIdx);
        assert(gb.content == oldMinutLastTwo);

        gb = gapbuffer(txt, 10);
        gb.deleteBetween(0.GrpmIdx, 10.GrpmIdx);
        assert(gb.length == 0);

        gb = gapbuffer(txt, 10);
        auto oldMinusMiddle = gb[0.GrpmIdx..2.GrpmIdx] ~ gb[4.GrpmIdx..10.GrpmIdx];
        gb.deleteBetween(2.GrpmIdx, 4.GrpmIdx);
        assert(gb.content == oldMinusMiddle);
    }
}

// addAtPosition
@safe unittest
{
    string text     = "1234567890";
    string combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 10);
        gb.addAtPosition(5.GrpmIdx, "foo");
        assert(gb[5.GrpmIdx..$.GrpmIdx] == "foo67890");
    }
}

// clear

/// clear without text
@safe unittest
{
    string text = "1234567890";
    string combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt, 10);
        auto oldBufLen = gb.buffer.length;
        gb.clear();

        // Should have not reallocated since the buffer is bigger than
        // text ("") + configuredGapSize
        assert(gb.buffer.length == oldBufLen);
        assert(gb.content.to!string == "");
        assert(gb.content.length == 0);
        assert(gb.gapStart == 0);
        assert(gb.gapEnd == gb.buffer.length);

        // should-reallocate test
        gb = gapbuffer(txt, 10);
        oldBufLen = gb.buffer.length;
        string newText = txt ~ txt ~ txt ~ txt;
        gb.clear(newText);

        assert(gb.buffer.length == (txt.to!dstring.length * 4) + gb.configuredGapSize);
        assert(gb.content.to!string == txt ~ txt ~ txt ~ txt);

    }
}

/// clear with some text, moving to the end
@safe unittest
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
        assert(gb.cursorPos == newText.length - 1);
        assert(gb.gapStart == newText.length);
        assert(gb.gapEnd == gb.buffer.length);
    }
}

/// clear with some text, moving to the start
@safe unittest
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

// reallocate

@safe unittest
{
    // without adding new text
    string text     = "1234567890";
    string combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt);
        gb.cursorForward(5.GrpmCount);
        immutable prevGapSize = gb.currentGapSize;
        immutable prevGapStart = gb.gapStart;
        immutable prevGapEnd = gb.gapEnd;
        immutable prevCursorPos = gb.cursorPos;

        gb.reallocate();
        assert(gb.reallocCount == 1);
        assert(gb.currentGapSize == prevGapSize);
        assert(prevGapStart == gb.gapStart);
        assert(prevGapEnd == gb.gapEnd);
        assert(prevCursorPos == gb.cursorPos);
    }
}
@safe unittest
{
    // adding new text
    string text     = "1234567890";
    string combtext = "r̈a⃑⊥ b⃑67890";

    foreach(txt; [text, combtext])
    {
        auto gb = gapbuffer(txt);
        gb.cursorForward(GrpmCount(4));

        immutable prevGapSize = gb.currentGapSize;
        immutable prevBufferLen = gb.buffer.length;
        immutable prevGapStart = gb.gapStart;
        immutable prevGapEnd = gb.gapEnd;
        immutable prevCursorPos = gb.cursorPos;

        string newtext = " and some new text ";
        gb.reallocate(newtext);
        assert(gb.reallocCount == 1);
        assert(gb.buffer.length == prevBufferLen + asArray(newtext).length);
        assert(gb.currentGapSize == prevGapSize);
        assert(gb.content.to!string ==
               txt.graphemeSlice(GrpmIdx(0), GrpmIdx(4)) ~
                    newtext ~
                    txt.graphemeSlice(GrpmIdx(4), "$"));
        assert(gb.gapStart == prevGapStart + asArray(newtext).length);
        assert(gb.gapEnd == prevGapEnd + asArray(newtext).length);
        assert(gb.cursorPos == prevCursorPos + newtext.byGrapheme.count);
    }
}

// opIndex

@safe unittest
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

// opSlice

@safe unittest
{
    auto gb = gapbuffer("polompos");
    assert(gb[0..2] == "po");
    assert(gb[0..$.to!long] == "polompos");

    dstring combtext = "r̈a⃑⊥ b⃑67890";
    auto gbc = gapbuffer(combtext);
    assert(gbc[0..$.to!long] == combtext);
    assert(gbc[0..2] == "r̈a⃑");
    assert(gbc[3..5] == " b⃑");
    assert(gbc[5..$.to!long] == "67890");
}

@safe unittest
{
    auto gb = gapbuffer("polompos");
    assert(gb[] == "polompos");
    assert(gb.content == "polompos");

    dstring combtext = "r̈a⃑⊥ b⃑67890";
    auto gbc = gapbuffer(combtext);
    assert(gbc[] == combtext);
    assert(gbc[] == gbc.content);
}

// indexNewLines

@safe unittest
{
    auto gb = gapbuffer("012345678\n012\n", 10);
    gb.indexNewLines;
    assert(gb._newLines.length == 2);
    assert(gb._newLines[0] == 9);
    assert(gb._newLines[1] == 13);
    assert(gb._averageLineLenCP == 7);
}
@safe unittest
{
    auto gb = gapbuffer("01234\n6789\n", 10);
    gb.cursorForward(5.GrpmCount);
    // \n just after gapEnd
    gb.indexNewLines;
    assert(gb._newLines.length == 2);
    assert(gb._newLines[0] == 5);
    assert(gb._newLines[1] == 10);
    assert(gb._averageLineLenCP == 6);

    gb.cursorForward(1.GrpmCount);
    // \n just before gapStart
    gb.indexNewLines;
    assert(gb._newLines.length == 2);
    assert(gb._newLines[0] == 5);
    assert(gb._newLines[1] == 10);
}
@safe unittest
{
    auto gb = gapbuffer("01234\n\n789\n", 10);
    // \n before and after gapStart
    gb.cursorForward(6.GrpmCount);
    gb.indexNewLines;
    assert(gb._newLines.length == 3);
    assert(gb._newLines[0] == 5);
    assert(gb._newLines[1] == 6);
    assert(gb._newLines[2] == 10);
}
@safe unittest
{
    auto gb = gapbuffer("\n", 10);
    gb.indexNewLines;
    assert(gb._newLines.length == 1);
    assert(gb._newLines[0] == 0);
    assert(gb._averageLineLenCP == 1);
}
@safe unittest
{
    auto gb = gapbuffer("\n\n", 10);
    gb.indexNewLines;
    assert(gb._newLines.length == 2);
    assert(gb._newLines[0] == 0);
    assert(gb._newLines[1] == 1);
    assert(gb._averageLineLenCP == 1);
}
@safe unittest
{
    auto gb = gapbuffer("12345", 10);
    gb.indexNewLines;
    assert(gb._newLines.length == 0);
    assert(gb._averageLineLenCP == 5);
}
@safe unittest
{
    auto gb = gapbuffer("", 10);
    gb.indexNewLines;
    assert(gb._newLines.length == 0);
    assert(gb._averageLineLenCP == 0);
}

// lineNumAtPos
@safe unittest
{
    string text =     "01\n34\n67\n90\n";
    string combtext = "01\n34\n67\n90\nr̈a⃑⊥ b⃑\n\n";

    foreach(txt; [text, combtext]) {
        auto gb = gapbuffer(txt, 10);

        assert(gb.lineNumAtPos(0.ArrayIdx) == 1);
        assert(gb.lineNumAtPos(1.ArrayIdx) == 1);
        assert(gb.lineNumAtPos(2.ArrayIdx) == 1);
        assert(gb.lineNumAtPos(3.ArrayIdx) == 2);
        assert(gb.lineNumAtPos(5.ArrayIdx) == 2);
        assert(gb.lineNumAtPos(6.ArrayIdx) == 3);
        assert(gb.lineNumAtPos(8.ArrayIdx) == 3);
        assert(gb.lineNumAtPos(9.ArrayIdx) == 4);
        assert(gb.lineNumAtPos(11.ArrayIdx) == 4);
        assert(gb.lineNumAtPos(999.ArrayIdx) == gb.numLines);

        if (txt == combtext) {
            assert(gb.lineNumAtPos(12.ArrayIdx) == 5);
        } else {
            assert(gb.lineNumAtPos(12.ArrayIdx) == 4);
        }
    }
}

// currentLine
@safe unittest
{
    string text =     "01\n34\n67\n90\n";
    string combtext = "01\n34\n67\n90\nr̈a⃑⊥ b⃑\n";

    foreach(txt; [text, combtext]) {
        auto gb = gapbuffer(txt, 10);
        gb.indexNewLines;

        assert(gb.currentLine == 1);   // pos = 0
        gb.cursorForward(1.GrpmCount); // pos = 1
        assert(gb.currentLine == 1);

        gb.cursorForward(1.GrpmCount); // pos = 2
        assert(gb.currentLine == 1);

        gb.cursorForward(1.GrpmCount); // pos = 3
        assert(gb.currentLine == 2);

        gb.cursorBackward(1.GrpmCount); // pos = 2
        assert(gb.currentLine == 1);

        gb.cursorForward(2.GrpmCount); // pos = 4
        assert(gb.currentLine == 2);

        gb.cursorForward(3.GrpmCount); // pos = 7
        assert(gb.currentLine == 3);

        gb.cursorForward(1.GrpmCount); // pos = 8
        assert(gb.currentLine == 3);

        gb.cursorForward(2.GrpmCount); // pos = 10
        assert(gb.currentLine == 4);

        gb.cursorForward(1.GrpmCount); // pos = 11
        assert(gb.currentLine == 4);
    }
}

// line & numLines
@safe unittest
{

    string text     = "01\n34\n\n";
    string combtext = "01\n34\n\nr̈a⃑⊥ b⃑\n";
    string nonl     = "abc";

    auto gb = gapbuffer(text, 10);
    auto cgb = gapbuffer(combtext, 10);
    auto ngb = gapbuffer(nonl, 10);

    assert(gb.numLines == 3);
    assert(cgb.numLines == 4);
    assert(ngb.numLines == 1);

    assert(gb.lineArraySubject(-3).text == "");
    assert(gb.lineArraySubject(0).text == "");
    assert(gb.lineArraySubject(99999).text == "");
    assert(cgb.lineArraySubject(-3).text == "");
    assert(cgb.lineArraySubject(0).text == "");
    assert(cgb.lineArraySubject(99999).text == "");

    assert(ngb.lineArraySubject(-3).text == "");
    assert(ngb.lineArraySubject(0).text == "");
    assert(ngb.lineArraySubject(99999).text == "");

    assert(gb.lineArraySubject(1).text == "01");
    assert(ngb.lineArraySubject(1).text == "abc");
    assert(cgb.lineArraySubject(1).text == "01");

    assert(gb.lineArraySubject(2).text == "34");
    assert(cgb.lineArraySubject(2).text == "34");

    assert(gb.lineArraySubject(3).text == "");
    assert(cgb.lineArraySubject(3).text == "");

    assert(cgb.lineArraySubject(4).text == "r̈a⃑⊥ b⃑");

    immutable numLinesPre = gb.numLines;
    gb.addText("another line\n");
    assert(gb.numLines == numLinesPre + 1);
    gb.addText("another line\n");
    assert(gb.numLines == numLinesPre + 2);

}

// lineStartPos
@safe unittest
{
    // Line:           1   2   3
    // Pos:            012 345 6
    string text     = "01\n34\n\n";
    //                 1    2    3  4       5
    string combtext = "01\n34\n\nr̈a⃑⊥ b⃑\n\n";
    string nonl     = "abc";

    auto gb = gapbuffer(text, 10);
    auto cgb = gapbuffer(combtext, 10);
    auto ngb = gapbuffer(nonl, 10);

    assert(gb.lineStartPos(0) == 0);
    assert(gb.lineStartPos(1) == 0);
    assert(gb.lineStartPos(2) == 3);
    assert(gb.lineStartPos(3) == 6);
    assert(gb.lineStartPos(4) == 7);
    assert(gb.lineStartPos(100) == 7);

    // _newLines: [0:2, 1:6, 2:8, 3:18, 4:20]
    assert(cgb.lineStartPos(0) == 0);
    assert(cgb.lineStartPos(1) == 0);
    assert(cgb.lineStartPos(2) == 3);
    assert(cgb.lineStartPos(3) == 6);
    assert(cgb.lineStartPos(4) == 7);
    assert(cgb.lineStartPos(5) == 16);
    assert(cgb.lineStartPos(6) == 17);
    assert(cgb.lineStartPos(100) == 17);

    assert(ngb.lineStartPos(0) == 0);
    assert(ngb.lineStartPos(1) == 0);
    assert(ngb.lineStartPos(2) == 0);
    assert(ngb.lineStartPos(100) == 0);

    gb = gapbuffer("01\n34\npok");
    assert(gb.numLines == 3);
    assert(gb.lineStartPos(3) == 6);
}

// lineEndPos
@safe unittest
{
    // Line:           1   2   3
    // Pos:            012 345 6
    string text     = "01\n34\n\n";
    string combtext = "01\n34\n\nr̈a⃑⊥ b⃑\n";
    string nonl     = "abc";

    auto gb = gapbuffer(text, 10);
    auto cgb = gapbuffer(combtext, 10);
    auto ngb = gapbuffer(nonl, 10);

    assert(gb.lineEndPos(0) == 0);
    assert(gb.lineEndPos(1) == 2);
    assert(gb.lineEndPos(2) == 5);
    assert(gb.lineEndPos(3) == 6);
    assert(gb.lineEndPos(4) == 6);
    assert(gb.lineEndPos(100) == 6);

    assert(cgb.lineEndPos(0) == 0);
    assert(cgb.lineEndPos(1) == 2);
    assert(cgb.lineEndPos(2) == 5);
    assert(cgb.lineEndPos(3) == 6);
    assert(cgb.lineEndPos(4) == 12);
    assert(cgb.lineEndPos(5) == 12);
    assert(cgb.lineEndPos(100) == 12);

    assert(ngb.lineEndPos(0) == 0);
    assert(ngb.lineEndPos(1) == 2);
    assert(ngb.lineEndPos(2) == 2);
    assert(ngb.lineEndPos(100) == 2);

                  //1   2   3
                  //012 345 678
    gb = gapbuffer("01\n34\npok");
    assert(gb.numLines == 3);
    assert(gb.lineEndPos(3) == 8);
}

// currentCol
@safe unittest
{
    // Line:           1   2   3
    // Pos:            012 345 6
    string text     = "01\n34\n\n";
    string combtext = "01\n34\n\nr̈a⃑⊥ b⃑\n";
    string nonl     = "abc";

    auto gb = gapbuffer(text, 10);
    auto cgb = gapbuffer(combtext, 10);
    auto ngb = gapbuffer(nonl, 10);

    // cursorPos == 0, line: 1, col: 1
    assert(gb.currentCol == 1);
    assert(cgb.currentCol == 1);

    gb.cursorForward(1.GrpmIdx);
    cgb.cursorForward(1.GrpmIdx);
    ngb.cursorForward(1.GrpmIdx);

    // cursorPos == 1, line: 1, col: 2
    assert(gb.currentCol == 2);
    assert(cgb.currentCol == 2);
    assert(ngb.currentCol == 2);

    gb.cursorForward(1.GrpmIdx);
    cgb.cursorForward(1.GrpmIdx);
    ngb.cursorForward(1.GrpmIdx);

    // cursorPos == 2, line: 1, col: 1 for gb & cgb (because of \n), 3 for ngb
    assert(gb.currentCol == 1);
    assert(cgb.currentCol == 1);
    assert(ngb.currentCol == 3);

    gb.cursorForward(1.GrpmIdx);
    cgb.cursorForward(1.GrpmIdx);
    ngb.cursorForward(1.GrpmIdx);

    // cursorPos == 3, line: 1, col: 1 for gb & cgb (because of \n), 3 for ngb
    // Second line for gb and cgb
    assert(gb.currentCol == 1);
    assert(cgb.currentCol == 1);
    assert(ngb.currentCol == 3);

    gb.cursorForward(1000.GrpmIdx);
    cgb.cursorForward(1000.GrpmIdx);
    ngb.cursorForward(1000.GrpmIdx);

    // assert(gb.currentCol == 1);
    assert(cgb.currentCol == 1);
    assert(ngb.currentCol == 3);
}

// cursorToLine
@safe unittest
{
    string text     = "01\n34\n\n";
    string combtext = "01\n34\n\nr̈a⃑⊥ b⃑\n";
    string nonl     = "abc";

    auto gb = gapbuffer(text, 10);
    auto cgb = gapbuffer(combtext, 10);
    auto ngb = gapbuffer(nonl, 10);

    ngb.cursorToLine(0);
    assert(ngb.cursorPos == 0);
    ngb.cursorToLine(10);
    assert(ngb.cursorPos == 0);

    gb.cursorToLine(0);
    assert(gb.cursorPos == 0);
    gb.cursorToLine(1);
    assert(gb.cursorPos == 0);
    gb.cursorToLine(2);
    assert(gb.cursorPos == 3);
    gb.cursorToLine(3);
    assert(gb.cursorPos == 6);
    gb.cursorToLine(4);
    assert(gb.cursorPos == 6);
    gb.cursorToLine(10);
    assert(gb.cursorPos == 6);

    cgb.cursorToLine(4);
    assert(cgb.cursorPos == 7);
    cgb.cursorToLine(5);
    assert(cgb.cursorPos == 12);
    cgb.cursorToLine(100);
    assert(cgb.cursorPos == 12);
}

// deleteLine
@safe unittest
{
    // Line:       1   2   3
    // Pos:        012 345 6
    string text = "01\n34\n\n";
    string nonl = "abc";

    auto gb = gapbuffer(text, 10);
    auto ngb = gapbuffer(nonl, 10);

    ngb.deleteLine(0);
    assert(ngb.content.to!string == nonl);
    ngb.deleteLine(1);
    assert(ngb.content.to!string == "");

    ngb = gapbuffer(nonl, 10);
    ngb.deleteLine(100);
    assert(ngb.content.to!string == nonl);

    gb.deleteLine(1);
    assert(gb.content.to!string == "34\n\n");
    gb.deleteLine(1);
    assert(gb.content.to!string == "\n");
    gb.deleteLine(1);
    assert(gb.content.to!string == "");

    gb = gapbuffer(text, 10);
    gb.deleteLine(2);
    assert(gb.content.to!string == "01\n\n");
    gb = gapbuffer(text, 10);
    gb.deleteLine(3);
    assert(gb.content.to!string == "01\n34\n");

    gb = gapbuffer("01\n34\npok\n", 10);
    gb.deleteLine(3);
    assert(gb.content.to!string == "01\n34\n");

    gb = gapbuffer("01\n34\npok", 10);
    gb.deleteLine(3);
    assert(gb.content.to!string == "01\n34\n");
}

// deleteLines
@safe unittest
{
    // Line:       1   2   3
    // Pos:        012 345 6
    string text = "01\n34\n\n";

    auto gb = gapbuffer(text, 10);
    gb.deleteLines([1, 3]);
    assert(gb.content == "34\n");

    gb = gapbuffer(text, 10);
    gb.deleteLines([1]);
    assert(gb.content == "34\n\n");

    gb = gapbuffer(text, 10);
    gb.deleteLines([2]);
    assert(gb.content == "01\n\n");

    gb = gapbuffer(text, 10);
    gb.deleteLines([3]);
    assert(gb.content == "01\n34\n");

    gb = gapbuffer(text, 10);
    gb.deleteLines([100]);
    assert(gb.content == "01\n34\n\n");

    gb = gapbuffer(text, 10);
    gb.deleteLines([2, 3]);
    assert(gb.content == "01\n");

    gb = gapbuffer(text, 10);
    gb.deleteLines([3, 2, 18, 999, 32, 43, 16, -1]);
    assert(gb.content == "01\n");

    string nonl = "abc";
    auto ngb = gapbuffer(nonl, 10);
    ngb.deleteLines([1]);
    assert(ngb.content == "");

    ngb = gapbuffer(nonl, 10);
    ngb.deleteLines([18]);
    assert(ngb.content == "abc");

    ngb = gapbuffer(nonl, 10);
    ngb.deleteLines([0, 1, 3, 9]);
    assert(ngb.content == "");
}

// grpmPos2CPPos
@safe unittest
{
    dstring text = " a⃑ b⃑ "d;

    auto gb = gapbuffer(text, 10);
    assert(gb.grpmPos2CPPos(0.GrpmIdx) == 0);
    assert(gb.grpmPos2CPPos(1.GrpmIdx) == 1);
    assert(gb.grpmPos2CPPos(2.GrpmIdx) == 3);
    assert(gb.grpmPos2CPPos(3.GrpmIdx) == 4);
    assert(gb.grpmPos2CPPos(4.GrpmIdx) == 6);
    assert(gb.grpmPos2CPPos(9.GrpmIdx) == 6);
}

// cpPos2grpmPos
@safe unittest
{
    dstring text = " a⃑ b⃑ "d;

    auto gb = gapbuffer(text, 10);
    assert(gb.CPPos2GrpmPos(0) == 0);
    assert(gb.CPPos2GrpmPos(1) == 1);
    assert(gb.CPPos2GrpmPos(2) == 1);
    assert(gb.CPPos2GrpmPos(3) == 2);
    assert(gb.CPPos2GrpmPos(4) == 3);
    assert(gb.CPPos2GrpmPos(5) == 3);
    assert(gb.CPPos2GrpmPos(6) == 4);
    assert(gb.CPPos2GrpmPos(9) == 4);
}