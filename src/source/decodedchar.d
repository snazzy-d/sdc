module source.decodedchar;

struct DecodedChar {
private:
	uint content;

public:
	import std.utf;
	this(dchar c) in(isValidDchar(c)) {
		content = c;
	}

	this(char c) {
		content = 0x7fffff00 | c;
	}

	@property
	bool isRaw() const {
		return (content | 0x7fffff00) == content;
	}

	@property
	bool isChar() const {
		return isRaw || content < 0x80;
	}

	@property
	char asChar() const in(isChar) {
		return char(content & 0xff);
	}

	@property
	dchar asDchar() const in(!isRaw) {
		return cast(dchar) content;
	}

	@property
	uint asIntegral() const {
		return isRaw ? asChar : content;
	}

	string appendTo(string s) const {
		if (isChar) {
			s ~= asChar;
			return s;
		}

		char[4] buf;

		import std.utf;
		auto i = encode(buf, asDchar);
		s ~= buf[0 .. i];

		return s;
	}
}
