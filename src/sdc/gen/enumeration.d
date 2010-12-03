/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
 module sdc.gen.enumeration;

import sdc.util;
import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.base;

void genEnumDeclaration(ast.EnumDeclaration decl, Module mod)
{	
	if (decl.name !is null) {
		Type base;
		if (decl.base is null) {
			base = new IntType(mod);
		} else {
			base = astTypeToBackendType(decl.base, mod, OnFailure.DieWithError);
		}
		
		auto type = new EnumType(mod, base);
		type.fullName = mod.name.dup;
		type.fullName.identifiers ~= decl.name;
		
		auto name = extractIdentifier(decl.name);
		mod.currentScope.add(name, new Store(type));
		
		
    } else {
		throw new CompilerPanic(decl.location, "anonymous enums are unimplemented.");
    }
}
