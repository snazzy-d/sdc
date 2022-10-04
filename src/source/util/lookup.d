/**
 * This implement a search algorihm with heuristic.
 * The algorithm first does a linear scan near the
 * provided location. If nothing is found, then
 * it switches to a binary search.
 */
module source.util.lookup;

uint lookup(alias f, uint N, T)(T[] items, uint needle, uint pivot) in {
	assert(items.length > 0, "items must not be empty");
	assert(pivot < items.length);
} do {
	return (needle > f(items[pivot]))
		? forwardLinearLookup!(f, N, binaryLookup)(items, needle, pivot)
		: backwardLinearLookup!(f, N, binaryLookup)(items, needle, pivot);
}

unittest {
	alias bl5 = lookup!(i => i, 5, uint);

	uint[] items = [1, 3, 5, 7, 11, 13, 17, 23];

	assert(bl5(items, 5, 6) == 2);
	assert(bl5(items, 16, 6) == 5);
	assert(bl5(items, 4, 3) == 1);
	assert(bl5(items, 2, 3) == 0);
	assert(bl5(items, 1, 6) == 0);
	assert(bl5(items, 1, 1) == 0);
	assert(bl5(items, 5, 7) == 2);
	assert(bl5(items, 3, 7) == 1);
	assert(bl5(items, 22, 4) == 6);
	assert(bl5(items, 23, 6) == 7);
	assert(bl5(items, 42, 0) == 7);
}

private:

uint forwardLinearLookup(alias f, uint N, alias fallback,
                         T)(T[] items, uint needle, uint first) in {
	assert(items.length > 0, "items must not be empty");
	assert(first < items.length - 1, "first is out of bound");
	assert(needle >= f(items[first + 1]), "needle is before first");
} do {
	auto l = cast(uint) items.length;

	uint stop = first + N + 2;
	if (stop > l) {
		stop = l;
	}

	auto i = first + 2;
	if (i < l) {
		do {
			if (f(items[i]) > needle) {
				return i - 1;
			}
		} while (++i != stop);
	}

	return fallback!f(items, needle, stop - 1, l);
}

unittest {
	static uint testFallback(alias f, T)(T[], uint, uint, uint) {
		return -1;
	}

	alias fll5 = forwardLinearLookup!(i => i, 5, testFallback, uint);
	alias fll8 = forwardLinearLookup!(i => i, 8, testFallback, uint);

	uint[] items = [1, 3, 5, 7, 11, 13, 17, 23];

	assert(fll5(items, 5, 0) == 2);
	assert(fll5(items, 16, 0) == 5);
	assert(fll5(items, 17, 0) == -1);
	assert(fll5(items, 17, 1) == 6);
	assert(fll8(items, 17, 0) == 6);
	assert(fll8(items, 22, 0) == 6);
	assert(fll5(items, 6, 1) == 2);
	assert(fll5(items, 5, 1) == 2);
}

uint backwardLinearLookup(alias f, uint N, alias fallback,
                          T)(T[] items, uint needle, uint last) in {
	assert(items.length > 0, "items must not be empty");
	assert(last > 0 && last < items.length, "last is out of bound");
	assert(needle >= f(items[0]), "needle is before first");
	assert(needle < f(items[last]), "needle is past last");
} do {
	auto stop = (last < N) ? 0 : last - N;

	auto i = last - 1;
	do {
		if (f(items[i]) <= needle) {
			return i;
		}
	} while (i-- != stop);

	return fallback!f(items, needle, 0, stop);
}

unittest {
	static uint testFallback(alias f, T)(T[], uint, uint, uint) {
		return -1;
	}

	alias bll5 = backwardLinearLookup!(i => i, 5, testFallback, uint);
	alias bll8 = backwardLinearLookup!(i => i, 8, testFallback, uint);

	uint[] items = [1, 3, 5, 7, 11, 13, 17, 23];

	assert(bll5(items, 5, 6) == 2);
	assert(bll5(items, 16, 6) == 5);
	assert(bll5(items, 4, 3) == 1);
	assert(bll5(items, 2, 3) == 0);
	assert(bll5(items, 1, 5) == 0);
	assert(bll5(items, 2, 6) == -1);
	assert(bll5(items, 5, 7) == 2);
	assert(bll5(items, 4, 7) == -1);
	assert(bll8(items, 3, 7) == 1);
}

uint binaryLookup(alias f, T)(T[] items, uint needle, uint min, uint max) in {
	assert(items.length > 0, "items must not be empty");
	assert(needle >= f(items[min]), "needle is before first");
	assert(max == items.length || needle < f(items[max]),
	       "needle is past last");
} do {
	min++;
	while (min < max) {
		auto i = (min + max - 1) / 2;
		auto c = f(items[i]);
		if (c == needle) {
			return i;
		}

		if (c < needle) {
			min = i + 1;
		} else {
			max = i;
		}
	}

	return min - 1;
}

unittest {
	alias bl = binaryLookup!(i => i, uint);

	uint[] items = [1, 3, 5, 7, 11, 13, 17, 23];

	assert(bl(items, 5, 0, 6) == 2);
	assert(bl(items, 16, 0, 6) == 5);
	assert(bl(items, 4, 0, 3) == 1);
	assert(bl(items, 2, 0, 3) == 0);
	assert(bl(items, 1, 0, 6) == 0);
	assert(bl(items, 5, 0, 7) == 2);
	assert(bl(items, 3, 0, 7) == 1);
	assert(bl(items, 22, 0, 7) == 6);
	assert(bl(items, 23, 0, 8) == 7);
	assert(bl(items, 42, 0, 8) == 7);
}
