module format.span;

import format.chunk;
import format.writer;

class Span {
	Span parent = null;

	this(Span parent) {
		this.parent = parent;
	}

	ulong getState(const ref SolveState s) const {
		return 0;
	}

	uint getCost(const ref SolveState s) const {
		return 10;
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

	uint computeIndent(const ref SolveState s, size_t i) const {
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

uint getIndent(const Span span, const ref SolveState s, size_t i) {
	if (span is null) {
		return 0;
	}

	return span.computeIndent(s, i) + span.parent.getIndent(s, i);
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
 * Span state management utilities.
 */
private mixin template CachedState() {
	import format.rulevalues;
	RuleValues __cachedSolveRuleValue;
	ulong __cachedState;

	final override ulong getState(const ref SolveState s) const {
		if (__cachedSolveRuleValue == s.ruleValues) {
			return __cachedState;
		}

		auto state = computeState(s);

		auto t = cast() this;
		t.__cachedSolveRuleValue = s.ruleValues.clone();
		t.__cachedState = state;

		return state;
	}
}

/**
 * This span can indent multiple times.
 */
final class IndentSpan : Span {
	uint indent;

	this(Span parent, uint indent) {
		super(parent);

		this.indent = indent;
	}

	override uint computeIndent(const ref SolveState s, size_t i) const {
		return super.computeIndent(s, i) ? indent : 0;
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
		return s.isUsed(this) ? 15 : 0;
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
enum ListType {
	Compact,
	Expanding,
}

final class ListSpan : Span {
	ListType type;

	size_t[] elements;
	size_t trailingSplit = size_t.max;

	@property
	bool hasTrailingSplit() const {
		return trailingSplit != size_t.max;
	}

	this(Span parent, ListType type = ListType.Compact) {
		super(parent);

		this.type = type;
	}

	bool isActive(const ref SolveState s) const {
		return s.isSplit(elements[0]) || !s.isUsed(this);
	}

	mixin CachedState;
	ulong computeState(const ref SolveState s) const {
		if (computeMustExplode(s)) {
			return -1;
		}

		return 0;
	}

	bool computeMustSplit(const ref SolveState s, size_t start,
	                      size_t stop) const {
		foreach (c; start .. stop) {
			if (!s.isSplit(c)) {
				continue;
			}

			return true;
		}

		return false;
	}

	bool mustSplit(const ref SolveState s, size_t start, size_t stop) const {
		return computeMustSplit(s, start, stop) || mustExplode(s);
	}

	bool computeMustExplode(const ref SolveState s) const {
		if (!hasTrailingSplit || type != ListType.Expanding) {
			// Not the exploding kind.
			return false;
		}

		if (elements.length < 2) {
			// Not worth exploding.
			return false;
		}

		// If the last element is broken, expand the whole thing.
		return computeMustSplit(s, elements[$ - 1] + 1, trailingSplit + 1);
	}

	bool mustExplode(const ref SolveState s) const {
		return getState(s) == -1;
	}

	override uint getCost(const ref SolveState s) const {
		// If there is just one element, make it slitghtly more exepensive to split.
		if (elements.length <= 1) {
			return 15;
		}

		if (isActive(s)) {
			foreach (p; elements[1 .. $]) {
				if (s.isSplit(p)) {
					return 14;
				}
			}
		}

		return 13;
	}

	void registerElement(size_t i) in {
		assert(elements.length == 0 || elements[$ - 1] < i);
		assert(!hasTrailingSplit);
	} do {
		elements ~= i;
	}

	void registerTrailingSplit(size_t i) in {
		assert(elements[$ - 1] < i);
		assert(!hasTrailingSplit);
	} do {
		trailingSplit = i;
	}

	override uint computeIndent(const ref SolveState s, size_t i) const {
		if (i >= trailingSplit) {
			return 0;
		}

		return (s.isSplit(elements[0]) && s.isUsed(this)) ? 1 : 0;
	}

	override size_t computeAlignIndex(const ref SolveState s, size_t i) const {
		if (i < elements[0] || i >= trailingSplit) {
			return 0;
		}

		return isActive(s) ? 0 : elements[0];
	}

	override Split computeSplit(const ref SolveState s, size_t i) const {
		if (i == trailingSplit) {
			return mustExplode(s) ? Split.Must : Split.No;
		}

		size_t previous = elements[0];
		foreach (k, p; elements) {
			if (p > i) {
				// We went past the index we are interested in.
				break;
			}

			if (p < i) {
				// We have not reached our goal, move on to the next param.
				previous = p;
				continue;
			}

			return mustSplit(s, previous + 1, p) ? Split.Must : Split.Can;
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

/**
 * Span that do not cause any indentation and is cheap to break.
 */

final class StorageClassSpan : Span {
	this(Span parent) {
		super(parent);
	}

	override uint getCost(const ref SolveState s) const {
		return 5;
	}

	override uint computeIndent(const ref SolveState s, size_t i) const {
		return 0;
	}
}
