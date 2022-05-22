module d.ir.instruction;

import source.context;
import source.location;
import source.name;

import d.ir.expression;
import d.ir.symbol;

struct Body {
private:
	BasicBlock[] basicBlocks;

public:
	ref inout(BasicBlock) opIndex(BasicBlockRef i) inout in {
		assert(i, "null block ref");
		assert(i.index <= basicBlocks.length, "Out of bounds block ref");
	} do {
		return basicBlocks.ptr[i.index - 1];
	}

	bool opCast(T : bool)() const {
		return basicBlocks.length > 0;
	}

	@property
	auto length() const {
		return basicBlocks.length;
	}

	// XXX: Required due to conversion rules.
	BasicBlockRef newBasicBlock(Name name) {
		BasicBlockRef landingpad;
		return newBasicBlock(name, landingpad);
	}

	BasicBlockRef newBasicBlock(Name name, BasicBlockRef landingpad) {
		auto i = cast(uint) basicBlocks.length;
		auto bbref = BasicBlockRef(i);
		// XXX: We can't happend because it is non copyable (DMD bug, IMO).
		// basicBlocks ~= BasicBlock(bbref);
		basicBlocks.length += 1;
		basicBlocks[i] = BasicBlock(name, landingpad);
		return bbref;
	}

	void dump(const Context c) const {
		foreach (ref b; basicBlocks) {
			dump(c, b);
		}
	}

	void dump(const Context c, const ref BasicBlock b) const {
		import std.stdio;
		writeln();
		dumpBasicBlockName(c, b);
		write(':');

		if (b.landingpad) {
			import std.stdio;
			write("\t\t\t\tunwind to ");
			dumpBasicBlockName(c, this[b.landingpad]);
		}

		writeln();

		foreach (ref i; b.instructions) {
			dump(c, b, i);
		}

		final switch (b.terminator) with (Terminator) {
			case None:
				writeln("unterminated...");
				break;

			case Branch:
				write("\tbranch ");
				if (b.value is null) {
					dumpBasicBlockName(c, this[b.successors[0]]);
				} else {
					write(b.value.toString(c), ", ");
					dumpBasicBlockName(c, this[b.successors[0]]);
					write(", ");
					dumpBasicBlockName(c, this[b.successors[1]]);
				}

				writeln();
				break;

			case Switch:
				writeln("\tswitch ", b.value.toString(c));
				write("\t\tdefault: ");
				dumpBasicBlockName(c, this[b.switchTable.defaultBlock]);
				foreach (ce; b.switchTable.cases) {
					write("\n\t\tcase ", ce.value, ": ");
					dumpBasicBlockName(c, this[ce.block]);
				}

				writeln();
				break;

			case Return:
				writeln("\treturn ", b.value ? b.value.toString(c) : "void");
				break;

			case Throw:
				if (b.value) {
					writeln("\tthrow ", b.value.toString(c));
				} else if (b.catchTable) {
					write("\tcatch");
					foreach (ca; b.catchTable.catches) {
						write("\n\t\t", ca.type.name.toString(c), ": ");
						dumpBasicBlockName(c, this[ca.block]);
					}

					writeln();
				} else {
					writeln("\trethrow");
				}

				break;

			case Halt:
				writeln("\thalt ", b.value ? b.value.toString(c) : "");
				break;
		}
	}

	void dumpBasicBlockName(const Context c, const ref BasicBlock b) const {
		size_t index = (cast(size_t) &b - cast(size_t) basicBlocks.ptr)
			/ BasicBlock.sizeof;

		import std.stdio;
		write(b.name.toString(c), index);
	}

	void dump(const Context c, const ref BasicBlock b,
	          const ref Instruction i) const {
		import std.stdio;
		final switch (i.op) with (OpCode) {
			case Alloca:
				writeln("\t", i.var.toString(c));
				break;

			case Destroy:
				writeln("\tdestroy\t", i.var.name.toString(c));
				break;

			case Evaluate:
				writeln("\t", i.expr.toString(c));
				break;

			case Declare:
				writeln("\t", i.sym.toString(c));
				break;
		}
	}
}

auto range(const Body fbody) {
	import std.algorithm, std.range;
	return iota(0, cast(uint) fbody.basicBlocks.length)
		.map!(i => BasicBlockRef(i));
}

struct BasicBlockRef {
private:
	uint index;

	this(uint index) {
		this.index = index + 1;
	}

public:
	bool opCast(T : bool)() const {
		return index != 0;
	}

	BasicBlockRef opAssign(typeof(null)) {
		index = 0;
		return this;
	}
}

auto range(inout Body fbody, BasicBlockRef b) {
	return fbody[b].instructions;
}

enum Terminator {
	None,
	Branch,
	Switch,
	Return,
	Throw,
	Halt,
}

struct BasicBlock {
private:
	Instruction[] instructions;

	import source.name;
	Name _name;

	Terminator _terminator;
	union {
		public BasicBlockRef[2] successors;
		public SwitchTable* switchTable;
		public CatchTable* catchTable;
	}

	// We need to win a uint in there so that this is 4 pointers sized.
	// We probably won't need more than 4G instructions, so we can win
	// int he instruction array length.
	BasicBlockRef _landingpad;

	// XXX: Let's say I'm not happy with that layout.
	public Location location;
	public Expression value;

	this(Name name, BasicBlockRef landingpad) {
		_name = name;
		_landingpad = landingpad;
	}

	@disable
	this(this);

	void add(Instruction i) in {
		assert(!terminate, "block does terminate already");
	} do {
		instructions ~= i;
	}

public:
	@property
	Name name() const {
		return _name;
	}

	@property
	Terminator terminator() const {
		return _terminator;
	}

	@property
	bool terminate() const {
		return terminator != Terminator.None;
	}

	@property
	bool empty() const {
		return !terminate && instructions.length == 0;
	}

	@property
	BasicBlockRef landingpad() const {
		return _landingpad;
	}

	@property
	BasicBlockRef landingpad(BasicBlockRef landingpad) {
		return _landingpad = landingpad;
	}

	void alloca(Location location, Variable v) {
		add(Instruction(location, v));
	}

	void destroy(Location location, Variable v) {
		add(Instruction.destroy(location, v));
	}

	void eval(Location location, Expression e) {
		add(Instruction(location, e));
	}

	void declare(Location location, Symbol s) {
		add(Instruction(location, s));
	}

	void branch(Location location, BasicBlockRef dst) {
		_terminator = Terminator.Branch;
		successors[0] = dst;
	}

	void branch(Location location, Expression cond, BasicBlockRef ifTrue,
	            BasicBlockRef ifFalse) {
		_terminator = Terminator.Branch;

		// XXX: ALARM! ALARM!
		value = cond;
		successors[0] = ifTrue;
		successors[1] = ifFalse;
	}

	void doSwitch(Location location, Expression e, SwitchTable* switchTable) {
		_terminator = Terminator.Switch;
		this.location = location;
		this.value = e;
		this.switchTable = switchTable;
	}

	void ret(Location location, Expression e = null) {
		_terminator = Terminator.Return;
		this.location = location;
		value = e;
	}

	void doThrow(Location location, Expression e = null) {
		_terminator = Terminator.Throw;
		this.location = location;
		value = e;
	}

	void doCatch(Location location, CatchTable* catchTable) {
		_terminator = Terminator.Throw;
		this.location = location;
		this.catchTable = catchTable;
	}

	void halt(Location location, Expression msg = null) {
		_terminator = Terminator.Halt;
		this.location = location;
		value = msg;
	}
}

enum OpCode {
	Alloca,
	Destroy,
	Evaluate,

	// FIXME: This is unecessary, but will makes things easier for now.
	Declare,
}

struct Instruction {
	Location location;

	OpCode op;

	union {
		Expression expr;
		Variable var;
		Symbol sym;
	}

private:
	this(Location location, Expression e) {
		this.location = location;
		op = OpCode.Evaluate;
		expr = e;
	}

	this(Location location, Variable v) in {
		assert(v.step == Step.Processed, "Variable is not processed");
	} do {
		this.location = location;
		op = OpCode.Alloca;
		var = v;
	}

	static destroy(Location location, Variable v) {
		auto i = Instruction(location, v);
		i.op = OpCode.Destroy;
		return i;
	}

	this(Location location, Symbol s) in {
		assert(s.step == Step.Processed, "Symbol is not processed");
		assert(!cast(Variable) s, "Use alloca for variables");
	} do {
		this.location = location;
		op = OpCode.Declare;
		sym = s;
	}
}

struct SwitchTable {
	BasicBlockRef defaultBlock;
	uint entryCount;

	@property
	inout(CaseEntry)[] cases() inout {
		return (cast(inout(CaseEntry)*) &(&this)[1])[0 .. entryCount];
	}
}

struct CaseEntry {
	BasicBlockRef block;
	uint value;
}

struct CatchTable {
	size_t catchCount;
	BasicBlockRef catchAll;

	@property
	inout(CatchPad)[] catches() inout {
		return (cast(inout(CatchPad)*) &(&this)[1])[0 .. catchCount];
	}
}

struct CatchPad {
	Class type;
	BasicBlockRef block;
}
