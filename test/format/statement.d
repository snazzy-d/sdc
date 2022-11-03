for (; popFront(), i; ++i, foo()) {}

foreach (a, b;
	zip(StoppingPolicy.shortest, as, bs)
)
	return false;

if (condition) // comment!
	foo();

if (condition) {
	foo();
} // comment!
else {
	bar();
}

if (condition)
	foo(); // foo!
else
	bar(); // bar!

if (a)
	if (b)
		if (c)
			while (d)
				e();
		else
			f();
	else
		g();
