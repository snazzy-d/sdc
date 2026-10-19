//T compiles:yes
//T has-passed:yes
//T retval:8

int main() {
	auto foobar = 0x80000000;
	return foobar.sizeof;
}
