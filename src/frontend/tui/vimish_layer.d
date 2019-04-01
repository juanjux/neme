module neme.frontend.tui.vimish_layer;

import std.conv: to;

import nice.ui.elements: WChar;
import neme.frontend.tui.keyboard_layer;


// XXX static functions instead?
class VimishLayer : KeyboardLayer
{
    Operations[WChar] key2Ops;

    this() {
        key2Ops = [
            WChar(260, true): Operations.CHAR_LEFT, // cursor-left
            WChar('h'): Operations.CHAR_LEFT,

            WChar(261, true): Operations.CHAR_RIGHT, // cursor-right
            WChar('l'): Operations.CHAR_RIGHT,

            WChar(259, true): Operations.LINE_UP, // cursor-up
            WChar('k'): Operations.LINE_UP,

            WChar(258, true): Operations.LINE_DOWN, // cursor-down
            WChar('j'): Operations.LINE_DOWN,

            WChar(339, true): Operations.PAGE_UP, // page-up
            WChar('\x15'): Operations.PAGE_UP, // ctrl-u

            WChar(338, true): Operations.PAGE_DOWN, // page-down
            WChar('\x04'): Operations.PAGE_DOWN, // ctrl-d

            WChar('Q'): Operations.QUIT,
        ];
    }

    override Operations getOpForKey(WChar key)
    {
        auto op = key in key2Ops;
        if (op != null) 
            return *op;

        return Operations.UNKNOWN;
    }
}