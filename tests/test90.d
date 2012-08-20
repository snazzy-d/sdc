//T compiles:yes
//T retval:11

int main() {
	for(int a = 1; a < 10; a--) {
		// TODO: +=
		a = a + 3;
	}
	
    return a;
}

