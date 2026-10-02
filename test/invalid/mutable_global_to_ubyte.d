//T error: mutable_global_to_ubyte.d:7:7:
//T error: Can't cast int to ubyte

int answer = 42;

int main() {
	ubyte b = answer;
}
