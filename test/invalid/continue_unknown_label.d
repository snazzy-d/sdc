//T error: continue_unknown_label.d:5:2:
//T error: No corresponding label for this continue statement.
void main() {
	foreach (i; 0 .. 3) {
		continue Nope;
	}
}
