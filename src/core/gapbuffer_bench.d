module neme.core.gapbuffer_bench;

import core.memory: GC;
import std.conv: to;
import std.datetime.stopwatch;
import std.stdio;
import std.typecons;

import neme.core.gapbuffer;

enum DO_SLOW = true;
enum DO_FAST = true;

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
private void benchProgrammingSessionCP(GBType)()
{
    // test 1: combining chars (slow path enabled)
    enum code_multi = import("fixtures/testbench_code_multicp.txt");
    enum code_nomulti = import("fixtures/testbench_code_nomulti.txt");
    enum gapsize = 1024*32; // seems to be the sweet spot for this test (we're not testing allocation)
    GBType preLoadedGapBuffer = void;

    void editSessionLowLevel() {
        // 32kb of buffer seems to be a sweet spot for this test
        GBType g = void;
        g = preLoadedGapBuffer;

        g.addText("private void benchProgrammingSessionCP(bool benchBufferLoad = true) {\n");
        g.cursorBackward(GrpmCount(10));
        g.cursorForward(GrpmCount(12));
        g.addText("enum code = import(\"fixtures/testbench_code_multicp.txt\");\nY");
        g.deleteLeft(1.to!GrpmCount);
        g.addText("X");
        g.addText("immutable fillreplicate = () => a = replicate(filler, 100);\n");
        g.cursorBackward(GrpmCount(10));
        g.deleteRight(GrpmCount(8));
        g.addText("1234567890 ");
        g.cursorForward(GrpmCount(2));
        g.deleteRight(GrpmCount(160));
        g.addText("// With a lot of overlap, this is much faster. I also benefits a lot from release mode.\n");
        g.addText("// is much faster specially when it doesnt need to extend much the currentGap blablabla.\n");
        g.addText("// End of the loop!\n");
        g.cursorBackward(GrpmCount(200));
    }

    void editSessionHighLevel() {
        import repl = neme.frontend.repl.repl_lib;
        GBType g = void;

        g = preLoadedGapBuffer;
        repl.Command cmd;

        cmd.textParam = "// dfjksdjkfhdskfh sdkjfhsdkj\n";
        repl.appendText(g, cmd);

        cmd.textParam = "private void benchProgrammingSessionCP(bool benchBufferLoad = true) {\n";
        repl.appendText(g, cmd);

        cmd.params = ["10"];
        repl.cursorLeft(g, cmd);

        cmd.textParam = "// dfjksdjkfhdskfh sdkjfhsdkj\n";
        repl.appendText(g, cmd);

        cmd.params = ["12"];
        repl.cursorRight(g, cmd);

        cmd.textParam = "enum code = import(\"fixtures/testbench_code_multicp.txt\");\nY";
        repl.appendText(g, cmd);

        cmd.params = ["1"];
        repl.deleteCharsLeft(g, cmd);

        cmd.textParam = "X";
        repl.appendText(g, cmd);

        cmd.textParam = "immutable fillreplicate = () => a = replicate(filler, 100);\n";
        repl.appendText(g, cmd);

        cmd.params = ["10"];
        repl.cursorLeft(g, cmd);

        cmd.params = ["8"];
        repl.deleteCharsRight(g, cmd);

        cmd.textParam = "1234567890 ";
        repl.appendText(g, cmd);

        cmd.params = ["2"];
        repl.cursorRight(g, cmd);

        cmd.params = ["160"];
        repl.deleteCharsRight(g, cmd);

        cmd.textParam = "// With a lot of overlap, this is much faster. I also benefits a lot from release mode.\n";
        repl.appendText(g, cmd);

        cmd.textParam = "// is much faster specially when it doesnt need to extend much the currentGap blablabla.\n";
        repl.appendText(g, cmd);

        cmd.textParam = "// End of the loop!\n";
        repl.appendText(g, cmd);

        cmd.params = ["200"];
        repl.cursorLeft(g, cmd);

        cmd.textParam = "line\n another line \n and even another line \n";
        repl.appendText(g, cmd);

        cmd.params = ["5"];
        repl.lineUp(g, cmd);

        cmd.params = ["2"];
        repl.deleteLines(g, cmd);

        cmd.params = ["1", "1"];
        repl.gotoLineCol(g, cmd);

        repl.insertLineAbove(g, cmd);
        repl.insertLineBelow(g, cmd);

        cmd.params = ["4", "1"];
        repl.gotoLineCol(g, cmd);

        cmd.params = ["4"];
        repl.wordLeft(g, cmd);
        repl.wordRight(g, cmd);

        cmd.params = ["3"];
        repl.lineUp(g, cmd);
        repl.lineDown(g, cmd);

        cmd.params = ["5"];
        repl.deleteWordLeft(g, cmd);
        repl.deleteWordRight(g, cmd);
    }

    enum iterations = 100;
    Duration[1] duration = void;

    // best benchmark done with dub run --compiler=ldc2 --build=release-nobounds --config=optimized

    /+
     ╔══════════════════════════════════════════════════════════════════════════════
     ║ ⚑ "Slow indexing" (compatible with Unicode multi CP graphemes)
     ╚══════════════════════════════════════════════════════════════════════════════
    +/
    if (DO_SLOW) { 
        writeln("1. Grapheme (slow) mode:");
        preLoadedGapBuffer = GBType(code_multi, gapsize);
        assert(preLoadedGapBuffer.hasCombiningGraphemes);
        duration = benchmark!(() => editSessionLowLevel) (iterations);
        writeln("\t1.1 Using 16 low level gapbuffer methods: ", to!Duration(duration[0]));

        preLoadedGapBuffer = GBType(code_multi, gapsize);
        assert(preLoadedGapBuffer.hasCombiningGraphemes);
        duration = benchmark!(() => editSessionHighLevel) (iterations);
        writeln("\t1.2 Using 27 high level text object operations: ", to!Duration(duration[0]));
    }

    writeln;

    /+
     ╔══════════════════════════════════════════════════════════════════════════════
     ║ ⚑ "Fast indexing" (incompatible with Unicode multi CP graphemes)
     ╚══════════════════════════════════════════════════════════════════════════════
    +/

    if (DO_FAST) {
        writeln("2. Single-CP (fast) mode:");
        preLoadedGapBuffer = GBType(code_nomulti, gapsize);
        assert(!preLoadedGapBuffer.hasCombiningGraphemes);
        duration = benchmark!(() => editSessionLowLevel) (iterations);
        writeln("\t2.1 Using 16 low level gapbuffer methods: ", to!Duration(duration[0]));

        preLoadedGapBuffer = GBType(code_nomulti, gapsize);
        assert(!preLoadedGapBuffer.hasCombiningGraphemes);
        duration = benchmark!(() => editSessionHighLevel) (iterations);
        writeln("\t2.2 Using 27 high level text object operations: ", to!Duration(duration[0]));
    }
}

// Test small, medium and big reallocations performance
void benchReallocations()
{
    import std.array: replicate;
    import core.memory: GC;


    dstring smalltext = "some text";
    enum dstring mediumtext = replicate(['-'.to!dchar], 1024*10);
    enum dstring bigtext = replicate(['-'.to!dchar], 1024*1024);

    pragma(inline)
    void reallocations(dstring newtext) {
        auto gb = gapbuffer("some initial text", 2);
        gb.addText(newtext);
        gb.clear(newtext);
    }

    immutable smallReallocs  = () => reallocations(smalltext);
    immutable mediumReallocs = () => reallocations(mediumtext);
    immutable bigReallocs    = () => reallocations(bigtext);

    Duration[1] duration = void;
    enum iterations = 100;

    duration = benchmark!smallReallocs(iterations);
    writeln("\t", iterations, " small reallocations: ", to!Duration(duration[0]));
    GC.minimize();

    duration = benchmark!mediumReallocs(iterations);
    writeln("\t", iterations, " medium reallocations: ", to!Duration(duration[0]));
    GC.minimize();

    duration = benchmark!bigReallocs(iterations);
    writeln("\t", iterations, " big reallocations: ", to!Duration(duration[0]));
    GC.minimize();
}

void bench()
{
    writeln("Emulated programming session (100 iterations): ");
    benchProgrammingSessionCP!GapBuffer;

    writeln;

    writeln("\nReallocations: ");
    benchReallocations;
}
