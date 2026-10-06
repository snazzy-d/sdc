//T error: this_not_consumed_union.d:11:1:
//T error: nope can't be resolved in type U.

union U {
	int x;
	float f;
}

void main() {
	U u;
	u.nope;
}
