module format.span;

import format.writer;
import format.chunk;

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
		if (span is null) {
			return "null";
		}

		return span.toString();
	}

	override string toString() const {
		import std.conv;
		return typeid(this).toString() ~ "(" ~ print(parent) ~ ")";
	}

protected:
	enum Split {
		No,
		Can,
		Must,
	}

	uint computeIndent(const ref SolveState s) const {
		return s.isUsed(this) ? 1 : 0;
	}

	size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		return 0;
	}

	Split computeSplit(const ref SolveState s, size_t i) const {
		return Split.Can;
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
		return 0;
	}

	auto ci = span.computeAlignIndex(s, i);
	if (ci > 0 && ci != i) {
		return ci;
	}

	if (auto pi = span.parent.getAlignIndex(s, i)) {
		return pi;
	}

	return ci;
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

	final switch (span.computeSplit(s, i)) with (Span.Split) {
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

	void alignOn(size_t i) {
		first = i;
	}

	override size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		return first;
	}
}

/**
 * Span ensuring lists of items are formatted as expected.
 */
final class ListSpan : Span {
	size_t[] elements;

	this(Span parent) {
		super(parent);
	}

	override uint getCost(const ref SolveState s) const {
		return elements.length <= 1 ? 5 : 3;
	}

	void registerElement(size_t i) in {
		assert(elements.length == 0 || elements[$ - 1] < i);
	} do {
		elements ~= i;
	}

	bool isActive(const ref SolveState s) const {
		return s.isSplit(elements[0]) || !s.isUsed(this);
	}

	override uint computeIndent(const ref SolveState s) const {
		return (s.isSplit(elements[0]) && s.isUsed(this)) ? 1 : 0;
	}

	override size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		return (s.isSplit(elements[0]) || !s.isUsed(this)) ? 0 : elements[0];
	}

	override Split computeSplit(const ref SolveState s, size_t i) const {
		size_t previous = elements[0];
		foreach (p; elements) {
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

final class TrainlingListSpan : Span {
	this(Span parent) {
		super(parent);
	}

	override uint computeIndent(const ref SolveState s) const {
		return 0;
	}

	override Split computeSplit(const ref SolveState s, size_t i) const {
		return Split.No;
	}
}

/**
 * Span used to format Condition expression, of the form:
 *     condition ? ifTrue : ifFalse
 */
final class ConditionalSpan : Span {
	size_t questionMarkIndex = size_t.max;
	size_t colonIndex = size_t.max;

	ConditionalSpan parentConditional = null;

	this(Span parent) {
		super(parent);
	}

	void setQuestionMarkIndex(size_t i) {
		questionMarkIndex = i;

		// Use the opportinity to detect if this is a nested conditional.
		static ConditionalSpan findParentConditional(const Span s, size_t i) {
			auto p = s.parent;
			if (p is null) {
				return null;
			}

			if (auto c = cast(ConditionalSpan) p) {
				// Skip over if we are in the parent's condition rather than nested.
				if (c.questionMarkIndex < i) {
					return c;
				}
			}

			return findParentConditional(p, i);
		}

		parentConditional = findParentConditional(this, i);
	}

	void setColonIndex(size_t i) {
		colonIndex = i;
	}

	override Split computeSplit(const ref SolveState s, size_t i) const {
		if (i == questionMarkIndex && parentConditional !is null) {
			auto pi = parentConditional.questionMarkIndex;
			return s.isSplit(pi) ? Split.Can : Split.No;
		}

		if (i == colonIndex) {
			return s.isSplit(questionMarkIndex) ? Split.Must : Split.No;
		}

		return Split.Can;
	}
}
