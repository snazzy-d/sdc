//T compiles:yes
//T has-passed:yes
//T retval:4

int main() {
	alias foo = int;
	// XXX: Remove when RVP is in.
	return cast(int) foo.sizeof;
}
