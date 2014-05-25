//T compiles:yes
//T has-passed:yes
//T retval:4

int main() {
	alias foo = int;
	
	return foo.sizeof;
}

