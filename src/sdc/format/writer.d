module sdc.format.writer;

import sdc.format.chunk;

struct FormatResult {
	uint cost;
	uint overflow;
	string text;
}

struct Writer {
	import std.array;
	Appender!string buffer;
	
	uint cost;
	uint overflow;
	
	FormatResult write(Chunk[] chunks) {
		import std.array;
		buffer = appender!string();
		
		cost = 0;
		overflow = 0;
		
		size_t start = 0;
		foreach (i, c; chunks) {
			if (!c.endsBreakableLine()) {
				continue;
			}
			
			writeLine(chunks[start .. i]);
			start = i;
		}
		
		// Make sure we write the last line too.
		writeLine(chunks[start .. $]);
		
		return FormatResult(cost, overflow, buffer.data);
	}
	
	void writeLine(Chunk[] line) in {
		assert(line.length > 0, "line must not be empty");
	} do {
		auto state = findBestState(line);
		
		cost += state.cost;
		overflow += state.overflow;
		
		foreach (uint i, c; line) {
			assert((i == 0) || !c.endsBreakableLine(), "Line splitting bug");
			
			if (state.isSplit(i)) {
				if (c.splitType == SplitType.TwoNewLines) {
					output("\n\n");
				} else {
					output('\n');
				}
				
				indent(c.indentation + state.getIndent(i));
			} else if (c.splitType == SplitType.Space) {
				output(' ');
			}
			
			output(c.text);
		}
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
}

enum INDENTATION_SIZE = 4;
enum PAGE_WIDTH = 80;
enum MAX_ATTEMPT = 5000;

import std.container.rbtree;
alias SolveStateQueue = RedBlackTree!SolveState;

SolveState findBestState(Chunk[] line) {
	auto best = SolveState(line);
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

struct SolveState {
	uint sunk = 0;
	uint overflow = 0;
	uint cost = 0;
	
	Chunk[] line;
	uint[] ruleValues;
	
	// The set of free to bind rules that affect the next overflowing line.
	RedBlackTree!uint liveRules;
	
	// Span that require indentation.
	RedBlackTree!Span usedSpans;
	
	this(Chunk[] line, uint[] ruleValues = []) {
		this.line = line;
		this.ruleValues = ruleValues;
		computeCost();
	}
	
	void computeCost() {
		sunk = 0;
		overflow = 0;
		cost = 0;
		
		// If there is nothing to be done, just skip.
		if (line.length == 0) {
			return;
		}
		
		foreach (uint i, ref c; line[1 .. $]) {
			if (c.span is null) {
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
				.filter!(i => !mustSplit(i));
			
			// If the line overflow, but has no split point, it is sunk.
			if (range.empty) {
				sunk += lineOverflow;
				return;
			}
			
			liveRules = redBlackTree(range);
		}
		
		void startLine(uint i) {
			start = i;
			
			auto indent = line[i].indentation;
			auto span = line[i].span;
			bool needInsert = true;
			
			// Make sure to keep track of the span that cross over line breaks.
			while (span !is null && needInsert) {
				scope(success) span = span.parent;
				
				if (brokenSpans is null) {
					brokenSpans = redBlackTree!Span();
				}
				
				needInsert = brokenSpans.insert(span) > 0;
			}
			
			length = INDENTATION_SIZE * (line[i].indentation + getIndent(i));
		}
		
		void newLine(uint i) {
			endLine(i);
			startLine(i);
		}
		
		startLine(0);
		
		foreach (uint i, ref c; line) {
			if (isSplit(i)) {
				if (i > 0) {
					newLine(i);
					cost += 1;
				}
			} else if (c.splitType == SplitType.Space) {
				length++;
			}
				
			length += c.length;
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
	
	bool mustSplit(uint i) const {
		auto st = line[i].splitType;
		return st == SplitType.TwoNewLines || st == SplitType.NewLine;
	}
	
	bool isSplit(uint i) const {
		return mustSplit(i) || getRuleValue(i) > 0;
	}
	
	uint getIndent(uint i) {
		if (usedSpans is null) {
			return 0;
		}
		
		uint indent = 0;
		
		auto span = line[i].span;
		while (span !is null) {
			scope(success) span = span.parent;
			
			if (span in usedSpans) {
				indent += span.indent;
			}
		}
		
		return indent;
	}
	
	SolveState withRuleValue(uint i, uint v) in {
		assert(i > ruleValues.length);
	} body {
		uint[] newRuleValues = ruleValues;
		newRuleValues.length = i;
		newRuleValues[i - 1] = v;
		
		return SolveState(line, newRuleValues);
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
	
	// Necessary due to https://issues.dlang.org/show_bug.cgi?id=21947
	size_t toHash() const @trusted nothrow {
		size_t h = 0;
		foreach (const ref v; this.tupleof) {
			static if (is(typeof(v) : S[], S)) {
				h = hashOf(v.length, h);
				h = hashOf(v.ptr, h);
			} else {
				h = hashOf(v, h);
			}
		}
		
		return h;
	}
}
