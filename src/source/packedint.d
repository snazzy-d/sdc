module source.packedint;

import source.context;

struct PackedInt(uint ExtraBits) {
private:
	enum PrefixBits = ExtraBits - 3;
	enum Mask = (1UL << (PrefixBits + 32)) - 1;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		bool, "_inline", 1,
		bool, "_unsigned", 1,
		bool, "_long", 1,
		uint, "_prefix", PrefixBits,
		uint, "_pad", 8 * uint.sizeof - ExtraBits,
		// sdfmt on
	));

	union {
		import source.name;
		Name name;
		uint _base;
	}

	this(Name name) {
		_inline = false;
		this.name = name;
	}

	this(ulong value) {
		_inline = true;
		_prefix = (value >> 32);
		_base = value & uint.max;
	}

public:
	static get(Context context, ulong value) {
		if ((value & Mask) == value) {
			return PackedInt(value);
		}

		union U {
			ulong value;
			immutable(char)[8] buf;
		}

		U v;
		v.value = value;
		return PackedInt(context.getName(v.buf[]));
	}

	static recompose(uint base, uint extra) {
		auto p = PackedInt(base);

		p._inline = extra & 0x01;
		p._unsigned = (extra >> 1) & 0x01;
		p._long = (extra >> 2) & 0x01;
		p._prefix = extra >> 3;

		return p;
	}

	@property
	uint base() const {
		return _base;
	}

	@property
	uint extra() const {
		return _inline | (_unsigned << 1) | (_long << 2) | (_prefix << 3);
	}

	ulong toInt(Context context) const {
		if (_inline) {
			return _base | (ulong(_prefix) << 32);
		}

		import source.swar.util;
		return unalignedLoad!ulong(name.toString(context));
	}
}

unittest {
	alias PI = PackedInt!24;

	auto c = new Context();

	foreach (i; 0 .. 54) {
		const n = (1UL << i) - 1;
		auto p = PI.get(c, n);

		assert(p._inline);
		assert(p.toInt(c) == n);
	}

	foreach (i; 54 .. 63) {
		const n = (1UL << i) - 1;
		auto p = PI.get(c, n);

		assert(!p._inline);
		assert(p.extra == 0);
		assert(p.toInt(c) == n);
	}
}
