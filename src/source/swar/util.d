module source.swar.util;

auto read(T)(string s) in(s.length >= T.sizeof) {
	return *(cast(T*) s.ptr);
}

auto read(T)(const(ubyte)[] data) in(data.length >= T.sizeof) {
	return *(cast(T*) data.ptr);
}
