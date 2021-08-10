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
	
	enum Split {
		No,
		Can,
		Must,
	}
	
	Split computeSplit(const ref SolveState s, const Chunk[] line, size_t i) const {
		return Split.Can;
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

bool canSplit(const Span span, const ref SolveState s, const Chunk[] line, size_t i) {
	if (span is null) {
		return true;
	}
	
	if (span.computeSplit(s, line, i) != Span.Split.Can) {
		return false;
	}
	
	return span.parent.canSplit(s, line, i);
}

bool mustSplit(const Span span, const ref SolveState s, const Chunk[] line, size_t i) {
	if (span is null) {
		return false;
	}
	
	final switch (span.computeSplit(s, line, i)) with (Span.Split)  {
		case No:
			return false;
		
		case Must:
			return true;
		
		case Can:
			return span.parent.mustSplit(s, line, i);
	}
}

/**
 * When broken up, this span will ensure code
 * remain align with the break point.
 */
final class AlignedSpan : Span {
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

final class ConditionalSpan : Span {
	size_t questionMarkIndex = size_t.max;
	size_t colonIndex = size_t.max;
	
	this(Span parent) {
		super(parent);
	}
	
	void setQuestionMarkIndex(size_t i) {
		questionMarkIndex = i;
	}
	
	void setColonIndex(size_t i) {
		colonIndex = i;
	}
	
	override Split computeSplit(const ref SolveState s, const Chunk[] line, size_t i) const {
		if (i != colonIndex) {
			return Split.Can;
		}
		
		return s.isSplit(line, questionMarkIndex)
			? Split.Must
			: Split.No;
	}
}