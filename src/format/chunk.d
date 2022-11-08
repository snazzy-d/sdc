module format.chunk;

enum ChunkKind {
	Text,
	Block,
}

enum Separator {
	None,
	Space,
	NewLine,
	TwoNewLines,
}

struct Chunk {
private:
	import util.bitfields, std.typetuple;
	alias FieldsTuple = TypeTuple!(
		// sdfmt off
		ChunkKind, "_kind", EnumSize!ChunkKind,
		Separator, "_separator", EnumSize!Separator,
		// Emit chunks one after the other,
		// without adding extra padding or indentation.
		bool, "_glued", 1,
		// Consider this chunk as a continuation of the previous one.
		// New lines won't be considered as split.
		bool, "_continuation", 1,
		// Consider this chunk a natural break.
		// No penality is imposed when the line started here
		// starts past the previous line.
		bool, "_naturalBreak", 1,
		// What is the base indentation level for this chunk.
		// This becomes irrelevent when the chunk is glued.
		uint, "_indentation", 10,
		// This marks the boundary between unwrapped lines.
		// Each unwrapped line can be formatted completely
		// independently of other unwrapped lines.
		bool, "_startsUnwrappedLine", 1,
		// This marks the boundary between regions.
		// The effect of formatting rtules are bounded by region
		// so the writer can use this to detect redundant paths.
		bool, "_startsRegion", 1,
		// The length of the line in graphemes.
		uint, "_length", 16,
		// sdfmt on
	);

	enum Pad = ulong.sizeof * 8 - SizeOfBitField!FieldsTuple;

	import std.bitmanip;
	mixin(bitfields!(FieldsTuple, ulong, "", Pad));

	import format.span;
	Span _span = null;

	union {
		string _text;
		Chunk[] _chunks;
	}

public:
	@property
	ChunkKind kind() const {
		return _kind;
	}

	@property
	Separator separator() const {
		return _separator;
	}

	@property
	uint newLineCount() const {
		return (separator >= Separator.NewLine)
			+ (separator == Separator.TwoNewLines);
	}

	@property
	bool glued() const {
		return _glued;
	}

	@property
	bool continuation() const {
		return _continuation;
	}

	bool canSplit() const {
		return !glued && !continuation;
	}

	@property
	bool naturalBreak() const {
		return _naturalBreak;
	}

	@property
	bool startsUnwrappedLine() const {
		return _startsUnwrappedLine;
	}

	@property
	bool startsRegion() const {
		return _startsRegion;
	}

	@property
	uint indentation() const {
		return _indentation;
	}

	@property
	uint length() const {
		return _length;
	}

	@property
	inout(Span) span() inout {
		return _span;
	}

	bool contains(const Span s) const {
		return span.contains(s);
	}

	@property
	bool empty() const {
		return kind ? chunks.length == 0 : text.length == 0;
	}

	@property
	ref inout(string) text() inout in(kind == ChunkKind.Text) {
		return _text;
	}

	@property
	ref inout(Chunk[]) chunks() inout in(kind == ChunkKind.Block) {
		return _chunks;
	}

	string toString() const {
		import std.conv;
		return "Chunk(" ~ separator.to!string
			~ ", " /* ~ Span.print(span) ~ ", " */
			~ glued.to!string ~ ", " ~ continuation.to!string ~ ", "
			~ indentation.to!string ~ ", " ~ length.to!string ~ ", "
			~ (kind ? chunks.to!string : [text].to!string) ~ ")";
	}
}

struct Builder {
private:
	Chunk chunk;
	Chunk[] source;

	Separator pendingSeparator = Separator.None;
	uint indentation;

	import format.span;
	Span spanStack = null;
	size_t spliceIndex = 0;

	struct Fixup {
		size_t index;
		Span span;
		void function(Span span, size_t i) fun;

		void fix(const ref Chunk c, size_t pre, size_t post) {
			fun(span, c.contains(span) ? pre : post);
		}
	}

	Fixup[] fixups;

public:
	Chunk[] build() {
		split();

		size_t start = 0;
		size_t fi = 0;

		// Make sure we consumed all fixups by the end of the process.
		scope(success) {
			assert(fi == fixups.length);
		}

		Span previousTop = null;

		foreach (i, ref c; source) {
			auto top = c.span.getTop();

			// If we have a new set of spans, then we have a new region.
			c._startsRegion = top is null || top !is previousTop;

			// Bucket brigade.
			previousTop = top;

			size_t indexInLine = i - start;

			scope(success) {
				// Run fixups that the parser may have registered.
				while (fi < fixups.length && fixups[fi].index == i) {
					fixups[fi++].fix(c, i - start, indexInLine);
				}
			}

			// If this is not a new region, this is not an unwrapped line break.
			if (!c.startsRegion) {
				continue;
			}

			// If this is glued, this is not an unwrapped line break.
			if (c.glued) {
				continue;
			}

			if (top !is null) {
				continue;
			}

			// If this is not a line break, this is not an unwrapped line break.
			if (i > 0 && c.newLineCount() == 0) {
				continue;
			}

			// This is a line break with no span in common.
			c._startsUnwrappedLine = true;
			start = i;
		}

		// Make sure we process any stragglers.
		size_t indexInLine = source.length - start;
		while (fi < fixups.length && fixups[fi].index == source.length) {
			fixups[fi++].fix(chunk, indexInLine, indexInLine);
		}

		return source;
	}

	/**
	 * Write into the next chunk.
	 */
	void write(string s) {
		emitPendingSeparator();

		if (s.length == 0) {
			return;
		}

		if (pendingSeparator == Separator.Space) {
			chunk.text ~= ' ';
			pendingSeparator = Separator.None;
		}

		import std.stdio;
		// writeln("write: ", [s]);
		chunk.text ~= s;
	}

	void space() {
		import std.stdio;
		// writeln("space!");
		setSeparator(Separator.Space);
	}

	void newline(int nLines = 1) {
		import std.stdio;
		// writeln("newline ", nLines);
		setSeparator(nLines > 1 ? Separator.TwoNewLines : Separator.NewLine);
	}

	void clearSeparator() {
		import std.stdio;
		// writeln("clearSeparator!");
		pendingSeparator = Separator.None;
	}

	void split(bool glued = false, bool continuation = false,
	           bool naturalBreak = false) {
		import std.stdio;

		// writeln("split!", glued ? " glued" : "", continuation ? " continuation" : "");

		scope(success) {
			chunk._span = spanStack;
			chunk._glued = glued;
			chunk._continuation = continuation;
			chunk._naturalBreak = naturalBreak;

			emitPendingSeparator();
		}

		// There is nothing to flush.
		if (chunk.empty) {
			if (chunk.newLineCount == 0) {
				// Fuse the chunk if it doesn't start a new line.
				return;
			}

			if (!continuation || !chunk.continuation) {
				// Only fuse if one of the chunks is not a continuation.
				// FIXME: This overfuse in the following case:
				//   newline, continuation = false, test = ""
				//   split(continuation : true)
				// Unfortunately, this erroneous behavior is relied upon,
				// so it'll have to stay for now.
				return;
			}
		}

		if (chunk.kind == ChunkKind.Text) {
			import std.uni, std.utf, std.range;
			chunk._length =
				cast(uint) chunk.text.byDchar.byGrapheme.walkLength();
		}

		source ~= chunk;
		chunk = Chunk();
	}

	/**
	 * Indentation and alignement.
	 */
	auto indent(uint level = 1) {
		emitPendingSeparator();

		static struct Guard {
			~this() {
				builder.indentation = oldLevel;
				builder.emitPendingSeparator();
			}

		private:
			Builder* builder;
			uint oldLevel;
		}

		uint oldLevel = indentation;
		indentation += level;

		return Guard(&this, oldLevel);
	}

	auto unindent(uint level = 1) {
		import std.algorithm;
		level = min(level, indentation);
		return indent(-level);
	}

	/**
	 * Span management.
	 */
	auto span(S = Span, T...)(T args) {
		emitPendingSeparator();

		static struct Guard {
			this(Builder* builder, S span) {
				this.builder = builder;
				this.span = span;
				this.spliceIndex = builder.source.length;
				builder.spanStack = span;
			}

			~this() {
				assert(builder.spanStack is span);
				builder.spanStack = span.parent;
				builder.spliceIndex = spliceIndex;

				if (builder.chunk.empty) {
					// Make sure we get the proper span.
					builder.chunk._span = span.parent;
				}
			}

			void registerFix(void function(S s, size_t i) fix) {
				builder.fixups ~= Fixup(
					builder.source.length,
					span,
					// Fixup is not templated, so we need to give it the type
					// it expects. The compiler cannot verify this for us, but we
					// know it is always called with the supplied span as argument,
					// which we know have the right type.
					cast(void function(Span span, ulong i)) fix
				);
			}

		private:
			Builder* builder;
			S span;
			size_t spliceIndex;
		}

		return Guard(&this, new S(spanStack, args));
	}

	auto virtualSpan() {
		emitPendingSeparator();

		static struct Guard {
			this(Builder* builder) {
				this.builder = builder;
				this.spliceIndex = builder.source.length;
			}

			~this() {
				builder.spliceIndex = spliceIndex;
			}

		private:
			Builder* builder;
			size_t spliceIndex;
		}

		return Guard(&this);
	}

	auto spliceSpan(S = Span, T...)(T args) {
		Span parent = spanStack;
		auto guard = span!S(args);

		Span span = guard.span;
		Span previous = parent;

		import std.range;
		foreach (ref c; source[spliceIndex .. $].chain(only(chunk)).retro()) {
			Span current = c.span;
			scope(success) {
				previous = current;
			}

			if (current is parent) {
				c._span = span;
				continue;
			}

			if (current is previous) {
				// We already handled this.
				continue;
			}

			Span insert = current;
			while (insert !is null && insert.parent !is parent) {
				insert = insert.parent;
			}

			if (insert is null) {
				// We reached the end of the parent span.
				break;
			}

			if (insert !is span) {
				insert.parent = span;
			}
		}

		return guard;
	}

	/**
	 * Block management.
	 */
	auto block() {
		static doNoting() {}
		return block!doNoting();
	}

	auto block(alias onClose, T...)(T args) {
		// We delegate indentation to the block itself.
		emitPendingSeparator();

		// We delegate indentation to the block itself.
		split(true, true, true);

		static struct Guard {
			~this() {
				auto chunk = outerBuilder.chunk;
				chunk._kind = ChunkKind.Block;
				chunk.chunks = builder.build();

				// Restore the outer builder.
				*builder = outerBuilder;
				builder.chunk = chunk;

				onClose(args);
				builder.split(false, true);
			}

		private:
			Builder* builder;
			Builder outerBuilder;

			T args;
		}

		auto guard = Guard(&this, this, args);

		// Get ready to build the block.
		this = Builder();

		return guard;
	}

private:
	void setSeparator(Separator s) {
		import std.algorithm;
		pendingSeparator = max(pendingSeparator, s);
	}

	void emitPendingSeparator() {
		if (chunk.empty) {
			import std.algorithm;
			chunk._separator = max(chunk.separator, pendingSeparator);
			pendingSeparator = Separator.None;

			// Indentation is part of the separator.
			chunk._indentation = indentation;

			return;
		}

		if (pendingSeparator >= Separator.NewLine) {
			split();
		}
	}
}
