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
	
	// lhs < rhs => rhs.opCmp(rhs) < 0
	final int opCmp(const Span rhs) const {
		auto lhsPtr = cast(void*) this;
		auto rhsPtr = cast(void*) rhs;
		
		return (lhsPtr > rhsPtr) - (lhsPtr < rhsPtr);
	}
	
	@trusted
	final override size_t toHash() const {
		return cast(size_t) cast(void*) this;
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
	
	enum Split {
		No,
		Can,
		Must,
	}
	
	uint computeIndent(const ref SolveState s, const Chunk[] line) const {
		return 1;
	}
	
	size_t computeAlignIndex(const ref SolveState s, const Chunk[] line) const {
		return 0;
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

uint getIndent(const Span span, const ref SolveState s, const Chunk[] line) {
	if (span is null || s.usedSpans is null) {
		return 0;
	}
	
	uint indent = 0;
	if (span in s.usedSpans) {
		indent += span.computeIndent(s, line);
	}
	
	return indent + span.parent.getIndent(s, line);
}

size_t getAlignIndex(const Span span, const ref SolveState s, const Chunk[] line) {
	if (span is null) {
		return 0;
	}
	
	if (auto i = span.computeAlignIndex(s, line)) {
		return i;
	}
	
	return span.parent.getAlignIndex(s, line);
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
 * Span that ensure breaks are aligned with the start of the span.
 */
final class AlignedSpan : Span {
	size_t first = size_t.max;
	
	this(Span parent) {
		super(parent);
	}
	
	override void register(size_t i) {
		first = i < first ? i : first;
	}
	
	override size_t computeAlignIndex(const ref SolveState s, const Chunk[] line) const {
		return first;
	}
}

/**
 * Span ensuring lists of items are formatted as expected.
 */
final class ListSpan : Span {
	size_t first = size_t.max;
	
	this(Span parent) {
		super(parent);
	}
	
	override void register(size_t i) {
		first = i < first ? i : first;
	}
	
	override uint computeIndent(const ref SolveState s, const Chunk[] line) const {
		return s.isSplit(line, first) ? 1 : 0;
	}

	override size_t computeAlignIndex(const ref SolveState s, const Chunk[] line) const {
		if (s.usedSpans is null || this !in s.usedSpans) {
			return 0;
		}
		
		return s.isSplit(line, first) ? 0 : first;
	}
}

/**
 * Span used to format Condition expression, of the form:
 *     condition ? ifTrue : ifFalse
 */
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