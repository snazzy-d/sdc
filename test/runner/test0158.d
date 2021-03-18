//T compiles:yes
//T has-passed:yes
//T retval:42
// alias of type and values

alias b = a;
alias c = 42;
alias d = c;
alias e = b;

b main() {
	a b = c;
	e f = b;
	return f;
}

alias a = uint;
