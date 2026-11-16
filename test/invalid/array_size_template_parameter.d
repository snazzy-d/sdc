//T error: array_size_template_parameter.d:5:5:
//T error: Can't cast string to ulong.

struct Sized(string S) {
	int[S] array;
}

Sized!"a" s;
