//T compiles:yes
//T has-passed:no
//T retval:30
//T dependency:test37_import.d

import test37_import;

alias Integer = int;
alias SS = test37_import.S;
alias bar = foo;
alias bas = bar;

int bazoooooooom() {
	return 2;
}

Integer main() {
	SS s;
	s.i = 30;
	bas(&s.i);
	
	return s;
}

