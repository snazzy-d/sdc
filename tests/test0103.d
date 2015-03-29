//T compiles:yes
//T has-passed:yes
//T retval:42

string CTString(string s) {
	return s;
}

mixin("auto foo() { return 12; }");

int main() {
	mixin(CTString("return foo() + bar!uint(30);"));
}

string getStringMixin() {
	return "T bar(T)(T t) { mixin(\"return t;\"); }";
}

mixin(getStringMixin());

