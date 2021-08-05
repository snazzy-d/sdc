module sdc.format.span;

import sdc.format.writer;
import sdc.format.chunk;

class Span {
	Span parent = null;
	
	this(Span parent) {
		this.parent = parent;
	}
	
	uint getCost() const {
		return 1;
	}
	
	uint getIndent() const {
		return 1;
	}
	
	// lhs < rhs => rhs.opCmp(rhs) < 0
	final int opCmp(const Span rhs) const {
		auto lhsPtr = cast(void*) this;
		auto rhsPtr = cast(void*) rhs;
		
		return (lhsPtr > rhsPtr) - (lhsPtr < rhsPtr);
	}
	
	static string print(const Span span) {
		if (span is null)  {
			return "null";
		}
		
		return span.toString();
	}
	
	override string toString() const {
		import std.conv;
		return typeid(this).toString() ~ "(" ~ print(parent) ~ ")";
	}
	
protected:
	void register(size_t i) {}
}

void register(Span span, size_t i) {
	while (span !is null) {
		span.register(i);
		span = span.parent;
	}
}

Span getTop(Span span) {
	Span top = span;
	
	while (span !is null) {
		top = span;
		span = span.parent;
	}
	
	return top;
}
