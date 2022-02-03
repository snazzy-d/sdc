if (condition) // comment!
	foo();

if (condition) {
	foo();
} // comment!
else {
	bar();
}

// FIXME: This split it absolutely not good,
// but the resulting identation is correct.
switch (
	n) if (() {
	       return true;
       }()) {
	case 1:
		break;

	foreach (k; Cases)
	case k:
		return funk();

	static if (c) {
			enum A = 3;

		case 2: {
			doSomething();
		}

			break;

		case 3:
			foobar();
	}
}

for (; popFront(), i; ++i, foo()) {}

if (a)
	if (b)
		if (c)
			while (d)
				e();
		else
			f();
	else
		g();
