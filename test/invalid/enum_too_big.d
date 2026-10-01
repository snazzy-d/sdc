//T error: enum_too_big.d:7:7:
//T error: Can't cast int to ubyte

enum int tooBig = 256;

int main() {
	ubyte b = tooBig;
}
