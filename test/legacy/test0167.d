//T compiles:yes
//T has-passed:yes
//T retval:57
// Tests TernaryOperator

int main() {
	int ret = 5;
	ret += ((ret++ == 5) ? (ret += 3) : (ret -= 11)) + ret;
	assert(ret == 27);

	ret += ((ret-- == 22) ? (ret += 5) : (ret -= 7)) + ret;
	assert(ret == 57);

	return ret;
}
