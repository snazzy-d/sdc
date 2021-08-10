module sdc.format.span;

import sdc.format.writer;
import sdc.format.chunk;

class Span {
	Span parent = null;
	
	this(Span parent) {
		this.parent = parent;
	}
	
	uint getCost() const {
		return 3;
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
	
	size_t computeAlignIndex() const {
		return 0;
	}
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

size_t getAlignIndex(const Span span) {
	if (span is null) {
		return 0;
	}
	
	if (auto i = span.computeAlignIndex()) {
		return i;
	}
	
	return span.parent.getAlignIndex();
}

/**
 * When broken up, this span will ensure code
 * remain align with the break point.
 */
class AlignedSpan : Span {
	size_t first = size_t.max;
	
	this(Span parent) {
		super(parent);
	}
	
	override void register(size_t i) {
		first = i < first ? i : first;
	}

	override size_t computeAlignIndex() const {
		return first;
	}
}
