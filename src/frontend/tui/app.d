module neme.frontend.tui.app;

import neme.core.gapbuffer;
import extractors = neme.core.extractors;

import std.stdio;
import std.conv: to;
import std.algorithm;
import std.format;
import std.file;
import std.string;
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

    auto benchData = BenchData("bench.txt");
    benchData.enabled = BENCHMARK;
    auto curses = new Curses(cfg);
    WINDOW* textPad;

    scope(exit) {
        // FIXME: ensure this runs also on Control+c
        benchData.scrRefreshWriteMean;
        delwin(textPad);
        destroy(curses);
        writeln("bye!");
    }

    auto scr = curses.stdscr;
    auto ui = new UI(curses, scr);

    Button.Config buttonCfg = { alignment: Align.left };
    auto loadButton = new Button(ui, 1, 5, 1, 1, "Load", buttonCfg);
    auto downButton = new Button(ui, 1, 6, 1, 6, "Down", buttonCfg);
    auto upButton = new Button(ui, 1, 4, 1, 11, "Up", buttonCfg);
    auto exitButton = new Button(ui, 1, 6, 1, 14, "Exit", buttonCfg);

    // Textbox holds both the text and the linecol
    auto textBox = scr.subwin(scr.height - 4, scr.width - 2, 2, 1);
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

    void updateWindowBorders()
    {
        lineCol.box('|', '-');
        textBox.box('|', '-');
        scr.box('|', '-');

        lineCol.refresh;
        textBox.refresh;
        statusBar.refresh;
        scr.refresh;
    }

    void displayNewText()
    {
        // Use wclear(textPad) instead of delete/recreate?
        import core.stdc.stdlib: free;

        if (textPad != null)
            delwin(textPad);

        numLines = gb.numLines;
        ulong maxLength;

        for(ulong idx; idx < numLines; idx++) {
            maxLength = max(maxLength, gb.lineAt(idx).length);
        }

        textPad = newpad(numLines.to!int, maxLength.to!int);
        wprintw(textPad, gb.content.to!string.toStringz);
        mustLoadText = false;
    }

    void updatePad()
    {
        if (mustLoadText)
            displayNewText;

        if (gb.length <= 0) return;

        auto startPos = gb.cursorPos;
        auto lines = extractors.lines(gb, startPos, Direction.Front, textBox.height - 1);
        auto endPos = gb.lineStartPos(gb.currentLine + lines.length + 1);

        auto numDisplayLines = min(numLines, textBox.height - 1);
        wclear(textPad);
        wprintw(textPad, gb[startPos..endPos].to!string.toStringz);
        pnoutrefresh(textPad, 0,0, 3,6, textBox.height,textBox.width - 6);
    }

    // Main loop
    while(true) {
        ui.draw;

        benchData.startScreenRefresh;
        updateStatusBar;
        updateWindowBorders;
        updatePad;
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
