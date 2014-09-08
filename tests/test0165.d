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
		// XXX: SDC do not capture parameters for now. Refactor when apropriate.
		auto d = c;
		class GinnyWeasley : MarvoloRiddle {
			this(uint b) {
				a += d++;
				this.b = b + a++;
			}
			
			auto bar() {
				return foo() + a + d;
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

