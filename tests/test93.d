//T compiles:yes
//T retval:4

int main() {
	alias int foo;
	
	// TODO: remove cast when implicit cast will be able to do without.
	return cast(int) foo.sizeof;
}

