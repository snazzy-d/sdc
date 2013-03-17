module d.semantic.symbol;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.dfunction;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import std.algorithm;
import std.array;
import std.conv;

// TODO: change ast to allow any statement as function body, then remove that import.
import d.ast.statement;

final class SymbolVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol visit(Symbol s) {
		auto oldSymbol = symbol;
		scope(exit) symbol = oldSymbol;
		
		symbol = s;
		
		return this.dispatch(s);
	}
	
	Symbol visit(FunctionDeclaration d) {
		// XXX: May yield, but is only resolved within function, so everything depending on this declaration happen after.
		d.parameters = d.parameters.map!(p => pass.scheduler.register(p, this.dispatch(p), Step.Processed)).array();
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		// Compute return type.
		if(typeid({ return d.returnType; }()) !is typeid(AutoType)) {
			d.returnType = pass.visit(d.returnType);
		}
		
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		scope(exit) returnType = oldReturnType;
		
		returnType = d.returnType;
		
		// If it isn't a static method, add this.
		// checking resolvedTypes Ensure that it isn't ran twice.
		if(!d.isStatic) {
			assert(thisType, "function must be static or thisType must be defined.");
			
			auto thisParameter = new Parameter(d.location, "this", thisType);
			thisParameter = pass.scheduler.register(thisParameter, this.dispatch(thisParameter), Step.Processed);
			thisParameter.isReference = isThisRef;
			
			d.parameters = thisParameter ~ d.parameters;
		}
		
		if(d.fbody) {
			auto oldLinkage = linkage;
			scope(exit) linkage = oldLinkage;
			
			linkage = "D";
			
			auto oldIsStatic = isStatic;
			scope(exit) isStatic = oldIsStatic;
			
			isStatic = false;
			
			auto oldBuildFields = buildFields;
			scope(exit) buildFields = oldBuildFields;
			
			buildFields = false;
			
			// Update scope.
			auto oldScope = currentScope;
			scope(exit) currentScope = oldScope;
			
			currentScope = d.dscope;
			
			// And visit.
			// TODO: change ast to allow any statement as function body;
			d.fbody = cast(BlockStatement) pass.visit(d.fbody);
		}
		
		if(typeid({ return d.returnType; }()) is typeid(AutoType)) {
			// Should be useless once return type inference is properly implemented.
			if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
				assert(0, "can't infer return type");
			}
			
			d.returnType = returnType;
		}
		
		d.type = new FunctionType(d.location, d.linkage, d.returnType, d.parameters, d.isVariadic);
		
		auto paramsToMangle = d.isStatic?d.parameters:d.parameters[1 .. $];
		switch(d.linkage) {
			case "D" :
				d.mangle = "_D" ~ manglePrefix ~ (d.isStatic?"F":"FM") ~ paramsToMangle.map!(p => (p.isReference?"K":"") ~ pass.typeMangler.visit(p.type)).join() ~ "Z" ~ typeMangler.visit(d.returnType);
				break;
			
			case "C" :
				d.mangle = d.name;
				break;
			
			default:
				assert(0, "Linkage " ~ d.linkage ~ " is not supported.");
		}
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Parameter visit(Parameter d) {
		d.type = pass.visit(d.type);
		
		return d;
	}
	
	VariableDeclaration visit(VariableDeclaration d) {
		d.value = pass.visit(d.value);
		
		// If the type is infered, then we use the type of the value.
		if(cast(AutoType) d.type) {
			d.type = d.value.type;
		} else {
			d.type = pass.visit(d.type);
		}
		
		d.value = implicitCast(d.location, d.type, d.value);
		
		if(d.isEnum) {
			d.value = evaluate(d.value);
		}
		
		if(d.isStatic) {
			assert(d.linkage == "D");
			d.mangle = "_D" ~ manglePrefix ~ to!string(d.name.length) ~ d.name ~ typeMangler.visit(d.type);
		}
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Symbol visit(FieldDeclaration d) {
		// XXX: hacky !
		auto oldIsEnum = d.isEnum;
		scope(exit) d.isEnum = oldIsEnum;
		
		d.isEnum = true;
		
		return visit(cast(VariableDeclaration) d);
	}
	
	Symbol visit(StructDefinition d) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = false;
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		assert(d.linkage == "D");
		d.mangle = "S" ~ manglePrefix;
		
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope = new SymbolScope(d, oldScope);
		
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(d.location, d);
		
		auto oldIsThisRef = isThisRef;
		scope(exit) isThisRef = oldIsThisRef;
		
		isThisRef = true;
		
		auto oldFieldIndex = fieldIndex;
		scope(exit) fieldIndex = oldFieldIndex;
		
		fieldIndex = 0;
		
		auto oldBuildFields = buildFields;
		scope(exit) buildFields = oldBuildFields;
		
		buildFields = true;
		
		auto members = pass.flatten(d.members, d);
		
		FieldDeclaration[] fields;
		auto otherSymbols = members.filter!((m) {
			if(auto f = cast(FieldDeclaration) m) {
				fields ~= f;
				return false;
			}
			
			return true;
		}).array();
		
		fields = cast(FieldDeclaration[]) scheduler.require(fields);
		
		auto tuple = new TupleExpression(d.location, fields.map!(f => f.value).array());
		tuple.type = thisType;
		
		auto init = new VariableDeclaration(d.location, thisType, "init", tuple);
		init.isStatic = true;
		init.mangle = "_D" ~ manglePrefix ~ to!string(init.name.length) ~ init.name ~ d.mangle;
		
		d.dscope.addSymbol(init);
		scheduler.register(init, init, Step.Processed);
		
		// XXX: big lie :D
		scheduler.register(d, d, Step.Processed);
		
		d.members = cast(Declaration[]) fields ~ cast(Declaration[]) scheduler.require(otherSymbols) ~ init;
		
		return d;
	}
	
	Symbol visit(ClassDefinition d) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = false;
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		assert(d.linkage == "D");
		d.mangle = "C" ~ manglePrefix;
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope = new SymbolScope(d, oldScope);
		
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(d.location, d);
		
		auto oldIsThisRef = isThisRef;
		scope(exit) isThisRef = oldIsThisRef;
		
		isThisRef = false;
		
		auto oldFieldIndex = fieldIndex;
		scope(exit) fieldIndex = oldFieldIndex;
		
		fieldIndex = 0;
		
		auto oldBuildFields = buildFields;
		scope(exit) buildFields = oldBuildFields;
		
		buildFields = true;
		
		auto members = pass.flatten(d.members, d);
		
		// XXX: Not quite right !
		scheduler.register(d, d, Step.Processed);
		
		d.members = cast(Declaration[]) scheduler.require(members);
		
		return d;
	}
	
	Symbol visit(EnumDeclaration d) {
		assert(d.name, "anonymous enums must be flattened !");
		
		auto type = pass.visit(d.type);
		
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = true;
		
		if(auto asEnum = cast(EnumType) type) {
			if(typeid({ return asEnum.type; }()) !is typeid(IntegerType)) {
				assert(0, "enum are of integer type.");
			}
		} else {
			assert(0, "enum must have an enum type !");
		}
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		assert(d.linkage == "D");
		d.mangle = "E" ~ manglePrefix;
		
		VariableDeclaration previous;
		foreach(e; d.enumEntries) {
			e.isEnum = true;
			
			if(typeid({ return e.value; }()) is typeid(DefaultInitializer)) {
				if(previous) {
					e.value = new AddExpression(e.location, new SymbolExpression(e.location, previous), makeLiteral(e.location, 1));
				} else {
					e.value = makeLiteral(e.location, 0);
				}
			}
			
			e.value = new CastExpression(e.location, type, e.value);
			e.type = type;
			
			previous = e;
		}
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope = new SymbolScope(d, oldScope);
		
		foreach(e; d.enumEntries) {
			d.dscope.addSymbol(e);
		}
		
		scheduler.register(d, d, Step.Populated);
		
		scheduler.schedule(d.enumEntries, e => visit(e));
		scheduler.require(d.enumEntries);
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Symbol visit(AliasDeclaration d) {
		d.type = pass.visit(d.type);
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Symbol visit(TemplateDeclaration d) {
		// XXX: compute a proper mangling for templates.
		d.mangle = manglePrefix;
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
}

