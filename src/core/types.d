module neme.core.types;

import neme.core.gapbuffer: GapBuffer;

import std.container.dlist;
import std.conv: to;
import std.format: format;
import std.typecons: Typedef;

/**
 * Types used in the gapbuffer and extractor implementations.
 **/

// Direction of text or operations
public enum Direction { Front, Back }

// Basic elements of the grapheme and grapheme container
public alias BufferElement = dchar;
public alias BufferType    = BufferElement[];

// For array positions / sizes. Using signed long to be able to detect negatives.
public alias ArrayIdx    = long;
public alias ImArrayIdx  = immutable long;
public alias ArraySize   = long;
public alias ImArraySize = immutable long;

// For grapheme positions / sizes. These are Typedefs to avoid bugs
// related to mixing ArrayIdx's with GrpmIdx's
public alias GrpmIdx = Typedef!(long, long.init, "grapheme");
public alias ImGrpmIdx = immutable GrpmIdx;

public alias GrpmCount = GrpmIdx;
public alias ImGrpmCount = immutable GrpmIdx;

// XXX Subject and ArraySubject should have a reference to the gapbuffer?
/// Subject contains the information of a extracted subject
public struct Subject
{
    // Position of the first grapheme of the subject
    GrpmIdx startPos;
    // Position of the last grapheme of the subject
    GrpmIdx endPos;
    // Text content of the subject
    const(BufferType) text;

    string toString()
    {
        return format!"(%s-%s)[%s]"(startPos.to!long, endPos.to!long, text);
    }
}

// Internal Subject using array positions. Public API will use types.Subject instead.
// FIXME: method to convert to Subject
package struct ArraySubject
{
    // Position of the first codepoint of the subject
    ArrayIdx startPos;
    // Position of the last codepoint of the subject
    ArrayIdx endPos;
    // Text content of the subject
    const(BufferType) text;

    // XXX should be const
    public const @safe
    const(Subject) toSubject(in GapBuffer gb)
    {
        return Subject(gb.CPPos2GrpmPos(startPos), gb.CPPos2GrpmPos(endPos), text);
    }

    public const pure @safe
    string toString()
    {
        return format!"(%s-%s)[%s]"(startPos.to!long, endPos.to!long, text);
    }
}

// Filters are used to select Subjects from a list
@safe public
alias bool function(in Subject subject) Predicate;

// Type for the function that'll check if a subject separator has been found and thus
// the subject should be added to the list
@safe public
alias bool function(in DList!BufferElement loaded, in BufferType curGrpm) SeparatorChecker;

// Extractors select one or more elements from the given position and direction
@safe public
alias const(Subject)[] function(in GapBuffer gb, GrpmIdx startPos, Direction dir,
        ArraySize count, Predicate predicate) Extractor;
