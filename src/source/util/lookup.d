/**
 * This implement a search algorihm with heuristic.
 * The algorithm first does a linear scan near the
 * provided location. If nothing is found, then
 * it switches to a binary search.
 */
module source.util.lookup;

uint lookup(alias f, uint N, T)(T[] items, uint needle, uint pivot)
		in(items.length > 0, "items must not be empty")
		in(pivot < items.length) {
	return (needle >= f(items[pivot]))
		? forwardLinearLookup!(f, N, binaryLookup)(items, needle, pivot)
		: backwardLinearLookup!(f, N, binaryLookup)(items, needle, pivot);
}

unittest {
	alias bl5 = lookup!(i => i, 5, uint);

	uint[16] entries =
		[1, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53];

	foreach (uint i, e; entries) {
		foreach (uint p; 0 .. entries.length) {
			if (i > 0) {
				assert(bl5(entries, e - 1, p) == i - 1);
			}

			assert(bl5(entries, e, p) == i);
			assert(bl5(entries, e + 1, p) == i);
		}
	}
}

private:

uint forwardLinearLookup(alias f, uint N, alias fallback,
                         T)(T[] items, uint needle, uint first)
		in(items.length > 0, "items must not be empty")
		in(first < items.length, "first is out of bound")
		in(needle >= f(items[first]), "needle is before first") {
	auto l = cast(uint) items.length;

	auto last = first + N;
	auto truncate = last >= l;
	if (truncate) {
		last = l - 1;
	}

	foreach (i; first .. last) {
		auto e = f(items[i + 1]);
		if (e >= needle) {
			return i + (e == needle);
		}
	}

	// We are past the end, so we know the last item is a match.
	if (truncate) {
		return last;
	}

	return fallback!f(items, needle, last, l);
}

unittest {
	static uint testFallback(alias f, T)(T[], uint, uint, uint) {
		return -1;
	}

	alias fll5 = forwardLinearLookup!(i => i, 5, testFallback, uint);
	alias fll8 = forwardLinearLookup!(i => i, 8, testFallback, uint);

	uint[16] entries =
		[1, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53];

	foreach (uint i, e; entries) {
		foreach (uint p; 0 .. i) {
			auto delta = i - p;

			if (i > 0) {
				auto e5 = delta <= 5 ? i : 0;
				assert(fll5(entries, e - 1, p) == e5 - 1);
			}

			auto e5 = delta <= 5 ? i : -1;
			assert(fll5(entries, e, p) == e5);

			auto e5n = delta < 5 ? i : -1;
			assert(fll5(entries, e + 1, p) == e5n);

			if (i > 0) {
				auto e8 = delta <= 8 ? i : 0;
				assert(fll8(entries, e - 1, p) == e8 - 1);
			}

			auto e8 = delta <= 8 ? i : -1;
			assert(fll8(entries, e, p) == e8);

			auto e8n = delta < 8 ? i : -1;
			assert(fll8(entries, e + 1, p) == e8n);
		}
	}
}

uint backwardLinearLookup(alias f, uint N, alias fallback,
                          T)(T[] items, uint needle, uint last)
		in(items.length > 0, "items must not be empty")
		in(last > 0 && last < items.length, "last is out of bound")
		in(needle >= f(items[0]), "needle is before first")
		in(needle < f(items[last]), "needle is past last") {
	auto first = (last < N) ? 0 : last - N;

	foreach_reverse (i; first .. last) {
		if (f(items[i]) <= needle) {
			return i;
		}
	}

	return fallback!f(items, needle, 0, first);
}

unittest {
	static uint testFallback(alias f, T)(T[], uint, uint, uint) {
		return -1;
	}

	alias bll5 = backwardLinearLookup!(i => i, 5, testFallback, uint);
	alias bll8 = backwardLinearLookup!(i => i, 8, testFallback, uint);

	uint[16] entries =
		[1, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53];

	foreach (uint i, e; entries) {
		foreach (uint p; i + 1 .. entries.length) {
			auto delta = p - i;

			if (i > 0) {
				auto e5 = delta < 5 ? i : 0;
				assert(bll5(entries, e - 1, p) == e5 - 1);
			}

			auto e5 = delta <= 5 ? i : -1;
			assert(bll5(entries, e, p) == e5);
			assert(bll5(entries, e + 1, p) == e5);

			if (i > 0) {
				auto e8 = delta < 8 ? i : 0;
				assert(bll8(entries, e - 1, p) == e8 - 1);
			}

			auto e8 = delta <= 8 ? i : -1;
			assert(bll8(entries, e, p) == e8);
			assert(bll8(entries, e + 1, p) == e8);
		}
	}
}

uint binaryLookup(alias f, T)(T[] items, uint needle, uint min, uint max)
		in(items.length > 0, "items must not be empty")
		in(needle >= f(items[min]), "needle is before first")
		in(max == items.length || needle < f(items[max]),
		   "needle is past last") {
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
