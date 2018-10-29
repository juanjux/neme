module neme.frontend.repl.app;

import neme.core.gapbuffer: gapbuffer, GapBuffer, ArrayIdx;
import neme.core.extractors;
import neme.core.types;
import extractors = neme.core.extractors;
import std.array: array;

import std.stdio;
import std.conv: to;
import std.algorithm.iteration: map, each;
import std.algorithm.comparison : max, min;


// Simple sed-like REPL interface. For benchmarks and integration tests.

/* TODO:
 * 1. Read a commandline argument to load a file from the start.
 * 2. Implement missing commands
 */

struct Command
{
    string cmd;
    string[] params;
    string textParam;
}


Command parseCmdLine(string line)
{
    import std.array: split, join, replace;
    import std.string: indexOf, strip;

    // Command format: cmd [param1,param2][:text]
    Command c;

    auto spaceIdx = line.indexOf(' ');
    auto colonIdx = line.indexOf(':');


    // FIXME: allow to scape colon?
    if (spaceIdx == -1 || ((colonIdx > -1) && (colonIdx < spaceIdx))) {
        if (colonIdx == -1)
            c.cmd = line;
        else {
            c.cmd = line[0..colonIdx];
            c.textParam = line[colonIdx + 1..$];
        }
    }
    else {
        c.cmd = line[0..spaceIdx];
        auto tmpParams = line[spaceIdx+1..$].split(",");

        if (tmpParams[$-1].indexOf(':') != -1) {
            auto subtmpParams = tmpParams[$-1].split(":");
            tmpParams[$-1] = subtmpParams[0];

            if (subtmpParams.length > 0) {
                c.textParam = join(subtmpParams[1..$]).to!string;
            }
        }

        c.params = tmpParams.map!(x => x.strip).array;
    }

    if (c.textParam.length > 0) {
        c.textParam = c.textParam.replace("\\n", "\n");
    }
    return c;
}


void error(Command command)
{
    writeln("Unkown command: ", command.cmd);
}

// Commands implementation follow

// pb (no params)
void printBuffer(ref GapBuffer gb)
{
    import std.string: splitLines, leftJustify;
    import std.format: format;

    auto contentLines = gb.content.splitLines;
    auto lwidth = contentLines.length.to!string.length;

    foreach(idx, line; contentLines) {
        writeln(leftJustify(format!"%d"(idx+1), lwidth), "| ", line);
    }

    writeln("Cursor position: line: ", gb.currentLine, " column: ", gb.currentCol);
}

// pl line1,line2,line3...
void printLines(ref GapBuffer gb, Command _)
{
    command.params.each!(lineNum => writeln(gb.lineAt(lineNum.to!long)));
}

// dl line1,line2,line3...
void deleteLines(ref GapBuffer gb, Command command)
{
    writeln("Deleting lines: ", command.params);
    gb.deleteLines(command.params.map!(to!ArrayIdx).array);
}

// ap :text to append at the end of the text
void appendText(ref GapBuffer gb, Command command)
{
    if (command.textParam.length == 0)
        return;

    gb.cursorPos(GrpmIdx(gb.contentGrpmLen - 1));
    gb.addText(command.textParam);
}

// a :text to add at cursor position
void addText(ref GapBuffer gb, Command command)
{
    if (command.textParam.length == 0)
        return;

    gb.addText(command.textParam);
}

// dcl howmany
void deleteCharsLeft(ref GapBuffer gb, Command command)
{
    gb.deleteLeft(command.params[0].to!long.to!GrpmCount);
}

// dcr howmany
void deleteCharsRight(ref GapBuffer gb, Command command)
{
    gb.deleteRight(command.params[0].to!long.to!GrpmCount);
}

// g line,col
void gotoLineCol(ref GapBuffer gb, Command command)
{
    auto line = min(gb.numLines,
                    max(1, command.params[0].to!long));
    GrpmIdx col;
    if (command.params.length > 1) { 
        col = min(gb.lineLength(line),
                    GrpmIdx(max(1, command.params[1].to!long)));
    } else
        col = 1;

    gb.cursorPos = GrpmIdx(gb.lineStartPos(line) + col - 1);
    writeln(gb.cursorPos);
}

// l howmany
void cursorLeft(ref GapBuffer gb, Command command)
{
    gb.cursorBackward(command.params[0].to!long.to!GrpmCount);
}

// r howmany
void cursorRight(ref GapBuffer gb, Command command)
{
    gb.cursorForward(command.params[0].to!long.to!GrpmCount);
}

// ila
void insertLineAbove(ref GapBuffer gb, Command _)
{
    auto lines = extractors.lines(gb, gb.cursorPos, Direction.Back, 1);
    if (lines.length > 0) {
        gb.cursorPos = (lines[0].startPos - 1).GrpmIdx;
        gb.addText("\n");
    }
}

// ilb
void insertLineBelow(ref GapBuffer gb, Command _)
{
    auto lines = extractors.lines(gb, gb.cursorPos, Direction.Front, 1);
    if (lines.length > 0) {
        gb.cursorPos = lines[0].endPos;
        gb.addText("\n");
    }
}

// YOLO error control but it doesn't matter since this crap is only for 
// integration testing
void loadFile(ref GapBuffer gb, Command command)
{
    import std.file: readText;
    gb.clear(readText(command.params[0]));
}

// Ditto
void saveFile(ref GapBuffer gb, Command command)
{ 
    import std.file: write;
    write(command.params[0], gb.content.to!string);
}

// wl [numWords]
void wordLeft(ref GapBuffer gb, Command command)
{
    auto count = command.params.length > 0 ? command.params[0].to!long : 1;
    auto words = extractors.words(gb, gb.cursorPos, Direction.Back, count);

    if (words.length > 0) {
        gb.cursorPos = (words[$-1].startPos - 1).GrpmIdx;
        writeln(words);
    }
}

// wr [numWords]
void wordRight(ref GapBuffer gb, Command command)
{
    auto count = command.params.length > 0 ? command.params[0].to!long : 1;
    auto words = extractors.words(gb, gb.cursorPos, Direction.Front, count + 1);
    if (words.length > 0) {
        gb.cursorPos = words.length > 1 ? words[$-1].startPos : words[$-1].endPos;
        writeln(words[0..count]);
    }
}

// lu [numLines]
void lineUp(ref GapBuffer gb, Command command)
{
    auto count = command.params.length > 0 ? command.params[0].to!long : 1;
    auto lines = extractors.lines(gb, (gb.cursorPos - 1).GrpmIdx, Direction.Back, count);
    if (lines.length > 0) {
        gb.cursorPos = lines[$-1].startPos;
        writeln(lines);
    }
}

// ld [numLines]
void lineDown(ref GapBuffer gb, Command command)
{
    auto count = command.params.length > 0 ? command.params[0].to!long : 1;
    auto lines = extractors.lines(gb, (gb.cursorPos).GrpmIdx, Direction.Front, count + 1);
    if (lines.length > 0) {
        gb.cursorPos = lines[$-1].startPos;
        writeln(lines[0..count]);
    }
}

void deleteWordLeft(ref GapBuffer gb, Command command)
{
    // XXX
}

void deleteWordRight(ref GapBuffer gb, Command command)
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
        auto command = parseCmdLine(line.to!string);

        writeln(command);

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
