
class JsonException : Exception {
    this(string s) {
        super(s);
    }
}

unittest {
    static struct MyConfig {
        string encoding;
        string[] plugins;
        int indent = 2;
        bool indentSpaces;
    }

    static class X {
        enum foos { Bar, Baz };

        real[] reals;
        int[string] ints;
        MyConfig conf;
        foos foo;

        void qux() { }
    }

    /* String decodes */
    assert(jsonDecode(`""`) == "");
    assert(jsonDecode(`"\u0391 \u0392\u0393\t\u03B3\u03b4"`) == "\u0391 \u0392\u0393\t\u03B3\u03B4");
    assert(jsonDecode(`"\uD834\uDD1E"`) == "\U0001D11E");
    assert(jsonDecode("\"\U0001D11E and \u0392\"") == "\U0001D11E and \u0392");

    /* String encodes */
    assert(jsonEncode("he\u03B3l\"lo") == "\"he\u03B3l\\\"lo\"");
    assert(jsonEncode("\U0001D11E and \u0392") == "\"\U0001D11E and \u0392\"");

    /* Mix string/dstring encode and decode */
    string narrowStr = "\"\\uD834\\uDD1E \U0001D11E\"";
    dstring wideLoad = "\"\\uD834\\uDD1E \U0001D11E\"";
    assert(jsonDecode!string(wideLoad) == "\U0001D11E \U0001D11E");
    assert(jsonDecode!dstring(wideLoad) == "\U0001D11E \U0001D11E");
    assert(jsonDecode!string(narrowStr) == "\U0001D11E \U0001D11E");
    assert(jsonDecode!dstring(narrowStr) == "\U0001D11E \U0001D11E");
    assert(jsonEncode!string(jsonDecode!string(wideLoad)) == "\"\U0001D11E \U0001D11E\"");
    assert(jsonEncode!dstring(jsonDecode!string(wideLoad)) == "\"\U0001D11E \U0001D11E\"");
    assert(jsonEncode!string(jsonDecode!dstring(wideLoad)) == "\"\U0001D11E \U0001D11E\"");
    assert(jsonEncode!dstring(jsonDecode!dstring(wideLoad)) == "\"\U0001D11E \U0001D11E\"");

    /* Decode associative array indexed by dstring */
    narrowStr = "{" ~ narrowStr ~ ": 3}";
    wideLoad  = "{" ~ wideLoad  ~ ": 3}";

    auto dstringAA1 = jsonDecode!(int[dstring])(narrowStr);
    auto dstringAA2 = jsonDecode!(int[dstring])(wideLoad);
    assert(dstringAA1["\U0001D11E \U0001D11E"] == 3);
    assert(dstringAA2["\U0001D11E \U0001D11E"] == 3);

    /* Decode JSON strings into D numbers */
    assert(jsonDecode!int(`"34"`) == 34);

    /* Deep associative array encode/decode */
    int[string][uint][string] daa;
    daa["foo"][2]["baz"] = 4;
    auto daaStr = jsonEncode(daa);
    assert(daaStr == `{"foo":{"2":{"baz":4}}}`);
    assert(jsonDecode!(int[string][uint][string])(daaStr)["foo"][2]["baz"] == 4);

    /* Structured decode into user-defined type */
    auto x = jsonDecode!X(`null`);
    assert(x is null);

    x = jsonDecode!X(`{}`);
    assert(x !is null);
    assert(x.conf.indent == 2);
    assert(x.foo == X.foos.Bar);

    auto xjson = `{
        "foo" : "Baz",
        "reals" : [ 3.4, 7.2e+4, 5, 0, -33 ],
        "ints" : { "one": 1, "two": 2 },
        "bogus" : "ignore me",
        "conf" : {
            "encoding" : "UTF-8",
            "indent" : 4,
            "plugins" : [ "perl", "d" ],
            "indentSpaces" : true
        }
    }`;

    x = jsonDecode!X(xjson);
    assert(x !is null);
    assert(x.foo == X.foos.Baz);
    assert(x.reals == [3.4L, 72000, 5, 0, -33]);
    assert(x.ints["one"] == 1);
    assert(x.ints["two"] == 2);
    assert(x.conf.encoding == "UTF-8");
    assert(x.conf.plugins == ["perl", "d"]);
    assert(x.conf.indent == 4);
    assert(x.conf.indentSpaces == true);

    /* Structured encode */
    assert(jsonEncode(x) ==
        `{"reals":[3.4,72000,5,0,-33],"ints":{"one":1,"two":2},"conf":{"encoding":"UTF-8","plugins":["perl","d"],"indent":4,"indentSpaces":true},"foo":"Baz"}`);

    /* Structured decode into JsonValue */
    auto xv = jsonDecode(`null`);
    assert(xv.type() == typeid(JsonNull));

    xv = jsonDecode(xjson);
    assert(xv["bogus"] == "ignore me");
    assert(xv["foo"] == "Baz");
    assert(xv["reals"][0] == 3.4L);
    assert(xv["reals"][1] == 72000L);
    assert(xv["reals"][2] == 5L);
    assert(xv["reals"][3] == 0L);
    assert(xv["reals"][4] == -33L);
    assert(xv["ints"]["two"] == 2);
    assert(xv["ints"]["two"] == 2);
    assert(xv["conf"]["encoding"] == "UTF-8");
    assert(xv["conf"]["plugins"][0] == "perl");
    assert(xv["conf"]["plugins"][1] == "d");
    assert(xv["conf"]["indent"] == 4);
    assert(xv["conf"]["indentSpaces"] == true);

    /* Encode JsonValue back to JSON */
    assert(jsonEncode(xv) ==
        `{"bogus":"ignore me","conf":{"encoding":"UTF-8","indent":4,"indentSpaces":true,"plugins":["perl","d"]},"foo":"Baz","ints":{"one":1,"two":2},"reals":[3.4,72000,5,0,-33]}`);

    /* All truncated streams should be errors */
    foreach(i;iota(xjson.length)) {
        bool caught;

        if(i < xjson.length) {
            caught = false;
            try {
                jsonDecode(xjson[0..i]);
            } catch(JsonException) {
                caught = true;
            }
            assert(caught);

            caught = false;
            try {
                jsonDecode!X(xjson[0..i]);
            } catch(JsonException) {
                caught = true;
            }
            assert(caught);
        }

        if(i > 0) {
            caught = false;
            try {
                jsonDecode(xjson[i..$]);
            } catch(JsonException) {
                caught = true;
            }
            assert(caught);            

            caught = false;
            try {
                jsonDecode!X(xjson[i..$]);
            } catch(JsonException) {
                caught = true;
            }
            assert(caught);
        }
    }

    /* Tests from std.json */
    auto jsons = [
        `null`,
        `true`,
        `false`,
        `0`,
        `123`,
        `-4321`,
        `0.23`,
        `-0.23`,
        `""`,
        `1.223e+24`,
        `"hello\nworld"`,
        `"\"\\\/\b\f\n\r\t"`,
        `[]`,
        `[12,"foo",true,false]`,
        `{}`,
        `{"a":1,"b":null}`,
        `{"goodbye":[true,"or",false,["test",42,{"nested":{"a":23.54,"b":0.0012}}]],"hello":{"array":[12,null,{}],"json":"is great"}}`
    ];

    foreach(json; jsons) {
        auto v = jsonDecode(json);
        auto rt = jsonEncode(v);
        assert(rt == json, "roundtrip -> " ~ json);
    }

    /* More tests from std.json */
    auto v = jsonDecode(`"\u003C\u003E"`);
    assert(jsonEncode(v) == "\"\&lt;\&gt;\"");
    v = jsonDecode(`"\u0391\u0392\u0393"`);
    assert(jsonEncode(v) == "\"\&Alpha;\&Beta;\&Gamma;\"");
    v = jsonDecode(`"\u2660\u2666"`);
    assert(jsonEncode(v) == "\"\&spades;\&diams;\"");
}
