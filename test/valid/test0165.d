//T compiles:yes
//T has-passed:yes
//T retval:41
// voldemort class with inheritance and 2 different contexts.

auto voldemort() {
	uint a = 7;

	class MarvoloRiddle {
		uint b;

		this(uint b) {
			this.b = b + a++;
		}

		auto foo() {
			return a + b;
		}
	}

	auto basilisk(uint c) {
		class GinnyWeasley : MarvoloRiddle {
			this(uint b) {
				a += c++;
				this.b = b + a++;
			}

			auto bar() {
				return foo() + a + c;
			}
		}

		return new GinnyWeasley(5);
	}

	return basilisk(3);
}

auto buzz(V)(V v) {
	return v.bar();
}

int main() {
	auto v = voldemort();
	return buzz(v);
}
