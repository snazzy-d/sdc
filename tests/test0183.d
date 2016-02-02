//T compiles:yes
//T has-passed:yes
//T retval:42
// StringComaprision

int main() {
	static if ("c" != "d") {
		int i = 12;
	} else {
		int i;
	}

	
	if ("hello" == "hello") {
		i *= 2; // 24
	}
	if ("a" != "b") {
		i -= 2; // 22
	}
	if (!("1" == "2")) {
		i *= 2; // 44
	}

	if ("war" == ("waro"[0 .. 3])) {
		i -= 2; // 42	
	}

	return i;
}
