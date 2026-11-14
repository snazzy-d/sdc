alias T = uint;
alias A = T[7];

unittest types {
	assert(T.sizeof == 4);
	assert(A.sizeof == 28);
}

enum E {
	A,
	B,
}

alias EA = E.A;
alias EB = E.B;
alias ESame = EA == EB;

unittest expressions {
	assert(ESame == false);
}

class AliasedException : Exception {}
alias ExceptionAlias = AliasedException;
class DerivedException : ExceptionAlias {}

unittest classes {
	// A class can be named by an alias where a class is expected.
	try {
		throw new DerivedException();
	} catch (ExceptionAlias e) {
		return;
	}
}
