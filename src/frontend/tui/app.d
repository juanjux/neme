module neme.frontend.tui.app;

import std.algorithm;
import std.conv: to;
import std.file;
import core.stdc.stdlib: exit;
import std.format;
import std.stdio;
import std.datetime.stopwatch;
import std.experimental.logger;

import nice.ui.elements;
import neme.core.gapbuffer;
import neme.frontend.tui.events;
import neme.frontend.tui.keyboard_layer;
import neme.frontend.tui.vimish_layer;
import extractors = neme.core.extractors;
import neme.core.types;

// import deimos.ncurses;

enum BENCHMARK = false;

version(BENCHMARK)
struct BenchData
{
    StopWatch scrRefreshSw = StopWatch(AutoStart.no);
    Duration scrTotalRefresh;
    ulong scrNumTimesRefresh;
    string benchFileName;

    this(string benchFile)
    {
        this.benchFileName = benchFile;
    }

    void startScreenRefresh()
    {
        scrRefreshSw.start;
    }

    void stopScreenRefresh()
    {
        scrRefreshSw.stop;
        scrRefreshTick;
    }

    void scrRefreshTick()
    {
        append(benchFileName, "Screen refresh time: " ~
                scrRefreshSw.peek.total!"usecs".to!string ~ "\n");
        scrTotalRefresh += scrRefreshSw.peek;
        ++scrNumTimesRefresh;
        scrRefreshSw.reset();
    }

    void scrRefreshWriteMean()
    {
        auto mean = scrTotalRefresh / scrNumTimesRefresh;
        append(benchFileName, "Average screen refresh time: " ~
               mean.to!string ~ "\n");
    }
}

int main(string[] args)
{
auto flog = new FileLogger("nemecurses.log");
Curses.Config cfg = {
    //disableEcho: true,
    cursLevel: 0
};

version(BENCHMARK)
    immutable benchData = BenchData("bench.txt");
auto curses = new Curses(cfg);

void tuiExit(string text, int code)
{
        destroy(curses);
        writeln(text);
        exit(code);
}
scope(exit) {
    version(BENCHMARK)
        benchData.scrRefreshWriteMean;
    tuiExit("", 0);
}

append("bench.txt", "Starting benchmark----\n");

auto scr = curses.stdscr;
auto ui = new UI(curses, scr);

Button.Config buttonCfg = { alignment: Align.left };
auto loadButton = new Button(ui, 1, 5, 1, 1, "Load", buttonCfg);
auto exitButton = new Button(ui, 1, 5, 1, 6, "Exit", buttonCfg);

// Textbox holds both the text and the linecol
auto textBox = scr.subwin(scr.height - 4, scr.width - 2, 2, 1);
immutable textAreaLines = textBox.height - 2;
immutable textAreaCols = textBox.width - 5;
auto textArea = textBox.subwin(textAreaLines, textAreaCols, 3, 5);
auto lineCol = textBox.subwin(textBox.height, 4, 2, 1);

// Status bar parent Window
auto statusY = scr.height - 2;
auto statusBar = scr.subwin(1, scr.width - 2, statusY, 1);

auto modeWidth = 15;
auto statusMode = statusBar.subwin(1, modeWidth, statusY, 1);

auto fileWidth = 20;
auto statusFile = statusBar.subwin(1, fileWidth, statusY, modeWidth + 1);

auto lineWidth = 15;
auto statusLine = statusBar.subwin(1, lineWidth, statusY, modeWidth + fileWidth + 1);

auto colWidth = 15;
auto statusCol = statusBar.subwin(1, colWidth, statusY, modeWidth + fileWidth +
        lineWidth + 1);

auto cmdLineWidth = scr.width / 4;
auto cmdLine = statusBar.subwin(1, cmdLineWidth, statusY, scr.width - cmdLineWidth - 5);

bool mustLoadText;
long currentLine;
GapBuffer gb;
// Used to save the last column resulting from user input (from cursor movement commands, 
// horizontal cursor movement keys or searches) to restore it when moving across lines
GrpmCount savedColumn;

/+
    ╔══════════════════════════════════════════════════════════════════════════════
    ║ ⚑ Draw / redraw functions
    ╚══════════════════════════════════════════════════════════════════════════════
+/

void updateStatusBar()
{
    ulong maxLines, curLineLength, curCol, maxCol;

    if (!gb.empty) {
        curCol = gb.currentCol.to!int;
        maxCol = gb.lineAt(gb.currentLine).length;
    }

    statusMode.insert("COMMAND MODE | ");
    statusFile.insert("./LICENSE | ");
    statusLine.insert(format!"Ln %d/%d | "(currentLine + 1, gb.numLines + 1));
    statusCol.insert(format!"Col %d/%d"(curCol, maxCol));
    cmdLine.insert("CMD: _____");

    statusMode.refresh;
    statusFile.refresh;
    statusLine.refresh;
    statusCol.refresh;
    cmdLine.refresh;
}

void fillText(GrpmIdx startPos)
{
    auto curLine = 0;
    auto gbCurLine = gb.currentLine;
    auto gbCurCol = gb.currentCol.to!int;
    flog.info("Current col: ", gbCurCol);
    auto gbStartPosLine = gb.lineNumAtPos(startPos.to!long);
    auto lines = extractors.lines(gb, startPos, Direction.Front,
                                    textAreaLines - 1);

    foreach(ref line; lines) {
        if ((gbStartPosLine + curLine) != gbCurLine) {
            textArea.addstr(curLine, 0, line.text);
        } else {
            // Current line: draw cursor
            if (line.text.length == 0) {
                // Empty line, draw cursor at the start
                textArea.addch(curLine, 0, ' ', Attr.reverse);
            } else {
                for (int i=0; i<line.text.length; i++) {
                    if (i == gbCurCol - 1) {
                        textArea.addch(curLine, i, line.text[i], Attr.reverse);
                    } else {
                        textArea.addch(curLine, i, line.text[i]);
                    }
                }
            }
        }
        ++curLine;
    }
}

void updateTextArea()
{
    GrpmIdx startPos;

    if (mustLoadText) {
        startPos = 0.GrpmIdx;
        mustLoadText = false;
    } else {
        startPos = gb.cursorPos;
    }

    fillText(startPos);
    textArea.refresh;
}

void drawBorders()
{
    lineCol.box('|', '-');
    textBox.box('|', '-');
    scr.box('|', '-');
}

void updateScreen()
{
    drawBorders;
    lineCol.refresh;
    textBox.refresh;
    statusBar.refresh;
    updateTextArea;
    updateStatusBar;
    scr.refresh;
}

auto opHandlr = new OperationHandlers(flog);
// TODO: make this configurable
KeyboardLayer keyLayer = new VimishLayer();

/+
    ╔══════════════════════════════════════════════════════════════════════════════
    ║ ⚑ Main loop
    ╚══════════════════════════════════════════════════════════════════════════════
+/
mainLoop: while(true) {
    ui.draw;

    version(BENCHMARK) benchData.startScreenRefresh;
    updateScreen;
    curses.update;
    version(BENCHMARK) benchData.stopScreenRefresh;

    WChar k = scr.getwch();
    try {
        ui.keystroke(k);
        flog.info("KeyStroke: ", k);

        Operations op = keyLayer.getOpForKey(k);
        // TODO: add as OperationHandlers.do
        // XXX repeat operations (like '5w'): take the repeat factor, the operation, and 
        // pass to it as a repeat argument
        switch(op) 
        {
            case Operations.CHAR_LEFT:
                gb.lineCursorBackward(1.GrpmIdx);
                savedColumn = gb.currentCol;
                break;
            case Operations.CHAR_RIGHT:
                gb.lineCursorForward(1.GrpmIdx);
                savedColumn = gb.currentCol;
                break;
            case Operations.LINE_DOWN:
                opHandlr.lineDown(currentLine, savedColumn);
                break;
            case Operations.LINE_UP:
                opHandlr.lineUp(currentLine, savedColumn);
                break;
            case Operations.PAGE_DOWN:
                opHandlr.pageDown(currentLine, textAreaLines, savedColumn);
                break;
            case Operations.PAGE_UP:
                opHandlr.pageUp(currentLine, textAreaLines, savedColumn);
                break;
            case Operations.WORD_LEFT:
                opHandlr.wordLeft();
                savedColumn = gb.currentCol;
                break;
            case Operations.UWORD_LEFT:
                opHandlr.uWordLeft();
                savedColumn = gb.currentCol;
                break;
            case Operations.WORD_RIGHT:
                opHandlr.wordRight();
                savedColumn = gb.currentCol;
                break;
            case Operations.UWORD_RIGHT:
                opHandlr.uWordRight();
                savedColumn = gb.currentCol;
                break;
            case Operations.LINE_START:
                opHandlr.lineStart();
                savedColumn = gb.currentCol;
                break;
            case Operations.LINE_END:
                opHandlr.lineEnd();
                savedColumn = gb.currentCol;
                break;
            case Operations.QUIT:
                break mainLoop;
            default:
        }

    // Button handlers
    } catch(Button.Signal s) {
        if (s.sender == loadButton) {
            import std.file: readText;
            gb = gapbuffer(readText("LICENSE"));
            opHandlr.gb = &gb;
            mustLoadText = true;
        }
        else if (s.sender == exitButton) {
            break mainLoop;
        }
        else {
            string msg = "Unknown signal received: " ~ s.to!string;
            flog.error(msg);
            tuiExit(msg, 1);
        }
    } catch (NCException e) {
        string msg2 = "Exception catched on signal processing: " ~ e.msg;
        flog.error(msg2);
        tuiExit(msg2, 1);
    }
}

return 0;
}