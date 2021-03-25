module sdc.format.writer;

import sdc.format.chunk;

struct Writer {
	import std.array;
	Appender!string buffer;
	
	string write(Chunk[] chunks) {
		import std.array;
		buffer = appender!string();
		
		uint cost = 0;
		size_t start = 0;
		foreach (i, c; chunks) {
			if (!c.isLineBreak()) {
				continue;
			}
			
			cost += Splitter(&this, chunks[start .. i]).write();
			start = i;
		}
		
		// Make sure we write the last line too.
		cost += Splitter(&this, chunks[start .. $]).write();
		
		return buffer.data;
	}
}

enum INDENTATION_SIZE = 4;
enum PAGE_WIDTH = 80;
enum MAX_ATTEMPT = 5000;

import std.container.rbtree;
alias SolveStateQueue = RedBlackTree!SolveState;

struct Splitter {
	Writer* writer;
	Chunk[] line;
	
	this(Writer* writer, Chunk[] line) {
		this.writer = writer;
		this.line = line;
	}
	
	uint write() {
		if (line.length == 0) {
			// This is empty.
			return 0;
		}
		
		auto best = findBestState();
		return LineWriter(best, writer.buffer).write();
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
			if (candidate < best) {
				best = candidate;
			}
			
			// We have our solution.
			if (candidate.overflow == 0) {
				break;
			}
			
			// We ran out of attempts.
			if (attempts++ > MAX_ATTEMPT) {
				break;
			}
			
			queue.removeFront();
			candidate.expand(queue);
		}
		
		return best;
	}
}

struct SolveState {
	uint overflow = 0;
	uint cost = 0;
	
	Splitter* splitter;
	uint[] ruleValues;
	
	RedBlackTree!uint liveRules;
	
	this(Splitter* splitter, uint[] ruleValues = []) {
		this.splitter = splitter;
		this.ruleValues = ruleValues;
		computeCost();
	}
	
	void computeCost() {
		overflow = 0;
		cost = 0;
		
		// If there is nothing to be done, just skip.
		auto line = splitter.line;
		if (line.length == 0) {
			return;
		}
		
		uint length = 0;
		uint start = 0;
		
		void endLine(uint i) {
			if (length <= PAGE_WIDTH) {
				return;
			}
			
			overflow += length - PAGE_WIDTH;
			
			// We try to split element in the first line that overflows.
			if (liveRules !is null) {
				return;
			}
			
			import std.algorithm, std.range;
			auto range = max(cast(uint) ruleValues.length, start + 1).iota(i);
			
			// If the line overflow, but has no split point, skip it.
			if (!range.empty) {
				liveRules = redBlackTree(range);
			}
		}
		
		void startLine(uint i) {
				start = i;
				length = line[i].length + INDENTATION_SIZE * line[i].indentation;
		}
		
		void newLine(uint i) {
			endLine(i);
			startLine(i);
		}
		
		startLine(0);
		
		foreach (uint i, ref c; line[1 .. $]) {
			if (getRuleValue(i)) {
				newLine(i + 1);
				
				// FIXME: compute proper cost.
				cost += 1;
				continue;
			}
			
			if (c.splitType == SplitType.Space) {
				length++;
			}
			
			length += c.length;
		}
		
		endLine(cast(uint) line.length);
	}
	
	uint getRuleValue(uint i) const {
		return i < ruleValues.length
			? ruleValues[i]
			: 0;
	}
	
	SolveState withRuleValue(uint i, uint v) in {
		assert(i >= ruleValues.length);
	} body {
		uint[] newRuleValues = ruleValues;
		newRuleValues.length = i + 1;
		newRuleValues[i] = v;
		
		return SolveState(splitter, newRuleValues);
	}
	
	void expand()(SolveStateQueue queue) {
		if (liveRules is null) {
			return;
		}
		
		foreach (r; liveRules) {
			queue.insert(withRuleValue(r, 1));
		}
	}
	
	// lhs < rhs => rhs.opCmp(rhs) < 0
	int opCmp(const ref SolveState rhs) const {
		if (overflow != rhs.overflow) {
			return overflow - rhs.overflow;
		}
		
		if (cost != rhs.cost) {
			return cost - rhs.cost;
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

struct LineWriter {
	SolveState state;
	
	import std.array;
	Appender!string buffer;
	
	this(SolveState state, Appender!string buffer) {
		this.state = state;
		this.buffer = buffer;
	}
	
	uint write() {
		auto line = state.splitter.line;
		assert(line.length > 0, "line must not be empty");
		
		final switch (line[0].splitType) with (SplitType) {
			case None:
				// File starts.
				break;
			
			case Space:
				assert(0, "Expected line break");
			
			case NewLine:
				output('\n');
				indent(line[0].indentation);
				break;
			
			case TwoNewLines:
				output("\n\n");
				indent(line[0].indentation);
				break;
		}
		
		output(line[0].text);
		
		foreach (uint i, c; line[1 .. $]) {
			assert(!c.isLineBreak(), "Line splitting bug");
			
			if (state.getRuleValue(i)) {
				output('\n');
				indent(c.indentation);
			} else if (c.splitType == SplitType.Space) {
				output(' ');
			}
			
			output(c.text);
		}
		
		return state.cost;
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
