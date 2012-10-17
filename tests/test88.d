//T compiles:yes
//T retval:42

int main() {
	int a = 42;
	
	// TODO: unary minus.
	int b = 0 - 14;
	
	while(a) {
		a--;
		
		if(a % 3) {
			b += 2;
		}
	}
	
	return b;
}

