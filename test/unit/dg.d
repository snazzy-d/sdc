unittest voiddg {
	uint a = 0;
	void increment() {
		a++;
	}

	increment();
	assert(a == 1);

	void forward(void delegate() dg) {
		return dg();
	}

	forward(increment);
	assert(a == 2);
}

struct Counter {
	int count;

	int next() {
		return ++count;
	}

	int current() const {
		return count;
	}
}

unittest delegate_struct_method {
	// A delegate refers to the struct it is created from.
	Counter c;
	int delegate() next = c.next;
	assert(next() == 1);
	assert(next() == 2);
	assert(c.count == 2);

	int delegate() current = c.current;
	assert(current() == 2);

	const(Counter)* pc = &c;
	int delegate() constCurrent = pc.current;
	assert(constCurrent() == 2);
}

unittest delegate_nested_function {
	int total = 1;
	int add(int x) {
		return total += x;
	}

	int delegate(int) dg = add;
	assert(dg(2) == 3);
	assert(total == 3);
}

class Base {}
class Derived : Base {}

unittest delegate_conversions {
	// What a delegate returns can be seen as anything it converts to, and
	// what it is given can be anything that converts to it.
	Derived d = new Derived();
	Derived make() {
		return d;
	}

	Base delegate() makeBase = make;
	assert(makeBase() is d);

	Base received;
	void take(Base b) {
		received = b;
	}

	void delegate(Derived) takeDerived = take;
	takeDerived(d);
	assert(received is d);
}

struct Holder {
	int value;

	int get() {
		return value;
	}
}

unittest delegate_pointer_method {
	// Through a pointer, the delegate refers to what it points to.
	Holder h;
	Holder* ph = &h;
	int delegate() get = ph.get;
	h.value = 5;
	assert(get() == 5);
}

class Accumulator {
	int total;

	int add(int x) {
		return total += x;
	}

	int current() const {
		return total;
	}
}

unittest delegate_class_method {
	// A delegate refers to the object it is created from.
	auto a = new Accumulator();
	int delegate(int) add = a.add;
	assert(add(3) == 3);
	assert(a.total == 3);

	const(Accumulator) ca = a;
	int delegate() current = ca.current;
	assert(current() == 3);
}

unittest delegate_context {
	// The context is given back to the function it is bound with, so a
	// delegate can be replaced by one with another context.
	Counter c;
	auto dg = c.next;
	assert(dg() == 1);

	dg = c.current;
	assert(dg() == 1);
	assert(c.count == 1);
}

class Constant {
	int value() {
		return 7;
	}
}

unittest delegate_context_kind {
	// The context is given back to the function it is bound with, so a
	// delegate on a struct can be replaced by one on a class.
	Counter c;
	auto dg = c.current;
	assert(dg() == 0);

	dg = (new Constant()).value;
	assert(dg() == 7);
}

struct Shared {
	int value;

	int get() immutable {
		return value;
	}

	int next() {
		return ++value;
	}

	int peek() shared {
		return 3;
	}
}

unittest delegate_qualifier {
	// A delegate can always be seen as const: its context could be changed
	// by the function when it was created, and still can.
	Shared s;
	const(int delegate()) next = s.next;
	assert(next() == 1);
	assert(s.value == 1);

	// A delegate with an immutable context can be immutable, and shared.
	Shared m;
	m.value = 5;
	immutable(Shared) i = m;
	immutable(int delegate()) get = i.get;
	assert(get() == 5);

	const(int delegate()) constGet = get;
	assert(constGet() == 5);

	shared(int delegate()) sharedGet = get;
	const(shared(int delegate())) constSharedGet = get;

	// Qualifiers can always be dropped.
	int delegate() mutableGet = get;
	assert(mutableGet() == 5);

	// A delegate with a shared context can be shared.
	shared(Shared) ss;
	shared(int delegate()) peek = ss.peek;
}
