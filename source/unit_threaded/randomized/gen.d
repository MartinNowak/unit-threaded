module unit_threaded.randomized.gen;

template from(string moduleName) {
    mixin("import from = " ~ moduleName ~ ";");
}


/* Return $(D true) if the passed $(D T) is a $(D Gen) struct.

A $(D Gen!T) is something that implicitly converts to $(D T), has a method
called $(D gen) that is accepting a $(D ref Random).

This module already brings Gens for numeric types, strings and ascii strings.

If a function needs to be benchmarked that has a parameter of custom type a
custom $(D Gen) is required.
*/
template isGen(T)
{
    static if (is(T : Gen!(S), S...))
        enum isGen = true;
    else
        enum isGen = false;
}

///
unittest
{
    static assert(!isGen!int);
    static assert(isGen!(Gen!(int, 0, 10)));
}

private template minimum(T) {
    import std.traits: isIntegral, isFloatingPoint, isSomeChar;
    static if(isIntegral!T || isSomeChar!T)
        enum minimum = T.min;
    else static if (isFloatingPoint!T)
        enum mininum = T.min_normal;
    else
        enum minimum = T.init;
}

private template maximum(T) {
    import std.traits: isNumeric;
    static if(isNumeric!T)
        enum maximum = T.max;
    else
        enum maximum = T.init;
}

/** A $(D Gen) type that generates numeric values between the values of the
template parameter $(D low) and $(D high).
*/
mixin template GenNumeric(T, T low, T high) {

    import std.random: Random;

    static assert(is(typeof(() {
        T[] res = frontLoaded();
    })), "GenNumeric needs a function frontLoaded returning " ~ T.stringof ~ "[]");

    alias Value = T;

    T value;

    T gen(ref Random gen)
    {
        import std.random: uniform;

        static assert(low <= high);

        this.value = _index < frontLoaded.length
            ? frontLoaded[_index++]
            : uniform!("[]")(low, high, gen);

        return this.value;
    }

    ref T opCall()
    {
        return this.value;
    }

    void toString(scope void delegate(const(char)[]) sink) @trusted
    {
        import std.format : formattedWrite;
        import std.traits: isFloatingPoint;

        static if (isFloatingPoint!T)
        {
            static if (low == T.min_normal && high == T.max)
            {
                formattedWrite(sink, "'%s'", this.value);
            }
        }
        else static if (low == T.min && high == T.max)
        {
            formattedWrite(sink, "'%s'", this.value);
        }
        else
        {
            formattedWrite(sink, "'%s' low = '%s' high = '%s'", this.value,
                low, high);
        }
    }

    alias opCall this;


    private int _index;
}

/** A $(D Gen) type that generates numeric values between the values of the
template parameter $(D low) and $(D high).
*/
struct Gen(T, T low = minimum!T, T high = maximum!T) if (from!"std.traits".isIntegral!T)
{
    private static T[] frontLoaded() @safe pure nothrow {
        import std.algorithm: filter;
        import std.array: array;
        T[] values = [0, 1, T.min, T.max];
        return values.filter!(a => a >= low && a <= high).array;
    }

    mixin GenNumeric!(T, low, high);
}

struct Gen(T, T low = 0, T high = 6.022E23) if(from!"std.traits".isFloatingPoint!T) {
     private static T[] frontLoaded() @safe pure nothrow {
        import std.algorithm: filter;
        import std.array: array;
         T[] values = [0, T.epsilon, T.min_normal, high];
         return values.filter!(a => a >= low && a <= high).array;
    }

    mixin GenNumeric!(T, low, high);
}

@safe pure unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    Gen!int gen;
    assertEqual(gen.gen(rnd), 0);
    assertEqual(gen.gen(rnd), 1);
    assertEqual(gen.gen(rnd), int.min);
    assertEqual(gen.gen(rnd), int.max);
    assertEqual(gen.gen(rnd), 1125387415); //1st non front-loaded value
}

@safe unittest {
    // not pure because of floating point flags
    import unit_threaded.asserts: assertEqual;
    import std.math: approxEqual;
    import std.conv: to;
    import std.random: Random;

    auto rnd = Random(1337);
    Gen!float gen;
    assertEqual(gen.gen(rnd), 0);
    assertEqual(gen.gen(rnd), float.epsilon);
    assertEqual(gen.gen(rnd), float.min_normal);
    assert(approxEqual(gen.gen(rnd), 6.022E23), gen.value.to!string);
    assert(approxEqual(gen.gen(rnd), 1.57791E23), gen.value.to!string);
}


@safe unittest {
    // not pure because of floating point flags
    import unit_threaded.asserts: assertEqual;
    import std.math: approxEqual;
    import std.conv: to;
    import std.random: Random;

    auto rnd = Random(1337);
    Gen!(float, 0, 5) gen;
    assertEqual(gen.gen(rnd), 0);
    assertEqual(gen.gen(rnd), float.epsilon);
    assertEqual(gen.gen(rnd), float.min_normal);
    assertEqual(gen.gen(rnd), 5);
    assert(approxEqual(gen.gen(rnd), 1.31012), gen.value.to!string);
}

/** A $(D Gen) type that generates unicode strings with a number of
charatacters that is between template parameter $(D low) and $(D high).
*/
struct Gen(T, size_t low = 0, size_t high = 32) if (from!"std.traits".isSomeString!T)
{
    import std.random: Random, uniform;

    static immutable T charSet;
    static immutable size_t numCharsInCharSet;
    alias Value = T;

    T value;
    static this()
    {
        import std.array : array;
        import std.uni : unicode;
        import std.format : format;
        import std.range : chain, iota;
        import std.algorithm : map, joiner;
        import std.conv : to;
        import std.utf : count;

        Gen!(T, low, high).charSet = chain(
            iota(0x21, 0x7E).map!(a => to!T(cast(dchar) a)),
            iota(0xA1, 0x1EF).map!(a => to!T(cast(dchar) a)))
            .joiner.array.to!T;
        Gen!(T, low, high).numCharsInCharSet = count(charSet);
    }

    T gen(ref Random gen)
    {
        static assert(low <= high);
        import std.array : appender;
        import std.utf : byDchar;

        if(_index < frontLoaded.length) {
            value = frontLoaded[_index++];
            return value;
        }

        auto app = appender!T();
        app.reserve(high);
        size_t numElems = uniform!("[]")(low, high, gen);

        for (size_t i = 0; i < numElems; ++i)
        {
            size_t charIndex = uniform!("[)")(0, numCharsInCharSet, gen);
            app.put(charSet[charIndex]);
        }

        this.value = app.data;
        return this.value;
    }

    ref T opCall()
    {
        return this.value;
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;

        static if (low == 0 && high == 32)
        {
            formattedWrite(sink, "'%s'", this.value);
        }
        else
        {
            formattedWrite(sink, "'%s' low = '%s' high = '%s'", this.value,
                           low, high);
        }
    }

    alias opCall this;

private:

    int _index;

    T[] frontLoaded() @safe pure nothrow const {
        import std.algorithm: filter;
        import std.array: array;
        T[] values = ["", "a", "é"];
        return values.filter!(a => a.length >= low && a.length <= high).array;
    }
}

unittest
{
    import std.meta : AliasSeq, aliasSeqOf;
    import std.range : iota;
    import std.array : empty;
    import std.random: Random;
    import unit_threaded.asserts;

    foreach (index, T; AliasSeq!(string, wstring, dstring)) {
        auto r = Random(1337);
        Gen!T a;
        T expected = "";
        assertEqual(a.gen(r), expected);
        expected = "a";
        assertEqual(a.gen(r), expected);
        expected = "é";
        assertEqual(a.gen(r), expected);
        assert(a.gen(r).length > 1);
    }
}

/// DITTO This random $(D string)s only consisting of ASCII character
struct GenASCIIString(size_t low = 1, size_t high = 32)
{
    import std.random: Random;

    static string charSet;
    static immutable size_t numCharsInCharSet;

    string value;

    static this()
    {
        import std.array : array;
        import std.uni : unicode;
        import std.format : format;
        import std.range : chain, iota;
        import std.algorithm : map, joiner;
                import std.conv : to;
                import std.utf : byDchar, count;

        GenASCIIString!(low, high).charSet = to!string(chain(iota(0x21,
            0x7E).map!(a => to!char(cast(dchar) a)).array));

        GenASCIIString!(low, high).numCharsInCharSet = count(charSet);
    }

    string gen(ref Random gen)
    {
        import std.array : appender;
        import std.random: uniform;

        if(_index < frontLoaded.length) {
            value = frontLoaded[_index++];
            return value;
        }

        auto app = appender!string();
        app.reserve(high);
        size_t numElems = uniform!("[]")(low, high, gen);

        for (size_t i = 0; i < numElems; ++i)
        {
            size_t toSelect = uniform!("[)")(0, numCharsInCharSet, gen);
            app.put(charSet[toSelect]);
        }

        this.value = app.data;
        return this.value;
    }

    ref string opCall()
    {
        return this.value;
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;

        static if (low == 0 && high == 32)
        {
            formattedWrite(sink, "'%s'", this.value);
        }
        else
        {
            formattedWrite(sink, "'%s' low = '%s' high = '%s'", this.value,
                low, high);
        }
    }

    alias opCall this;

private:

    int _index;

    string[] frontLoaded() @safe pure nothrow const {
        return ["", "a"];
    }
}


@safe unittest {
    import unit_threaded.asserts;
    import std.random: Random;

    auto rnd = Random(1337);
    GenASCIIString!() gen;
    assertEqual(gen.gen(rnd), "");
    assertEqual(gen.gen(rnd), "a");
    version(Windows)
        assertEqual(gen.gen(rnd), "yt4>%PnZwJ*Nv3L5:9I#N_ZK");
    else
        assertEqual(gen.gen(rnd), "i<pDqp7-LV;W`d)w/}VXi}TR=8CO|m");
}

struct Gen(T, size_t low = 1, size_t high = 1024)
    if(from!"std.range.primitives".isInputRange!T && !from!"std.traits".isSomeString!T)
{

    import std.traits: Unqual, isIntegral, isFloatingPoint;
    import std.range: ElementType;
    import std.random: Random;

    alias Value = T;
    alias E = Unqual!(ElementType!T);

    T value;
    Gen!E elementGen;

    T gen(ref Random rnd) {
        value = _index < frontLoaded.length
            ? frontLoaded[_index++]
            : genArray(rnd);
        return value;
    }

    alias value this;

private:

    size_t _index;
     //these values are always generated
    T[] frontLoaded() @safe nothrow {
        T[] ret = [[]];
        return ret;
    }

    T genArray(ref Random rnd) {
        import std.array: appender;
        import std.random: uniform;

        immutable length = uniform(low, high, rnd);
        auto app = appender!T;
        app.reserve(length);
        foreach(i; 0 .. length) {
            app.put(elementGen.gen(rnd));
        }

        return app.data;
    }
}

static assert(isGen!(Gen!(int[])));


@("Gen!int[] generates random arrays of int")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    auto gen = Gen!(int[], 1, 10)();

    // first the front-loaded values
    assertEqual(gen.gen(rnd), []);
    version(Windows)
        assertEqual(gen.gen(rnd), [0, 1]);
    else
        assertEqual(gen.gen(rnd), [0, 1, -2147483648, 2147483647, 681542492, 913057000, 1194544295, -1962453543, 1972751015]);
}

@("Gen!ubyte[] generates random arrays of ubyte")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    auto gen = Gen!(ubyte[], 1, 10)();
    assertEqual(gen.gen(rnd), []);
}


@("Gen!double[] generates random arrays of double")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    auto gen = Gen!(double[], 1, 10)();

    // first the front-loaded values
    assertEqual(gen.gen(rnd), []);
    // then the pseudo-random ones
    version(Windows)
        assertEqual(gen.gen(rnd).length, 2);
    else
        assertEqual(gen.gen(rnd).length, 9);
}

@("Gen!string[] generates random arrays of string")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    auto gen = Gen!(string[])();

    assertEqual(gen.gen(rnd), []);
    auto strings = gen.gen(rnd);
    assert(strings.length > 1);
    assertEqual(strings[1], "a");
}

@("Gen!string[][] generates random arrays of string")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    auto gen = Gen!(string[][])();

    assertEqual(gen.gen(rnd), []);
    // takes too long
    // auto strings = gen.gen(rnd);
    // assert(strings.length > 1);
}


struct Gen(T) if(is(T == bool)) {
    import std.random: Random;

    bool value;
    alias value this;

    bool gen(ref Random rnd) @safe {
        import std.random: uniform;
        value = [false, true][uniform(0, 2, rnd)];
        return value;
    }
}

@("Gen!bool generates random booleans")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    auto rnd = Random(1337);
    auto gen = Gen!bool();

    assertEqual(gen.gen(rnd), true);
    assertEqual(gen.gen(rnd), true);
    assertEqual(gen.gen(rnd), false);
    assertEqual(gen.gen(rnd), false);
}


struct Gen(T, T low = minimum!T, T high = maximum!T) if (from!"std.traits".isSomeChar!T)
{
    private static T[] frontLoaded() @safe pure nothrow { return []; }
    mixin GenNumeric!(T, low, high);
}


@("Gen char, wchar, dchar")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    {
        auto rnd = Random(1337);
        Gen!char gen;
        assertEqual(cast(int)gen.gen(rnd), 151);
    }
    {
        auto rnd = Random(1337);
        Gen!wchar gen;
        assertEqual(cast(int)gen.gen(rnd), 3223);
    }
    {
        auto rnd = Random(1337);
        Gen!dchar gen;
        assertEqual(cast(int)gen.gen(rnd), 3223);
    }
}

private template AggregateTuple(T...) {
    import unit_threaded.randomized.random: ParameterToGen;
    import std.meta: staticMap;
    alias AggregateTuple = staticMap!(ParameterToGen, T);
}

struct Gen(T) if(from!"std.traits".isAggregateType!T) {

    import std.traits: Fields;
    import std.random: Random;

    AggregateTuple!(Fields!T) generators;

    alias Value = T;
    Value value;

    T gen(ref Random rnd) @safe {
        static if(is(T == class))
            if(value is null)
                value = new T;

        foreach(i, ref g; generators) {
            value.tupleof[i] = g.gen(rnd);
        }

        return value;
    }

    inout(T) opCall() inout {
        return this.value;
    }

    alias opCall this;

}

@("struct")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    struct Foo {
        int i;
        string s;
    }

    auto rnd = Random(1337);
    Gen!Foo gen;
    assertEqual(gen.gen(rnd), Foo(0, ""));
    assertEqual(gen.gen(rnd), Foo(1, "a"));
    assertEqual(gen.gen(rnd), Foo(int.min, "é"));
}

@("class")
@safe unittest {
    import unit_threaded.asserts: assertEqual;
    import std.random: Random;

    static class Foo {
        this() {}
        this(int i, string s) { this.i = i; this.s = s; }
        override string toString() @safe const pure nothrow {
            import std.conv;
            return text(`Foo(`, i, `, "`, s, `")`);
        }
        override bool opEquals(Object _rhs) @safe const pure nothrow {
            auto rhs = cast(Foo)_rhs;
            return i == rhs.i && s == rhs.s;
        }
        int i;
        string s;
    }

    auto rnd = Random(1337);
    Gen!Foo gen;
    assertEqual(gen.gen(rnd), new Foo(0, ""));
    assertEqual(gen.gen(rnd), new Foo(1, "a"));
    assertEqual(gen.gen(rnd), new Foo(int.min, "é"));
}
