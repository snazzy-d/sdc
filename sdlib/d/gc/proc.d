module d.gc.proc;

import sys.posix.types;

/**
 * Because Linux forces us to use signals to stop the world.
 * And because linux provides no way to know if a signal is received,
 * pending, blocked or ignored, we need to check this via the
 * /proc virtual file system.
 */
bool isDetached(pid_t tid) {
	char[1024] buffer = void;

	import core.stdc.unistd, core.stdc.stdio;
	auto len =
		snprintf(buffer.ptr, buffer.length, "/proc/self/task/%d/status\0", tid);

	import core.stdc.fcntl;
	auto fd = open(buffer.ptr, O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		return false;
	}

	scope(exit) close(fd);

	ulong pending;
	ulong blocked;
	ulong ignored;

	char[] line, workset;
	while (next_line(fd, buffer[0 .. buffer.length], line, workset)) {
		if (line.length != 25) {
			continue;
		}

		// Must start with Sig.
		if (line[0] != 'S' || line[1] != 'i' || line[2] != 'g') {
			continue;
		}

		if (line[6] != ':' || line[7] != '\t') {
			continue;
		}

		// write(STDERR_FILENO, line.ptr, line.length);

		ulong h = decodeHex(line.ptr + 8);
		ulong l = decodeHex(line.ptr + 16);
		ulong v = (h << 32) | l;

		if (line[3] == 'P' && line[4] == 'n' && line[5] == 'd') {
			pending = v;
			continue;
		}

		if (line[3] == 'B' && line[4] == 'l' && line[5] == 'k') {
			blocked = v;
			continue;
		}

		if (line[3] == 'I' && line[4] == 'g' && line[5] == 'n') {
			ignored = v;
			continue;
		}
	}

	import d.gc.signal;
	auto sigmask = 1UL << (SIGSUSPEND - 1);

	if ((pending & sigmask) == 0) {
		// There are no signal pending here, move on.
		return false;
	}

	auto all = blocked | ignored;
	return (all & sigmask) != 0;
}

private:

uint decodeHex(char* s) {
	ulong v;
	foreach (i; 0 .. 8) {
		v |= ulong(s[i]) << (8 * i);
	}

	/**
	 * For '0' to '9', the lower bits are what we are looking for.
	 * For letters, we get 'a'/'A'=1, 'b'/'B'=2, etc...
	 * So we add 9 whenever a letter is detected.
	 */
	auto base = v & 0x0f0f0f0f0f0f0f0f;
	auto letter = v & 0x4040404040404040;
	auto fixup = letter >> 3 | letter >> 6;

	// v = [a, b, c, d, e, f, g, h]
	v = base + fixup;

	// v = [ba, dc, fe, hg]
	v |= v << 12;

	// a = [fe00ba, fe]
	auto a = (v >> 24) & 0x000000ff000000ff;
	a |= a << 48;

	// b = [hg00dc00, hg00]
	auto b = v & 0x0000ff000000ff00;
	b |= b << 48;

	// hgfedcba
	return (a | b) >> 32;
}

unittest decodeHex {
	assert(decodeHex("00000000") == 0x00000000);
	assert(decodeHex("99999999") == 0x99999999);
	assert(decodeHex("aaaaaaaa") == 0xaaaaaaaa);
	assert(decodeHex("ffffffff") == 0xffffffff);

	assert(decodeHex("abcd1234") == 0xabcd1234);
	assert(decodeHex("abcdef09") == 0xabcdef09);
	assert(decodeHex("12345678") == 0x12345678);
	assert(decodeHex("feedf00d") == 0xfeedf00d);
}

bool next_line(int fd, char[] buffer, ref char[] line, ref char[] workset) {
	auto lstart = line.ptr + line.length;
	auto current = lstart;

	while (true) {
		auto start = workset.ptr;
		auto stop = start + workset.length;

		while (current < stop) {
			// We found the end of the new line, return it.
			if (*current == '\n') {
				line = lstart[0 .. current - lstart + 1];
				return true;
			}

			current++;
		}

		// We don't have the space left in the buffer to store
		// the new line, make room for it.
		auto bstart = buffer.ptr;
		auto bsize = buffer.length;

		auto lsize = current - lstart;
		auto rsize = bsize - lsize;
		if (rsize == 0) {
			// The line is too long and doesn't fit.
			return false;
		}

		memmove(bstart, lstart, lsize);
		lstart = bstart;
		current = bstart + lsize;

		import core.stdc.unistd;
		auto n = read(fd, current, rsize);
		if (n <= 0) {
			// We failed to read or reached EOF.
			return false;
		}

		workset = current[0 .. n];
	}
}
