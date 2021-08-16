module sdc.format.writer;

import sdc.format.chunk;

import std.container.rbtree;

struct BlockSpecifier {
	Chunk[] chunks;
	uint baseIndent;
	uint baseAlign;
	
	bool opEquals(const ref BlockSpecifier rhs) const {
		return chunks is rhs.chunks
			&& baseIndent == rhs.baseIndent && baseAlign == rhs.baseAlign;
	}
	
	size_t toHash() const @safe nothrow {
		size_t h = cast(size_t) chunks.ptr;
		
		h ^=  (h >>> 33);
		h *= 0xff51afd7ed558ccd;
		h += chunks.length;
		h ^=  (h >>> 33);
		h *= 0xc4ceb9fe1a85ec53;
		h += baseIndent * 0x9e3779b97f4a7c15 + baseAlign;
		
		return h;
	}
}

struct FormatResult {
	uint cost;
	uint overflow;
	string text;
}

struct Writer {
	uint cost;
	uint overflow;
	
	uint baseIndent = 0;
	uint baseAlign = 0;
	Chunk[] chunks;
	
	FormatResult[BlockSpecifier] cache;
	
	import std.array;
	Appender!string buffer;
	
	this(Chunk[] chunks) {
		this.chunks = chunks;
	}
	
	this(BlockSpecifier block, FormatResult[BlockSpecifier] cache) in {
		assert(cache !is null);
	} do {
		baseIndent = block.baseIndent;
		baseAlign = block.baseAlign;
		chunks = block.chunks;
		
		this.cache = cache;
	}
	
	FormatResult write() {
		cost = 0;
		overflow = 0;
		
		import std.array;
		buffer = appender!string();
		
		size_t start = 0;
		foreach (i, ref c; chunks) {
			if (i == 0 || !c.startsUnwrappedLine) {
				continue;
			}
			
			LineWriter(&this, chunks[start .. i]).write();
			start = i;
		}
		
		// Make sure we write the last line too.
		LineWriter(&this, chunks[start .. $]).write();
		
		return FormatResult(cost, overflow, buffer.data);
	}
	
	FormatResult formatBlock(Chunk[] chunks, uint baseIndent, uint baseAlign) {
		auto block = BlockSpecifier(chunks, baseIndent, baseAlign);
		return cache.require(block, Writer(block, cache).write());
	}
	
	void output(char c) {
		buffer ~= c;
	}
	
	void output(string s) {
		buffer ~= s;
	}
	
	void indent(uint level) {
		foreach (_; 0 .. level) {
			output('\t');
		}
	}
	
	void outputAlign(uint columns) {
		foreach (_; 0 .. columns) {
			output(' ');
		}
	}
}

enum MAX_ATTEMPT = 5000;

struct LineWriter {
	Writer* writer;
	alias writer this;
	
	Chunk[] line;
	
	this(Writer* writer, Chunk[] line) in {
		assert(line.length > 0, "line must not be empty");
	} do {
		this.writer = writer;
		this.line = line;
	}
	
	void write() {
		auto state = findBestState();
		
		cost += state.cost;
		overflow += state.overflow;
		
		bool newline = state.mustSplit(line, 0);
		foreach (i, c; line) {
			assert(i == 0 || !c.startsUnwrappedLine, "Line splitting bug");
			
			if (newline || (i > 0 && state.isSplit(i))) {
				output('\n');
				
				if (c.splitType == SplitType.TwoNewLines) {
					output('\n');
				}
				
				indent(state.getIndent(line, i));
				outputAlign(state.getAlign(line, i));
			} else if (c.splitType == SplitType.Space) {
				output(' ');
			}
			
			final switch (c.kind) with(ChunkKind) {
				case Text:
					newline = false;
					output(c.text);
					break;
				
				case Block:
					auto f = formatBlock(c.chunks, state.getIndent(line, i), state.getAlign(line, i));
					
					cost += f.cost;
					overflow += f.overflow;
					
					newline = true;
					
					output(f.text);
					break;
			}
		}
	}
	
	SolveState findBestState() {
		auto best = SolveState(this);
		if (best.overflow == 0 || !best.canExpand) {
			// Either the line already fit, or it is not breakable.
			return best;
		}
		
		uint attempts = 0;
		scope queue = redBlackTree(best);
		
		// Once we have a solution that fits, or no more things
		// to try, then we are done.
		while (!queue.empty) {
			auto next = queue.front;
			queue.removeFront();
			
			// We found the lowest cost solution that fit on the page.
			if (next.overflow == 0) {
				break;
			}
			
			// There is no point trying to expand this if it cannot
			// lead to a a solution better than the current best.
			if (next.isDeadSubTree(best)) {
				continue;
			}
			
			// This algorithm is exponential in nature, so make sure to stop
			// after some time, even if we haven't found an optimal solution.
			if (attempts++ > MAX_ATTEMPT) {
				break;
			}
			
			bool split = false;
			foreach (rule; next.ruleValues.frozen .. line.length) {
				if (split) {
					// We reach a split point, bail.
					break;
				}
				
				auto newRuleValues = next.ruleValues.withFrozen(rule + 1);
				
				split = next.isSplit(rule);
				if (!split) {
					if (!next.canSplit(line, rule)) {
						continue;
					}
					
					// If this can be split, then split.
					newRuleValues.setValue(rule, true);
				}
				
				auto candidate = SolveState(this, newRuleValues);
				
				if (candidate.isBetterThan(best)) {
					best = candidate;
				}
				
				// This candidate cannot be expanded further.
				if (!candidate.canExpand) {
					continue;
				}
				
				// This candidate can never expand to something better than the best.
				if (candidate.isDeadSubTree(best)) {
					continue;
				}
				
				queue.insert(candidate);
			}
		}
		
		return best;
	}
}

enum INDENTATION_SIZE = 4;
enum PAGE_WIDTH = 80;

struct RuleValues {
private:
	import core.bitop;
	enum DirectBits = 16 * size_t.sizeof;
	enum DirectCapacity = DirectBits - bsf(DirectBits);
	enum DirectShift = DirectCapacity - 8 * size_t.sizeof;
	
	union {
		struct {
			size_t* uptr;
			size_t ulength;
		}
		
		size_t[2] direct;
	}
	
	bool isDirect() const {
		return direct[0] & 0x01;
	}
	
public:
	this(size_t frozen, size_t capacity) in {
		assert(frozen > 0 && capacity >= frozen);
	} do {
		if (capacity > DirectCapacity) {
			indirect = new size_t[capacity + 1];
			indirect[0] = frozen;
			indirect[1] = 0x01;
		} else {
			direct[0] = 0x01;
			direct[1] = frozen << DirectShift;
		}
	}
	
	RuleValues withFrozen(size_t f) const in {
		assert(f > frozen && f <= length);
	} do {
		RuleValues ret = void;
		if (isDirect()) {
			ret.direct = direct;
		} else {
			ret.indirect = indirect.dup;
		}
		
		ret.frozen = f;
		return ret;
	}
	
	@property
	size_t length() const {
		return isDirect()
			? DirectCapacity
			: indirect.length - 1;
	}
	
	@property
	size_t frozen() const {
		return isDirect()
			? direct[1] >> DirectShift
			: indirect[0];
	}
	
	@property
	size_t frozen(size_t f) in {
		assert(f >= frozen && f <= length);
	} do {
		if (isDirect()) {
			// Replace the previous frozen value.
			direct[1] &= (size_t(1) << DirectShift) - 1;
			direct[1] |= f << DirectShift;
		} else {
			*uptr = f;
		}
		
		return frozen;
	}
	
	bool opIndex(size_t i) const {
		return (values[word(i)] >> shift(i)) & 0x01;
	}
	
	void opIndexAssign(bool v, size_t i) in {
		assert(i >= frozen && i < length);
	} do {
		setValue(i, v);
	}
	
private:
	@property
	inout(size_t)[] values() inout {
		return isDirect() ? direct[] : indirect[1 .. $];
	}
	
	@property
	inout(size_t)[] indirect() inout {
		return uptr[0 .. ulength];
	}
	
	@property
	size_t[] indirect(size_t[] v) {
		uptr = v.ptr;
		ulength = v.length;
		return indirect;
	}
	
	enum Bits = 8 * size_t.sizeof;
	enum Mask = Bits - 1;
	
	static word(size_t i) {
		return i / Bits;
	}
	
	static shift(size_t i) {
		return i & Mask;
	}
	
	/**
	 * Internal version without in contract.
	 */
	void setValue(size_t i, bool v) {
		auto w = word(i);
		auto m = size_t(1) << shift(i);
		
		if (v) {
			values[w] |= m;
		} else {
			values[v] &= m;
		}
	}
}

struct SolveState {
	uint cost = 0;
	uint overflow = 0;
	uint sunk = 0;
	uint baseIndent = 0;
	uint baseAlign = 0;
	
	RuleValues ruleValues;
	
	import sdc.format.span, std.bitmanip;
	mixin(taggedClassRef!(
		// Spans that require indentation.
		RedBlackTree!(const(Span)), "usedSpans",
		bool, "canExpand", 1,
	));
	
	this(ref LineWriter lineWriter) {
		this(lineWriter, RuleValues(1, lineWriter.line.length));
	}
	
	this(ref LineWriter lineWriter, RuleValues ruleValues) {
		this.ruleValues = ruleValues;
		this.baseIndent = lineWriter.baseIndent;
		this.baseAlign = lineWriter.baseAlign;
		computeCost(lineWriter.line, lineWriter.writer);
	}
	
	void computeCost(Chunk[] line, Writer* writer) {
		sunk = 0;
		overflow = 0;
		cost = 0;
		
		// If there is nothing to be done, just skip.
		if (line.length == 0) {
			return;
		}
		
		bool wasBlock = false;
		foreach (i, ref c; line) {
			bool isBlock = c.kind == ChunkKind.Block;
			scope(success) {
				wasBlock = isBlock;
			}
			
			// Blocks are magic and do not break spans.
			if (isBlock || wasBlock) {
				continue;
			}
			
			if (!isSplit(i)) {
				if (!mustSplit(line, i)) {
					continue;
				}
				
				// Mark this as split.
				ruleValues[i] = true;
			}
			
			// If there are no spans to break, move on.
			if (c.span is null) {
				continue;
			}
			
			if (usedSpans is null) {
				usedSpans = redBlackTree!(const(Span))();
			}
			
			usedSpans.insert(c.span);
		}
		
		// All the span which do not fit on one line.
		RedBlackTree!Span brokenSpans;
		
		uint length = 0;
		size_t regionStart = 0;
		
		foreach (i, ref c; line) {
			uint lineLength = 0;
			
			if (c.startsRegion) {
				regionStart = i;
			}
			
			final switch (c.kind) with (ChunkKind) {
				case Block:
					auto f = writer.formatBlock(c.chunks, getIndent(line, i), getAlign(line, i));
					
					cost += f.cost;
					overflow += f.overflow;
					
					if (!tryWrap(line, i)) {
						sunk += f.overflow;
					}
					
					break;
				
				case Text:
					if (c.glued || isSplit(i)) {
						lineLength = c.length;
						break;
					}
					
					length += (c.splitType == SplitType.Space) + c.length;
					continue;
			}
			
			if (i > 0) {
				// End the previous line if there is one.
				endLine(line, i, length);
			}
			
			length = getIndent(line, i) * INDENTATION_SIZE + getAlign(line, i) + lineLength;
			
			if (c.glued) {
				continue;
			}
			
			cost += 1;
			
			// If we do not plan to expand, freeze previous regions.
			if (!canExpand && regionStart > ruleValues.frozen) {
				ruleValues.frozen = regionStart;
			}
			
			auto span = c.span;
			bool needInsert = true;
			
			// Make sure to keep track of the span that cross over line breaks.
			while (span !is null && needInsert) {
				scope(success) span = span.parent;
				
				if (brokenSpans is null) {
					brokenSpans = redBlackTree!Span();
				}
				
				needInsert = brokenSpans.insert(span) > 0;
			}
		}
		
		endLine(line, line.length, length);
		
		// Account for the cost of breaking spans.
		if (brokenSpans !is null) {
			foreach (s; brokenSpans) {
				cost += s.getCost(this);
			}
		}
	}
	
	bool tryWrap(const Chunk[] line, size_t i) {
		if (canExpand) {
			return true;
		}
		
		foreach (j; ruleValues.frozen .. i) {
			if (canSplit(line, j)) {
				canExpand = true;
				return true;
			}
		}
		
		return false;
	}
	
	void endLine(const Chunk[] line, size_t i, uint length) {
		if (length <= PAGE_WIDTH) {
			return;
		}
		
		uint lineOverflow = length - PAGE_WIDTH;
		overflow += lineOverflow;
		
		// If the line overflow, but has no split point, it is sunk.
		if (!tryWrap(line, i)) {
			sunk += lineOverflow;
		}
	}
	
	bool canSplit(const Chunk[] line, size_t i) const {
		if (isSplit(i)) {
			return false;
		}
		
		auto c = line[i];
		if (c.glued) {
			return false;
		}
		
		return c.span.canSplit(this, i);
	}
	
	bool mustSplit(const Chunk[] line, size_t i) const {
		auto c = line[i];
		return c.mustSplit() || c.span.mustSplit(this, i);
	}
	
	bool isSplit(size_t i) const {
		return ruleValues[i];
	}
	
	bool isUsed(const Span span) const {
		return usedSpans !is null && span in usedSpans;
	}
	
	uint getIndent(Chunk[] line, size_t i) {
		return baseIndent + line[i].indentation
			+ line[i].span.getIndent(this);
	}
	
	uint getAlign(const Chunk[] line, size_t i) {
		uint ret = baseAlign;
		
		// Find the preceding line break.
		size_t c = line[i].span.getAlignIndex(this, i);
		while (c > 0 && !isSplit(c)) {
			ret += line[c].splitType == SplitType.Space;
			ret += line[--c].length;
		}
		
		if (c != i) {
			ret += getAlign(line, c);
		}
		
		return ret;
	}
	
	// Return if this solve state must be chosen over rhs as a solution.
	bool isDeadSubTree(const ref SolveState best) const {
		if (sunk > best.overflow) {
			// We already have comitted to an overflow greater than the best.
			return true;
		}
		
		if (sunk == best.overflow && cost >= best.cost) {
			// We already comitted to a cost greater than the best.
			return true;
		}
		
		// There is still hope to find a better solution down that path.
		return false;
	}
	
	// Return if this solve state must be chosen over rhs as a solution.
	bool isBetterThan(const ref SolveState rhs) const {
		if (overflow < rhs.overflow) {
			return true;
		}
		
		if (overflow == rhs.overflow && cost < rhs.cost) {
			return true;
		}
		
		return false;
	}
	
	// lhs < rhs => rhs.opCmp(rhs) < 0
	int opCmp(const ref SolveState rhs) const {
		if (cost != rhs.cost) {
			return cost - rhs.cost;
		}
		
		if (overflow != rhs.overflow) {
			return overflow - rhs.overflow;
		}
		
		if (sunk != rhs.sunk) {
			return sunk - rhs.sunk;
		}
		
		return opCmpSlow(rhs);
	}
	
	int opCmpSlow(const ref SolveState rhs) const {
		// Explore candidate with a lot of follow up first.
		if (ruleValues.frozen != rhs.ruleValues.frozen) {
			return cast(int) (ruleValues.frozen - rhs.ruleValues.frozen);
		}
		
		foreach (i; 0 .. ruleValues.frozen) {
			if (ruleValues[i] != rhs.ruleValues[i]) {
				return rhs.ruleValues[i] - ruleValues[i];
			}
		}
		
		return 0;
	}
}
