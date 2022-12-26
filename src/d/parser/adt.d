module d.parser.adt;

import d.parser.base;
import d.parser.declaration;
import d.parser.dtemplate;
import d.parser.expression;
import d.parser.identifier;
import d.parser.type;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

/**
 * Parse class
 */
auto parseClass(ref TokenRange trange, StorageClass stc) {
	return trange.parsePolymorphic!true(stc);
}

/**
 * Parse interface
 */
auto parseInterface(ref TokenRange trange, StorageClass stc) {
	return trange.parsePolymorphic!false(stc);
}

private Declaration parsePolymorphic(bool isClass = true)(ref TokenRange trange,
                                                          StorageClass stc) {
	Location location = trange.front.location;

	static if (isClass) {
		trange.match(TokenType.Class);
		alias DeclarationType = ClassDeclaration;
	} else {
		trange.match(TokenType.Interface);
		alias DeclarationType = InterfaceDeclaration;
	}

	import source.name;
	Name name;
	AstTemplateParameter[] parameters;
	bool isTemplate = false;

	if (trange.front.type == TokenType.Identifier) {
		name = trange.front.name;
		trange.match(TokenType.Identifier);

		isTemplate = trange.front.type == TokenType.OpenParen;
		if (isTemplate) {
			parameters = trange.parseTemplateParameters();
		}
	}

	Identifier[] bases;
	if (trange.front.type == TokenType.Colon) {
		do {
			trange.popFront();
			bases ~= trange.parseIdentifier();
		} while (trange.front.type == TokenType.Comma);
	}

	if (isTemplate && trange.front.type == TokenType.If) {
		trange.parseConstraint();
	}

	auto members = trange.parseAggregate();
	location = location.spanTo(trange.previous);
	auto adt = new DeclarationType(location, stc, name, bases, members);
	if (!isTemplate) {
		return adt;
	}

	return new TemplateDeclaration(location, stc, name, parameters, [adt]);
}

/**
 * Parse struct
 */
auto parseStruct(ref TokenRange trange, StorageClass stc) {
	return trange.parseMonomorphic!true(stc);
}

/**
 * Parse union
 */
auto parseUnion(ref TokenRange trange, StorageClass stc) {
	return trange.parseMonomorphic!false(stc);
}

private
Declaration parseMonomorphic(bool isStruct = true)(ref TokenRange trange,
                                                   StorageClass stc) {
	Location location = trange.front.location;

	static if (isStruct) {
		trange.match(TokenType.Struct);
		alias DeclarationType = StructDeclaration;
	} else {
		trange.match(TokenType.Union);
		alias DeclarationType = UnionDeclaration;
	}

	import source.name;
	Name name;
	AstTemplateParameter[] parameters;
	bool isTemplate = false;

	if (trange.front.type == TokenType.Identifier) {
		name = trange.front.name;
		trange.popFront();

		switch (trange.front.type) with (TokenType) {
			// Handle opaque declarations.
			case Semicolon:
				trange.popFront();
				location = location.spanTo(trange.previous);

				assert(0, "Opaque declaration aren't supported.");

			// Template structs
			case OpenParen:
				isTemplate = true;
				parameters = trange.parseTemplateParameters();

				if (trange.front.type == If) {
					trange.parseConstraint();
				}

				break;

			default:
				break;
		}
	}

	auto members = trange.parseAggregate();

	location = location.spanTo(trange.previous);

	auto adt = new DeclarationType(location, stc, name, members);
	if (!isTemplate) {
		return adt;
	}

	return new TemplateDeclaration(location, stc, name, parameters, [adt]);
}

/**
 * Parse enums
 */
Declaration parseEnum(ref TokenRange trange, StorageClass stc)
		in(stc.isEnum == true) {
	Location location = trange.front.location;
	trange.match(TokenType.Enum);

	import source.name;
	Name name;
	AstType type = AstType.getAuto();

	switch (trange.front.type) with (TokenType) {
		case Identifier:
			name = trange.front.name;
			trange.popFront();

			// Ensure we are not in case of manifest constant.
			assert(
				trange.front.type != Equal,
				"Manifest constant must be parsed as auto declaration and not as enums."
			);

			// If we have a colon, we go to the apropriate case.
			if (trange.front.type == Colon) {
				goto case Colon;
			}

			// If not, then it is time to parse the enum content.
			goto case OpenBrace;

		case Colon:
			trange.popFront();
			type = trange.parseType();

			break;

		case OpenBrace:
			break;

		default:
			throw unexpectedTokenError(trange, "an identifier, `:` or `{`");
	}

	trange.match(TokenType.OpenBrace);
	VariableDeclaration[] enumEntries;

	while (trange.front.type != TokenType.CloseBrace) {
		auto entryName = trange.front.name;
		auto entryLocation = trange.front.location;

		trange.match(TokenType.Identifier);

		AstExpression entryValue;
		if (trange.front.type == TokenType.Equal) {
			trange.popFront();
			entryValue = trange.parseAssignExpression();
		}

		enumEntries ~=
			new VariableDeclaration(entryLocation.spanTo(trange.previous), stc,
			                        type, entryName, entryValue);

		// If it is not a comma, then we abort the loop.
		if (!trange.popOnMatch(TokenType.Comma)) {
			break;
		}
	}

	trange.match(TokenType.CloseBrace);
	return new EnumDeclaration(location.spanTo(trange.previous), stc, name,
	                           type, enumEntries);
}
