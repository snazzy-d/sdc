module sdc.format.span;

import sdc.format.writer;
import sdc.format.chunk;

class Span {
	Span parent = null;
	
	this(Span parent) {
		this.parent = parent;
	}
	
	uint getCost(const ref SolveState s) const {
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
	
	uint computeIndent(const ref SolveState s) const {
		return s.isUsed(this) ? 1 : 0;
	}
	
	size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		return i;
	}
	
	Split computeSplit(const ref SolveState s, size_t i) const {
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

bool contains(const Span span, const Span s) {
	if (span is null) {
		return false;
	}
	
	if (span is s) {
		return true;
	}
	
	return span.parent.contains(s);
}

uint getIndent(const Span span, const ref SolveState s) {
	if (span is null) {
		return 0;
	}
	
	return span.computeIndent(s) + span.parent.getIndent(s);
}

size_t getAlignIndex(const Span span, const ref SolveState s, size_t i) {
	if (span is null) {
		return i;
	}
	
	auto ci = span.computeAlignIndex(s, i);
	if (ci != i) {
		return ci;
	}
	
	return span.parent.getAlignIndex(s, i);
}

bool canSplit(const Span span, const ref SolveState s, size_t i) {
	if (span is null) {
		return true;
	}
	
	if (span.computeSplit(s, i) != Span.Split.Can) {
		return false;
	}
	
	return span.parent.canSplit(s, i);
}

bool mustSplit(const Span span, const ref SolveState s, size_t i) {
	if (span is null) {
		return false;
	}
	
	final switch (span.computeSplit(s, i)) with (Span.Split)  {
		case No:
			return false;
		
		case Must:
			return true;
		
		case Can:
			return span.parent.mustSplit(s, i);
	}
}

/**
 * This span only has a cost when directly broken.
 */
final class PrefixSpan : Span {
	this(Span parent) {
		super(parent);
	}
	
	override uint getCost(const ref SolveState s) const {
		return s.isUsed(this) ? 5 : 0;
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
	
	override size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		return first;
	}
}

/**
 * Span ensuring lists of items are formatted as expected.
 */
final class ListSpan : Span {
	size_t[] params;
	
	this(Span parent) {
		super(parent);
	}
	
	void registerParam(size_t i) in {
		assert(params.length == 0 || params[$ - 1] < i);
	} do {
		params ~= i;
	}
	
	bool isActive(const ref SolveState s) const {
		return s.isSplit(params[0]) || !s.isUsed(this);
	}
	
	override uint computeIndent(const ref SolveState s) const {
		return (s.isSplit(params[0]) && s.isUsed(this)) ? 1 : 0;
	}
	
	override size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		return (s.isSplit(params[0]) || !s.isUsed(this)) ? i : params[0];
	}
	
	override Split computeSplit(const ref SolveState s, size_t i) const {
		size_t previous = params[0];
		foreach (p; params) {
			if (p > i) {
				// We went past the index we are interested in.
				break;
			}
			
			if (p < i) {
				// We have not reached our goal, move on to the next param.
				previous = p;
				continue;
			}
			
			// We are at a parameter junction. Split here if the preceding
			// parameter is split.
			foreach (c; previous + 1 .. p) {
				if (s.isSplit(c)) {
					return Split.Must;
				}
			}
			
			// Previous parameters isn't split, so there are no constraints.
			break;
		}
		
		return Split.Can;
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
	
	override Split computeSplit(const ref SolveState s, size_t i) const {
		if (i != colonIndex) {
			return Split.Can;
		}
		
		return s.isSplit(questionMarkIndex) ? Split.Must : Split.No;
	}
}
