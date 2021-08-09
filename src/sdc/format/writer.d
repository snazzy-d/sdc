module sdc.format.writer;

import sdc.format.chunk;

import std.container.rbtree;

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
	
	FormatResult formatBlock(Chunk[] chunks, uint baseIndent) {
		auto block = BlockSpecifier(chunks, baseIndent);
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
		
		bool newline = false;
		foreach (i, c; line) {
			assert(i == 0 || !c.startsUnwrappedLine, "Line splitting bug");
			
			uint chunkIndent = state.getIndent(line, i);
			if (newline || state.isSplit(line, i)) {
				output('\n');
				
				if (c.splitType == SplitType.TwoNewLines) {
					output('\n');
				}
				
				indent(chunkIndent);
				
				if (!newline) {
					outputAlign(state.getAlign(line, i));
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
	
	SolveState findBestState() {
		auto best = SolveState(&this);
		if (best.overflow == 0 || best.liveRules is null) {
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
			
			foreach (r; next.liveRules) {
				uint[] newRuleValues = next.ruleValues;
				newRuleValues.length = r;
				newRuleValues[$ - 1] = 1;
				
				auto candidate = SolveState(&this, newRuleValues);
				
				if (candidate.isBetterThan(best)) {
					best = candidate;
				}
				
				// This candidate cannot be expanded further.
				if (candidate.liveRules is null) {
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
enum MAX_ATTEMPT = 5000;

struct SolveState {
	uint cost = 0;
	uint overflow = 0;
	uint sunk = 0;
	uint baseIndent = 0;
	
	uint[] ruleValues;
	
	// The set of free to bind rules that affect the next overflowing line.
	RedBlackTree!size_t liveRules;
	
	// Span that require indentation.
	import sdc.format.span;
	RedBlackTree!Span usedSpans;
	
	this(LineWriter* lineWriter, uint[] ruleValues = []) {
		this.ruleValues = ruleValues;
		this.baseIndent = lineWriter.baseIndent;
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
			
			// If there are no spans to break, move on.
			if (c.span is null) {
				continue;
			}
			
			if (!isSplit(line, i)) {
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
		size_t start = 0;
		
		void endLine(size_t i) {
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
			auto range = max(ruleValues.length, start + 1)
				.iota(i)
				.filter!(i => cansSplit(line, i));
			
			// If the line overflow, but has no split point, it is sunk.
			if (range.empty) {
				sunk += lineOverflow;
				return;
			}
			
			liveRules = redBlackTree(range);
		}
		
		bool salvageNextSpan = true;
		
		foreach (i, ref c; line) {
			bool salvageSpan = salvageNextSpan;
			uint lineLength = 0;
			
			final switch (c.kind) with (ChunkKind) {
				case Block:
					salvageNextSpan = true;
					
					auto f = writer.formatBlock(c.chunks, getIndent(line, i));
					
					cost += f.cost;
					overflow += f.overflow;
					
					if (i <= ruleValues.length) {
						sunk += f.overflow;
					}
					
					break;
				
				case Text:
					salvageNextSpan = false;
					
					if (!salvageSpan && !isSplit(line, i)) {
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
			
			length = getIndent(line, i) * INDENTATION_SIZE + lineLength;
			start = i;
			
			if (salvageSpan) {
				continue;
			}
			
			length += getAlign(line, i);
			
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
	
	uint getRuleValue(size_t i) const {
		return (i - 1) < ruleValues.length
			? ruleValues[i - 1]
			: 0;
	}
	
	bool cansSplit(const Chunk[] line, size_t i) const {
		if (mustSplit(line, i)) {
			return false;
		}
		
		auto c = line[i];
		if (c.kind == ChunkKind.Block) {
			return false;
		}
		
		if (c.splitIndex != 0) {
			return false;
		}
		
		return true;
	}
	
	bool mustSplit(const Chunk[] line, size_t i) const {
		auto st = line[i].splitType;
		return st == SplitType.TwoNewLines || st == SplitType.NewLine;
	}
	
	bool isSplit(const Chunk[] line, size_t i) const {
		if (mustSplit(line, i)) {
			return true;
		}
		
		auto splitIndex = line[i].splitIndex;
		return splitIndex > 0
			? isSplit(line, i - splitIndex)
			: getRuleValue(i) > 0;
	}
	
	uint getIndent(Chunk[] line, size_t i) {
		uint indent = baseIndent + line[i].indentation;
		if (usedSpans is null) {
			return indent;
		}
		
		auto span = line[i].span;
		while (span !is null) {
			scope(success) span = span.parent;
			
			if (span in usedSpans) {
				indent += span.indent;
			}
		}
		
		return indent;
	}
	
	uint getAlign(const Chunk[] line, size_t i) {
		i -= line[i].alignIndex;
		uint ret = 0;
		
		// Find the preceding line break.
		while (i > 0 && !isSplit(line, i)) {
			ret += line[i].splitType == SplitType.Space;
			ret += line[--i].length;
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
