//T error: immutable_global_too_big.d:7:7:
//T error: Can't cast immutable(int) to ubyte

immutable int tooBig = 256;

int main() {
	ubyte b = tooBig;
}
