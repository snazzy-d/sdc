version(Foo) {
	version(Bar) {}

	version(123) {}
} else {
	version(unittest) {}

	version(assert) {}
}

version = Baz;
version = 456;

debug(Foo) {
	debug(Bar) {}

	debug(123) {}
} else {
	debug {}
}

debug = Baz;
debug = 456;
