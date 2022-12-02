module config.util;

bool isPow2(uint x) {
	return (x & (x - 1)) == 0;
}

// I have not figured out how to do this in a sensible way.
// See: https://forum.dlang.org/post/zsaghidvbsdwqthadphx@forum.dlang.org
ulong mulhi(ulong a, ulong b) nothrow {
	version(LDC) {
		import ldc.llvmasm;
		return __ir!(`
				%a = zext i64 %0 to i128
				%b = zext i64 %1 to i128
				%r = mul i128 %a, %b
				%r2 = lshr i128 %r, 64
				%r3 = trunc i128 %r2 to i64
				ret i64 %r3`, ulong)(a, b);
	} else {
		// Not mulhi at all, but will do for now.
		return (a * b) >> 28;
	}
}
