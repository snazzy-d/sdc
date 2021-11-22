//T compiles:yes
//T has-passed:yes
//T retval:42
// Tests UTF-8 characters.

int åäö() {
	return 2;
}

int aäo() {
	return 20;
}

int åäo() {
	return 20;
}

int main() {
	return åäö() + aäo() + åäo();
}
