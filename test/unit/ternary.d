unittest ternary_value {
	// A conditional between two lvalues, used as a value, reads
	// from the selected branch.
	int a = 1, b = 2;
	assert((true ? a : b) == 1);
	assert((false ? a : b) == 2);
}

unittest ternary_assign {
	// A conditional between two lvalues is itself an lvalue:
	// assignment writes to the selected branch only.
	int a = 1, b = 2;

	(true ? a : b) = 10;
	assert(a == 10 && b == 2);

	(false ? a : b) = 20;
	assert(a == 10 && b == 20);
}

unittest ternary_op_assign {
	// Op-assign through a conditional updates the selected branch
	// and evaluates to the new value.
	int a = 1, b = 2;

	assert(((true ? a : b) += 10) == 11);
	assert(a == 11 && b == 2);

	assert(((false ? a : b) += 20) == 22);
	assert(a == 11 && b == 22);
}

unittest ternary_inc_dec {
	int a = 1, b = 2;

	// Post-increment evaluates to the old value of the branch.
	assert((true ? a : b)++ == 1);
	assert(a == 2 && b == 2);

	// Pre-increment evaluates to the new value of the branch.
	assert(++(false ? a : b) == 3);
	assert(a == 2 && b == 3);

	assert((false ? a : b)-- == 3);
	assert(b == 2);
}

unittest ternary_address {
	// The address of a conditional is the address of the
	// selected branch.
	int a = 1, b = 2;

	int* p = &(true ? a : b);
	assert(p is &a);

	*p = 42;
	assert(a == 42 && b == 2);

	assert(&(false ? a : b) is &b);
}

void bump(ref int x) {
	x += 100;
}

ref int pick(bool c, ref int a, ref int b) {
	return c ? a : b;
}

unittest ternary_ref {
	// A conditional between two lvalues can be passed and
	// returned by ref.
	int a = 1, b = 2;

	bump(true ? a : b);
	assert(a == 101 && b == 2);

	bump(false ? a : b);
	assert(a == 101 && b == 102);

	pick(true, a, b) = 7;
	assert(a == 7 && b == 102);

	pick(false, a, b) += 1;
	assert(a == 7 && b == 103);
}

unittest ternary_member_and_index {
	// The branches can be any lvalues, including fields and
	// indexed elements.
	struct S {
		int x;
	}

	S s;
	s.x = 1;

	int[2] arr = [2, 3];

	(true ? s.x : arr[0]) = 10;
	assert(s.x == 10 && arr[0] == 2);

	(false ? s.x : arr[0]) = 20;
	assert(s.x == 10 && arr[0] == 20);
}

unittest ternary_nested {
	// Conditionals nest: the inner conditional is an lvalue
	// branch of the outer one.
	int a = 1, b = 2, d = 3;

	(true ? (false ? a : b) : d) = 10;
	assert(a == 1 && b == 10 && d == 3);

	(false ? (true ? a : b) : d) = 30;
	assert(a == 1 && b == 10 && d == 30);
}
