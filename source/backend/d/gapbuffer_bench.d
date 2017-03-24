module gapbuffer_benchmark;

import core.memory: GC;
import gapbuffer: GapBuffer;
import std.conv: to;
import std.datetime;
import std.stdio;


//private void bench_overlaps1(uint iterations)
//{
    //auto overlaps1_call = () => overlaps(0, 4, 2, 3);
    //auto duration = benchmark!overlaps1_call(iterations);
    //writeln("overlaps simple: ", to!Duration(duration[0]));
//}

version(none) {
private void bench_fill(uint iterations)
{
    import std.algorithm: fill;
    import std.array: replicate;

    dchar[] a = null;
    dchar[] filler = ['-'];

    // no fill: 1.4 seconds. This wins for release builds.
    immutable fillrandom = () => a = new dchar[100];
    auto duration = benchmark!fillrandom(iterations);
    writeln("fillrandom: ", to!Duration(duration[0]));

    // with replicate: 1.98 seconds. This wins for debug builds
    // (seeing some marked chars for the gap when printing the buffer helps a lot)
    immutable fillreplicate = () => a = replicate(filler, 100);
    duration = benchmark!fillreplicate(iterations);
    writeln("fillreplicate: ", to!Duration(duration[0]));

    // with fill: 18.656 seconds, bug? check with the forums
    void fillfill() {
        a = new dchar[100];
        fill(a, filler);
    }
    duration = benchmark!fillfill(iterations);
    writeln("fillfill: ", to!Duration(duration[0]));

    // Conclusion:
    // Replicate will be used for debug builds, no fill (new CharT[size]) for release builds
}
}

// This benchs 3 implementations of the cursor movement methods:
// 1. Simple slice copy in the array, using .dup if there is overlap
// 2. Using std.algorithm.copy
// 3. Always using .dup
version(none) {
private void bench_cursorMovement(uint iterations)
{
    // First test, using a extremely small buffer to provoke overlap
    scope gb = GapBuffer("This is some fine initial text", 2);

    void moveSliceIntelligentDup() {
        gb.cursorBackward(1000);
        gb.cursorForward(15);
        gb.cursorBackward(10);
    }

    void moveSliceAlwaysDup() {
        gb.cursorBackward_alwaysdup(1000);
        gb.cursorForward_alwaysdup(15);
        gb.cursorBackward_alwaysdup(10);
    }

    void moveSliceAlgoCopy() {
        gb.cursorBackward_algocopy(1000);
        gb.cursorForward_algocopy(15);
        gb.cursorBackward_algocopy(10);
    }

    // Results for 100.000.00 iterations (debug/release/release_no bounds_check, in seconds)
    writeln("Cursor movement/text copy with a tiny gap");

    // 37.24/29.3/29.1
    auto duration = benchmark!moveSliceIntelligentDup(iterations);
    writeln("move_intelDup: ", to!Duration(duration[0]));

    // 35.58/30.5/28.9
    // Since the copies in this test almost always overlap and we always
    // need to .duplicate, the previous version loses a little more time
    // checking for overlap
    duration = benchmark!moveSliceAlwaysDup(iterations);
    writeln("move_alwaysDup: ", to!Duration(duration[0]));

    // 13.12/6.1/6.34
    // With a lot of overlap, this is much faster. I also benefits a lot from release mode.
    duration = benchmark!moveSliceAlgoCopy(iterations);
    writeln("move_algoCopyDup: ", to!Duration(duration[0]));

    // Repeat with a big gap that wont overlap
    gb = GapBuffer("This is some fine initial text", 1024);

    // 8.8/4.8/4.1
    // Takes a lot less time than the previous tests since now the
    // "intelligent" overlap detection actually prevents a lot of .dups
    writeln("Cursor movement/text copy with a medium gap");
    duration = benchmark!moveSliceIntelligentDup(iterations);
    writeln("move_intelDup: ", to!Duration(duration[0]));

    // 34.8/31.5/29.8
    // Same as the previous test, except now its worse compared with
    // intelDup and algoCopy
    duration = benchmark!moveSliceAlwaysDup(iterations);
    writeln("move_alwaysDup: ", to!Duration(duration[0]));

    // 9.3/6.3/6.3
    // Slightly slower than "intelligentDup" but not so much
    // as to not be selected as winner because of the performance increase with many
    // overlaps, legibility and maintanibility of this version
    duration = benchmark!moveSliceAlgoCopy(iterations);
    writeln("move_algoCopyDup: ", to!Duration(duration[0]));

    // Conclusions:
    // 1. Use std.algorithm.copy to copy parts of the buffer
    // 2. -noboundscheck slight performance increase is not worth it
    // 3. There is negligible difference between dchar/dstring and char/string as base types
}
}

/// This benchmark will call reallocate with different sized buffers and texts.
/// It must determine if simple array concatenation (a ~ b ~ c) is faster than
/// using an appender
version(none) {
private void bench_appendarray(uint iterations)
{
    scope gb = GapBuffer("This is some fine initial text", 16);
    gb.addText("bu");
    auto textToAdd = " and this is some aditional text that is a little longer";

    void realloc() {
        gb.addText("polompos"); // so gap is smaller than originalGapSize and must extend
        gb.reallocate(textToAdd);
    }
    void realloc_insert() {
        gb.addText("polompos"); // so gap is smaller than originalGapSize and must extend
        gb.reallocate_insert(textToAdd);
    }

    // 1.2
    auto duration = benchmark!realloc(iterations);
    writeln("Realloc with array concatenation: ", to!Duration(duration[0]));
    writeln(gb.gapExtensionCount);

    // 6.3...
    //duration = benchmark!realloc_appender(iterations);
    //writeln("Realloc with appender: ", to!Duration(duration[0]));

    // 28 msecs!
    duration = benchmark!realloc_insert(iterations);
    writeln("Realloc with inserter: ", to!Duration(duration[0]));
    writeln(gb.gapExtensionCount);

    // Conclusion:
    // reallocating and extending the gap with the insertInPlace
    // is much faster specially when it doesnt need to extend much the currentGap
}
}

void bench()
{
    auto g = GapBuffer!string("");

    //uint iterations = 10_000_000;
    //bench_overlaps1(iterations);
    //bench_fill(iterations);

    //iterations = 100_000_000;
    //bench_cursorMovement(iterations);

    //uint iterations = 10_000;
    //bench_appendarray(iterations);
}
