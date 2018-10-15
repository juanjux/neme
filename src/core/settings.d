module neme.core.settings;

import neme.core.gapbuffer;
import std.conv;
import std.container.rbtree;

class Settings
{

    RedBlackTree!BufferElement wordSeparators;

    this()
    {
        // FIXME: use a real set or rbtree. Improve the collection
        wordSeparators = redBlackTree(
            ' '.to!BufferElement,
            '\t'.to!BufferElement,
            '\n'.to!BufferElement,
            '.'.to!BufferElement,
            ','.to!BufferElement,
            '-'.to!BufferElement,
            '+'.to!BufferElement,
            '='.to!BufferElement,
            ':'.to!BufferElement,
            ';'.to!BufferElement,
            '['.to!BufferElement,
            ']'.to!BufferElement,
            '('.to!BufferElement,
            ')'.to!BufferElement,
            '{'.to!BufferElement,
            '}'.to!BufferElement,
            '/'.to!BufferElement,
            '\\'.to!BufferElement,
            '&'.to!BufferElement,
            '^'.to!BufferElement,
            '%'.to!BufferElement,
            '#'.to!BufferElement,
            '@'.to!BufferElement,
            '!'.to!BufferElement,
            '?'.to!BufferElement,
            '~'.to!BufferElement,
            '$'.to!BufferElement,
            '"'.to!BufferElement,
            '\''.to!BufferElement,
            '*'.to!BufferElement,
            );
    }
}

Settings globalSettings;

static this() {
    globalSettings = new Settings;
}
