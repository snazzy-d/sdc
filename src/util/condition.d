module util.condition;

template isCondition(T) {
	enum isCondition = is(typeof({
		switch(T.init.outcome) {
			default:
		}
	}()));
}

private template handler(C) if(isCondition!C) {
	void function(ref C) handler = function void(ref C c) {};
}

ref C raiseCondition(C)(ref C c) if(isCondition!C) {
	handler!C(c);
	
	return c;
}

auto ref withConditionHandler(alias fun, C)(void function(ref C) newHandler) if(isCondition!C && is(typeof(fun()))) {
	auto oldHandler = handler!C;
	scope(exit) handler!C = oldHandler;
	
	handler!C = newHandler;
	
	return fun();
}

unittest {
	struct Condition {
		uint outcome;
	}
	
	static auto test() {
		return raiseCondition(Condition()).outcome;
	}
	
	assert(test() == 0);
	
	withConditionHandler!({
		assert(test() == 42);
	})(function void(ref Condition c) {
		c.outcome = 42;
	});
	
	assert(test() == 0);
	
	bool hasThrown = false;
	try {
		withConditionHandler!({
			test();
			assert(false);
		})(function void(ref Condition c) {
			throw new Exception("foobar");
		});
	} catch(Exception e) {
		assert(e.msg == "foobar");
		
		hasThrown = true;
	}
	
	assert(hasThrown);
	assert(test() == 0);
}

