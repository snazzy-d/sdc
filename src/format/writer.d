module format.writer;

import format.chunk;
import format.config;

import std.container.rbtree;

string write(Chunk[] chunks, Config config) {
	auto context = Context(config, null);
	auto w = Writer(BlockSpecifier(chunks, LinePrefix(0, 0)), &context);
	w.write();
	w.buffer ~= '\n';
	return w.buffer.data;
}

package:

struct LinePrefix {
	uint indent;
	uint offset;

	size_t toHash() const @safe nothrow {
		return indent * 0x9e3779b97f4a7c15 + offset + 0xbf4600628f7c64f5;
	}
}

struct BlockSpecifier {
	Chunk[] chunks;
	LinePrefix prefix;

	this(Chunk[] chunks, LinePrefix prefix) {
		this.chunks = chunks;
		this.prefix = prefix;
	}

	bool opEquals(const ref BlockSpecifier rhs) const {
		return chunks is rhs.chunks && prefix == rhs.prefix;
	}

	size_t toHash() const @safe nothrow {
		size_t h = cast(size_t) chunks.ptr;

		h ^= (h >>> 33);
		h *= 0xff51afd7ed558ccd;
		h += chunks.length;
		h ^= (h >>> 33);
		h *= 0xc4ceb9fe1a85ec53;

		return h + prefix.toHash();
	}
}

struct FormatResult {
	uint cost;
	uint overflow;
	string text;
}

struct Context {
	Config config;
	FormatResult[BlockSpecifier] cache;
}

struct Writer {
	Context* context;
	alias context this;

	uint cost;
	uint overflow;

	Chunk[] chunks;
	LinePrefix prefix;

	import std.array;
	Appender!string buffer;

	this(BlockSpecifier block, Context* context) in {
		assert(context !is null);
	} do {
		chunks = block.chunks;
		prefix = block.prefix;

		this.context = context;
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

	FormatResult formatBlock(Chunk[] chunks, LinePrefix prefix) {
		auto block = BlockSpecifier(chunks, prefix);
		return cache.require(block, Writer(block, context).write());
	}

	void output(char c) {
		buffer ~= c;
	}

	void output(string s) {
		buffer ~= s;
	}

	void indent(uint level) {
		if (config.useTabs) {
			foreach (_; 0 .. level) {
				output('\t');
			}
		} else {
			foreach (_; 0 .. level * config.indentationSize) {
				output(' ');
			}
		}
	}

	void outputOffset(uint columns) {
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

		writeLine(state);
	}

	void writeLine(SolveState state) {
		foreach (i, c; line) {
			uint lineCount = 0;
			if (i > 0 || line.ptr !is chunks.ptr) {
				assert(i == 0 || !c.startsUnwrappedLine, "Line splitting bug");
				lineCount = state.newLineCount(line, i);
			}

			foreach (_; 0 .. lineCount) {
				output('\n');
			}

			if ((i == 0 || lineCount > 0) && !c.glued) {
				auto prefix = state.getLinePrefix(line, i);
				indent(prefix.indent);
				outputOffset(prefix.offset);
			}

			if (lineCount == 0 && c.separator == Separator.Space) {
				output(' ');
			}

			final switch (c.kind) with (ChunkKind) {
				case Text:
					output(c.text);
					break;

				case Block:
					auto f =
						formatBlock(c.chunks, state.getLinePrefix(line, i));

					cost += f.cost;
					overflow += f.overflow;

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
		auto checkpoints = CheckPoints(&this);
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
			if (next.isDeadSubTree(best) || checkpoints.isRedundant(next)) {
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

				split = next.isSplit(rule);
				if (!split && !next.canSplit(line, rule)) {
					// If we cannot split here, move on.
					continue;
				}

				auto newRuleValues = next.ruleValues.withFrozenSplit(rule);
				auto candidate = SolveState(this, newRuleValues);

				if (candidate.isBetterThan(best)) {
					best = candidate;
				}

				// We check for redundant path first so that, even in the
				// case where this candidate is rulled out, it can serve
				// as a checkpoint.
				if (checkpoints.isRedundant(candidate)) {
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

struct CheckPoints {
	LineWriter* lineWriter;
	SolveState[ulong][] paths;

	this(LineWriter* lineWriter) {
		this.lineWriter = lineWriter;
		this.paths.length = lineWriter.line.length;
	}

	import format.span;
	static getSpanStateHash(const ref SolveState s, const Span span, ulong h) {
		if (span is null) {
			h ^= (h >>> 33);
			h *= 0x4cd6944c5cc20b6d;
			h ^= (h >>> 33);
			h *= 0xfc12c5b19d3259e9;

			return h;
		}

		h ^= (h >>> 33);
		h *= 0x7fb5d329728ea185;
		h ^= (h >>> 33);
		h *= 0x81dadef4bc2dd44d;

		h += span.getState(s);

		h ^= (h >>> 33);
		h *= 0x99bcf6822b23ca35;
		h ^= (h >>> 33);
		h *= 0x14020a57acced8b7;

		h += s.isUsed(span);

		return getSpanStateHash(s, span.parent, h);
	}

	ulong getPathHash(const ref SolveState s, size_t i) {
		const prefix = s.getLinePrefix(lineWriter.line, i);
		return getSpanStateHash(s, lineWriter.line[i].span, prefix.toHash());
	}

	static isSameSpanState(const ref SolveState a, const ref SolveState b,
	                       const Span span) {
		if (span is null) {
			return true;
		}

		if (a.isUsed(span) != b.isUsed(span)) {
			return false;
		}

		if (span.getState(a) != span.getState(b)) {
			return false;
		}

		return isSameSpanState(a, b, span.parent);
	}

	bool isSamePath(const ref SolveState a, const ref SolveState b, size_t i) {
		if (a == b) {
			return false;
		}

		if (a.getLinePrefix(lineWriter.line, i)
			    != b.getLinePrefix(lineWriter.line, i)) {
			return false;
		}

		return isSameSpanState(a, b, lineWriter.line[i].span);
	}

	bool isRedundant(const ref SolveState s) {
		if (!s.canExpand || s.ruleValues.frozen >= lineWriter.line.length) {
			// There is nothing more to explore down this path.
			return true;
		}

		const i = s.ruleValues.frozen - 1;
		const h = getPathHash(s, i);

		const c = h in paths[i];
		const cmp = s.opCmp(c);
		if (cmp == 0) {
			// We are at the checkpoint.
			return false;
		}

		if (cmp < 0) {
			// We have a new best on that specific path.
			paths[i][h] = cast() s;
			return false;
		}

		// We are on a path that is worse than the checkpoint.
		// If this isn't a collision, this path is redundant.
		return isSamePath(s, *c, i);
	}
}

struct SolveState {
	uint cost = 0;
	uint overflow = 0;
	uint sunk = 0;

	LinePrefix prefix;

	import format.rulevalues;
	RuleValues ruleValues;

	import format.span, std.bitmanip;
	mixin(taggedClassRef!(
		// sdfmt off
		// Spans that require indentation.
		RedBlackTree!(const Span), "usedSpans",
		bool, "canExpand", 1,
		// sdfmt on
	));

	this(ref LineWriter lineWriter) {
		this(lineWriter, RuleValues(1, lineWriter.line.length));
	}

	this(ref LineWriter lineWriter, RuleValues ruleValues) {
		this.ruleValues = ruleValues;
		this.prefix = lineWriter.prefix;

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

		// Preparatory work.
		computeUsedSpans(line);

		// All the span which do not fit on one line.
		RedBlackTree!Span brokenSpans;

		uint length = 0;
		uint previousColumn = 0;
		Span previousSpan = null;
		size_t regionStart = 0;

		const indentationSize = writer.config.indentationSize;
		const pageWidth = writer.config.pageWidth;

		foreach (i, ref c; line) {
			uint lineLength = 0;
			uint column = 0;

			if (c.startsRegion) {
				regionStart = i;
			}

			if (c.kind == ChunkKind.Block) {
				auto f = writer.formatBlock(c.chunks, getLinePrefix(line, i));

				// Compute the column at which the block starts.
				auto text = f.text;

				foreach (n; 0 .. f.text.length) {
					if (text[n] == ' ') {
						column++;
						continue;
					}

					if (text[n] == '\t') {
						column += indentationSize;
						continue;
					}

					break;
				}

				cost += f.cost;
				overflow += f.overflow;
				updateSunk(line, i);
			} else {
				if (newLineCount(line, i) == 0) {
					length += (c.separator == Separator.Space) + c.length;
					continue;
				}

				column = 0;
				lineLength = c.length;

				if (!c.glued) {
					const prefix = getLinePrefix(line, i);
					column = prefix.indent * indentationSize + prefix.offset;
				}
			}

			if (i > 0) {
				// Try to avoid subsequent line to have the same indentation
				// level if they belong to a different span.
				uint penality = computeNewLinePenality(
					c, column, length, previousColumn, previousSpan);

				// End the previous line if there is one.
				endLine(line, i, length, pageWidth, penality);
			}

			previousSpan = c.span;
			previousColumn = column;
			length = column + lineLength;

			// If we do not plan to expand, freeze previous regions.
			if (!canExpand && regionStart > ruleValues.frozen) {
				ruleValues.frozen = regionStart;
			}

			if (c.continuation) {
				continue;
			}

			cost += 1;

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

		endLine(line, line.length, length, pageWidth);

		// Account for the cost of breaking spans.
		if (brokenSpans !is null) {
			foreach (s; brokenSpans) {
				cost += s.getCost(this);
			}
		}
	}

	void computeUsedSpans(Chunk[] line) {
		auto freezePoint = ruleValues.frozen;
		ruleValues.frozen = 1;

		scope(success) {
			ruleValues.frozen = freezePoint;
		}

		foreach (i, ref c; line) {
			// Continuation are not considered line splits.
			if (c.continuation) {
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
	}

	uint computeNewLinePenality(
		const ref Chunk c,
		uint column,
		uint length,
		uint previousColumn,
		const(Span) previousSpan
	) const {
		// No penality for top level.
		if (column == 0) {
			return 0;
		}

		// Avoid line break that make the next lien starts past the previous line.
		if (column >= length && c.kind != ChunkKind.Block) {
			return 1;
		}

		// No penality for mismatching levels.
		if (column != previousColumn) {
			return 0;
		}

		// No penality for double line breaks.
		if (c.separator == Separator.TwoNewLines) {
			return 0;
		}

		// If both spans are expected to be on the same level,
		// then it's all good.
		if (previousSpan.isSameLevel(c.span)) {
			return 0;
		}

		// This new line is at the same level as the previous line, yet belong to another span.
		// This tends to make the code confusing to read, so we penalize this solution.
		return 1;
	}

	void updateSunk(const Chunk[] line, size_t i) {
		if (canExpand) {
			return;
		}

		foreach (j; ruleValues.frozen .. i) {
			if (canSplit(line, j)) {
				canExpand = true;
				return;
			}
		}

		// If the line overflow, but has no split point, it is sunk.
		sunk = overflow;
	}

	void endLine(const Chunk[] line, size_t i, uint length, uint pageWidth,
	             uint penality = 0) {
		if (length > pageWidth) {
			penality += length - pageWidth;
		}

		if (penality > 0) {
			overflow += penality;
			updateSunk(line, i);
		}
	}

	bool canSplit(const Chunk[] line, size_t i) const {
		if (isSplit(i)) {
			return false;
		}

		auto c = line[i];
		if (!c.canSplit()) {
			return false;
		}

		return c.span.canSplit(this, i);
	}

	bool mustSplit(const Chunk[] line, size_t i) const {
		auto c = line[i];
		return c.newLineCount() > 0 || c.span.mustSplit(this, i);
	}

	bool isSplit(size_t i) const {
		return ruleValues[i];
	}

	uint newLineCount(const Chunk[] line, size_t i) const {
		if (auto c = line[i].newLineCount()) {
			return c;
		}

		return isSplit(i);
	}

	bool isUsed(const Span span) const {
		return usedSpans !is null && span in usedSpans;
	}

	LinePrefix getLinePrefix(Chunk[] line, size_t i) const {
		uint offset = 0;
		const c = line[i];

		// Find the preceding line break.
		size_t r = c.span.getAlignIndex(this, i);
		while (r > 0 && newLineCount(line, r) == 0) {
			offset += line[r].separator == Separator.Space;
			offset += line[--r].length;
		}

		if (line[r].glued) {
			return LinePrefix(0, offset);
		}

		if (r == 0 || r == i) {
			// We don't need to do any alignement magic.
			const indent = c.indentation + c.span.getIndent(this, i);
			return LinePrefix(prefix.indent + indent, prefix.offset + offset);
		}

		const base = getLinePrefix(line, r);
		const indent = line[i].span.getExtraIndent(line[r].span, this, i);

		return LinePrefix(base.indent + indent, base.offset + offset);
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
		if (overflow != rhs.overflow) {
			return overflow < rhs.overflow;
		}

		if (cost != rhs.cost) {
			return cost < rhs.cost;
		}

		return ruleValues < rhs.ruleValues;
	}

	// lhs < rhs => lhs.opCmp(rhs) < 0
	int opCmp(const ref SolveState rhs) const {
		if (sunk != rhs.sunk) {
			return sunk - rhs.sunk;
		}

		if (cost != rhs.cost) {
			return cost - rhs.cost;
		}

		if (overflow != rhs.overflow) {
			return overflow - rhs.overflow;
		}

		return ruleValues.opCmp(rhs.ruleValues);
	}

	int opCmp(const SolveState* rhs) const {
		if (rhs is null) {
			return -1;
		}

		return this.opCmp(*rhs);
	}
}
