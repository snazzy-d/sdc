//T compiles:no
//T has-passed:yes
//T retval:0

void main() {
	string str = "foobar";

	// This is narrowing, SDC disallows this.
	foreach (byte i, c; str) {}
}
