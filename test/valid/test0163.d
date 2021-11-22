//T compiles:yes
//T has-passed:yes
//T retval:42
// voldemort struct on the heap.

auto voldemort() {
	uint a = 7;

	struct MarvoloRiddle {
		uint b;

		this(uint b) {
			this.b = b + a++;
		}

		auto foo() {
			return a + b;
		}
	}

	return new MarvoloRiddle(27);
}

auto bar(V)(V v) {
	return v.foo();
}

int main() {
	auto v = voldemort();
	return bar(v);
}
