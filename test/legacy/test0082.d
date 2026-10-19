//T compiles:yes
//T has-passed:yes
//T retval:65

int main() {
	ubyte[123] arr;
	auto p = &arr[0];
	*p++ = cast(ubyte) 'A';
	return arr[0];
}
