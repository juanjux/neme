module neme.frontend.tui.app;

import neme.core.gapbuffer;
import extractors = neme.core.extractors;
import neme.core.types;

import std.algorithm;
import std.conv: to;
import std.file;
import core.stdc.stdlib: exit;
import std.format;
import std.stdio;
import std.datetime.stopwatch;
import std.experimental.logger;

import nice.ui.elements;
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
    auto downButton = new Button(ui, 1, 5, 1, 6, "Down", buttonCfg);
    auto upButton = new Button(ui, 1, 3, 1, 11, "Up", buttonCfg);
    auto pageDownButton = new Button(ui, 1, 7, 1, 14, "PageDw", buttonCfg);
    auto pageUpButton = new Button(ui, 1, 7, 1, 21, "PageUp", buttonCfg);
    auto exitButton = new Button(ui, 1, 5, 1, 28, "Exit", buttonCfg);
    auto curLeftButton = new Button(ui, 1, 5, 1, 33, "Left", buttonCfg);
    auto curRightButton = new Button(ui, 1, 6, 1, 38, "Right", buttonCfg);

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
            curCol = gb.currentCol.to!int;
            maxCol = gb.lineAt(gb.currentLine).length;
        }

        statusMode.insert("COMMAND MODE | ");
        statusFile.insert("./LICENSE | ");
        statusLine.insert(format!"Ln %d/%d | "(currentLine + 1, numLines + 1));
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

    void updateCursor()
    {
        auto viewCursorPos = (currentLine % textAreaLines) + 4;
    }

    void updateScreen()
    {
        drawBorders;
        lineCol.refresh;
        updateCursor;
        textBox.refresh;
        statusBar.refresh;
        updateTextArea;
        updateStatusBar;
        scr.refresh;
    }


    // Main loop
    while(true) {
        ui.draw;

        version(BENCHMARK) {
            import core.time;
            benchData.startScreenRefresh;
        }

        updateScreen;
        curses.update;
        version(BENCHMARK)
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
            else if (s.sender == pageDownButton) {
                currentLine = min(numLines - 1, currentLine + textAreaLines);
                gb.cursorToLine(currentLine + textAreaLines);
            }
            else if (s.sender == pageUpButton) {
                currentLine = max(0, currentLine - textAreaLines);
                gb.cursorToLine(currentLine - textAreaLines);
            }
            else if (s.sender == curLeftButton) {
                gb.lineCursorForward(1.GrpmIdx);
            }
            else if (s.sender == curRightButton) {
                gb.lineCursorBackward(1.GrpmIdx);
            }
            else if (s.sender == exitButton) {
                break;
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
