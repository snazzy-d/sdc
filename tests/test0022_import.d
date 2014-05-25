import test0022;

int start() {
	return begin() + 1;
}

int ten() {
	return 10;
}

int addOne(int function() fn) {
	return fn() + 1;
}

int function() tenptr() {
	return &ten;
}

