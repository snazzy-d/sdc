//T error: this_not_consumed_union.d:11:1:
//T error: *&u has not been consumed.

union U {
	int x;
	float f;
}

void main() {
	U u;
	u.nope;
}
