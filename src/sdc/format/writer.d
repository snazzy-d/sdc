module sdc.format.writer;

import sdc.format.chunk;

struct BlockSpecifier {
	Chunk[] chunks;
	uint baseIndent;
	
	bool opEquals(const ref BlockSpecifier rhs) const {
		return chunks is rhs.chunks && baseIndent == rhs.baseIndent;
	}
	
	size_t toHash() const @safe nothrow {
		size_t h = cast(size_t) chunks.ptr;
		
		h ^=  (h >>> 33);
		h *= 0xff51afd7ed558ccd;
		h += chunks.length;
		h ^=  (h >>> 33);
		h *= 0xc4ceb9fe1a85ec53;
		h += baseIndent;
		
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
	Chunk[] chunks;
	Chunk[] line;
	
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
			if (i == 0 || !c.endsBreakableLine()) {
				continue;
			}
			
			line = chunks[start .. i];
			writeLine();
			start = i;
		}
		
		// Make sure we write the last line too.
		line = chunks[start .. $];
		writeLine();
		
		return FormatResult(cost, overflow, buffer.data);
	}
	
	void writeLine() in {
		assert(line.length > 0, "line must not be empty");
	} do {
		auto state = findBestState();
		
		cost += state.cost;
		overflow += state.overflow;
		
		bool newline = false;
		foreach (uint i, c; line) {
			assert(i == 0 || !c.endsBreakableLine(), "Line splitting bug");
			
			uint chunkIndent = state.getIndent(i);
			if (newline || state.isSplit(i)) {
				output('\n');
				
				if (c.splitType == SplitType.TwoNewLines) {
					output('\n');
				}
				
				indent(chunkIndent);
				
				if (!newline) {
					outputAlign(state.getAlign(i));
				}
			} else if (c.splitType == SplitType.Space) {
				output(' ');
			}
			
			final switch (c.kind) with(ChunkKind) {
				case Text:
					newline = false;
					output(c.text);
					break;
				
				case Block:
					auto f = formatBlock(c.chunks, chunkIndent);
					
					cost += f.cost;
					overflow += f.overflow;
					
					newline = true;
					
					output(f.text);
					break;
			}
		}
	}
	
	FormatResult formatBlock(Chunk[] chunks, uint baseIndent) {
		auto block = BlockSpecifier(chunks, baseIndent);
		return cache.require(block, Writer(block, cache).write());
	}
	
	SolveState findBestState() {
		auto best = SolveState(&this);
		if (best.overflow == 0) {
			return best;
		}
		
		uint attempts = 0;
		scope queue = redBlackTree(best);
		
		// Once we have a solution that fits, or no more things
		// to try, then we are done.
		while (!queue.empty) {
			auto candidate = queue.front;
			queue.removeFront();
			
			if (candidate.isDeadSubTree(best)) {
				continue;
			}
			
			if (candidate.isBetterThan(best)) {
				best = candidate;
				if (candidate.overflow == 0) {
					// We found the lowest cost solution that fit on the page.
					break;
				}
			}
			
			// We ran out of attempts.
			if (attempts++ > MAX_ATTEMPT) {
				break;
			}
			
			candidate.expand(queue);
		}
		
		return best;
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

enum INDENTATION_SIZE = 4;
enum PAGE_WIDTH = 80;
enum MAX_ATTEMPT = 5000;

import std.container.rbtree;
alias SolveStateQueue = RedBlackTree!SolveState;

struct SolveState {
	// XXX: Keeping that reference in the object is not strictlynecessary.
	// Because there are possibly many instances, this needs to be removed.
	Writer* writer;
	
	uint cost = 0;
	uint overflow = 0;
	uint sunk = 0;
	
	uint[] ruleValues;
	
	// The set of free to bind rules that affect the next overflowing line.
	RedBlackTree!uint liveRules;
	
	// Span that require indentation.
	import sdc.format.span;
	RedBlackTree!Span usedSpans;
	
	this(Writer* writer, uint[] ruleValues = []) {
		this.writer = writer;
		this.ruleValues = ruleValues;
		computeCost();
	}
	
	void computeCost() {
		sunk = 0;
		overflow = 0;
		cost = 0;
		
		auto line = writer.line;
		
		// If there is nothing to be done, just skip.
		if (line.length == 0) {
			return;
		}
		
		foreach (uint i, ref c; line[1 .. $]) {
			if (c.span is null) {
				continue;
			}
			
			// Block are magic and do not break spans.
			if (c.kind == ChunkKind.Block || line[i].kind == ChunkKind.Block) {
				continue;
			}
			
			if (!isSplit(i + 1)) {
				continue;
			}
			
			if (usedSpans is null) {
				usedSpans = redBlackTree!Span();
			}
			
			usedSpans.insert(c.span);
		}
		
		// All the span which do not fit on one line.
		RedBlackTree!Span brokenSpans;
		
		uint length = 0;
		uint start = 0;
		
		void endLine(uint i) {
			if (length <= PAGE_WIDTH) {
				return;
			}
			
			uint lineOverflow = length - PAGE_WIDTH;
			overflow += lineOverflow;
			
			// We try to split element in the first line that overflows.
			if (liveRules !is null) {
				return;
			}
			
			import std.algorithm, std.range;
			auto range = max(cast(uint) ruleValues.length, start + 1)
				.iota(i)
				.filter!(i => cansSplit(i));
			
			// If the line overflow, but has no split point, it is sunk.
			if (range.empty) {
				sunk += lineOverflow;
				return;
			}
			
			liveRules = redBlackTree(range);
		}
		
		bool salvageNextSpan = true;
		
		foreach (uint i, ref c; line) {
			bool salvageSpan = salvageNextSpan;
			uint lineLength = 0;
			
			final switch (c.kind) with (ChunkKind) {
				case Block:
					salvageNextSpan = true;
					
					auto f = writer.formatBlock(c.chunks, getIndent(i));
					
					cost += f.cost;
					overflow += f.overflow;
					
					if (i <= ruleValues.length) {
						sunk += f.overflow;
					}
					
					break;
				
				case Text:
					salvageNextSpan = false;
					
					if (!salvageSpan && !isSplit(i)) {
						length += (c.splitType == SplitType.Space) + c.length;
						continue;
					}
					
					cost += 1;
					lineLength = c.length;
					break;
			}
			
			if (i > 0) {
				// End the previous line if there is one.
				endLine(i);
			}
			
			length = getIndent(i) * INDENTATION_SIZE + lineLength;
			start = i;
			
			if (salvageSpan) {
				continue;
			}
			
			length += getAlign(i);
			
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
		
		endLine(cast(uint) line.length);
		
		// Account for the cost of breaking spans.
		if (brokenSpans !is null) {
			foreach (s; brokenSpans) {
				cost += s.cost;
			}
		}
	}
	
	uint getRuleValue(uint i) const {
		return (i - 1) < ruleValues.length
			? ruleValues[i - 1]
			: 0;
	}
	
	bool cansSplit(uint i) const {
		if (mustSplit(i)) {
			return false;
		}
		
		auto c = writer.line[i];
		if (c.kind == ChunkKind.Block) {
			return false;
		}
		
		if (c.splitIndex != 0) {
			return false;
		}
		
		return true;
	}
	
	bool mustSplit(uint i) const {
		auto st = writer.line[i].splitType;
		return st == SplitType.TwoNewLines || st == SplitType.NewLine;
	}
	
	bool isSplit(uint i) const {
		if (mustSplit(i)) {
			return true;
		}
		
		auto splitIndex = writer.line[i].splitIndex;
		return splitIndex > 0
			? isSplit(i - splitIndex)
			: getRuleValue(i) > 0;
	}
	
	uint getIndent(uint i) {
		uint indent = writer.baseIndent + writer.line[i].indentation;
		if (usedSpans is null) {
			return indent;
		}
		
		auto span = writer.line[i].span;
		while (span !is null) {
			scope(success) span = span.parent;
			
			if (span in usedSpans) {
				indent += span.indent;
			}
		}
		
		return indent;
	}
	
	uint getAlign(uint i) {
		i -= writer.line[i].alignIndex;
		uint ret = 0;
		
		// Find the preceding line break.
		while (i > 0 && !isSplit(i)) {
			ret += writer.line[i].splitType == SplitType.Space;
			ret += writer.line[--i].length;
		}
		
		return ret;
	}
	
	SolveState withRuleValue(uint i, uint v) in {
		assert(i > ruleValues.length);
	} do {
		uint[] newRuleValues = ruleValues;
		newRuleValues.length = i;
		newRuleValues[i - 1] = v;
		
		return SolveState(writer, newRuleValues);
	}
	
	void expand()(SolveStateQueue queue) {
		if (liveRules is null) {
			return;
		}
		
		foreach (r; liveRules) {
			queue.insert(withRuleValue(r, 1));
		}
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
		if (ruleValues.length != rhs.ruleValues.length) {
			return cast(int) (ruleValues.length - rhs.ruleValues.length);
		}
		
		foreach (i; 0 .. ruleValues.length) {
			if (ruleValues[i] != rhs.ruleValues[i]) {
				return rhs.ruleValues[i] - ruleValues[i];
			}
		}
		
		return 0;
	}
}
