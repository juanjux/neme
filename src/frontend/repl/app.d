module neme.frontend.repl.app;

import neme.core.gapbuffer: gapbuffer, GapBuffer, ArrayIdx;
import neme.core.extractors;
import neme.core.types;
import neme.frontend.repl.repl_lib;
import extractors = neme.core.extractors;
import std.array: array;

import std.stdio;
import std.conv: to;
import std.algorithm.iteration: map, each;
import std.algorithm.comparison : max, min;


// Simple sed-like REPL interface. For benchmarks and integration tests.

int main(string[] args)
{
    import std.file: readText;

    GapBuffer gb = null;

    if (args.length > 1) {
        gb = gapbuffer(readText(args[1]));
    }
    else {
        gb = gapbuffer("");
    }

    foreach(line; stdin.byLine()) {
        auto command = parseCmdLine(line.to!string);
        // writeln(command);

        // FIXME: autogenerate at compile time
        switch(command.cmd)
        {
        case "p":
        case "print":
            printBuffer(gb);
            break;
        case "pl":
        case "printLines":
            printLines(gb, command);
            break;
        case "dl":
        case "deleteLines":
            deleteLines(gb, command);
            break;
        case "a":
        case "addText":
            addText(gb, command);
            break;
        case "ap":
        case "appendText":
            appendText(gb, command);
            break;
        case "dcl":
        case "deleteCharsLeft":
            deleteCharsLeft(gb, command);
            break;
        case "dcr":
        case "deleteCharsRight":
            deleteCharsRight(gb, command);
            break;
        case "g":
        case "goto":
            gotoLineCol(gb, command);
            break;
        case "l":
        case "curLeft":
            cursorLeft(gb, command);
            break;
        case "r":
        case "curRight":
            cursorRight(gb, command);
            break;
        case "ila":
        case "insertLineAbove":
            insertLineAbove(gb, command);
            break;
        case "ilb":
        case "insertLineBelow":
            insertLineBelow(gb, command);
            break;
        case "lf":
        case "loadFile":
            loadFile(gb, command);
            break;
        case "sf":
        case "saveFile":
            saveFile(gb, command);
            break;
        case "wl":
        case "wordLeft":
            wordLeft(gb, command);
            break;
        case "wr":
        case "wordRight":
            wordRight(gb, command);
            break;
        case "lu":
        case "lineUp":
            lineUp(gb, command);
            break;
        case "ld":
        case "lineDown":
            lineDown(gb, command);
            break;
        case "dwl":
        case "deleteWordLeft":
            deleteWordLeft(gb, command);
            break;
        case "dwr":
        case "deleteWordRight":
            deleteWordRight(gb, command);
            break;
        case "q":
        case "quit":
            writeln("Bye!");
            return 0;

        default:
            error(command);
            break;
        }
    }

    return 0;
}
