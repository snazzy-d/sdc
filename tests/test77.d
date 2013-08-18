//T compiles:yes
//T has-passed:no
//T retval:0

void main() {
	string str = "foobar";

    // This is narrowing, but valid.
	foreach(byte i, c; str) {}
}

