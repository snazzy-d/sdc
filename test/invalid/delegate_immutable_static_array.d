//T error: delegate_immutable_static_array.d:4:30:
//T error: Can't cast int delegate() <{void*}>[1] to immutable(int delegate() <{void*}>[1]).
void f(int delegate()[1] a) {
	immutable(int delegate())[1] b = a;
}
