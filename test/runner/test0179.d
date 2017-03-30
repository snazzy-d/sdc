//T compiles:yes
//T retval:42
//T has-passed:yes
// Tests ambiguous parsing.

int main() {
	T* function() f;
	T* delegate() dg;
	
	T* ptr;
	T** ptrptr;
	
	// Expression * function T() { return 0; }
	// Expression * delegate T() { return 0; }
	
	return 42;
}

alias T = uint;
