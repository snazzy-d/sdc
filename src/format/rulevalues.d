module format.rulevalues;

struct RuleValues {
private:
	import core.bitop;
	enum Bits = 8 * size_t.sizeof;
	enum Mask = Bits - 1;
	enum DirectBits = 2 * Bits;
	enum DirectCapacity = DirectBits - bsf(DirectBits);
	enum DirectShift = DirectCapacity - Bits;

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
	this(size_t frozen, size_t capacity) in(frozen > 0 && capacity >= frozen) {
		if (capacity > DirectCapacity) {
			size_t length = 1 + (capacity + Bits - 1) / Bits;

			indirect = new size_t[length];
			indirect[0] = frozen;
			indirect[1] = 0x01;
		} else {
			direct[0] = 0x01;
			direct[1] = frozen << DirectShift;
		}
	}

	RuleValues clone() const {
		RuleValues ret = void;
		if (isDirect()) {
			ret.direct = direct;
		} else {
			ret.indirect = indirect.dup;
		}

		return ret;
	}

	RuleValues withFrozenSplit(size_t i) const in(i >= frozen && i < capacity) {
		RuleValues ret = clone();

		ret[i] = true;
		ret.frozen = i + 1;
		return ret;
	}

	@property
	size_t capacity() const {
		return isDirect() ? DirectCapacity : (indirect.length - 1) * Bits;
	}

	@property
	size_t frozen() const {
		return isDirect() ? (direct[1] >> DirectShift) : indirect[0];
	}

	@property
	size_t frozen(size_t f) in {
		assert(f > 0 && f <= capacity);
		assert(this[f - 1]);
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

	void opIndexAssign(bool v, size_t i) in(i >= frozen && i < capacity) {
		auto w = word(i);
		auto m = size_t(1) << shift(i);

		if (v) {
			values[w] |= m;
		} else {
			values[w] &= ~m;
		}
	}

	bool opEqual(const ref RuleValues rhs) const {
		const d = isDirect();
		if (rhs.isDirect() != d) {
			return false;
		}

		return d ? direct == rhs.direct : indirect == rhs.indirect;
	}

	int opCmp(const ref RuleValues rhs) const {
		// We don't really use this, but let's be throurough.
		if (capacity != rhs.capacity) {
			return cast(int) (capacity - rhs.capacity);
		}

		// Explore candidate with a few follow up first.
		if (frozen != rhs.frozen) {
			return cast(int) (rhs.frozen - frozen);
		}

		foreach_reverse (i; 0 .. capacity) {
			if (this[i] != rhs[i]) {
				return rhs[i] - this[i];
			}
		}

		return 0;
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

	static word(size_t i) {
		return i / Bits;
	}

	static shift(size_t i) {
		return i & Mask;
	}
}

unittest {
	foreach (i; 0 .. RuleValues.DirectCapacity) {
		const c = i + 1;
		const rv = RuleValues(1, c);
		assert(rv.isDirect());
		assert(rv.capacity == RuleValues.DirectCapacity);
	}

	foreach (i; RuleValues.DirectCapacity .. 16 * size_t.sizeof) {
		const c = i + 1;
		const rv = RuleValues(1, c);
		assert(!rv.isDirect());
		assert(rv.capacity == 16 * size_t.sizeof);
	}

	foreach (i; 16 * size_t.sizeof .. 24 * size_t.sizeof) {
		const c = i + 1;
		const rv = RuleValues(1, c);
		assert(!rv.isDirect());
		assert(rv.capacity == 24 * size_t.sizeof);
	}
}

unittest {
	auto r0 = RuleValues(1, 10);
	auto r1 = r0.clone();
	assert(r0 == r1);
	assert(!(r0 < r1));
	assert(!(r1 > r0));

	r0[5] = true;
	assert(r0 != r1);
	assert(r0 < r1);
	assert(r1 > r0);

	r1[5] = true;
	assert(r0 == r1);
	assert(!(r0 < r1));
	assert(!(r1 > r0));

	r1.frozen = 6;
	assert(r0 != r1);
	assert(r0 > r1);
	assert(r1 < r0);

	r0.frozen = 6;
	assert(r0 == r1);
	assert(!(r0 < r1));
	assert(!(r1 > r0));

	auto r2 = RuleValues(1, 1000);
	assert(r0 != r2);
	assert(r0 < r2);
	assert(r1 != r2);
	assert(r1 < r2);
}

unittest {
	auto rv = RuleValues(1, 10);

	assert(rv[0]);
	foreach (i; 1 .. 10) {
		assert(!rv[i]);
	}

	rv[9] = true;

	assert(rv[0]);
	assert(rv[9]);
	foreach (i; 1 .. 9) {
		assert(!rv[i]);
	}

	rv[7] = true;

	assert(rv[0]);
	assert(rv[7]);
	assert(!rv[8]);
	assert(rv[9]);
	foreach (i; 1 .. 7) {
		assert(!rv[i]);
	}

	rv[9] = false;

	assert(rv[0]);
	assert(rv[7]);
	assert(!rv[8]);
	assert(!rv[9]);
	foreach (i; 1 .. 7) {
		assert(!rv[i]);
	}

	rv[7] = false;

	assert(rv[0]);
	foreach (i; 1 .. 10) {
		assert(!rv[i]);
	}
}
