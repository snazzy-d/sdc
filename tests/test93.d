//T compiles:yes
//T retval:4

int main() {
	alias int foo;
	
	return foo.sizeof;
}

