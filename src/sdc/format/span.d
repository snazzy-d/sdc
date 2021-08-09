module sdc.format.span;

final class Span {
	Span parent = null;
	uint cost = 1;
	uint indent = 1;
	
	this(Span parent, uint cost, uint indent) {
		this.parent = parent;
		this.cost = cost;
		this.indent = indent;
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
		return "Span(" ~ print(parent) ~ ", " ~ cost.to!string ~ ", " ~ indent.to!string ~ ")";
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
