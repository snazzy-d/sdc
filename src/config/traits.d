module config.traits;

import config.value;

import std.traits;

enum isPrimitiveValue(T) = is(T : typeof(null)) || is(T : bool)
	|| is(T : string) || isIntegral!T || isFloatingPoint!T;

enum isValue(T) = is(T : const(Value)) || isPrimitiveValue!T || isArrayValue!T
	|| isObjectValue!T || isMapValue!T;

enum isArrayValue(X) = false;
enum isArrayValue(A : E[], E) = isValue!E;

enum isObjectValue(X) = false;
enum isObjectValue(A : E[string], E) = isValue!E;

enum isMapValue(X) = false;
enum isMapValue(A : V[K], K, V) = !isObjectValue!A && isValue!K && isValue!V;

unittest {
	import std.meta;
	alias PrimitiveTypes = AliasSeq!(typeof(null), bool, byte, ubyte, short,
	                                 ushort, long, ulong, string);

	foreach (T; PrimitiveTypes) {
		assert(isValue!T);
		assert(isPrimitiveValue!T);
		assert(!isArrayValue!T);
		assert(!isObjectValue!T);
		assert(!isMapValue!T);

		alias A = T[];
		assert(isValue!A);
		assert(!isPrimitiveValue!A);
		assert(isArrayValue!A);
		assert(!isObjectValue!A);
		assert(!isMapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(!isArrayValue!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(!isArrayValue!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(!isArrayValue!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isArrayValue!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(!isArrayValue!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isArrayValue!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(!isArrayValue!OO);
		assert(isObjectValue!OO);
		assert(!isMapValue!OO);
	}
}
