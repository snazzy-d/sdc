/*
Copyright (c) 2013, w0rp <devw0rp@gmail.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/++

This module defines JSON types, reading, and writing.

Example: Working with objects
---
    // Create an object conveniently with a helper function.
    JSON object = jsonObject();

    // We can assign compatible types to keys.
    object["key"] = 3;

    // We can check for existence.
    assert("key" in object);

    // We can convert back to some primitive value again.
    double num = cast(double) object["key"];

    // We can get direct access to the object with a runtime check.
    object.object["key"] == object["key"];

    // This is not an object!
    assertThrown(object["key"].object);
---

Example: Working with arrays.
---
    // Create an array conveniently with a helper function.
    JSON array = jsonArray();

    // We can append some values to the arrays.

    array ~= null;
    array ~= "a string";
    // Another array.
    array ~= jsonArray();

    // Check the types with some properties.
    assert(array[0].isNull);
    assert(array[1].isString);
    assert(array[2].isArray);

    // Once again we can use direct access, runtime checked.
    assert(array.array ~= JSON(347));
    assert(array[3] == 347);

    // We can allocate arrays conveniently with a given size.
    JSON anotherArray = jsonArray(10);

    assert(anotherArray.length == 10);

    // foreach works with size_t on arrays and string on objects.
    foreach(size_t index, value; anotherArray) {
        // JSON values default to null.
        assert(value.isNull);
    }
---
+/

module sdc.util.json;
version = dson_relaxed;

import std.conv;
import std.traits;
import std.range;
import std.array;
import std.algorithm;
import std.string;
import std.uni;
import std.utf : encode;
import std.stdio;
import std.math;

version(unittest) {
    import std.exception;
}

/**
 * Determine if a type can represent a JSON primitive type.
 */
template isJSONPrimitive(T) {
    enum isJSONPrimitive = __traits(isArithmetic, T)
        || is(T == typeof(null))
        || is(T == string);
}

/**
 * Determine if a type can represent a JSON array.
 */
template isJSONArray(T) {
    enum isJSONArray = isArray!T && isJSON!(ElementType!T);
}

/**
 * Determine if a type can represent a JSON object.
 */
template isJSONObject(T) {
    static if(__traits(isAssociativeArray, T)) {
        enum isJSONObject = is(KeyType!T == string) && isJSON!(ValueType!T);
    } else {
        enum isJSONObject = false;
    }
}

/**
 * Determine if a type can represent any JSON value.
 *
 * The special JSON type is included here.
 */
template isJSON(T) {
    immutable bool isJSON = is(T == JSON) || isJSONPrimitive!T
        || isJSONArray!T || isJSONObject!T;
}

// Test the templates.
unittest {
    assert(isJSONPrimitive!(typeof(null)));
    assert(isJSONPrimitive!bool);
    assert(isJSONPrimitive!int);
    assert(isJSONPrimitive!uint);
    assert(isJSONPrimitive!real);
    assert(isJSONPrimitive!string);
    assert(isJSON!(typeof(null)));
    assert(isJSON!bool);
    assert(isJSON!int);
    assert(isJSON!uint);
    assert(isJSON!real);
    assert(isJSON!string);
    assert(isJSONArray!(string[]));
    assert(isJSONArray!(int[]));
    assert(isJSONArray!(int[][]));
    assert(isJSONArray!(string));
    assert(isJSONArray!(string[][][]));
    assert(isJSONArray!(int[string][][]));
    assert(!isJSONArray!int);
    assert(!isJSONArray!bool);
    assert(!isJSONArray!(typeof(null)));
    assert(isJSONObject!(int[string]));
    assert(!isJSONObject!(string[bool]));
    assert(isJSONObject!(real[string]));
    assert(isJSONObject!(int[][string]));
}

/**
 * This class of exception may be thrown when something goes wrong
 * while reading JSON data.
 */
class JSONParseException : Exception {
    /**
     * The line number (starting at 1) where the problem occurred.
     */
    public const long line;

    /**
     * The column number (starting at 1) where the problem occurred.
     */
    public const long column;

    this(string reason, long line, long column) {
        this.line = line;
        this.column = column;

        super(reason ~ " at line " ~ to!string(line)
            ~ " column " ~ to!string(column) ~ "!");
    }
}

/// The possible types of JSON values.
enum JSON_TYPE : byte {
    /// The JSON value holds null. (This is the default value)
    NULL,
    /// The JSON value holds explicitly true or false.
    BOOL,
    /// The JSON value holds a string.
    STRING,
    /// The JSON value holds an integer.
    INT,
    /// The JSON value holds a floating point number.
    FLOAT,
    /// The JSON value holds a JSON object. (associative array)
    OBJECT,
    /// The JSON value holds a JSON array.
    ARRAY
}

/// A discriminated union representation of any JSON value.
struct JSON {
private:
    union {
        bool _boolean;
        string _str;
        long _integer;
        real _floating;
        JSON[string] _object;
        JSON[] _array;
    }

    JSON_TYPE _type;
public:
    // Any method accessing the union must be marked as @trusted, not @safe.
    // This is because @safe rejects the union.

    /**
     * Initialize the JSON type from an integer.
     */
    @trusted pure nothrow this(long integer) inout {
        _integer = integer;
        _type = JSON_TYPE.INT;
    }

    /**
     * Initialize the JSON type from a boolean.
     */
    @trusted pure nothrow this(bool boolean) inout {
        _boolean = boolean;
        _type = JSON_TYPE.BOOL;
    }

    /**
     * Initialize the JSON type from a floating point value.
     */
    @trusted pure nothrow this(real floating) inout {
        _floating = floating;
        _type = JSON_TYPE.FLOAT;
    }

    /**
     * Initialize the JSON type explicitly to null.
     */
    @trusted pure nothrow this(typeof(null) nothing) inout {
        _integer = 0;
        _type = JSON_TYPE.NULL;
    }

    /**
     * Initialize the JSON type as a string.
     */
    @trusted pure nothrow this(inout(string) str) inout {
        _str = str;
        _type = JSON_TYPE.STRING;
    }

    /**
     * Initialize the JSON type from an existing JSON array.
     */
    @trusted pure nothrow this(inout(JSON[]) array) inout {
        _array = array;
        _type = JSON_TYPE.ARRAY;
    }

    /**
     * Initialize the JSON type from an existing JSON object.
     */
    @trusted pure nothrow this(inout(JSON[string]) object) inout {
        _object = object;
        _type = JSON_TYPE.OBJECT;
    }

    /**
     * Assign an integer to the JSON value.
     */
    @trusted pure nothrow long opAssign(long integer) {
        _type = JSON_TYPE.INT;
        return _integer = integer;
    }

    /**
     * Assign a boolean to the JSON value.
     */
    @trusted pure nothrow bool opAssign(bool boolean) {
        _type = JSON_TYPE.BOOL;
        return _boolean = boolean;
    }

    /**
     * Assign a floating point number to the JSON value.
     */
    @trusted pure nothrow real opAssign(real floating) {
        _type = JSON_TYPE.FLOAT;
        return _floating = floating;
    }

    /**
     * Assign null to the JSON value.
     */
    @trusted pure nothrow typeof(null) opAssign(typeof(null) nothing) {
        _integer = 0;
        _type = JSON_TYPE.NULL;

        return null;
    }

    /**
     * Assign a string the JSON value.
     */
    @trusted pure nothrow string opAssign(string str) {
        _type = JSON_TYPE.STRING;
        return _str = str;
    }

    /**
     * Assign an array to the JSON value.
     */
    @trusted pure nothrow JSON[] opAssign(JSON[] array) {
        _type = JSON_TYPE.ARRAY;
        return _array = array;
    }

    /**
     * Assign an object to the JSON value.
     */
    @trusted pure nothrow JSON[string] opAssign(JSON[string] object) {
        _type = JSON_TYPE.OBJECT;
        return _object = object;
    }

    /**
     * Returns: An enum describing the current type of the JSON value.
     */
    @trusted pure nothrow @property JSON_TYPE type() const {
        return _type;
    }

    /**
     * Returns: true if this JSON value is a boolean value.
     */
    @trusted pure nothrow @property bool isBool() const {
        return _type == JSON_TYPE.BOOL;
    }

    /**
     * Returns: true if this JSON value contains a numeric type.
     *  This includes boolean values.
     */
    @trusted pure nothrow @property bool isNumber() const {
        with(JSON_TYPE) switch(_type) {
        case BOOL, INT, FLOAT:
            return true;
        default:
            return false;
        }
    }

    /**
     * Returns: true if the value is a string.
     */
    @trusted pure nothrow @property bool isString() const {
        with(JSON_TYPE) switch(_type) {
        case STRING:
            return true;
        default:
            return false;
        }
    }

    /**
     * Returns: true if this JSON value is null.
     */
    @trusted pure nothrow @property bool isNull() const {
        return _type == JSON_TYPE.NULL;
    }

    /**
     * Returns: true if this JSON value is an array.
     */
    @trusted pure nothrow @property bool isArray() const {
        return _type == JSON_TYPE.ARRAY;
    }

    /**
     * Returns: true if this JSON value is an object.
     */
    @trusted pure nothrow @property bool isObject() const {
        return _type == JSON_TYPE.OBJECT;
    }

    /**
     * Returns: A reference to the JSON array stored in this object.
     * Throws: Exception when the JSON type is not an array.
     */
    @trusted pure @property ref inout(JSON[]) array() inout {
        if (_type != JSON_TYPE.ARRAY) {
            throw new Exception("JSON value is not an array!");
        }

        return _array;
    }

    /**
     * Returns: A reference to the JSON object stored in this object.
     * Throws: Exception when the JSON type is not an object.
     */
    @trusted pure @property ref inout(JSON[string]) object() inout {
        if (_type != JSON_TYPE.OBJECT) {
            throw new Exception("JSON value is not an object!");
        }

        return _object;
    }

    /**
     * Returns: The length of the inner JSON array or object.
     * Throws: Exception when this is not an array or object.
     */
    @trusted @property size_t length() const {
        if (_type == JSON_TYPE.ARRAY) {
           return _array.length;
        } else if (_type == JSON_TYPE.OBJECT) {
           return _object.length;
        } else {
            throw new Exception("length called on non array or object type.");
        }
    }

    /**
     * Set the length of the inner JSON array.
     * Throws: Exception when this is not an array.
     */
    @trusted pure @property void length(size_t len) {
        if (_type == JSON_TYPE.ARRAY) {
           _array.length = len;
        } else {
            throw new Exception("Cannot set length on non array!");
        }
    }

    /**
     * Returns: The JSON value converted to a string.
     */
    @trusted string toString() const {
        with(JSON_TYPE) final switch (_type) {
        case BOOL:
            return _boolean ? "true" : "false";
        case INT:
            return to!string(_integer);
        case FLOAT:
            return to!string(_floating);
        case STRING:
            return _str;
        case ARRAY:
            return to!string(_array);
        case OBJECT:
            return to!string(_object);
        case NULL:
            return "null";
        }
    }

    /**
     * Returns: The JSON value cast to another value.
     * Throws: Exception when the type held in the JSON value does not match.
     */
    @trusted pure inout(T) opCast(T)() inout {
        static if (__traits(isArithmetic, T)) {
            with(JSON_TYPE) switch (_type) {
            case BOOL:
                return cast(T) _boolean;
            case INT:
                return cast(T) _integer;
            case FLOAT:
                return cast(T) _floating;
            default:
                throw new Exception("cast to number failed!");
            }
        } else static if (is(T == string)) {
            if (_type != JSON_TYPE.STRING) {
                throw new Exception("cast(string) failed!");
            }

            return _str;
        } else static if(is(T == JSON[])) {
            if (_type != JSON_TYPE.ARRAY) {
                throw new Exception("JSON value is not an array!");
            }

            return _array;
        } else static if(is(T == JSON[string])) {
            if (_type != JSON_TYPE.OBJECT) {
                throw new Exception("JSON value is not an object!");
            }

            return _object;
        } else {
            static assert(false, "Unsupported cast from JSON!");
        }
    }

    /**
     * Cast the JSON type to a bool. <br />
     * For objects, arrays, and strings, this is length > 0. <br />
     * For numeric types, this is value != 0. <br />
     * null becomes false.
     *
     * Returns: The JSON value cast to a boolean.
     */
    @trusted nothrow inout(T) opCast(T: bool)() inout {
        with(JSON_TYPE) final switch (_type) {
        case BOOL:
            return cast(T) _boolean;
        case INT:
            return cast(T) _integer;
        case FLOAT:
            return cast(T) _floating;
        case STRING:
            return _str.length > 0;
        case ARRAY:
            return _array.length > 0;
        case OBJECT:
                return _object.length > 0;
        case NULL:
            return false;
        }
    }

    /**
     * Concatenate this JSON array with another value.
     * This will place the value inside of the array, including other arrays.
     *
     * Example:
     * ---
     *     JSON arr = jsonArray(); // []
     *     JSON arr2 = arr ~ 3 // [3]
     *     JSON arr3 = arr2 ~ jsonArray() // [3, []]
     * ---
     *
     *
     * Params:
     *  val= A JSON value.
     *
     * Returns: A new JSON array with the value on the end.
     */
    @trusted pure
    JSON opBinary(string op : "~", T)(T val) if (isJSON!T) {
        return JSON(array ~ JSON(val));
    }

    @trusted pure
    JSON opBinary(string op : "~", T : JSON)(T val) {
        // We can avoid a copy for JSON types.
        return JSON(array ~ val);
    }

    /**
     * Add a value to this JSON array.
     *
     * Throws: Exception when this is not an array.
     */
    @trusted pure
    void put(T)(T val) if (isJSON!T) {
        array ~= JSON(val);
    }

    @trusted pure
    void put(T : JSON)(T val) {
        array ~= val;
    }

    /**
     * See_Also: put
     */
    @trusted pure
    void opOpAssign(string op : "~", T)(T val) {
        put(val);
    }

    /**
     * Params:
     *  index = The index for the value in the array.
     *
     * Returns: A reference to a value in the array.
     * Throws: Exception when this is not an array.
     * Throws: Error when the index is out of bounds.
     */
    @trusted pure ref inout(JSON) opIndex(size_t index) inout {
        return array[index];
    }

    /**
     * Params:
     *  key = The key for the value in the object.
     *
     * Returns: A reference to a value in the object.
     * Throws: Exception when this is not an object.
     */
    @trusted pure ref inout(JSON) opIndex(string key) inout {
        return object[key];
    }

    /**
     * When this JSON value is an array, assign a value to an index of it.
     *
     * Params:
     *  value= The value to assign to the index.
     *  index= The index in the array.
     *
     * Throws: Exception when the JSON value is not an array.
     */
    @trusted pure void opIndexAssign(T)(T value, size_t index) {
        array[index] = value;
    }

    /**
     * When this JSON value is an object, assign a value to a key of it.
     *
     * Params:
     *  value= The value to assign to the index.
     *  index= The key in the object.
     *
     * Throws: Exception when the JSON value is not an object.
     */
    @trusted pure void opIndexAssign(T)(T value, string key) {
        object[key] = value;
    }

    /**
     * When this JSON value is an object, test for existence of a key in it.
     *
     * Params:
     *  key= The key in the object.
     *
     * Returns: A pointer to the value in the object.
     * Throws: Exception when the JSON value is not an object.
     */
    @trusted pure inout(JSON*)
    opBinaryRight(string op : "in") (string key) inout {
        return key in object;
    }

    /**
     * Support foreach through JSON values in an array or object.
     *
     * If the JSON value is not an array or object, foreach does not throw
     * an exception.
     *
     * Example:
     * ---
     *     foreach(value; someArray) { ... }
     * ---
     */
    @trusted int opApply(int delegate(ref JSON val) dg) {
        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach(ref val; _array) {
                if((result = dg(val)) > 0) {
                    break;
                }
            }
        } else if (_type == JSON_TYPE.OBJECT) {
            foreach(ref val; _object) {
                if((result = dg(val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    /**
     * Support foreach through key-value pairs.
     *
     * If the JSON value is not an object, foreach does not throw an exception.
     * If the JSON value is an array, indices will be converted to strings.
     *
     * Example:
     * ---
     *     foreach(string key, value; someObject) { ... }
     * ---
     */
    @trusted int opApply(int delegate(string key, ref JSON val) dg) {
        int result;

        if (_type == JSON_TYPE.OBJECT) {
            foreach(key, ref val; _object) {
                if((result = dg(key, val)) > 0) {
                    break;
                }
            }
        } else if(_type == JSON_TYPE.ARRAY) {
            foreach(index, ref val; _array) {
                if((result = dg(to!string(index), val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    /**
     * Support foreach through index-value pairs.
     *
     * If the JSON value is not an array or object, no exceptions will be
     * thrown.
     *
     * Example:
     * ---
     *     foreach(size_t index, value; someObject) { ... }
     * ---
     *
     * Throws: Exception when the JSON value is an object.
     */
    @trusted int opApply(int delegate(size_t index, ref JSON val) dg) {
        if(_type == JSON_TYPE.OBJECT) {
            throw new Exception("index-value foreach not supported for "
                ~ "objects!");
        }

        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach(index, ref val; _array) {
                if((result = dg(index, val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    /// foreach_reverse support
    @trusted int opApplyReverse(int delegate(ref JSON val) dg) {
        if (_type == JSON_TYPE.OBJECT) {
            // Map are unordered, so the same code for foreach can be used.
            return opApply(dg);
        }

        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach_reverse(ref val; _array) {
                if((result = dg(val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    /// ditto
    @trusted int opApplyReverse(int delegate(string key, ref JSON val) dg) {
        if (_type == JSON_TYPE.OBJECT) {
            return opApply(dg);
        }

        int result;

        if(_type == JSON_TYPE.ARRAY) {
            foreach_reverse(index, ref val; _array) {
                if((result = dg(to!string(index), val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    /// ditto
    @trusted int opApplyReverse(int delegate(size_t index, ref JSON val) dg) {
        if(_type == JSON_TYPE.OBJECT) {
            throw new Exception("index-value foreach_reverse not supported "
                ~ "for objects!");
        }

        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach_reverse(index, ref val; _array) {
                if((result = dg(index, val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    /// Returns: true if this JSON value is equal to another value.
    @trusted nothrow bool opEquals(T)(inout(T) other) inout
    if(!is(T == typeof(null))) {
        static if(is(T == JSON)) {
            if (_type != other._type) {
                return false;
            }

            with(JSON_TYPE) final switch (_type) {
            case BOOL:
                return _boolean == other._boolean;
            case INT:
                return _integer == other._integer;
            case FLOAT:
                return _floating == other._floating;
            case STRING:
                return _str == other._str;
            case ARRAY:
                return _array == other._array;
            case OBJECT:
                return _object == other._object;
            case NULL:
                // The types match, so this is true.
                return true;
            }
        } else static if(is(T : const(char[]))) {
            return _type == JSON_TYPE.STRING && _str == other;
        } else static if(isJSONArray!T) {
            if (_type != JSON_TYPE.ARRAY || _array.length != other.length) {
                return false;
            }

            for (size_t i = 0; i < _array.length; ++i) {
                if (_array[0] != other[0]) {
                    return false;
                }
            }

            return true;
        } else static if(isJSONObject!T) {
            if (_type != JSON_TYPE.OBJECT || _object.length != other.length) {
                return false;
            }

            foreach(key, val; _object) {
                auto other_val_p = key in other;

                if (!other_val_p || val != *other_val_p) {
                    return false;
                }
            }

            return true;
        } else static if(__traits(isArithmetic, T)) {
            with(JSON_TYPE) switch (_type) {
            case BOOL:
                return _boolean == other;
            case INT:
                return _integer == other;
            case FLOAT:
                return _floating == other;
            default:
                return false;
            }
        } else {
            static assert(false, "No match for JSON opEquals!");
        }
    }

    // TODO: opCmp
}

// Test opAssign.
unittest {
    JSON j;

    assert((j = 3) == 3);
}

// Test type return values.
unittest {
    assert(JSON(null).type == JSON_TYPE.NULL);
    assert(JSON(true).type == JSON_TYPE.BOOL);
    assert(JSON(3).type == JSON_TYPE.INT);
    assert(JSON(7.3).type == JSON_TYPE.FLOAT);
    assert(JSON("").type == JSON_TYPE.STRING);
    assert(JSON(new JSON[0]).type == JSON_TYPE.ARRAY);

    // TODO: Fix this.
    // assert(JSON(0).type == JSON_TYPE.INT);
    // assert(JSON(1).type == JSON_TYPE.INT);

    JSON[string] object;

    assert(JSON(object).type == JSON_TYPE.OBJECT);

    // It's important to make sure than normal assignment still
    // works properly.
    JSON j1;
    JSON j2 = j1;

    assert(j2.type == JSON_TYPE.NULL);
}

// Test cast(bool)

unittest {
    assert(cast(bool) JSON(false) == false);
    assert(cast(bool) JSON(true));
    assert(cast(bool) JSON(0) == false);
    assert(cast(bool) JSON(-2));
    assert(cast(bool) JSON(new JSON[0]) == false);
    assert(cast(bool) JSON(new JSON[2]) == true);

    JSON[string] x;
    x["wat"] = null;
    JSON j = x;

    assert(cast(bool) j == true);
}

// Test integer casts.
unittest {
    assert(cast(long) JSON(false) == 0);
    assert(cast(long) JSON(true) == 1);
    assert(cast(long) JSON(0) == 0);
    assert(cast(long) JSON(-2) == -2);
    assertThrown(cast(int) JSON("some string"));
    assertThrown(cast(int) JSON(new JSON[0]));

    JSON[string] obj;
    assertThrown(cast(int) JSON(obj));
}

// Test float casts.
unittest {
    assert(cast(real) JSON(false) == 0.0);
    assert(cast(real) JSON(true) == 1.0);
    assert(cast(double) JSON(35) == 35);
    assert(approxEqual(cast(float) JSON(2.5), 2.5, 0.001));
    assertThrown(cast(real) JSON("some string"));
    assertThrown(cast(real) JSON(new JSON[0]));

    JSON[string] obj;
    assertThrown(cast(real) JSON(obj));
}

// Test string casts.
unittest {
    assert(cast(string) JSON("foo") == "foo");
    assertThrown(cast(string) JSON(null));
    assertThrown(cast(string) JSON(2u));
    assertThrown(cast(string) JSON(-2));
    assertThrown(cast(string) JSON(true));
    assertThrown(cast(string) JSON(new JSON[0]));

    JSON[string] obj;
    assertThrown(cast(string) JSON(obj));
}

// Test toString()
unittest {
    assert(JSON(false).toString() == "false");
    assert(JSON(true).toString() == "true");
    assert(JSON(33).toString() == "33");
    assert(JSON(-2).toString() == "-2");
    assert(JSON(0L).toString() == "0");
    assert(JSON(25).toString() == "25");
    assert(JSON(2.5).toString() == "2.5");
    assert(JSON("abc").toString() == "abc");
}

// Test JSON -> JSON cast
unittest {
    JSON x;
    JSON y = cast(JSON) x;
}

// Test valid JSON -> JSON[] cast
unittest {
    JSON[] arr;
    JSON x = arr;

    assert(cast(JSON[]) x == arr);
}

// Test invalid JSON -> JSON[] cast
unittest {
    JSON x;

    assertThrown(cast(JSON[]) x);
}

// Test valid JSON -> JSON[string] cast
unittest {
    JSON[string] map;
    JSON x = map;

    assert(cast(JSON[string]) x == map);
}

// Test invalid JSON -> JSON[string] cast
unittest {
    JSON x;

    assertThrown(cast(JSON[string]) x);
}

// Test that casting to a class doesn't even compile
unittest {
    class Test() {}
    JSON x;

    static if(__traits(compiles, cast(Test) x)) {
        assert(false);
    }
}

// Test .array
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assertThrown(j.array);

    j = b;
    assertThrown(j.array);

    j = n;
    assertThrown(j.array);

    j = r;
    assertThrown(j.array);

    j = str;
    assertThrown(j.array);

    j = arr;
    assert(j.array == arr);

    j = obj;
    assertThrown(j.array);
}

// Test .object
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assertThrown(j.object);

    j = b;
    assertThrown(j.object);

    j = n;
    assertThrown(j.object);

    j = r;
    assertThrown(j.object);

    j = str;
    assertThrown(j.object);

    j = arr;
    assertThrown(j.object);

    j = obj;
    assert(j.object == obj);
}

// Test isNumber
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isNumber);

    j = b;
    assert(j.isNumber);

    j = n;
    assert(j.isNumber);

    j = r;
    assert(j.isNumber);

    j = str;
    assert(!j.isNumber);

    j = arr;
    assert(!j.isNumber);

    j = obj;
    assert(!j.isNumber);
}

// Test isString
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isNumber);

    j = b;
    assert(!j.isString);

    j = n;
    assert(!j.isString);

    j = r;
    assert(!j.isString);

    j = str;
    assert(j.isString);

    j = arr;
    assert(!j.isString);

    j = obj;
    assert(!j.isString);
}

// Test isNull
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(j.isNull);

    j = b;
    assert(!j.isNull);

    j = n;
    assert(!j.isNull);

    j = r;
    assert(!j.isNull);

    j = str;
    assert(!j.isNull);

    j = arr;
    assert(!j.isNull);

    j = obj;
    assert(!j.isNull);
}

// Test isArray
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isArray);

    j = b;
    assert(!j.isArray);

    j = n;
    assert(!j.isArray);

    j = r;
    assert(!j.isArray);

    j = str;
    assert(!j.isArray);

    j = arr;
    assert(j.isArray);

    j = obj;
    assert(!j.isArray);
}

// Test isObject
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isObject);

    j = b;
    assert(!j.isObject);

    j = n;
    assert(!j.isObject);

    j = r;
    assert(!j.isObject);

    j = str;
    assert(!j.isObject);

    j = arr;
    assert(!j.isObject);

    j = obj;
    assert(j.isObject);
}

/**
 * Returns: A new JSON object.
 */
@trusted pure nothrow JSON jsonObject() {
    JSON object;
    object._object = null;
    object._type = JSON_TYPE.OBJECT;

    return object;
}

// Basic jsonObject test.
unittest {
    JSON obj = jsonObject();

    assert(obj.isObject);
    assert(obj.length == 0);
}

// Test object key get.
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "bla";
    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    JSON[string] origObj;

    origObj["a"] = JSON(null);
    origObj["b"] = JSON(b);
    origObj["d"] = JSON(n);
    origObj["e"] = JSON(r);
    origObj["f"] = JSON(str);
    origObj["g"] = JSON(arr);
    origObj["h"] = JSON(obj);
    origObj["i"] = otherJ;

    JSON j = origObj;

    assert(j["a"].isNull);
    assert(cast(bool) j["b"] == b);
    assert(cast(int) j["d"] == n);
    assert(cast(real) j["e"] == r);
    assert(cast(string) j["f"] == str);
    assert(j["g"].array.length == 0);
    assert(j["h"].object.length == 0);
    assert(j["i"] == otherJ);
}

// Test object key set.
unittest {
    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    JSON j = jsonObject();

    j["a"] = null;
    j["b"] = true;
    j["c"] = 1u;
    j["d"] = 1;
    j["e"] = 1.0;
    j["f"] = "bla";
    j["g"] = arr;
    j["h"] = obj;
    j["i"] = otherJ;

    assert(j["a"].isNull);
    assert(cast(bool) j["b"] == true);
    assert(cast(int) j["d"] == 1);
    assert(cast(real) j["e"] == 1.0);
    assert(cast(string) j["f"] == "bla");
    assert(j["g"].array.length == 0);
    assert(j["h"].object.length == 0);
    assert(j["i"] == otherJ);
}

// Test "in" operator for object.
unittest {
    JSON obj = jsonObject();

    obj["a"] = 347;
    obj["b"] = true;
    obj["c"] = "beepbeep";
    obj["d"] = null;

    assert(cast(int) (*("a" in obj)) == 347);
    assert(cast(bool) (*("b" in obj)) == true);
    assert(cast(string) (*("c" in obj)) == "beepbeep");
    assert((*("d" in obj)).isNull);
}


/**
 * Params:
 *     size= The initial size of the new array.
 *
 * Returns: A new JSON array.
 */
@trusted pure nothrow JSON jsonArray(size_t size = 0) {
    JSON array;
    array._array = new JSON[size];
    array._type = JSON_TYPE.ARRAY;

    return array;
}

// Basic jsonArray test.
unittest {
    JSON arr = jsonArray();

    assert(arr.isArray);
    assert(arr.length == 0);

    JSON otherArr = jsonArray(10);

    assert(otherArr.isArray);
    assert(otherArr.length == 10);

    foreach(index, value; otherArr.array) {
        assert(value.isNull, "Non-null default array value at "
            ~ to!string(index));
    }
}

// Test array concatenate.
unittest {
    JSON j = jsonArray();

    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    j = j ~ null;
    j = j ~ true;
    j = j ~ 1u;
    j = j ~ 1;
    j = j ~ 1.0;
    j = j ~ "bla";
    j = j ~ arr;
    j = j ~ obj;
    j = j ~ otherJ;

    assert(j.array[0].isNull);
    assert(cast(bool) j.array[1] == true);
    assert(cast(int) j.array[3] == 1);
    assert(cast(real) j.array[4] == 1.0);
    assert(cast(string) j.array[5] == "bla");
    assert(j.array[6].array == []);
    assert(j.array[7].object.length == 0);
    assert(cast(int) j.array[8] == 3);
}

// Test array append.
unittest {
    JSON j = jsonArray();

    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    // It's important to use rvalues for these kinds of tests.
    // Otherwise, we might end up with broken code because the overloads
    // except references to lvalues.
    j ~= null;
    j ~= true;
    j ~= 1u;
    j ~= 1;
    j ~= 1.0;
    j ~= "bla";
    j ~= arr;
    j ~= obj;
    j ~= otherJ;

    assert(j.array[0].isNull);
    assert(cast(bool) j.array[1] == true);
    assert(cast(int) j.array[3] == 1);
    assert(cast(float) j.array[4] == 1.0);
    assert(cast(string) j.array[5] == "bla");
    assert(j.array[6].array == arr);
    assert(j.array[7].object == obj);
    assert(cast(int) j.array[8] == 3);
}

// Test array index get.
unittest {
    JSON j = jsonArray();

    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "bla";
    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    j.array ~= JSON(null);
    j.array ~= JSON(b);
    j.array ~= JSON(n);
    j.array ~= JSON(r);
    j.array ~= JSON(str);
    j.array ~= JSON(arr);
    j.array ~= JSON(obj);
    j.array ~= otherJ;

    assert(j[0].isNull);
    assert(cast(bool) j[1] == b);
    assert(cast(int) j[3] == n);
    assert(cast(real) j[3] == r);
    assert(cast(string) j[4] == str);
    assert(j[5].array == arr);
    assert(j[6].object == obj);
    assert(cast(int) j[7] == 3);
}

// Test array index set.
unittest {
    JSON j = jsonArray();

    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    j.length = 9;

    j[0] = null;
    j[1] = true;
    j[2] = 1u;
    j[3] = 1;
    j[4] = 1.0;
    j[5] = "bla";
    j[6] = arr;
    j[7] = obj;
    j[8] = otherJ;

    assert(j[0].isNull);
    assert(cast(bool) j[1] == true);
    assert(cast(int) j[3] == 1);
    assert(cast(real) j[4] == 1.0);
    assert(cast(string) j[5] == "bla");
    assert(j[6].array == arr);
    assert(j[7].object == obj);
    assert(cast(int) j[8] == 3);
}


/**
 * Concatenate two JSON arrays
 *
 * Example:
 * ---
 *     JSON arr = jsonArray(); // []
 *     arr ~= 1; // [1]
 *
 *     JSON arr2 = jsonArray(); // []
 *     arr2 ~= 3; // [3]
 *
 *     JSON arr3 = arr.concat(arr2); // [1, 3]
 * ---
 *
 * Params:
 *     left= The first JSON array.
 *     right= The right JSON array.
 *
 * Returns: The concatenation of the two arrays as a JSON value.
 * Throws: Exception if either value is not an array.
 */
@safe pure JSON concat()(auto ref JSON left, auto ref JSON right) {
    return JSON(left.array ~ right.array);
}

/// ditto
@safe pure JSON concat()(auto ref JSON left, JSON[] right) {
    return JSON(left.array ~ right);
}

/// ditto
@safe pure JSON concat()(JSON[] left, auto ref JSON right) {
    return JSON(left ~ right.array);
}

/// ditto
@safe pure nothrow JSON concat()(JSON[] left, JSON[] right) {
    return JSON(left ~ right);
}

unittest {
    auto left = jsonArray();

    left ~= 1;

    auto right = jsonArray();

    right ~= 2;

    assert(left.concat(right) == [1, 2]);

    auto special = left.concat(right).concat(new JSON[1]);

    assert(special.length == 3);
    assert(special[0] == 1);
    assert(special[1] == 2);
    assert(special[2].isNull);
}

/**
 * Example:
 * ---
 *     JSON arr = convertJSON([1, 2, 3, 4, 5]);
 * ---
 *
 * Params:
 *     value= A value which can be converted to JSON.
 *
 * Returns:
 *     A JSON object created using the value.
 */
JSON convertJSON(JSONCompatible)(auto ref JSONCompatible value)
if (isJSON!JSONCompatible) {
    static if (is(JSONCompatible == JSON)) {
        // No conversion neeeded.
        return value;
    } else static if (is(JSONCompatible == JSON[])
    || is(JSONCompatible == JSON[string])
    || isJSONPrimitive!JSONCompatible) {
        // This is a straight conversion.
        return JSON(value);
    } else static if(isJSONArray!JSONCompatible)  {
        auto arr = new JSON[](value.length);

        for (size_t i = 0; i < value.length; ++i) {
            arr[i] = convertJSON(value[i]);
        }

        return JSON(arr);
    } else static if(isJSONObject!JSONCompatible) {
        JSON[string] map;

        foreach(mapKey, mapValue; value) {
            map[mapKey] = convertJSON(mapValue);
        }

        return JSON(map);
    } else {
        static assert(false, "Invalid type for convertJSON!");
    }
}

// Test convertJSON with JSON itself.
unittest {
    JSON j;

    JSON x = convertJSON(j);
}

// Test convertJSON with primitives.
unittest {
    JSON a = convertJSON(3);
    JSON b = convertJSON("bee");
    JSON c = convertJSON(null);
    JSON d = convertJSON(4.5);

    assert(cast(int) a == 3);
    assert(cast(string) b == "bee");
    assert(c.isNull);
    assert(cast(real) d == 4.5);
}

// Test convertJSON with an array literal.
unittest {
    JSON j = convertJSON([
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9]
    ]);

    assert(j.length == 3);
    assert(j[0].length == 3);
    assert(cast(int) j[0][0] == 1);
    assert(cast(int) j[0][1] == 2);
    assert(cast(int) j[0][2] == 3);
    assert(j[1].length == 3);
    assert(cast(int) j[1][0] == 4);
    assert(cast(int) j[1][1] == 5);
    assert(cast(int) j[1][2] == 6);
    assert(j[2].length == 3);
    assert(cast(int) j[2][0] == 7);
    assert(cast(int) j[2][1] == 8);
    assert(cast(int) j[2][2] == 9);
}

// Test convertJSON with an object literal.
unittest {
    JSON j = convertJSON([
        "a": [1, 2, 3],
        "b": [4, 5, 6],
        "c": [7, 8, 9]
    ]);

    assert(j.length == 3);
    assert("a" in j && j["a"].length == 3);
    assert(cast(int) j["a"][0] == 1);
    assert(cast(int) j["a"][1] == 2);
    assert(cast(int) j["a"][2] == 3);
    assert("b" in j && j["b"].length == 3);
    assert(cast(int) j["b"][0] == 4);
    assert(cast(int) j["b"][1] == 5);
    assert(cast(int) j["b"][2] == 6);
    assert("c" in j && j["c"].length == 3);
    assert(cast(int) j["c"][0] == 7);
    assert(cast(int) j["c"][1] == 8);
    assert(cast(int) j["c"][2] == 9);
}

// Test convertJSON with something invalid
unittest {
    static if(__traits(compiles, convertJSON([1 : [1, 2, 3]]))) {
        assert(false);
    }
}

private void newline(T)(T outRange) {
    outRange.put('\n');
}

private void indent(T)(T outRange, int spaces) {
    repeat(' ').take(spaces).copy(outRange);
}

/**
 * Given a string to write to, write the given string as a valid JSON string.
 *
 * Control characters found in the string will be either escaped or skipped.
 */
void writeJSONString(OutputRange)
(string str, OutputRange outRange)
if(isOutputRange!(OutputRange, char)) {
    outRange.put('"');

    foreach(c; str) {
        switch (c) {
        case '"':
            copy(`\"`, outRange);
        break;
        case '\\':
            copy(`\\`, outRange);
        break;
        case '/':
            copy(`\/`, outRange);
        break;
        case '\b':
            copy(`\b`, outRange);
        break;
        case '\f':
            copy(`\f`, outRange);
        break;
        case '\n':
            copy(`\n`, outRange);
        break;
        case '\r':
            copy(`\r`, outRange);
        break;
        case '\t':
            copy(`\t`, outRange);
        break;
        default:
            if (c > 127) {
                // Let starting and continuation bytes pass through.
                outRange.put(c);
            } else if (isControl(c)) {
                copy(`\u00`, outRange);

                char hexChar(ubyte num) {
                    switch(num) {
                    case 0: .. case 9:
                        return cast(char) ('0' + num);
                    case 10: .. case 15:
                        return cast(char) (num - 10 + 'A');
                    default:
                        assert(false);
                    }
                }

                outRange.put(hexChar(c / 16));
                outRange.put(hexChar(c % 16));
            } else {
                outRange.put(c);
            }
        }
    }

    outRange.put('"');
}

/**
 * Given a string to write to, write the JSON array to the string.
 */
private void writeJSONArray(int spaces, T)
(in JSON[] array, T outRange, int level) {
    outRange.put('[');

    for (size_t i = 0; i < array.length; ++i) {
        if (i != 0) {
            outRange.put(',');
        }

        static if (spaces > 0) {
            newline(outRange);
            indent(outRange, spaces * (level + 1));
        }

        writePrettyJSON!spaces(array[i], outRange, level + 1);
    }

    static if (spaces > 0) {
        if (array.length > 0) {
            newline(outRange);

            if (level > 0) {
                indent(outRange, spaces * level);
            }
        }
    }

    outRange.put(']');
}

/**
 * Given a string to write to, write the JSON object to the string.
 */
private void writeJSONObject(int spaces, T)
(in JSON[string] object, T outRange, int level) {
    outRange.put('{');

    bool first = true;

    foreach(key, val; object) {
        if (!first) {
            outRange.put(',');
        }

        static if (spaces > 0) {
            newline(outRange);
            indent(outRange, spaces * (level + 1));
        }

        writeJSONString(key, outRange);

        outRange.put(':');

        static if (spaces > 0) {
            outRange.put(' ');
        }

        writePrettyJSON!spaces(val, outRange, level + 1);

        first = false;
    }

    static if (spaces > 0) {
        if (!first) {
            newline(outRange);

            if (level > 0) {
                indent(outRange, spaces * level);
            }
        }
    }

    outRange.put('}');
}


/**
 * Given a string to write to, write the JSON value to the string.
 */
private void writePrettyJSON (int spaces = 0, T)
(in JSON json, T outRange, int level = 0) {
    with(JSON_TYPE) final switch (json.type) {
    case NULL:
        outRange.put("null");
    break;
    case BOOL:
        outRange.put(json._boolean ? "true" : "false");
    break;
    case INT:
        copy(to!string(json._integer), outRange);
    break;
    case FLOAT:
        copy(to!string(json._floating), outRange);
    break;
    case STRING:
        writeJSONString(json._str, outRange);
    break;
    case ARRAY:
        writeJSONArray!spaces(json._array, outRange, level);
    break;
    case OBJECT:
        writeJSONObject!spaces(json._object, outRange, level);
    break;
    }
}

/**
 * Write a JSON value to an output range.
 *
 * Params:
 *  spaces= The number of spaces to indent the output with.
 *  json= A JSON value to write to the outputRange.
 *  outputRange= An output range to write the JSON value to.
 */
void writeJSON(int spaces = 0, OutputRange)
(in JSON json, OutputRange outputRange)
if(isOutputRange!(OutputRange, dchar)) {
    static assert(spaces >= 0, "Negative number of spaces for writeJSON.");

    writePrettyJSON!(spaces, OutputRange)(json, outputRange);
}

/**
 * Write a JSON value to a file.
 *
 * Params:
 *  spaces= The number of spaces to indent the output with.
 *  json= A JSON value to write to the file.
 *  file= A file to write the JSON value to.
 */
void writeJSON(int spaces = 0)(in JSON json, File file) {
    writeJSON!spaces(json, file.lockingTextWriter);
}

/**
 * Create a JSON string from a given JSON value.
 *
 * Params:
 *  spaces= The number of spaces to indent the output with.
 *  json= A JSON value to create the string with.
 */
string toJSON(int spaces = 0)(in JSON json) {
    auto result = appender!string();

    writeJSON!(spaces)(json, result);

    return result.data();
}

// This will address a bug with misplacement of @safe.
unittest {
    toJSON(JSON());
}

//is order independent for non-nested objects
version(unittest) auto objectStringTest(R, Rs...)(R res, Rs components)
{
    return only(components)
        .permutations
        .map!(p => chain(`{`, p.joiner(`,`), `}`))
        .canFind!equal(res);
}

// Test various kinds of output from toJSON with JSON types.
unittest {
    assert(toJSON(JSON("bla\\")) == `"bla\\"`);
    assert(toJSON(JSON(4.7)) == "4.7");
    assert(toJSON(JSON(12)) == "12");

    JSON j0 = convertJSON([
        "abc\"", "def", "djw\nw"
    ]);

    assert(toJSON(j0) == `["abc\"","def","djw\nw"]`);

    JSON j1 = convertJSON([
        "abc\"": 1234,
        "def": 5,
        "djw\nw": 1337
    ]);

    assert(objectStringTest(toJSON(j1),
        `"abc\"":1234`, `"def":5`, `"djw\nw":1337`));

    JSON j2 = convertJSON([
        "abc\"": ["bla", "bla", "bla"],
        "def": [],
        "djw\nw": ["beep", "boop"]
    ]);

    assert(objectStringTest(toJSON(j2),
        `"abc\"":["bla","bla","bla"]`,
        `"def":[]`,
        `"djw\nw":["beep","boop"]`));
}


// Test indented writing
unittest {
    JSON j = jsonArray();

    j ~= 3;
    j ~= "hello";
    j ~= 4.5;

    string result = toJSON!4(j);

    assert(result ==
`[
    3,
    "hello",
    4.5
]`);
}

private struct JSONReader(InputRange) {
    InputRange inputRange;
    long line = 1;
    long column = 1;

    static if (isSomeString!InputRange) {
        size_t rangeIndex = 0;
    }

    this(InputRange inputRange) {
        this.inputRange = inputRange;
    }

    auto complaint(string reason) {
        return new JSONParseException(reason, line, column);
    }

    static if (isSomeString!InputRange) {
        // Optimisation for strings.
        // Using an index and checking the length is faster.

        bool empty() {
            return rangeIndex >= inputRange.length;
        }

        auto front() {
            if (rangeIndex >= inputRange.length) {
                throw complaint("Unexpected end of input");
            }

            return inputRange[rangeIndex];
        }

        void popFront() {
            if (rangeIndex >= inputRange.length) {
                throw complaint("Unexpected end of input");
            }

            ++column;
            ++rangeIndex;
        }

        auto moveFront() {
            if (rangeIndex >= inputRange.length) {
                throw complaint("Unexpected end of input");
            }

            ++column;

            return inputRange[rangeIndex++];
        }
    } else {
        bool empty() {
            return inputRange.empty();
        }

        void popFront() {
            ++column;

            scope(failure) --column;

            inputRange.popFront();
        }

        auto front() {
            return inputRange.front();
        }

        auto moveFront() {
            ++column;

            scope(failure) --column;

            auto c = inputRange.front();
            inputRange.popFront();

            return c;
        }
    }

    void skipWhitespace(bool last = false)() {
        while (true) {
            // empty checks only need to happen when reading whitespace
            // at the end of the stream.
            static if (last) {
                if (empty()) {
                    return;
                }
            }

            if (!isWhite(front())) {
                return;
            }

            // Accept \n, \r, or \r\n for newlines.
            // Skip every other whitespace character.
            switch (moveFront()) {
            case '\r':
                static if (last) {
                    if (!empty() && front() == '\n') {
                        popFront();
                    }
                } else {
                    if (front() == '\n') {
                        popFront();
                    }
                }
            goto case;
            case '\n':
                ++line;
                column = 1;
            break;
            default:
            }
        }
    }

    string parseString() {
        auto result = appender!string();

        if (moveFront() != '"') {
            throw complaint("Expected \"");
        }

        loop: while (true) {
            auto c = moveFront();

            switch (c) {
            case '"':
                // End of the string.
                break loop;
            case '\\':
                switch (moveFront()) {
                case '"':
                     result.put('"');
                break;
                case '\\':
                     result.put('\\');
                break;
                case '/':
                     result.put('/');
                break;
                case 'b':
                     result.put('\b');
                break;
                case 'f':
                     result.put('\f');
                break;
                case 'n':
                     result.put('\n');
                break;
                case 'r':
                     result.put('\r');
                break;
                case 't':
                     result.put('\t');
                break;
                case 'u':
                    dchar val = 0;

                    foreach_reverse(i; 0 .. 4) {
                        dchar adjust;

                        switch (front()) {
                        case '0': .. case '9':
                            adjust = '0';
                        break;
                        case 'a': .. case 'f':
                            adjust = 'a' - 10;
                        break;
                        case 'A': .. case 'F':
                            adjust = 'A' - 10;
                        break;
                        default:
                            throw complaint("Expected a hex character");
                        }

                        val += (moveFront() - adjust) << (4 * i);

                    }

                    char[4] buf;

                    size_t i = encode(buf, val);
                    result.put(buf[0 .. i]);
                break;
                default:
                    throw complaint("Invalid escape character");
                }
            break;
            default:
                // We'll just skip control characters.
                if (!isControl(c)) {
                    result.put(c);
                } else {
                }
            break;
            }
        }

        return result.data();
    }

    JSON parseNumber() {
        enum byte NEGATIVE = 1;
        enum byte EXP_NEGATIVE = 2;

        long integer   = 0;
        long remainder = 0;
        short exponent = 0;
        byte signInfo  = 0;

        // Accumulate digits reading left-to-right in a number.
        size_t parseDigits(T)(ref T accum) {
            size_t digitCount = 0;

            while (!empty()) {
                switch(front()) {
                case '0': .. case '9':
                    accum = cast(T) (accum * 10 + (moveFront() - '0'));
                    ++digitCount;

                    if (accum < 0) {
                        throw complaint("overflow error!");
                    }
                break;
                default:
                    return digitCount;
                }
            }

            return digitCount;
        }

        if (front() == '-') {
            popFront();

            signInfo = NEGATIVE;
        }

        if (front() == '0') {
            popFront();
        }

        parseDigits(integer);

        size_t fractionalDigitCount = 0;

        if (!empty() && front() == '.') {
            popFront();

            fractionalDigitCount = parseDigits(remainder);
        }

        if (!empty() && (front() == 'e' || front() == 'E')) {
            popFront();

            switch (front()) {
            case '-':
                signInfo |= EXP_NEGATIVE;
            goto case;
            case '+':
                popFront();
            break;
            default:
            break;
            }

            parseDigits(exponent);
        }

        // NOTE: -0 becomes +0.
        if (remainder == 0 && exponent == 0) {
            // It's an integer.
            return JSON(signInfo & NEGATIVE ? -integer : integer);
        }

        real whole = cast(real) integer;

        if (remainder != 0) {
            // Add in the remainder.
            whole += remainder / (10.0 ^^ fractionalDigitCount);
        }

        if (signInfo & NEGATIVE) {
            whole = -whole;
        }

        if (exponent != 0) {
            // Raise the whole number to the power of the exponent.
            return JSON(whole * (10.0 ^^
                (signInfo & EXP_NEGATIVE ? -exponent : exponent)));
        }


        return JSON(whole);
    }

    JSON[] parseArray() {
        JSON[] arr;

        popFront();

        skipWhitespace();

        if (front() == ']') {
            popFront();
            return arr;
        }

        while (true) {
            arr ~= parseValue();

            skipWhitespace();

            if (front() == ']') {
                // We hit the end of the array
                popFront();
                break;
            }

            if (moveFront() != ',') {
                throw complaint("Expected ]");
            }

            skipWhitespace();
        }

        return arr;
    }

    JSON[string] parseObject() {
        JSON[string] obj;

        popFront();

        skipWhitespace();

        if (front() == '}') {
            popFront();

            return obj;
        }

        FieldLoop: while (true) {
            string key = parseString();

            skipWhitespace();

            if (moveFront() != ':') {
                throw complaint("Expected :");
            }

            skipWhitespace();

            obj[key] = parseValue();

            skipWhitespace();

            // this switch statement stolen from SDC fork
            switch(front()) {
            case ',':
                popFront();
                skipWhitespace();

                // Allow trailing comma.
                version (dson_relaxed) if (front() == '}') {
                    goto case '}';
                }

                // Next field.
                continue;

            case '}':
                popFront();
                break FieldLoop;

            default:
                throw complaint("Expected , or }");
            }
        }

        return obj;
    }

    void parseChars(string matching)() {
        foreach(c; matching) {
            if (moveFront() != c) {
                throw complaint("Invalid input");
            }
        }
    }

    JSON parseValue() {
        switch (front()) {
        case 't':
            popFront();

            parseChars!"rue"();

            return JSON(true);
        case 'f':
            popFront();

            parseChars!"alse"();

            return JSON(false);
        case 'n':
            popFront();

            parseChars!"ull"();

            return JSON(null);
        case '{':
            return JSON(parseObject());
        case '[':
            return JSON(parseArray());
        case '"':
            return JSON(parseString());
        case '-': case '0': .. case '9':
            return parseNumber();
        default:
            throw complaint("Invalid input");
        }
    }

    JSON parseJSON() {
        skipWhitespace();

        JSON val = parseValue();

        if (!empty()) {
            skipWhitespace!true();

            if (!empty()) {
                throw complaint("Trailing character found");
            }
        }

        return val;
    }
}

/**
 * Params:
 *  inputRange = A range of characters to read a JSON string from.
 *
 * Returns:
 *     A JSON value.
 *
 * Throws:
 *     JSONParseException When the range contains invalid JSON.
 */
JSON parseJSON(InputRange)(InputRange inputRange)
if(isInputRange!InputRange && is(ElementType!InputRange : dchar)) {
    return JSONReader!InputRange(inputRange).parseJSON();
}

/**
 * Params:
 *  chunkSize = The number of bytes to read at a time.
 *  file = A file object to read the JSON value from.
 *
 * Returns:
 *     A JSON value.
 *
 * Throws:
 *     JSONParseException When the range contains invalid JSON.
 */
JSON parseJSON(size_t chunkSize = 4096)(File file) {
    return file.byChunk(chunkSize).joiner().parseJSON();
}

// Test parseJSON for keywords
unittest {
    assert(parseJSON(`null`).isNull);
    assert(parseJSON(`true`).type == JSON_TYPE.BOOL);
    assert(parseJSON(`true`));
    assert(parseJSON(`false`).type == JSON_TYPE.BOOL);
    assert(!parseJSON(`false`));
}

// Test parseJSON for various string inputs
unittest {
    assert(cast(string) parseJSON(`"foo"`) == "foo");
    assert(cast(string) parseJSON("\r\n  \t\"foo\" \t \n") == "foo");
    assert(cast(string) parseJSON(`"\r\n\"\t\f\b\/"`) == "\r\n\"\t\f\b/");
    assert(cast(string) parseJSON(`"\u0347"`) == "\u0347");
    assert(cast(string) parseJSON(`"\u7430"`) == "\u7430");
    assert(cast(string) parseJSON(`"\uabcd"`) == "\uabcd");
    assert(cast(string) parseJSON(`"\uABCD"`) == "\uABCD");
}

// Test parseJSON for various number inputs
unittest {
    assert(cast(int) parseJSON(`123`) == 123);
    assert(cast(int) parseJSON(`-340`) == -340);
    assert(approxEqual(cast(real) parseJSON(`9.53`), 9.53, 0.001));
    assert(cast(int) parseJSON(`-123E3`) == -123_000);
    assert(cast(int) parseJSON(`-123E+3`) == -123_000);
    assert(approxEqual(cast(double) parseJSON(`123E-3`), 123e-3, 0.001));
    assert(approxEqual(cast(double) parseJSON(`12345678910.12345678910`),
        12345678910.12345678910));
    assert(approxEqual(cast(double) parseJSON(`-12345678910.12345678910`),
        -12345678910.12345678910));
    assert(cast(int) parseJSON(`-0.`) == 0);
    // Make sure long is represented precisely.
    assert(cast(long) parseJSON(to!string(long.max)) == long.max);
}

// Test parseJSON for various arrays.
unittest {
    JSON arr1 = parseJSON(`  [1, 2, 3, 4, 5]` ~ "\n\t\r");

    assert(arr1.isArray);
    assert(arr1.length == 5);
    assert(cast(int) arr1[0] == 1);
    assert(cast(int) arr1[1] == 2);
    assert(cast(int) arr1[2] == 3);
    assert(cast(int) arr1[3] == 4);
    assert(cast(int) arr1[4] == 5);

    JSON arr2 = parseJSON("  [\"bla bla\",\n true, \r\n null, false]\n\t\r");

    assert(arr2.isArray);
    assert(arr2.length == 4);
    assert(cast(string) arr2[0] == "bla bla");
    assert(cast(bool) arr2[1] == true);
    assert(arr2[2].isNull);
    assert(cast(bool) arr2[3] == false);
}

// Test parseJSON for various objects.
unittest {
    JSON obj1 = parseJSON(`  {"a":1, "b" :  2, "c" : 3, "d" : 4}` ~ "\n\t\r");

    assert(obj1.isObject);
    assert(obj1.length == 4);
    assert(cast(int) obj1["a"] == 1);
    assert(cast(int) obj1["b"] == 2);
    assert(cast(int) obj1["c"] == 3);
    assert(cast(int) obj1["d"] == 4);

    JSON obj2 = parseJSON(`{
        "foo" : "bla de bla",
        "john" : "something else",
        "bar" : null,
        "jane" : 4.7
    }`);

    assert(obj2.isObject);
    assert(obj2.length == 4);
    assert(cast(string) obj2["foo"] == "bla de bla");
    assert(cast(string) obj2["john"] == "something else");
    assert(obj2["bar"].isNull);
    assert(approxEqual(cast(real) obj2["jane"], 4.7, 0.001));
}

// Test parseJSON on empty arrays and objects
unittest {
    assert(parseJSON(`[]`).length == 0);
    assert(parseJSON(`{}`).length == 0);
    assert(parseJSON(" [\t \n] ").length == 0);
    assert(parseJSON(" {\r\n } ").length == 0);
}

//test trailing comma in objects
version (dson_relaxed) unittest {
    assert(parseJSON(`{ "a": 1 , }`) == parseJSON(`{"a":1}`));
}

// Test complicated parseJSON examples
unittest {
    JSON obj = parseJSON(`{
        "array" : [1, 2, 3, 4, 5],
        "matrix" : [
            [ 1,  2,  3,  4,  5],
            [ 6,  7,  8,  9, 10],
            [11, 12, 13, 14, 15]
        ],
        "obj" : {
            "this" : 1,
            "is": 2,
            "enough": true
        }
    }`);

    assert(obj.isObject);
    assert(obj.length == 3);
    assert("array" in obj);

    JSON array = obj["array"];

    assert(array.isArray);
    assert(array.length == 5);
    assert(cast(int) array[0] == 1);
    assert(cast(int) array[1] == 2);
    assert(cast(int) array[2] == 3);
    assert(cast(int) array[3] == 4);
    assert(cast(int) array[4] == 5);

    assert("matrix" in obj);

    JSON matrix = obj["matrix"];

    assert(matrix.isArray);
    assert(matrix.length == 3);

    assert(matrix[0].isArray);
    assert(matrix[0].length == 5);
    assert(cast(int) matrix[0][0] == 1);
    assert(cast(int) matrix[0][1] == 2);
    assert(cast(int) matrix[0][2] == 3);
    assert(cast(int) matrix[0][3] == 4);
    assert(cast(int) matrix[0][4] == 5);
    assert(matrix[1].isArray);
    assert(matrix[1].length == 5);
    assert(cast(int) matrix[1][0] == 6);
    assert(cast(int) matrix[1][1] == 7);
    assert(cast(int) matrix[1][2] == 8);
    assert(cast(int) matrix[1][3] == 9);
    assert(cast(int) matrix[1][4] == 10);
    assert(matrix[2].isArray);
    assert(matrix[2].length == 5);
    assert(cast(int) matrix[2][0] == 11);
    assert(cast(int) matrix[2][1] == 12);
    assert(cast(int) matrix[2][2] == 13);
    assert(cast(int) matrix[2][3] == 14);
    assert(cast(int) matrix[2][4] == 15);

    assert("obj" in obj);

    JSON subObj = obj["obj"];

    assert(subObj.isObject);
    assert(subObj.length == 3);

    assert(cast(int) subObj["this"] == 1);
    assert(cast(int) subObj["is"] == 2);
    assert(cast(bool) subObj["enough"] == true);
}

// TODO: immutable JSON?
// TODO: This caused a RangeViolation: obj["a"] ~= 347;

// Test immutable
unittest {
    immutable JSON j1 = true;
    assert(j1 == true);

    immutable JSON j2 = 3;
    assert(j2 == 3);

    immutable JSON j3 = -33;
    assert(j3 == -33);

    immutable JSON j4 = 4.5;
    assert(j4 == 4.5);

    // FIXME: This fails.
    //immutable JSON j5 = "some text";
    //assert(j5 == "some text");
}

// Test for correct float parsing.
unittest {
    import std.typecons : tuple;
    auto jsonComponents = tuple(`"a":1.001`, `"b":1.02345`, `"c":1.05678`);
    auto jsonString = `{` ~ jsonComponents[0]
                    ~ `,` ~ jsonComponents[1]
                    ~ `,` ~ jsonComponents[2] ~ `}`;

    auto object = parseJSON(jsonString);

    assert(object["a"] == 1.001L);
    assert(objectStringTest(toJSON(object), jsonComponents.expand));
}

// Test for correct character encoding
unittest {
    auto obj = jsonObject();

    obj["x"] = "é".toUpper();

    assert(obj["x"] == "É");

    auto str = obj.toJSON();

    assert(str == `{"x":"É"}`);
}
