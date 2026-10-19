//T error: break_unknown_label.d:5:2:
//T error: No corresponding label for this break statement.
void main() {
	foreach (i; 0 .. 3) {
		break Nope;
	}
}
