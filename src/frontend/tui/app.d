module neme.frontend.tui.app;

import std.stdio;
import std.file: readText;
import nice.ui.elements;

int main(string[] args)
{
    Curses.Config cfg = {
        //disableEcho: true,
        cursLevel: 0
    };

    auto curses = new Curses(cfg);
    scope(exit) destroy(curses);
    auto scr = curses.stdscr;

    auto ui = new UI(curses, scr);

    Button.Config buttonCfg = { alignment: Align.left };
    auto loadButton = new Button(ui, 1, 5, 1, 1, "Load", buttonCfg);
    auto downButton = new Button(ui, 1, 6, 1, 6, "Down", buttonCfg);
    auto upButton = new Button(ui, 1, 4, 1, 11, "Up", buttonCfg);

    // Textbox holds both the text and the linecol
    auto textBox = scr.subwin(scr.height - 4, scr.width - 2, 2, 1);
    auto lineCol = textBox.subwin(textBox.height, 4, 2, 1);
    auto textArea = scr.subwin(textBox.height, textBox.width - 6, 2, 6);

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

    auto x = true; // FIXME: workaround for "code not reachable" remove
    bool borderDrawn = false;

    string loadedText;

    void updateStatusBar()
    {
        statusMode.insert("COMMAND MODE | ");
        statusFile.insert("./LICENSE | ");
        statusLine.insert("Ln 1/83 | ");
        statusCol.insert("Col 1/80");
        cmdLine.insert("CMD: _____");


        statusMode.refresh;
        statusFile.refresh;
        statusLine.refresh;
        statusCol.refresh;
        cmdLine.refresh;
    }

    while(x) {
        ui.draw;

        if (loadedText.length > 0) {
            textArea.insert(1, 0, loadedText);
        }

        updateStatusBar;
        lineCol.box('|', '-');
        textBox.box('|', '-');
        scr.box('|', '-');

        lineCol.refresh;
        textBox.refresh;
        statusBar.refresh;
        scr.refresh;

        curses.update;
        WChar k = scr.getwch();

        try {
            ui.keystroke(k);
        } catch(Button.Signal s) {
            if (s.sender == loadButton) {
                loadedText = readText("LICENSE");
            }
            else if (s.sender == downButton) {
                textArea.scroll(1);
            }
            else if (s.sender == upButton) {
                textArea.scroll(-1);
            }
        }
    }

    return 0;
}
