module format.span;

import format.chunk;
import format.rulevalues;
import format.writer;

class Span {
	Span parent = null;

	this(Span parent) {
		this.parent = parent;
	}

	const(SpanState) getState(const ref SolveState s) const {
		return SpanState(0);
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
	RuleValues __cachedSolveRuleValue;
	SpanState __cachedState;

	final override const(SpanState) getState(const ref SolveState s) const {
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

struct SpanState {
private:
	RuleValues values;

public:
	this(size_t capacity) {
		this.values = RuleValues(1, capacity);
	}

	@property
	size_t capacity() const {
		return values.capacity - 1;
	}

	@property
	size_t frozen() const {
		return values.frozen - 1;
	}

	@property
	size_t frozen(size_t f) {
		return (values.frozen = f + 1) - 1;
	}

	bool opIndex(size_t i) const {
		return values[i + 1];
	}

	void opIndexAssign(bool v, size_t i) {
		values[i + 1] = v;
	}

	bool opEqual(const ref SpanState rhs) const {
		return values == rhs.values;
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
	Packed,
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

	this(Span parent, ListType type = ListType.Packed) {
		super(parent);

		this.type = type;
	}

	bool isActive(const ref SolveState s) const {
		return s.isSplit(elements[0]) || !s.isUsed(this);
	}

	mixin CachedState;

	SpanState computeState(const ref SolveState s) const {
		auto state = SpanState(elements.length + 1);

		if (hasTrailingSplit && type == ListType.Expanding
			    && elements.length > 1) {
			foreach (n; elements[$ - 1] .. trailingSplit) {
				const c = n + 1;
				if (!s.isSplit(c)) {
					continue;
				}

				// The trailing parameter must split => split all parameters.
				foreach (i; 0 .. elements.length + 1) {
					state[i] = true;
				}

				return state;
			}
		}

		size_t previous = elements[0];
		foreach (i, p; elements) {
			scope(success) {
				previous = p + 1;
			}

			// Ok let's go over the parameter and see if it must split.
			foreach (c; previous .. p) {
				if (s.isSplit(c)) {
					// This parameter must split.
					state[i] = true;
					break;
				}
			}
		}

		return state;
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
			return getState(s)[elements.length] ? Split.Must : Split.No;
		}

		foreach (k, p; elements) {
			if (p < i) {
				// We have not reached our goal, move on to the next param.
				continue;
			}

			if (p > i) {
				// We went past the index we are interested in.
				break;
			}

			if (getState(s)[k]) {
				return Split.Must;
			}
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
