module format.rulevalues;

struct RuleValues {
private:
	import core.bitop;
	enum DirectBits = 16 * size_t.sizeof;
	enum DirectCapacity = DirectBits - bsf(DirectBits);
	enum DirectShift = DirectCapacity - 8 * size_t.sizeof;

	union {
		struct {
			size_t* uptr;
			size_t ulength;
		}

		size_t[2] direct;
	}

	bool isDirect() const {
		return direct[0] & 0x01;
	}

public:
	this(size_t frozen, size_t capacity) in {
		assert(frozen > 0 && capacity >= frozen);
	} do {
		if (capacity > DirectCapacity) {
			indirect = new size_t[capacity + 1];
			indirect[0] = frozen;
			indirect[1] = 0x01;
		} else {
			direct[0] = 0x01;
			direct[1] = frozen << DirectShift;
		}
	}

	RuleValues withFrozen(size_t f) const in {
		assert(f > frozen && f <= length);
	} do {
		RuleValues ret = void;
		if (isDirect()) {
			ret.direct = direct;
		} else {
			ret.indirect = indirect.dup;
		}

		ret.frozen = f;
		return ret;
	}

	@property
	size_t length() const {
		return isDirect() ? DirectCapacity : indirect.length - 1;
	}

	@property
	size_t frozen() const {
		return isDirect() ? direct[1] >> DirectShift : indirect[0];
	}

	@property
	size_t frozen(size_t f) in {
		assert(f >= frozen && f <= length);
	} do {
		if (isDirect()) {
			// Replace the previous frozen value.
			direct[1] &= (size_t(1) << DirectShift) - 1;
			direct[1] |= f << DirectShift;
		} else {
			*uptr = f;
		}

		return frozen;
	}

	bool opIndex(size_t i) const {
		return (values[word(i)] >> shift(i)) & 0x01;
	}

	void opIndexAssign(bool v, size_t i) in {
		assert(i < length);
	} do {
		auto w = word(i);
		auto m = size_t(1) << shift(i);

		if (v) {
			values[w] |= m;
		} else {
			values[v] &= m;
		}
	}

private:
	@property
	inout(size_t)[] values() inout {
		return isDirect() ? direct[] : indirect[1 .. $];
	}

	@property
	inout(size_t)[] indirect() inout {
		return uptr[0 .. ulength];
	}

	@property
	size_t[] indirect(size_t[] v) {
		uptr = v.ptr;
		ulength = v.length;
		return indirect;
	}

	enum Bits = 8 * size_t.sizeof;
	enum Mask = Bits - 1;

	static word(size_t i) {
		return i / Bits;
	}

	static shift(size_t i) {
		return i & Mask;
	}
}
