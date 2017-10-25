module neme.frontend.repl.app;

import neme.core.gapbuffer: gapbuffer, GapBuffer, ArrayIdx;
import std.array: array;

import std.stdio;
import std.conv: to;
import std.algorithm.iteration: map, each;


// Simple sed-like (but dumber) REPL interface. For benchmarks and integration tests.

/* TODO:
 * 1. Read a commandline argument to load a file from the start.
 * 2. Commands:
 *  - go to line
 *  - move cursor left or right
 *  - add text at cursor position
 *  - add text at specific position
 *  - delete n characters from position
 *  - insert new line (optional: with text)
 *  - load and save file
 *  - move words left, right
 *  - move chars left, right
 *  - move lines up, down
 *  - delete words left, right
 *  - replace words left, right
 */


void printBuffer(ref GapBuffer gb)
{
    import std.string: splitLines, leftJustify;
    import std.format;

    auto contentLines = gb.content.splitLines;
    auto lwidth = contentLines.length.to!string.length;

    foreach(idx, line; contentLines) {
        writeln(leftJustify(format!"%d"(idx+1), lwidth), "| ", line);
    }
}


struct Command
{
    string cmd;
    string[] params;
    string textParam;
}


Command parseLine(string line)
{
    import std.array: split, join;
    import std.string: indexOf;

    // Cmd format: cmd[param1,param2] [text]
    // Param1 is usually the line number or the start of a range
    Command c;
    string[] tmpParams;

    auto tokens = line.split(",");

    if (tokens.length > 0) {
        c.cmd = tokens[0].to!string;
        tmpParams = tokens[1..$];
    }

    if (tmpParams.length > 1) {
        tmpParams = to!(string[])(tmpParams[0..$]);

        if (indexOf(tmpParams[$-1], ' ') != -1) {
            auto subtokens = tmpParams[$-1].split(" ");
            tmpParams[$-1] = subtokens[0];

            if (subtokens.length > 0) {
                c.textParam =  join(subtokens[1..$]).to!string;
            }
        }
    }
    c.params = tmpParams;
    return c;
}


void error(Command command)
{
    writeln("Unkown command: ", command.cmd);
}


void printLines(GapBuffer gb, Command command)
{
    command.params.each!(a => writeln(gb.line(a.to!long)));
}

void deleteLines(GapBuffer gb, Command command)
{
    writeln("Deleting lines: ", command.params);
    gb.deleteLines(command.params.map!(to!ArrayIdx).array);
}


void addText(GapBuffer gb, Command command)
{
    // XXX
}


void deleteText(GapBuffer bb, Command command)
{
    // XXX
}


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
        auto command = parseLine(line.to!string);

        writeln(command);
        // XXX strip command
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
        case "d":
        case "deleteText":
            deleteText(gb, command);
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
