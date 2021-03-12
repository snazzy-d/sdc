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
	import util.bitfields;
	import std.typetuple;
	alias FieldsTuple = TypeTuple!(
		ChunkKind, "_kind", EnumSize!ChunkKind,
		SplitType, "_splitType", EnumSize!SplitType,
		uint, "_indentation", 10,
	);

	enum Pad = ulong.sizeof * 8 - SizeOfBitField!FieldsTuple;
	
	import std.bitmanip;
	mixin(bitfields!(FieldsTuple, ulong, "", Pad));
	
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
	
	@property
	SplitType splitType(SplitType st) {
		_splitType = st;
		return splitType;
	}
	
	@property
	uint indentation() const {
		return _indentation;
	}
	
	@property
	uint indentation(uint i) {
		_indentation = i;
		return i;
	}
	
	@property
	bool empty() const {
		return kind ? chunks.length == 0 : text.length == 0;
	}
	
	@property
	ref inout(string) text() inout in {
		assert(kind == ChunkKind.Text);
	} body {
		return _text;
	}
	
	@property
	const(Chunk)[] chunks() const in {
		assert(kind == ChunkKind.Block);
	} body {
		return _chunks;
	}
	
	string toString() const {
		import std.conv;
		return "Chunk(" ~ splitType.to!string ~ ", "
			~ indentation.to!string ~ ", "
			~ (kind ? chunks.to!string : [text].to!string) ~ ")";
	}
}

struct Builder {
public:
	Chunk chunk;
	Chunk[] source;
	
	SplitType pendingWhiteSpace = SplitType.None;
	uint indentation;
	
public:
	Chunk[] build() {
		split();
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
		setWhiteSpace(SplitType.Space);
	}
	
	void forceSpace() {
		pendingWhiteSpace = SplitType.Space;
	}
	
	void newline(int nLines = 1) {
		setWhiteSpace(nLines > 1 ? SplitType.TwoNewLines : SplitType.NewLine);
	}
	
	void forceNewLine(int nLines = 1) {
		pendingWhiteSpace = nLines > 1 ? SplitType.TwoNewLines : SplitType.NewLine;
	}
	
	void split() {
		scope(success) {
			chunk.indentation = indentation;
		}
		
		// There is nothing to flush.
		if (chunk.empty) {
			return;
		}
		
		source ~= chunk;
		chunk = Chunk();
		
		// TODO: Process rules.
	}
	
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
		
		// Make sure we don't overflow.
		if (int(indentation) < 0) {
			indentation = 0;
		}
		
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
	void startSpan() {
		import std.stdio;
		// writeln("startSpan");
	}
	
	void endSpan() {
		import std.stdio;
		// writeln("endSpan");
	}

private:
	void setWhiteSpace(SplitType st) {
		import std.algorithm;
		pendingWhiteSpace = max(pendingWhiteSpace, st);
	}
	
	void emitPendingWhiteSpace() {
		scope(success) {
			import std.algorithm;
			chunk.splitType = max(chunk.splitType, pendingWhiteSpace);
			
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
