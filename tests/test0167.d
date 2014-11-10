//T compiles:yes
//T has-passed:yes
//T retval:53
// Tests TernaryOperator

int main() {
	int ret = 5;
	ret += ((ret++ == 5) ? (ret += 3) : (ret -= 11)) + ret;
	assert(ret == 23);

	ret += ((ret-- == 22) ? (ret += 5) : (ret -= 7)) + ret;
	assert(ret == 53);

	return ret;
}

