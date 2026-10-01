//T error: enum_negative_ubyte.d:7:7:
//T error: Can't cast int to ubyte

enum int negative = -1;

int main() {
	ubyte b = negative;
}
