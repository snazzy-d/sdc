//T error: template_default_narrow.d:9:1:
//T error: No match

ubyte narrowDefault(ubyte N = 300)() {
	return N;
}

void main() {
	narrowDefault!()();
}
