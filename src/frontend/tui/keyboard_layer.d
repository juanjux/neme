module neme.frontend.tui.keyboard_layer;

import nice.ui.elements: WChar;

import neme.frontend.tui.events: Operations;

// Interface defining the key commands that keyboard layers must 
// implement. Every command returns one or more WChars matching the
// nice-curses codes for the keys that implement the command, as returned by 
// src.getwch
interface KeyboardLayer
{
    Operations getOpForKey(WChar key);
}