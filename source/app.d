module neme;

import gapbuffer_benchmark: bench;
import std.stdio;

void main()
{
    /// Force to run the unittests with these datatypes
    //scope gbMain = GapBuffer!(char, string)("", 100);
    //scope gbMainDefault = GapBuffer!(wchar, string)("", 100);
    //scope gbMainDefault2 = GapBuffer!(dchar, string)("", 100);

    //scope gbMainDefault3 = GapBuffer!(char, wstring)("", 100);
    //scope gbMainDefault4 = GapBuffer!(wchar, wstring)("", 100);
    //scope gbMainDefault5 = GapBuffer!(dchar, wstring)("", 100);

    //scope gbMainDefault6 = GapBuffer!(char,  dstring)("", 100);
    //scope gbMainDefault7 = GapBuffer!(wchar, dstring)("", 100);
    //scope gbMainDefault8 = GapBuffer!(dchar, dstring)("", 100);
    bench;
}
