alias T = uint;
alias A = T[7];

unittest aliases {
	assert(T.sizeof == 4);
	assert(A.sizeof == 28);
}
