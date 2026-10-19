//T compiles:yes
//T has-passed:yes
//T retval:42

mixin("auto foo() { return 12; }");

int main() {
	return foo() + bar!uint(30);
}

enum StringMixin = getStringMixin();

string getStringMixin() {
	return "T bar(T)(T t) { mixin(\"return t;\"); }";
}

mixin(StringMixin);
