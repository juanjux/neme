module neme.frontend.tui.vimish_layer;

import std.conv: to;

import nice.ui.elements: WChar;
import neme.frontend.tui.keyboard_layer;

class VimishLayer : KeyboardLayer
{
    WChar[] charLeft() 
    { 
        return [
            WChar(260, true)
        ];
    } 

    WChar[] charRight() 
    { 
        return [
            WChar(261, true)
        ];
    } 

    WChar[] lineUp() 
    { 
        return [
            WChar(259, true)
        ];
    } 

    WChar[] lineDown() 
    { 
        return [
            WChar(258, true)
        ];
    } 

    WChar[] pageUp() 
    { 
        return [
            WChar(339, true)
        ];
    } 

    WChar[] pageDown() 
    { 
        return [
            WChar(338, true)
        ];
    } 

    WChar[] loadFile() 
    { 
        return [
            WChar('L')
        ];
    } 

    WChar[] quit() 
    { 
        return [
            WChar('Q')
        ];
    } 
}