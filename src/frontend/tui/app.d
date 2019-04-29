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

enum BENCHMARK = false;
Curses _curses;

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

class TUI
{
    private:

    version(BENCHMARK)
        immutable _benchData = BenchData("bench.txt");

    GapBuffer _gb;
    UI _ui = void;
    FileLogger _flog = void;
    bool _mustLoadText;
    long _currentLine;

    // Used to save the last column resulting from user input (from cursor movement commands,
    // horizontal cursor movement keys or searches) to restore it when moving across lines
    GrpmCount _savedColumn;

    Button _loadButton = void;
    Button _exitButton = void;

    Window _textBox = void;
    Window _textArea = void;
    Window _lineCol = void;
    Window _statusBar = void;
    Window _statusMode = void;
    Window _statusFile = void;
    Window _statusLine = void;
    Window _statusCol = void;
    Window _cmdLine = void;

    int _textAreaLines;
    int _textAreaCols;

    void createUI()
    {
        auto scr = _curses.stdscr;
        _ui = new UI(_curses, scr);

        Button.Config buttonCfg = { alignment: Align.left };
        _loadButton = new Button(_ui, 1, 5, 1, 1, "Load", buttonCfg);
        _exitButton = new Button(_ui, 1, 5, 1, 6, "Exit", buttonCfg);

        // Textbox holds both the text and the linecol
        _textBox = scr.subwin(scr.height - 4, scr.width - 2, 2, 1);
        _textAreaLines = _textBox.height - 2;
        _textAreaCols = _textBox.width - 5;
        _textArea = _textBox.subwin(_textAreaLines, _textAreaCols, 3, 5);
        _lineCol = _textBox.subwin(_textBox.height, 4, 2, 1);

        // Status bar parent Window
        auto statusY = scr.height - 2;
        _statusBar = scr.subwin(1, scr.width - 2, statusY, 1);

        auto modeWidth = 15;
        _statusMode = _statusBar.subwin(1, modeWidth, statusY, 1);

        auto fileWidth = 20;
        _statusFile = _statusBar.subwin(1, fileWidth, statusY, modeWidth + 1);

        auto lineWidth = 15;
        _statusLine = _statusBar.subwin(1, lineWidth, statusY, modeWidth + fileWidth + 1);

        auto colWidth = 15;
        _statusCol = _statusBar.subwin(1, colWidth, statusY, modeWidth + fileWidth +
                lineWidth + 1);

        auto cmdLineWidth = scr.width / 4;
        _cmdLine = _statusBar.subwin(1, cmdLineWidth, statusY, scr.width - cmdLineWidth - 5);
    }

    void tuiExit(string text, int code)
    {
        if (text.length)
            writeln(text);
        exit(code);
    }

    void updateStatusBar()
    {
        ulong maxLines, curLineLength, curCol, maxCol;

        if (!_gb.empty) {
            curCol = _gb.currentCol.to!int;
            maxCol = _gb.lineAt(_gb.currentLine).length;
        }

        _statusMode.insert("COMMAND MODE | ");
        _statusFile.insert("./LICENSE | ");

        _statusLine.insert(format!"Ln %d/%d | "(_currentLine + 1, _gb.numLines + 1));
        _statusCol.insert(format!"Col %d/%d"(curCol, maxCol));
        _cmdLine.insert("CMD: _____");

        _statusMode.refresh;
        _statusFile.refresh;
        _statusLine.refresh;
        _statusCol.refresh;
        _cmdLine.refresh;
    }

    void fillText(GrpmIdx startPos)
    {
        auto curLine = 0;
        auto gbCurCol = _gb.currentCol.to!int;
        _flog.info("Current col: ", gbCurCol);
        auto gbStartPosLine = _gb.lineNumAtPos(startPos.to!long);
        auto lines = extractors.lines(_gb, startPos, Direction.Front,
                                        _textAreaLines - 1);

        foreach(ref line; lines) {
            if ((gbStartPosLine + curLine) != _gb.currentLine) {
                _textArea.addstr(curLine, 0, line.text);
            } else {
                // Current line: draw cursor
                if (line.text.length == 0) {
                    // Empty line, draw cursor at the start
                    _textArea.addch(curLine, 0, ' ', Attr.reverse);
                } else {
                    for (int i=0; i<line.text.length; i++) {
                        if (i == gbCurCol - 1) {
                            _textArea.addch(curLine, i, line.text[i], Attr.reverse);
                        } else {
                            _textArea.addch(curLine, i, line.text[i]);
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

        if (_mustLoadText) {
            startPos = 0.GrpmIdx;
            _mustLoadText = false;
        } else {
            startPos = _gb.cursorPos;
        }

        fillText(startPos);
        _textArea.refresh;
    }

    void drawBorders()
    {
        _lineCol.box('|', '-');
        _textBox.box('|', '-');
        _curses.stdscr.box('|', '-');
    }

    void updateScreen()
    {
        drawBorders;
        _lineCol.refresh;
        _textBox.refresh;
        _statusBar.refresh;
        updateTextArea;
        updateStatusBar;
        _curses.stdscr.refresh;
    }

    public:

    this(FileLogger log)
    {
        _flog = log;
    }

    void run()
    {
        createUI;

        version(BENCHMARK)
            append("bench.txt", "Starting benchmark----\n");

        auto opHandlr = new OperationHandlers(_flog);
        // TODO: make this configurable
        KeyboardLayer keyLayer = new VimishLayer();

        /+
        ╔════════════════════════════════════════════════════════════════════
        ║ ⚑ Main loop
        ╚════════════════════════════════════════════════════════════════════
        +/
        mainLoop: while(true) {
            _ui.draw;

            version(BENCHMARK) _benchData.startScreenRefresh;
            updateScreen;
            _curses.update;
            version(BENCHMARK) _benchData.stopScreenRefresh;

            WChar k = _curses.stdscr.getwch();

            try {
                _ui.keystroke(k);
                _flog.info("KeyStroke: ", k);

                Operations op = keyLayer.getOpForKey(k);
                // TODO: add as OperationHandlers.do
                // XXX repeat operations (like '5w'): take the repeat factor, the operation, and
                // pass to it as a repeat argument
                switch(op)
                {
                    case Operations.CHAR_LEFT:
                        _gb.lineCursorBackward(1.GrpmIdx);
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.CHAR_RIGHT:
                        _gb.lineCursorForward(1.GrpmIdx);
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.LINE_DOWN:
                        opHandlr.lineDown(_currentLine, _savedColumn);
                        break;
                    case Operations.LINE_UP:
                        opHandlr.lineUp(_currentLine, _savedColumn);
                        break;
                    case Operations.PAGE_DOWN:
                        opHandlr.pageDown(_currentLine, _textAreaLines, _savedColumn);
                        break;
                    case Operations.PAGE_UP:
                        opHandlr.pageUp(_currentLine, _textAreaLines, _savedColumn);
                        break;
                    case Operations.WORD_LEFT:
                        opHandlr.wordLeft();
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.UWORD_LEFT:
                        opHandlr.uWordLeft();
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.WORD_RIGHT:
                        opHandlr.wordRight();
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.UWORD_RIGHT:
                        opHandlr.uWordRight();
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.LINE_START:
                        opHandlr.lineStart();
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.LINE_END:
                        opHandlr.lineEnd();
                        _savedColumn = _gb.currentCol;
                        break;
                    case Operations.QUIT:
                        break mainLoop;
                    case Operations.JUMPTO_CHAR_RIGHT:
                        opHandlr.jumpToCharRight(_currentLine, _savedColumn, 'e');
                        break;
                    default:
                }

            // Button handlers
            } catch(Button.Signal s) {
                if (s.sender == _loadButton) {
                    import std.file: readText;
                    _gb = gapbuffer(readText("LICENSE"));
                    opHandlr.gb = &_gb;
                    _mustLoadText = true;
                }
                else if (s.sender == _exitButton) {
                    break mainLoop;
                }
                else {
                    string msg = "Unknown signal received: " ~ s.to!string;
                    _flog.error(msg);
                    tuiExit(msg, 1);
                }
            } catch (NCException e) {
                string msg2 = "Exception catched on signal processing: " ~ e.msg;
                _flog.error(msg2);
                tuiExit(msg2, 1);
            }
        }
    }
}

int main(string[] args)
{
    Curses.Config cfg = { cursLevel: 0 };
    _curses = new Curses(cfg);
    scope(exit) destroy(_curses);

    auto tui = new TUI(new FileLogger("nemecurses.log"));
    tui.run();

    return 0;
}
