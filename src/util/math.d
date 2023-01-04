module util.math;

import std.traits;

bool isPow2(T)(T x) if (isIntegral!T) {
	return (x & (x - 1)) == 0;
}

// I have not figured out how to do this in a sensible way.
// See: https://forum.dlang.org/post/zsaghidvbsdwqthadphx@forum.dlang.org
ulong mulhi()(ulong a, ulong b) {
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
		// (a0 << 32 + a1)(b0 << 32 + b1) = a0b0 << 64 + (a0b1 + a1b0) << 32 + a1b1
		auto a0 = a >> 32;
		auto a1 = a & uint.max;

		auto b0 = b >> 32;
		auto b1 = b & uint.max;

		auto a0b0 = a0 * b0;
		auto a0b1 = a0 * b1;
		auto a1b0 = a1 * b0;
		auto a1b1 = a1 * b1;

		auto carry = (a1b1 >> 32 + ((a0b1 + a1b0) & uint.max)) >> 32;
		return a0b0 + (a0b1 >> 32) + (a1b0 >> 32) + carry;
	}
}
