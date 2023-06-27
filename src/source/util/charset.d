module source.util.charset;

bool isDualByteCodePoint(char c0, char c1) {
	auto k0 = (c0 - 0xc0) & 0xe0;
	auto k1 = (c1 - 0x80) & 0xc0;

	return (k0 | k1) == 0;
}

unittest {
	foreach (char c0; [0x00, 0x42, 0xbf, 0xc0, 0xdf, 0xe0, 0xff]) {
		auto isC0Dual = (c0 >> 5) == 0x06;

		foreach (char c1; [0x00, 0x42, 0x7f, 0x80, 0xaa, 0xbf, 0xc0, 0xff]) {
			auto isC1Dual = (c1 >> 6) == 0x02;
			assert(isDualByteCodePoint(c0, c1) == (isC0Dual && isC1Dual));
		}
	}
}

bool matchDualByteCodepoint(const ref ulong[32] table, char c0, char c1)
		in(isDualByteCodePoint(c0, c1)) {
	auto k0 = c0 & 0x1f;
	auto k1 = c1 & 0x3f;

	return (table[k0] >> k1) & 0x01;
}

ulong[32] generateDualByteLookupTable(const dchar[2][] ranges) {
	ulong[32] ret;

	foreach (r; ranges) {
		if (r[0] < 0x80) {
			assert(r[1] < 0x80);
			continue;
		}

		if (r[0] >= 0x800) {
			continue;
		}

		assert(r[1] < 0x800);

		foreach (c; r[0] .. r[1]) {
			auto k0 = c >> 6;
			auto k1 = c & 0x3f;

			ret[k0] |= 1UL << k1;
		}
	}

	return ret;
}

bool matchTrieCodepoint(const ref ubyte[4096] roots, const ulong[] leaves,
                        dchar c) {
	auto k0 = (c >> 6) & 0xfff;
	auto k1 = c & 0x3f;
	auto m = ulong(c < 0x40000) << k1;

	return (leaves.ptr[roots[k0]] & m) != 0;
}

ulong[] generateTrieLeaves(const dchar[2][] ranges) {
	/**
	 * We try to pack the leaves that are most likely to
	 * be accessed toward the start of the trie.
	 * 
	 * To do so, we assume access pattern follows a
	 * power law, where element are less likely to be
	 * accessed as codepoints go higher.
	 */
	double[ulong] scores;
	ulong[] ret;

	void save(ulong k0, ulong leaf) {
		auto s = 1.0 / (k0 + 1);
		if (leaf in scores) {
			scores[leaf] += s;
		} else {
			scores[leaf] = s;
			ret ~= leaf;
		}
	}

	ulong currentK0 = 0;
	ulong currentLeaf = 0;

	foreach (r; ranges) {
		if (r[0] < 0x800) {
			assert(r[1] < 0x800);
			continue;
		}

		if (r[0] >= 0x40000) {
			continue;
		}

		assert(r[1] < 0x40000);

		foreach (c; r[0] .. r[1]) {
			auto k0 = c >> 6;
			auto k1 = c & 0x3f;

			if (k0 != currentK0) {
				save(currentK0, currentLeaf);

				currentK0 = k0;
				currentLeaf = 0;
			}

			currentLeaf |= 1UL << k1;
		}
	}

	save(currentK0, currentLeaf);

	import std.algorithm;
	sort!((a, b) => scores[a] >= scores[b])(ret[1 .. $]);

	return ret;
}

ubyte[4096] generateTrieRoots(const dchar[2][] ranges, const ulong[] leaves)
		in(leaves.length <= 256) {
	ubyte[ulong] indices;

	foreach (i, l; leaves) {
		indices[l] = i & 0xff;
	}

	ubyte[4096] ret;

	ulong currentK0 = 0;
	ulong currentLeaf = 0;

	foreach (r; ranges) {
		if (r[0] < 0x800) {
			assert(r[1] < 0x800);
			continue;
		}

		if (r[0] >= 0x40000) {
			continue;
		}

		assert(r[1] < 0x40000);

		foreach (c; r[0] .. r[1]) {
			auto k0 = c >> 6;
			auto k1 = c & 0x3f;

			if (k0 != currentK0) {
				ret[currentK0] = indices[currentLeaf];

				currentK0 = k0;
				currentLeaf = 0;
			}

			currentLeaf |= 1UL << k1;
		}
	}

	ret[currentK0] = indices[currentLeaf];
	return ret;
}
