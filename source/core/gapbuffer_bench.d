module neme.core.gapbuffer_bench;

import core.memory: GC;
import neme.core.gapbuffer;
import std.conv: to;
import std.datetime;
import std.stdio;
import std.typecons;


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
    scope gb = gapbuffer("This is some fine initial text", 2);

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
    gb = gapbuffer("This is some fine initial text", 1024);

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
    scope gb = gapbuffer("This is some fine initial text", 16);
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

/** This benchmarks the performance of an emulated coding session doing these operations:

    1. Opening a buffer (optionally this can be ignored in the benchmark)
    2. Writing small chunk of text, going back 10 characters, deleting 2, inserting 2,
       another chunk, replace the last character, chunk, back 10, delete 8 (word), add 10,
       deleting 160 to the right (two lines), adding 160, repeat.
*/
// TODO: add some other operations:
// Searches
// Replacements
// Operations on text objects
// ...etc
private void benchProgrammingSessionCP()
{
    // test 1: combining chars (slow path enabled)
    enum code = import("fixtures/testbench_code_multicp.txt");
    enum gapsize = 1024*32; // seems to be the sweet spot for this test (we're not testing allocation)
    GapBuffer preLoadedGapBuffer = void;

    void editSession(string code, Flag!"forceFastMode" forceFastMode, Flag!"doLoad" doLoad=Yes.doLoad) {
        // 32kb of buffer seems to be a sweet spot for this test
        GapBuffer g = void;
        if (doLoad) {
            g = gapbuffer("", gapsize);
            g.forceFastMode = forceFastMode;
            g.clear(code);
            g.cursorPos = g.contentLength / 2;
        } else {
            g = preLoadedGapBuffer;
        }

        foreach (i; 0..100) {
            g.addText("private void benchProgrammingSessionCP(bool benchBufferLoad = true) {\n");
            g.cursorBackward(10);
            g.addText("XX");
            g.cursorForward(12);
            g.addText("enum code = import(\"fixtures/testbench_code_multicp.txt\");\nY");
            g.deleteLeft(1);
            g.addText("X");
            g.addText("immutable fillreplicate = () => a = replicate(filler, 100);\n");
            g.cursorBackward(10);
            g.deleteRight(8);
            g.addText("1234567890 ");
            g.cursorForward(2);
            g.deleteRight(160);
            g.addText("// With a lot of overlap, this is much faster. I also benefits a lot from release mode.\n");
            g.addText("// is much faster specially when it doesnt need to extend much the currentGap blablabla.\n");
            g.addText("// End of the loop!\n");
            g.cursorBackward(200);
        }
    }

    enum iterations = 10;

    auto editSessionSlow   = () => editSession(code, No.forceFastMode);
    auto editSessionFast   = () => editSession(code, Yes.forceFastMode);
    auto editSessionNoLoad = () => editSession(code, Yes.forceFastMode, No.doLoad);

    TickDuration[1] duration = void;

    // best benchmark done with dub run --compiler=ldc2 --build=release-nobounds
    // dmd / dmd-release / ldc / ldc-release (10 iterations)

    // before indexes:
    // 3 mins 1 sec || release: 51 secs || ldc: 2 mins 36 secs || ldc-release: 18.21 secs
    duration = benchmark!editSessionSlow(iterations);
    writeln("Edit session, slow operations: ", to!Duration(duration[0]));

    // before indexes:
    // 1 min 54 secs || release: 33 secs || ldc: 1min 38 secs || ldc-release: 11.66 secs
    preLoadedGapBuffer = gapbuffer(code, gapsize);
    preLoadedGapBuffer.forceFastMode = false;
    duration = benchmark!editSessionNoLoad(iterations);
    writeln("Edit session, slow operations, not including initial load: ", to!Duration(duration[0]));

    // before indexes:
    // 19 msecs || release: 6 msecs || ldc: 16 msecs || ldc-release: 2.2 msecs
    duration = benchmark!editSessionFast(1);
    writeln("Edit session, fast operations: ", to!Duration(duration[0]));

    // before indexes:
    // 605 μs || release: 395 μs || ldc: 395 μs || ldc-release: 179 μs
    preLoadedGapBuffer = gapbuffer(code, gapsize);
    preLoadedGapBuffer.forceFastMode = true;
    duration = benchmark!editSessionNoLoad(iterations);
    writeln("Edit session, fast operations, not including initial load: ", to!Duration(duration[0]));
}

void bench()
{
    auto g = gapbuffer();
    benchProgrammingSessionCP();

    //uint iterations = 10_000_000;
    //bench_overlaps1(iterations);
    //bench_fill(iterations);

    //iterations = 100_000_000;
    //bench_cursorMovement(iterations);

    //uint iterations = 10_000;
    //bench_appendarray(iterations);
}
