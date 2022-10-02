switch (n) static if (c)

	// FIXME: no double empty line before the label.
	Label:
	case A:
		foo();
else {
	case B:
		bar();

	default:
		buzz();
}

switch (n) {
	foreach (c; Cases)
		case k:
			return foo(k);
	foreach (c; Cases) {
		case k:
			return foo(k);
	}

	static foreach (c; Cases)
		case k:
			return foo(k);
	static foreach (c; Cases) {
		case k:
			return foo(k);
	}

	Label:
		foreach (k; Cases)
			foo(k);
		static foreach (k; Cases)
			foo(k);

	foreach (k; Cases)
		static if (k == MyCase)
			default:
				foo(k);
}

// FIXME: This split it absolutely not good,
// but the resulting identation is correct.
switch (n) if (() {
	               return true;
               }()) {
	case 10:
		break;

	static if (c) {
			enum A = 3;

		case 20:
		case 21: {
			doSomething();
		}

			break;

		case 22:
			foobar();
	} else static if (c2)
		case 30:
		case 31:
			buzz("c2 is true");
	else
		case 32:
		case 33:
			buzz("c2 is false");
}

switch (n) {
	Foo:
		return Foo;

		Bar: {
			return Bar;
		}

	case 1:
		goto Foo;
	case 2:
		goto Bar;
	default:
		break;
}
