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

enum isObjectValue(X) = false;
enum isObjectValue(T : const(VObject)) = true;
enum isObjectValue(O : V[K], K, V) = isStringValue!K && isValue!V;

enum isMapValue(X) = false;
enum isMapValue(T : const(VMap)) = true;
enum isMapValue(M : V[K], K, V) = !isObjectValue!M && isValue!K && isValue!V;

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
		assert(!isObjectValue!T);
		assert(!isMapValue!T);

		alias A = T[];
		assert(isValue!A);
		assert(!isPrimitiveValue!A);
		assert(isHeapValue!A);
		assert(!isStringValue!A);
		assert(isArrayValue!A);
		assert(!isObjectValue!A);
		assert(!isMapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(isHeapValue!O);
		assert(!isStringValue!O);
		assert(!isArrayValue!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(isHeapValue!M);
		assert(!isStringValue!M);
		assert(!isArrayValue!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(isHeapValue!MM);
		assert(!isStringValue!MM);
		assert(!isArrayValue!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isHeapValue!AA);
		assert(!isStringValue!AA);
		assert(isArrayValue!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(isHeapValue!AO);
		assert(!isStringValue!AO);
		assert(!isArrayValue!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isHeapValue!OA);
		assert(!isStringValue!OA);
		assert(isArrayValue!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(isHeapValue!OO);
		assert(!isStringValue!OO);
		assert(!isArrayValue!OO);
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
		assert(!isObjectValue!A);
		assert(!isMapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(isHeapValue!O);
		assert(!isStringValue!O);
		assert(!isArrayValue!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(isHeapValue!M);
		assert(!isStringValue!M);
		assert(!isArrayValue!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(isHeapValue!MM);
		assert(!isStringValue!MM);
		assert(!isArrayValue!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isHeapValue!AA);
		assert(!isStringValue!AA);
		assert(isArrayValue!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(isHeapValue!AO);
		assert(!isStringValue!AO);
		assert(!isArrayValue!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isHeapValue!OA);
		assert(!isStringValue!OA);
		assert(isArrayValue!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(isHeapValue!OO);
		assert(!isStringValue!OO);
		assert(!isArrayValue!OO);
		assert(isObjectValue!OO);
		assert(!isMapValue!OO);
	}
}
