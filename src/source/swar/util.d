module source.swar.util;

auto read(T)(string s) in(s.length >= T.sizeof) {
	return *(cast(T*) s.ptr);
}
