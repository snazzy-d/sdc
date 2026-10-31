//T error: ref_argument_no_candidate.d:7:8:
//T error: No candidate for function call.
int f(ref const(int)* x);
int f(ref int x);

int g(int* y) {
	return f(y);
}
