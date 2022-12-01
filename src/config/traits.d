module config.traits;

import config.heap;
import config.map;
import config.value;

import std.traits;

enum isValue(T) = is(T : const(Value)) || isPrimitiveValue!T || isHeapValue!T;

enum isPrimitiveValue(T) =
	is(T : typeof(null)) || is(T : bool) || isIntegral!T || isFloatingPoint!T;

enum isHeapValue(T) = is(T : const(HeapValue)) || isStringValue!T
	|| isArrayValue!T || isObjectValue!T || isMapValue!T;

enum isStringValue(T) =
	!is(T : typeof(null)) && (is(T : string) || is(T : const(VString)));

enum isArrayValue(X) = false;
enum isArrayValue(T : const(VArray)) = true;
enum isArrayValue(A : E[], E) = isValue!E;

enum isKeyLike(T) = isPrimitiveValue!T || isStringValue!T
	|| (is(T : E[], E) && isKeyLike!E) || isBoxedValue!T;

enum isMapLike(X) = false;
enum isMapLike(T : const(VObject)) = true;
enum isMapLike(T : const(VMap)) = true;
enum isMapLike(M : V[K], K, V) = isValue!K && isValue!V;

enum isObjectValue(X) = false;
enum isObjectValue(T : const(VObject)) = true;
enum isObjectValue(O : V[K], K, V) = isStringValue!K && isValue!V;

enum isMapValue(X) = false;
enum isMapValue(T : const(VMap)) = true;
enum isMapValue(M : V[K], K, V) = isMapLike!M && !isObjectValue!M;

enum isBoxedValue(T) = is(T : const(Value)) || isBoxedHeapValue!T;
enum isBoxedHeapValue(T) = is(T : const(HeapValue)) || is(T : const(VString))
	|| is(T : const(VArray)) || is(T : const(VObject)) || is(T : const(VMap));

unittest {
	import std.meta;
	alias PrimitiveTypes =
		AliasSeq!(typeof(null), bool, byte, ubyte, short, ushort, long, ulong);

	foreach (T; PrimitiveTypes) {
		assert(isValue!T);
		assert(isPrimitiveValue!T);
		assert(!isHeapValue!T);
		assert(!isStringValue!T, T.stringof);
		assert(!isArrayValue!T);
		assert(!isMapLike!T);
		assert(!isObjectValue!T);
		assert(!isMapValue!T);

		alias A = T[];
		assert(isValue!A);
		assert(!isPrimitiveValue!A);
		assert(isHeapValue!A);
		assert(!isStringValue!A);
		assert(isArrayValue!A);
		assert(!isMapLike!A);
		assert(!isObjectValue!A);
		assert(!isMapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(isHeapValue!O);
		assert(!isStringValue!O);
		assert(!isArrayValue!O);
		assert(isMapLike!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(isHeapValue!M);
		assert(!isStringValue!M);
		assert(!isArrayValue!M);
		assert(isMapLike!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(isHeapValue!MM);
		assert(!isStringValue!MM);
		assert(!isArrayValue!MM);
		assert(isMapLike!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isHeapValue!AA);
		assert(!isStringValue!AA);
		assert(isArrayValue!AA);
		assert(!isMapLike!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(isHeapValue!AO);
		assert(!isStringValue!AO);
		assert(!isArrayValue!AO);
		assert(isMapLike!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isHeapValue!OA);
		assert(!isStringValue!OA);
		assert(isArrayValue!OA);
		assert(!isMapLike!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(isHeapValue!OO);
		assert(!isStringValue!OO);
		assert(!isArrayValue!OO);
		assert(isMapLike!OO);
		assert(isObjectValue!OO);
		assert(!isMapValue!OO);
	}

	alias ComplexTypes = AliasSeq!(Value, HeapValue, VString, VObject, VMap);
	foreach (T; ComplexTypes) {
		assert(isValue!T);
		assert(!isPrimitiveValue!T);

		alias A = T[];
		assert(isValue!A);
		assert(!isPrimitiveValue!A);
		assert(isHeapValue!A);
		assert(!isStringValue!A);
		assert(isArrayValue!A);
		assert(!isMapLike!A);
		assert(!isObjectValue!A);
		assert(!isMapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(isHeapValue!O);
		assert(!isStringValue!O);
		assert(!isArrayValue!O);
		assert(isMapLike!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(isHeapValue!M);
		assert(!isStringValue!M);
		assert(!isArrayValue!M);
		assert(isMapLike!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(isHeapValue!MM);
		assert(!isStringValue!MM);
		assert(!isArrayValue!MM);
		assert(isMapLike!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isHeapValue!AA);
		assert(!isStringValue!AA);
		assert(isArrayValue!AA);
		assert(!isMapLike!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(isHeapValue!AO);
		assert(!isStringValue!AO);
		assert(!isArrayValue!AO);
		assert(isMapLike!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isHeapValue!OA);
		assert(!isStringValue!OA);
		assert(isArrayValue!OA);
		assert(!isMapLike!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(isHeapValue!OO);
		assert(!isStringValue!OO);
		assert(!isArrayValue!OO);
		assert(isMapLike!OO);
		assert(isObjectValue!OO);
		assert(!isMapValue!OO);
	}
}
