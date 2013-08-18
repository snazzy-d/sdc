//T compiles:yes
//T has-passed:yes
//T retval:4

int main() {
	alias int foo;
	
	return foo.sizeof;
}

