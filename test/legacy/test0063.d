//T has-passed:yes
//T compiles:yes
//T retval:0

int main() {
	assert(0b0010 == 2);
	assert(0xF_F == 25_5);
	assert(0x0FL == 15L);
	return 0;
}
