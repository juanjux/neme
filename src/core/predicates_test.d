module neme.core.predicates_test;

import neme.core.predicates;
import neme.core.types;

import std.conv;

// All & None
@safe unittest
{
    auto some = Subject(0.GrpmIdx, 0.GrpmIdx, to!(dchar[])("some"));
    assert(All(some));
    assert(!None(some));
}

// Empty & NonEmpty
@safe unittest
{
    auto some = Subject(0.GrpmIdx, 0.GrpmIdx, to!(dchar[])(""));
    assert(Empty(some));
    assert(!NotEmpty(some));
}
