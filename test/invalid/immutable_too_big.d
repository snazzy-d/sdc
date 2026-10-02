//T error: immutable_too_big.d:6:7:
//T error: Can't cast immutable(int) to ubyte

int main() {
	immutable int tooBig = 256;
	ubyte b = tooBig;
}
