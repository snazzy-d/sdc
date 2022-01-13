module util.bitfields;

template SizeOfBitField(T...) {
	static if (T.length < 2) {
		enum SizeOfBitField = 0;
	} else {
		enum SizeOfBitField = T[2] + SizeOfBitField!(T[3 .. $]);
	}
}

enum EnumSize(E) = computeEnumSize!E();

private:

size_t computeEnumSize(E)() {
	size_t size = 0;

	import std.traits;
	foreach (m; EnumMembers!E) {
		size_t ms = 0;
		while ((m >> ms) != 0) {
			ms++;
		}

		import std.algorithm;
		size = max(size, ms);
	}

	return size;
}
