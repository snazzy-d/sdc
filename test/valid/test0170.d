//T compiles:yes
//T has-passed:yes
//T retval:23
// Goto over and in/out blocks.

int main() {
	goto Over;

Reachable:
	while (true) {
		int i;
	}

Over:
	while (false) {
	InLoop:
		int i;
		goto PostLoop;
	}

	goto InLoop;

PostLoop:
	bool hasJumped = false;

Jump:
	uint i;
	assert(i == 0);

	i = 5;
	if (!hasJumped) {
		hasJumped = true;
		goto Jump;
	}

	// Backward unwind.

Reloop:
	while (i < 13) {
		scope(exit) i += 7;
		goto Reloop;
	}

	// Forward unwind.

	{
		scope(exit) i += 4;
		goto Exit;
	}

Exit:
	return i;
}
