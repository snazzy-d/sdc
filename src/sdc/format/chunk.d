module sdc.format.chunk;

enum SplitType {
	None,
	Space,
	NewLine,
	TwoNewLines,
}

enum ChunkKind {
	Text,
	Block,
}

struct Chunk {
private:
	import util.bitfields, std.typetuple;
	alias FieldsTuple = TypeTuple!(
		// sdfmt off
		ChunkKind, "_kind", EnumSize!ChunkKind,
		SplitType, "_splitType", EnumSize!SplitType,
		bool, "_startsUnwrappedLine", 1,
		uint, "_indentation", 10,
		uint, "_length", 16,
		uint, "_splitIndex", 16,
		// sdfmt on
	);
	
	enum Pad = ulong.sizeof * 8 - SizeOfBitField!FieldsTuple;
	
	import std.bitmanip;
	mixin(bitfields!(FieldsTuple, ulong, "", Pad));
	
	import sdc.format.span;
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
	SplitType splitType() const {
		return _splitType;
	}
	
	bool mustSplit() const {
		return splitType == SplitType.TwoNewLines
			|| splitType == SplitType.NewLine;
	}
	
	@property
	bool startsUnwrappedLine() const {
		return _startsUnwrappedLine;
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
	uint splitIndex() const {
		return _splitIndex;
	}
	
	@property
	inout(Span) span() inout {
		return _span;
	}
	
	@property
	bool empty() const {
		return kind ? chunks.length == 0 : text.length == 0;
	}
	
	@property
	ref inout(string) text() inout in {
		assert(kind == ChunkKind.Text);
	} do {
		return _text;
	}
	
	@property
	ref inout(Chunk[]) chunks() inout in {
		assert(kind == ChunkKind.Block);
	} do {
		return _chunks;
	}
	
	string toString() const {
		import std.conv;
		return "Chunk(" ~ splitType.to!string ~ ", "
			~ Span.print(span) ~ ", "
			~ indentation.to!string ~ ", "
			~ length.to!string ~ ", "
			~ splitIndex.to!string ~ ", "
			~ (kind ? chunks.to!string : [text].to!string) ~ ")";
	}
}

struct Builder {
private:
	Chunk chunk;
	Chunk[] source;
	
	SplitType pendingWhiteSpace = SplitType.None;
	uint indentation;
	
	import sdc.format.span;
	Span spanStack = null;
	
public:
	Chunk[] build() {
		split();
		
		size_t start = 0;
		foreach (i, ref c; source) {
			scope(success) {
				// Make sure we let the spans know where they are in the line.
				c.span.register(i - start);
			}
			
			if (i == 0) {
				// The first chunk obviously starts a new line.
				goto FoundLineBreak;
			}
			
			// This is not a line break.
			if (c.kind != ChunkKind.Block && !c.mustSplit()) {
				continue;
			}
			
			// Check if these two have a span in common.
			{
				auto top = c.span.getTop();
				if (top !is null && top is source[i].span.getTop()) {
					continue;
				}
			}
			
		FoundLineBreak:
			// This is a line break with no span in common.
			c._startsUnwrappedLine = true;
			start = i;
		}
		
		return source;
	}
	
	/**
	 * Write into the next chunk.
	 */
	void write(string s) {
		emitPendingWhiteSpace();
		
		import std.stdio;
		// writeln("write: ", [s]);
		chunk.text ~= s;
	}
	
	void space() {
		import std.stdio;
		// writeln("space!");
		setWhiteSpace(SplitType.Space);
	}
	
	void newline(int nLines = 1) {
		import std.stdio;
		// writeln("newline ", nLines);
		setWhiteSpace(nLines > 1 ? SplitType.TwoNewLines : SplitType.NewLine);
	}
	
	void clearSplitType() {
		import std.stdio;
		// writeln("clearSplitType!");
		pendingWhiteSpace = SplitType.None;
	}
	
	auto split() {
		import std.stdio;
		// writeln("split!");
		
		scope(success) {
			chunk._indentation = indentation;
			chunk._span = spanStack;
		}
		
		uint nlCount = 0;
		
		size_t last = chunk.text.length;
		while (last > 0) {
			char lastChar = chunk.text[last - 1];
			
			import std.ascii;
			if (!isWhite(lastChar)) {
				break;
			}
			
			last--;
			if (lastChar == ' ') {
				space();
			}
			
			if (lastChar == '\n') {
				nlCount++;
			}
		}
		
		if (nlCount) {
			newline(nlCount);
		}
		
		chunk.text = chunk.text[0 .. last];
		
		// There is nothing to flush.
		if (chunk.empty) {
			return cast(uint) source.length;
		}
		
		import std.uni, std.range;
		chunk._length = cast(uint) chunk.text.byGrapheme.walkLength();
		
		source ~= chunk;
		chunk = Chunk();
		
		return cast(uint) source.length;
	}
	
	void setSplitIndex(uint index) in {
		assert(index <= source.length, "Invalid split index");
	} do {
		chunk._splitIndex = cast(uint) (source.length - index);
	}
	
	/**
	 * Indentation and alignement.
	 */
	auto indent(uint level = 1) {
		static struct Guard {
			~this() {
				builder.indentation = oldLevel;
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
	auto span(S = Span)() {
		emitPendingWhiteSpace();
		
		static struct Guard {
			~this() {
				assert(builder.spanStack is span);
				builder.spanStack = span.parent;
			}
			
		private:
			Builder* builder;
			Span span;
		}
		
		spanStack = new S(spanStack);
		return Guard(&this, spanStack);
	}
	
	bool spliceSpan() {
		Span parent = spanStack.parent;
		Span insert;
		
		import std.range;
		foreach (ref c; only(chunk).chain(source.retro())) {
			if (c.span !is parent) {
				insert = c.span;
				break;
			}
			
			c._span = spanStack;
		}
		
		while (insert !is null && insert.parent !is parent) {
			insert = insert.parent;
		}
		
		bool doSlice = insert !is null && insert !is spanStack;
		if (doSlice) {
			insert.parent = spanStack;
		}
		
		return doSlice;
	}
	
	/**
	 * Block management.
	 */
	auto block() {
		split();
		emitPendingWhiteSpace();
		
		static struct Guard {
			~this() {
				auto chunk = outerBuilder.chunk;
				chunk._kind = ChunkKind.Block;
				chunk.chunks = builder.build();
				outerBuilder.source ~= chunk;
				
				// Restore the outer builder.
				*builder = outerBuilder;
			}
			
		private:
			Builder* builder;
			Builder outerBuilder;
		}
		
		auto guard = Guard(&this, this);
		
		// Get ready to buidl the block.
		source = [];
		chunk = Chunk();
		
		pendingWhiteSpace = SplitType.None;
		indentation = 0;
		spanStack = null;
		
		return guard;
	}
	
private:
	void setWhiteSpace(SplitType st) {
		import std.algorithm;
		pendingWhiteSpace = max(pendingWhiteSpace, st);
	}
	
	void emitPendingWhiteSpace() {
		scope(success) {
			import std.algorithm;
			chunk._splitType = max(chunk.splitType, pendingWhiteSpace);
			
			pendingWhiteSpace = SplitType.None;
		}
		
		final switch (pendingWhiteSpace) with (SplitType) {
			case None:
				// nothing to do.
				return;
			
			case Space:
				if (!chunk.empty) {
					chunk.text ~= ' ';
					pendingWhiteSpace = SplitType.None;
				}
				return;
			
			case NewLine, TwoNewLines:
				split();
		}
	}
}
