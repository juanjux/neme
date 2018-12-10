module neme.frontend.tui.app;

import neme.core.gapbuffer;
import extractors = neme.core.extractors;
import neme.core.types;

import std.algorithm;
import std.conv: to;
import std.file;
import std.format;
import std.stdio;
import std.datetime.stopwatch;

import nice.ui.elements;
import deimos.ncurses;

enum BENCHMARK = true;

struct BenchData
{
    StopWatch scrRefreshSw = StopWatch(AutoStart.no);
    Duration scrTotalRefresh;
    ulong scrNumTimesRefresh;
    string benchFileName;
    bool enabled = true;

    this(string benchFile)
    {
        this.benchFileName = benchFile;
    }

    void startScreenRefresh()
    {
        if (!enabled) return;
        scrRefreshSw.start;
    }

    void stopScreenRefresh()
    {
        if (!enabled) return;
        scrRefreshSw.stop;
        scrRefreshTick;
    }

    void scrRefreshTick()
    {
        if (!enabled) return;
        append(benchFileName, "Screen refresh time: " ~
                scrRefreshSw.peek.total!"usecs".to!string ~ "\n");
        scrTotalRefresh += scrRefreshSw.peek;
        ++scrNumTimesRefresh;
        scrRefreshSw.reset();
    }

    void scrRefreshWriteMean()
    {
        if (!enabled) return;
        auto mean = scrTotalRefresh / scrNumTimesRefresh;
        append(benchFileName, "Average screen refresh time: " ~ 
               mean.to!string ~ "\n");
    }
}

int main(string[] args)
{
    Curses.Config cfg = {
        //disableEcho: true,
        cursLevel: 0
    };

    BenchData benchData = BenchData("bench.txt");
    benchData.enabled = BENCHMARK;
    auto curses = new Curses(cfg);

    scope(exit) {
        // FIXME: ensure this runs also on Control+c
        benchData.scrRefreshWriteMean;
        destroy(curses);
        writeln("bye!");
    }

    append("bench.txt", "Starting benchmark----\n");

    auto scr = curses.stdscr;
    auto ui = new UI(curses, scr);

    Button.Config buttonCfg = { alignment: Align.left };
    auto loadButton = new Button(ui, 1, 5, 1, 1, "Load", buttonCfg);
    auto downButton = new Button(ui, 1, 6, 1, 6, "Down", buttonCfg);
    auto upButton = new Button(ui, 1, 4, 1, 11, "Up", buttonCfg);
    auto exitButton = new Button(ui, 1, 6, 1, 14, "Exit", buttonCfg);

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
    int currentLine;
    ulong numLines;
    GapBuffer gb;

    void updateStatusBar()
    {
        ulong maxLines, curLineLength, curCol, maxCol;

        if (!gb.empty) {
            curCol = 0; // FIXME: Change when allowing cursor movement
            maxCol = gb.lineAt(gb.currentLine).length;
        }

        statusMode.insert("COMMAND MODE | ");
        statusFile.insert("./LICENSE | ");
        statusLine.insert(format!"Ln %d/%d | "(currentLine + 1, numLines + 1));
        statusCol.insert(format!"Col %d/%d"(curCol + 1, maxCol + 1));
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
        auto lines = extractors.lines(gb, startPos, Direction.Front, 
                                      textAreaLines - 1);
                                    
        foreach(ref line; lines) {
            textArea.addstr(curLine, 0, line.text);
            ++curLine;
        }
    }

    void updateTextArea()
    {
        GrpmIdx startPos;

        if (mustLoadText) {
            startPos = 0.GrpmIdx;
            numLines = gb.numLines;
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


    // Main loop
    while(true) {
        ui.draw;

        import core.time;

        benchData.startScreenRefresh;
        updateScreen;
        curses.update;
        benchData.stopScreenRefresh;

        WChar k = scr.getwch();
        try {
            ui.keystroke(k);
        } catch(Button.Signal s) {
            if (s.sender == loadButton) {
                import std.file: readText;
                gb = gapbuffer(readText("LICENSE"));
                mustLoadText = true;
            }
            else if (s.sender == downButton) {
                currentLine = min(numLines - 1, currentLine + 1);
                gb.cursorToLine(currentLine + 1);
            }
            else if (s.sender == upButton) {
                currentLine = max(0, currentLine - 1);
                gb.cursorToLine(currentLine + 1);
            }
            else if (s.sender == exitButton) {
                break;
            }
        }
    }

    return 0;
}
