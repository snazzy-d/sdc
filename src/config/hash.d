module config.hash;

import config.traits;
import config.util;
import config.value;

hash_t hash(T)(T t) if (isKeyLike!T) {
	return rehash(Hasher().hash(t));
}

/**
 * The hash generated does not have good collision resistance over
 * all subsets of the bits of the hash value, which causes clumping.
 *
 * In order to fix this, we mix the bits around to ensure good entropy
 * over the ranges we are interested in.
 *
 * NB: On architecture that provide hardware support
 * for CRC32 (ARMv8.1+, x86), we might want to use that.
 */
hash_t rehash(hash_t h) {
	enum K = 0xc4ceb9fe1a85ec53;
	auto hi = mulhi(h, K);
	auto lo = h * K;
	return (hi ^ lo) * K;
}

enum isHashable(T) = is(typeof(const(T).init.toHash()) : hash_t);

struct Hasher {
	ulong state = 0;

	hash_t mix(ulong k) {
		auto hi = mulhi(state, k);
		auto lo = state * k;
		state = hi ^ lo;
		return state;
	}

	hash_t hash(T)(T t) if (isPrimitiveValue!T) {
		return hash(Value(t));
	}

	hash_t hash(H)(H h) if (isHashable!H) {
		state += h.toHash();
		return state;
	}

	hash_t hash(string s) {
		// Ensure we have a non zero hash for empty strings.
		state += (s.length - 8);

		while (s.length >= 8) {
			mix(0x87c37b91114253d5);

			import source.swar.util;
			state += read!ulong(s);

			s = s[8 .. $];
		}

		ulong last = 0;
		if (s.length >= 4) {
			import source.swar.util;
			last = read!uint(s[$ - 4 .. $]);
			s = s[$ - 4 .. $];
			last <<= (8 * s.length);
		}

		switch (s.length) {
			case 3:
				last |= s[2] << (2 * 8);
				goto case;
			case 2:
				last |= s[1] << (1 * 8);
				goto case;
			case 1:
				last |= s[0];
				goto default;

			default:
				mix(0x1b87359352dce729);
				state += last;
				return state;
		}
	}

	hash_t hash(A : E[], E)(A a) if (isKeyLike!E) {
		// Make sure we mix things a bit so that an empty
		// array has a diffrent hash than an empty string.
		state += (a.length ^ 0x1b87359352dce729);
		state ^= (state >> 33);

		foreach (ref e; a) {
			mix(0xe6546b64cc9e2d51);
			state += Hasher().hash(e);
		}

		return state;
	}
}

unittest {
	int[] empty;
	assert(hash("") != 0);
	assert(hash(empty) != 0);
	assert(hash("") != hash(empty));

	import config.heap;
	static void testString(string s) {
		auto vs = VString(s);
		assert(hash(s) == hash(vs));
		assert(hash(s) == rehash(vs.toHash()));

		auto v = Value(s);
		assert(hash(s) == hash(v));
		assert(hash(s) == rehash(v.toHash()));
	}

	testString("");
	testString("foo");
	testString("bar");
	testString("foobar");
	testString("Banana! Banana! Banana! Banana!");

	static void testArray(E)(E[] a) {
		auto va = VArray(a);
		assert(hash(a) == hash(va));
		assert(hash(a) == rehash(va.toHash()));

		auto v = Value(a);
		assert(hash(a) == hash(v));
		assert(hash(a) == rehash(v.toHash()));
	}

	testArray(empty);
	testArray([1, 2, 3]);
	testArray(["1", "2", "3"]);

	ulong[] arr = [1, 2, 3];
	assert(hash(arr) == hash(Value([1, 2, 3])));
}
