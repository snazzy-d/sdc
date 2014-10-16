//T compiles:yes
//T has-passed:yes
//T retval:42
//? Tests TernaryOperator

int main() {
	ubyte right = cast(ubyte) 42;
	bool b_wrong = cast(bool) 0;
	int i_wrong;
	int ret = 18;
	uint ui_wrong;
	bool[12] bs;

	for (int i = 0; i < 12; i++) {
		// parens around bs[i] are needed because of a bug in the parser
		(bs[i]) = cast(bool) (i % 2);  
	}

	for (int i = 0; i < 12; i++) {
		// ditto
		(bs[i] || true && false) ? (ret += 7) : (ret -= 3); 
	}

	if ((i_wrong ? right : b_wrong) ? 5 : ret != 42) {
		ret = 0;
	}

	return ret;
}
