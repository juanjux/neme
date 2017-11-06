module neme.core.extractors_test;

import extractors = neme.core.extractors;
import neme.core.types;
import neme.core.predicates;
import neme.core.gapbuffer;

import std.stdio;
import std.conv;

// lines
@safe unittest
{
    string text     = "01\n34\n\n";
    auto gb = gapbuffer(text, 10);

    auto res = extractors.lines(gb, 3.GrpmIdx, Direction.Front, 4);
    assert(res.length == 3);
    assert(res[0] == Subject(3.GrpmIdx, 5.GrpmIdx, "34".to!BufferType));
    assert(res[1] == Subject(6.GrpmIdx, 6.GrpmIdx, "".to!BufferType));
    assert(res[2] == Subject(0.GrpmIdx, 2.GrpmIdx, "01".to!BufferType));

    auto resback = extractors.lines(gb, 2.GrpmIdx, Direction.Back, 4);
    assert(resback[0] == res[2]);
    assert(resback[1] == res[1]);
    assert(resback[2] == res[0]);

    gb.cursorForward(3.GrpmCount);
    auto res2 = extractors.lines(gb, 3.GrpmIdx, Direction.Front, 4);
    assert(res == res2);

    // test wraparound
    gb = gapbuffer(text, 10);
    res = extractors.lines(gb, 3.GrpmIdx, Direction.Front, 3);
    assert(res[0] == Subject(3.GrpmIdx, 5.GrpmIdx, "34".to!BufferType));
}
@safe unittest
{
    auto ngb = gapbuffer("abc", 10);

    auto res = extractors.lines(ngb, 0.GrpmIdx, Direction.Front, 1);
    assert(res.length == 1);
    assert(res[0] == Subject(0.GrpmIdx, 3.GrpmIdx, "abc".to!BufferType));

    auto res2 = extractors.lines(ngb, 1.GrpmIdx, Direction.Front, 1);
    assert(res == res2);

    res = extractors.lines(ngb, 1.GrpmIdx, Direction.Front, 3);
    assert(res.length == 1);

    auto res3 = extractors.lines(ngb, 1.GrpmIdx, Direction.Back, 3);
    assert(res3 == res);

}
@safe unittest
{
    auto gb = gapbuffer("", 10);

    auto res = extractors.lines(gb, 0.GrpmIdx, Direction.Front, 1);
    assert(res[0] == Subject(0.GrpmIdx, 0.GrpmIdx, "".to!BufferType));

    auto res2 = extractors.lines(gb, 100.GrpmIdx, Direction.Front, 1);
    assert(res2 == res);

    auto res3 = extractors.lines(gb, 0.GrpmIdx, Direction.Front, 3);
    assert(res3 == res2);

    auto res4 = extractors.lines(gb, 0.GrpmIdx, Direction.Back, 3);
    assert(res4 == res2);
}
@safe unittest
{
    string combtext = "01\n34\n\n a⃑ b⃑ \n";
    auto gb = gapbuffer(combtext, 10);

    auto res = extractors.lines(gb, 0.GrpmIdx, Direction.Front, 4);
    assert(res[0] == Subject(0.GrpmIdx, 2.GrpmIdx, "01".to!BufferType));
    assert(res[1] == Subject(3.GrpmIdx, 5.GrpmIdx, "34".to!BufferType));
    assert(res[2] == Subject(6.GrpmIdx, 6.GrpmIdx, "".to!BufferType));
    assert(res[3] == Subject(7.GrpmIdx, 12.GrpmIdx, " a⃑ b⃑ ".to!BufferType));

    auto resback = extractors.lines(gb, gb.length, Direction.Back, 4);
    assert(resback[0] == res[3]);
    assert(resback[1] == res[2]);
    assert(resback[2] == res[1]);
    assert(resback[3] == res[0]);

    gb.cursorForward(3.GrpmCount);

    auto res2 = extractors.lines(gb, 0.GrpmIdx, Direction.Front, 4);
    assert(res == res2);
}


// words
@safe unittest
{
    string text = "foo\nbar polompos\npok,.{}\tsomething\n";

    auto gb = gapbuffer(text, 10);
    // XXX test wrap-around
    auto res = extractors.words(gb, 4.GrpmIdx, Direction.Front, 4);
    assert(res.length == 4);
    assert(res[0] == Subject(4.GrpmIdx, 6.GrpmIdx, "bar".to!BufferType));
    assert(res[1] == Subject(8.GrpmIdx, 15.GrpmIdx, "polompos".to!BufferType));
    assert(res[2] == Subject(17.GrpmIdx, 19.GrpmIdx, "pok".to!BufferType));
    assert(res[3] == Subject(25.GrpmIdx, 33.GrpmIdx, "something".to!BufferType));
}


// XXX word tests: wrap around, empty line, single word and multi code point