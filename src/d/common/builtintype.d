module d.common.builtintype;

// Byte, Ubyte instead of Ubyte, Byte
enum BuiltinType : ubyte {
	None,
	Void,
	Bool,
	Char,
	Wchar,
	Dchar,
	Byte,
	Ubyte,
	Short,
	Ushort,
	Int,
	Uint,
	Long,
	Ulong,
	Cent,
	Ucent,
	Float,
	Double,
	Real,
	Null,
}

string toString(BuiltinType t) {
	final switch (t) with (BuiltinType) {
		case None:
			return "__none__";

		case Void:
			return "void";

		case Bool:
			return "bool";

		case Char:
			return "char";

		case Wchar:
			return "wchar";

		case Dchar:
			return "dchar";

		case Byte:
			return "byte";

		case Ubyte:
			return "ubyte";

		case Short:
			return "short";

		case Ushort:
			return "ushort";

		case Int:
			return "int";

		case Uint:
			return "uint";

		case Long:
			return "long";

		case Ulong:
			return "ulong";

		case Cent:
			return "cent";

		case Ucent:
			return "ucent";

		case Float:
			return "float";

		case Double:
			return "double";

		case Real:
			return "real";

		case Null:
			return "typeof(null)";
	}
}

bool isChar(BuiltinType t) {
	return (t >= BuiltinType.Char) && (t <= BuiltinType.Dchar);
}

BuiltinType integralOfChar(BuiltinType t)
		in(isChar(t), "integralOfChar only applys to character types") {
	return cast(BuiltinType) ((t * 2) | 0x01);
}

unittest {
	assert(integralOfChar(BuiltinType.Char) == BuiltinType.Ubyte);
	assert(integralOfChar(BuiltinType.Wchar) == BuiltinType.Ushort);
	assert(integralOfChar(BuiltinType.Dchar) == BuiltinType.Uint);
}

bool isIntegral(BuiltinType t) {
	return (t >= BuiltinType.Byte) && (t <= BuiltinType.Ucent);
}

bool canConvertToIntegral(BuiltinType t) {
	return (t >= BuiltinType.Bool) && (t <= BuiltinType.Ucent);
}

bool isSigned(BuiltinType t)
		in(isIntegral(t), "isSigned only applys to integral types") {
	return (t & 0x01) == 0;
}

unittest {
	assert(isSigned(BuiltinType.Byte));
	assert(isSigned(BuiltinType.Short));
	assert(isSigned(BuiltinType.Int));
	assert(isSigned(BuiltinType.Long));
	assert(isSigned(BuiltinType.Cent));

	assert(!isSigned(BuiltinType.Ubyte));
	assert(!isSigned(BuiltinType.Ushort));
	assert(!isSigned(BuiltinType.Uint));
	assert(!isSigned(BuiltinType.Ulong));
	assert(!isSigned(BuiltinType.Ucent));
}

BuiltinType unsigned(BuiltinType t)
		in(isIntegral(t), "unsigned only applys to integral types") {
	return cast(BuiltinType) (t | 0x01);
}

unittest {
	assert(unsigned(BuiltinType.Byte) == BuiltinType.Ubyte);
	assert(unsigned(BuiltinType.Ubyte) == BuiltinType.Ubyte);

	assert(unsigned(BuiltinType.Short) == BuiltinType.Ushort);
	assert(unsigned(BuiltinType.Ushort) == BuiltinType.Ushort);

	assert(unsigned(BuiltinType.Int) == BuiltinType.Uint);
	assert(unsigned(BuiltinType.Uint) == BuiltinType.Uint);

	assert(unsigned(BuiltinType.Long) == BuiltinType.Ulong);
	assert(unsigned(BuiltinType.Ulong) == BuiltinType.Ulong);

	assert(unsigned(BuiltinType.Cent) == BuiltinType.Ucent);
	assert(unsigned(BuiltinType.Ucent) == BuiltinType.Ucent);
}

BuiltinType signed(BuiltinType t)
		in(isIntegral(t), "signed only applys to integral types") {
	return cast(BuiltinType) (t & ~0x01);
}

unittest {
	assert(signed(BuiltinType.Byte) == BuiltinType.Byte);
	assert(signed(BuiltinType.Ubyte) == BuiltinType.Byte);

	assert(signed(BuiltinType.Short) == BuiltinType.Short);
	assert(signed(BuiltinType.Ushort) == BuiltinType.Short);

	assert(signed(BuiltinType.Int) == BuiltinType.Int);
	assert(signed(BuiltinType.Uint) == BuiltinType.Int);

	assert(signed(BuiltinType.Long) == BuiltinType.Long);
	assert(signed(BuiltinType.Ulong) == BuiltinType.Long);

	assert(signed(BuiltinType.Cent) == BuiltinType.Cent);
	assert(signed(BuiltinType.Ucent) == BuiltinType.Cent);
}

bool isFloat(BuiltinType t) {
	return (t >= BuiltinType.Float) && (t <= BuiltinType.Real);
}

uint getIntegralSize(BuiltinType t)
		in(isIntegral(t), "getIntegralSize only apply to integral types") {
	return 1 << ((t / 2) - 3);
}

uint getSize(BuiltinType t) {
	final switch (t) with (BuiltinType) {
		case Bool, Void:
			return 1;

		case Char, Wchar, Dchar:
			return 1 << (t - Char);

		case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent, Ucent:
			return getIntegralSize(t);

		case Float, Double:
			return 1 << (t - Float + 2);

		case None, Real, Null:
			import std.conv;
			assert(0, "Use SizeofVisitor for " ~ t.to!string());
	}
}

unittest {
	assert(getSize(BuiltinType.Bool) == 1);
	assert(getSize(BuiltinType.Byte) == 1);
	assert(getSize(BuiltinType.Ubyte) == 1);
	assert(getSize(BuiltinType.Char) == 1);

	assert(getSize(BuiltinType.Short) == 2);
	assert(getSize(BuiltinType.Ushort) == 2);
	assert(getSize(BuiltinType.Wchar) == 2);

	assert(getSize(BuiltinType.Int) == 4);
	assert(getSize(BuiltinType.Uint) == 4);
	assert(getSize(BuiltinType.Dchar) == 4);
	assert(getSize(BuiltinType.Float) == 4);

	assert(getSize(BuiltinType.Long) == 8);
	assert(getSize(BuiltinType.Ulong) == 8);
	assert(getSize(BuiltinType.Double) == 8);

	assert(getSize(BuiltinType.Cent) == 16);
	assert(getSize(BuiltinType.Ucent) == 16);
}

uint getBits(BuiltinType t) {
	if (t == BuiltinType.Bool) {
		return 1;
	}

	return getSize(t) * 8;
}

unittest {
	assert(getBits(BuiltinType.Bool) == 1);

	assert(getBits(BuiltinType.Byte) == 8);
	assert(getBits(BuiltinType.Ubyte) == 8);
	assert(getBits(BuiltinType.Char) == 8);

	assert(getBits(BuiltinType.Short) == 16);
	assert(getBits(BuiltinType.Ushort) == 16);
	assert(getBits(BuiltinType.Wchar) == 16);

	assert(getBits(BuiltinType.Int) == 32);
	assert(getBits(BuiltinType.Uint) == 32);
	assert(getBits(BuiltinType.Dchar) == 32);
	assert(getBits(BuiltinType.Float) == 32);

	assert(getBits(BuiltinType.Long) == 64);
	assert(getBits(BuiltinType.Ulong) == 64);
	assert(getBits(BuiltinType.Double) == 64);

	assert(getBits(BuiltinType.Cent) == 128);
	assert(getBits(BuiltinType.Ucent) == 128);
}

ulong getMax(BuiltinType t)
		in(isIntegral(t), "getMax only applys to integral types") {
	auto base = 1UL << (8 - isSigned(t));
	return (base << (getIntegralSize(t) - 1) * 8) - 1;
}

unittest {
	assert(getMax(BuiltinType.Byte) == 127);
	assert(getMax(BuiltinType.Ubyte) == 255);

	assert(getMax(BuiltinType.Short) == 32767);
	assert(getMax(BuiltinType.Ushort) == 65535);

	assert(getMax(BuiltinType.Int) == 2147483647);
	assert(getMax(BuiltinType.Uint) == 4294967295);

	assert(getMax(BuiltinType.Long) == 9223372036854775807);
	assert(getMax(BuiltinType.Ulong) == 18446744073709551615UL);
}

ulong getMin(BuiltinType t)
		in(isIntegral(t), "getMin only applys to integral types") {
	return isSigned(t) ? -(1UL << getIntegralSize(t) * 8 - 1) : 0;
}

unittest {
	assert(getMin(BuiltinType.Ubyte) == 0);
	assert(getMin(BuiltinType.Ushort) == 0);
	assert(getMin(BuiltinType.Uint) == 0);
	assert(getMin(BuiltinType.Ulong) == 0);
	assert(getMin(BuiltinType.Ucent) == 0);

	assert(getMin(BuiltinType.Byte) == -128);
	assert(getMin(BuiltinType.Short) == -32768);
	assert(getMin(BuiltinType.Int) == -2147483648);
	assert(getMin(BuiltinType.Long) == -9223372036854775808UL);
}

uint getCharInit(BuiltinType t)
		in(isChar(t), "getCharInit only applys to character types") {
	switch (t) with (BuiltinType) {
		case Char:
			return 0xff;

		case Wchar, Dchar:
			return 0xffff;

		default:
			assert(0, "getCharInit only applies to character types");
	}
}

unittest {
	assert(getCharInit(BuiltinType.Char) == 0xff);
	assert(getCharInit(BuiltinType.Wchar) == 0xffff);
	assert(getCharInit(BuiltinType.Dchar) == 0xffff);
}

uint getCharMax(BuiltinType t)
		in(isChar(t), "getCharMax only applys to character types") {
	switch (t) with (BuiltinType) {
		case Char:
			return 0xff;

		case Wchar:
			return 0xffff;

		case Dchar:
			return 0x10ffff;

		default:
			assert(0, "getCharMax only applys to character types");
	}
}

unittest {
	assert(getCharMax(BuiltinType.Char) == 0xff);
	assert(getCharMax(BuiltinType.Wchar) == 0xffff);
	assert(getCharMax(BuiltinType.Dchar) == 0x10ffff);
}
