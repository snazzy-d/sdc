//T error: function_return_class.d:9:14:
//T error: Can't cast A function() to B function().
class A {}
class B : A {}

A f();

auto g() {
	B function() fp = &f;
	return fp;
}
