module neme.util.proxify;

import std.conv: to;
import std.traits;

/**
 * This function will return as string that can be mixed into a Struct or Class to
 * generate delegates to any preexisting methods in the class with a name starting
 * with one of the specified Selectors and a "rebindProxies!selector" method that
 * can be used to switch from one set of alternative methods to others starting
 * with another name.
 *
 * This can be useful for example for having alternative implementations of some
 * methods and you want to be able to switch from one set to the other at runtime
 * without having to change other callers or pollute all the code with branches
 * checking the switch condition boolean to call one method or other.
 *
 * Example:
 *
 * struct Calendar
 * {
 *     string offline_update() {
 *         ...code to update the calendar when not connected...
 *     }
 *     string online_update()  {
 *         ...code to update the calendar when connected...
 *     }
 *     string online_alert() { ...ditto... }
 *     string offline_alert() { ...ditto... }
 *
 *     mixin(switchableMethods!(Calendar, "offline_", "online_");
 *
 *     void checkConnection() {
 *        if (connectionLost) {
 *            rebindProxies!"offline_";
 *        }
 *        if (connectionRestored) {
 *            rebindProxies!"online_";
 *        }
 *     }
 *
 *     void miscFunction() {
 *         auto x = update(); // single call
 *         ... do stuff ...
 *         alert();
 *     }
 * }
 */

// TODO: use UDA decorated functions instead of prefixes.
// TODO: allow for optional rebindProxies name so the mixin can be used more
//       than once for different sets of switchable methods.
// TODO: investigate how to recover the default parameters of the target method

string Proxify(S, Selectors...)()
{
    // delegateDecls will hold the code string for delegate declarations, like:
    // ReturnType!slow_bar delegate(Parameters!slow_bar) bar;
    // ReturnType!slow_bar delegate(Parameters!slow_bar) bar;
    char[] delegateDecls;

    // methodsSelector will hold the code of the generated rebindProxies function to rebind the
    // delegates to another set of functions by selector
    string methodsSelector;

    // This hold the strings for the cases (one per selector) inside the generated
    // rebindProxies function with the assignments of base = selector_base (e. g. foo = &slow_foo)
    string[string] selectorCases;

    foreach(selector; Selectors) // e.g. "slow_"
    {
        selectorCases[selector] = "\tcase \"" ~ selector ~ "\":\n"; // case "slow_":
        string caseText;

        foreach(member; __traits(allMembers, S))
        {
            static if (member.length > selector.length && member[0..selector.length] == selector) {
                // if the selctor is "slow_" we've found a "slow_something"

                static if (selector == Selectors[0]) {
                    // generate the delegate declaration copying the target function attributes
                    enum attributes = to!string(__traits(getFunctionAttributes, __traits(getMember, S, member)));
                    enum declaration = to!string(attributes ~ " ReturnType!" ~ member ~
                                                  " delegate(Parameters!" ~ member ~ ") " ~
                                                  member[5..$] ~ ";");
                    delegateDecls ~= declaration;
                }

                // Add this to the switch cases:
                // foo = &slow_foo;
                enum baseName = member[selector.length..$]; // "something"
                selectorCases[selector] ~= baseName ~ " = &" ~ selector ~ baseName ~ ";";
            }
        }
    }

    string cases;
    foreach(case_; selectorCases) {
        cases ~= case_ ~ "break;";
    }
    cases ~= "default: return;";
    methodsSelector = "void rebindProxies(string S)() { switch(S){" ~ cases ~ "}}";

    return to!string(delegateDecls ~ "\n" ~ methodsSelector);
}

///
unittest
{
    struct TestStruct
    {
        mixin(Proxify!(typeof(this), "slow_", "fast_"));
        string slow_foo(int param1) { return "slow foo"; }
        string fast_foo(int param)  { return "fast foo"; }

        string slow_bar(string param="default", int param2=4) { return "slow bar"; }
        string fast_bar(string param="default", int param2=4) { return "fast bar"; }
    }

    TestStruct m;

    m.rebindProxies!"fast_";

    assert(m.bar("abc", 123) == m.fast_bar("abc", 123));
    assert(m.foo(3) == m.fast_foo(3));
    assert(m.bar == &m.fast_bar);
    assert(m.foo == &m.fast_foo);

    m.rebindProxies!"slow_";

    assert(m.bar("abc", 123) == m.slow_bar("abc", 123));
    assert(m.foo(3) == m.slow_foo(3));
    assert(m.bar == &m.slow_bar);
    assert(m.foo == &m.slow_foo);
}


/* Example generated code:

Proxify!(TestStruct, "fast_", "slow_");

@system ReturnType!slow_foo delegate(Parameters!slow_foo) foo;
@system ReturnType!slow_bar delegate(Parameters!slow_bar) bar;

void rebindProxies(string S)() {
    switch(S)
    {
        case "fast_":
            foo = &fast_foo;
            bar = &fast_bar;
            break;
        case "slow_":
            foo = &slow_foo;
            bar = &slow_bar;
            break;
        default: return;
    }
}
*/
