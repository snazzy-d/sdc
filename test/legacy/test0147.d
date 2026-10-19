//T compiles:yes
//T has-passed:yes
//T retval:0
// bitwize operations

void main() {
	uint i = 1;

	assert((i << 2) == 4);
	assert((i >> 1) == 0);
	assert((i & 2) == 0);
	assert((i | 2) == 3);
	assert((i ^ 3) == 2);
}
