//T compiles:yes
//T retval:11

int main() {
	int b;
	
	for(int a = 1; a < 10; a--) {
		// TODO: +=
		a = a + 4;
		b = a;
	}
	
	return b;
}

