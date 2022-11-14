module source.escapesequence;

enum SequenceType {
	Invalid,
	Character,
}

struct EscapeSequence {
private:
	import util.bitfields;
	enum TypeSize = EnumSize!SequenceType;
	enum ExtraBits = 8 * uint.sizeof - TypeSize;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		SequenceType, "_type", TypeSize,
		uint, "_extra", ExtraBits,
		// sdfmt on
	));

	import source.name;
	Name _name;

	union {
		import source.decodedchar;
		DecodedChar _decodedChar;

		import source.location;
		Location _location;
	}

public:
	this(char c) {
		_type = SequenceType.Character;
		_decodedChar = DecodedChar(c);
	}

	this(dchar d) {
		_type = SequenceType.Character;
		_decodedChar = DecodedChar(d);
	}

	static fromError(Location location, Name error) {
		EscapeSequence r;
		r._type = SequenceType.Invalid;
		r._name = error;
		r._location = location;

		return r;
	}

	@property
	auto type() const {
		return _type;
	}

	@property
	auto location() const in(type == SequenceType.Invalid) {
		return _location;
	}

	@property
	auto error() const in(type == SequenceType.Invalid) {
		return _name;
	}

	@property
	auto decodedChar() const in(type == SequenceType.Character) {
		return _decodedChar;
	}

	string appendTo(string s) const in(type != SequenceType.Invalid) {
		return decodedChar.appendTo(s);
	}
}

static assert(EscapeSequence.sizeof == 16);
