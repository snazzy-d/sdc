module config.traits;

import config.heap;
import config.map;
import config.value;

import std.traits;

enum isValue(T) = is(T : const(Value)) || isPrimitiveValue!T || isHeapValue!T;

enum isPrimitiveValue(T) =
	is(T : typeof(null)) || is(T : bool) || isIntegral!T || isFloatingPoint!T;

enum isHeapValue(T) =
	isStringValue!T || isArrayValue!T || isObjectValue!T || isMapValue!T;

enum isStringValue(T) = is(T : string) && !is(T : typeof(null));

enum isArrayValue(X) = false;
enum isArrayValue(A : E[], E) = isValue!E;

enum isKeyLike(T) = isPrimitiveValue!T || isStringValue!T
	|| (is(T : E[], E) && isKeyLike!E) || isBoxedValue!T;

enum isMapLike(X) = false;
enum isMapLike(M : V[K], K, V) = isValue!K && isValue!V;

enum isObjectValue(X) = false;
enum isObjectValue(O : V[K], K, V) = isStringValue!K && isValue!V;

enum isMapValue(X) = false;
enum isMapValue(M : V[K], K, V) = isMapLike!M && !isObjectValue!M;

enum isBoxedValue(T) = is(T : const(Value)) || isBoxedHeapValue!T;
enum isBoxedHeapValue(T) = is(T : const(HeapValue)) || is(T : const(VString))
	|| is(T : const(VArray)) || is(T : const(VObject)) || is(T : const(VMap));

unittest {
	assert(isValue!Value);
	assert(!isPrimitiveValue!Value);
	assert(!isHeapValue!Value);
	assert(!isStringValue!Value);
	assert(!isArrayValue!Value);
	assert(isKeyLike!Value);
	assert(!isMapLike!Value);
	assert(!isObjectValue!Value);
	assert(!isMapValue!Value);
	assert(isBoxedValue!Value);
	assert(!isBoxedHeapValue!Value);

	assert(isValue!string);
	assert(!isPrimitiveValue!string);
	assert(isHeapValue!string);
	assert(isStringValue!string);
	assert(!isArrayValue!string);
	assert(isKeyLike!string);
	assert(!isMapLike!string);
	assert(!isObjectValue!string);
	assert(!isMapValue!string);
	assert(!isBoxedValue!string);
	assert(!isBoxedHeapValue!string);

	import std.meta;
	alias PrimitiveTypes =
		AliasSeq!(typeof(null), bool, byte, ubyte, short, ushort, long, ulong);

	foreach (T; PrimitiveTypes) {
		assert(isValue!T);
		assert(isPrimitiveValue!T);
		assert(!isHeapValue!T);
		assert(!isStringValue!T);
		assert(!isArrayValue!T);
		assert(isKeyLike!T);
		assert(!isMapLike!T);
		assert(!isObjectValue!T);
		assert(!isMapValue!T);
		assert(!isBoxedValue!T);
		assert(!isBoxedHeapValue!T);

		alias A = T[];
		assert(isValue!A);
		assert(!isPrimitiveValue!A);
		assert(isHeapValue!A);
		assert(!isStringValue!A);
		assert(isArrayValue!A);
		assert(isKeyLike!A);
		assert(!isMapLike!A);
		assert(!isObjectValue!A);
		assert(!isMapValue!A);
		assert(!isBoxedValue!A);
		assert(!isBoxedHeapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(isHeapValue!O);
		assert(!isStringValue!O);
		assert(!isArrayValue!O);
		assert(!isKeyLike!O);
		assert(isMapLike!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);
		assert(!isBoxedValue!O);
		assert(!isBoxedHeapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(isHeapValue!M);
		assert(!isStringValue!M);
		assert(!isArrayValue!M);
		assert(!isKeyLike!M);
		assert(isMapLike!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);
		assert(!isBoxedValue!M);
		assert(!isBoxedHeapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(isHeapValue!MM);
		assert(!isStringValue!MM);
		assert(!isArrayValue!MM);
		assert(!isKeyLike!MM);
		assert(isMapLike!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);
		assert(!isBoxedValue!MM);
		assert(!isBoxedHeapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isHeapValue!AA);
		assert(!isStringValue!AA);
		assert(isArrayValue!AA);
		assert(isKeyLike!AA);
		assert(!isMapLike!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);
		assert(!isBoxedValue!AA);
		assert(!isBoxedHeapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(isHeapValue!AO);
		assert(!isStringValue!AO);
		assert(!isArrayValue!AO);
		assert(!isKeyLike!AO);
		assert(isMapLike!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);
		assert(!isBoxedValue!AO);
		assert(!isBoxedHeapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isHeapValue!OA);
		assert(!isStringValue!OA);
		assert(isArrayValue!OA);
		assert(!isKeyLike!OA);
		assert(!isMapLike!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);
		assert(!isBoxedValue!OA);
		assert(!isBoxedHeapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(isHeapValue!OO);
		assert(!isStringValue!OO);
		assert(!isArrayValue!OO);
		assert(!isKeyLike!OO);
		assert(isMapLike!OO);
		assert(isObjectValue!OO);
		assert(!isMapValue!OO);
		assert(!isBoxedValue!OO);
		assert(!isBoxedHeapValue!OO);
	}

	alias ComplexTypes = AliasSeq!(HeapValue, VString, VArray, VObject, VMap);
	foreach (T; ComplexTypes) {
		assert(!isValue!T);
		assert(!isPrimitiveValue!T);
		assert(!isHeapValue!T);
		assert(!isStringValue!T);
		assert(!isArrayValue!T);
		assert(isKeyLike!T);
		assert(!isMapLike!T);
		assert(!isObjectValue!T);
		assert(!isMapValue!T);
		assert(isBoxedValue!T);
		assert(isBoxedHeapValue!T);
	}
}
