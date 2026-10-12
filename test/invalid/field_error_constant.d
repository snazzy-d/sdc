//T error: field_error_constant.d:5:9:
//T error: Expected a slice.

struct S {
	int x = 1 ~ "a";
}
