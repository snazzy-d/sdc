//T error: mutable_to_ubyte.d:6:7:
//T error: Can't cast int to ubyte

int main() {
	int answer = 42;
	ubyte b = answer;
}
