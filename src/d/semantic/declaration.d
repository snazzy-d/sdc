module d.semantic.declaration;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.conditional;
import d.ast.dfunction;
import d.ast.declaration;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import std.algorithm;
import std.array;
import std.conv;


// TODO: change ast to allow any statement as function body, then remove that import.
import d.ast.statement;

final class DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol visit(Declaration d) {
		auto oldDeclaration = declaration;
		scope(exit) declaration = oldDeclaration;
		
		declaration = d;
		
		return this.dispatch(d);
	}
	
	// TODO: merge function delcaration and definition.
	Symbol visit(FunctionDeclaration d) {
		// XXX: May yield, but is only resolved within function, so everything depending on this declaration happen after.
		d.parameters = d.parameters.map!(p => pass.scheduler.register(p, this.dispatch(p), Step.Processed)).array();
		
		d.returnType = pass.visit(d.returnType);
		
		d.type = new FunctionType(d.location, d.linkage, d.returnType, d.parameters, d.isVariadic);
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
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
		
		return d;
	}
	
	Symbol visit(FunctionDefinition d) {
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
			auto thisParameter = new Parameter(d.location, "this", thisType);
			thisParameter = pass.scheduler.register(thisParameter, this.dispatch(thisParameter), Step.Processed);
			thisParameter.isReference = true;
			
			d.parameters = thisParameter ~ d.parameters;
		}
		
		{
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
		
		if(d.isEnum) {
			d.value = evaluate(d.value);
		}
		
		d.value = implicitCast(d.location, d.type, d.value);
		
		if(d.isStatic) {
			d.mangle = "_D" ~ manglePrefix ~ to!string(d.name.length) ~ d.name ~ typeMangler.visit(d.type);
		}
		
		return d;
	}
	
	Symbol visit(FieldDeclaration d) {
		// XXX: hacky !
		auto oldIsEnum = d.isEnum;
		scope(exit) d.isEnum = oldIsEnum;
		
		return visit(cast(VariableDeclaration) d);
	}
	
	Symbol visit(StructDefinition d) {
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		d.mangle = "S" ~ manglePrefix;
		
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope;
		
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(d.location, d);
		
		auto fields = cast(FieldDeclaration[]) scheduler.schedule(d.members.filter!(m => typeid(m) is typeid(FieldDeclaration)).array(), m => visit(m));
		
		auto initDecl = cast(VariableDeclaration) d.dscope.resolve("init");
		assert(initDecl);
		
		auto tuple = new TupleExpression(d.location, fields.map!(f => f.value).array());
		tuple.type = thisType;
		
		initDecl.value = tuple;
		initDecl.type = thisType;
		initDecl.mangle = "_D" ~ manglePrefix ~ to!string(initDecl.name.length) ~ initDecl.name ~ d.mangle;
		
		scheduler.register(initDecl, initDecl, Step.Processed);
		
		// XXX: Not quite right !
		scheduler.register(d, d, Step.Processed);
		
		auto otherSymbols = d.members.filter!(delegate bool(Declaration m) {
			return typeid(m) !is typeid(FieldDeclaration) && m !is initDecl;
		}).array();
		
		d.members = cast(Declaration[]) fields ~ cast(Declaration[]) scheduler.schedule(otherSymbols, m => visit(m)) ~ initDecl;
		
		return d;
	}
	
	Symbol visit(ClassDefinition d) {
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		d.mangle = "C" ~ manglePrefix;
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope;
		
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(d.location, d);
		
		// XXX: Not quite right !
		scheduler.register(d, d, Step.Processed);
		
		d.members = cast(Declaration[]) scheduler.schedule(d.members, m => visit(m));
		
		return d;
	}
	
	Symbol visit(EnumDeclaration d) {
		auto type = pass.visit(d.type);
		
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
		
		d.mangle = "E" ~ manglePrefix;
		
		scheduler.register(d, d, Step.Processed);
		
		VariableDeclaration previous;
		foreach(e; d.enumEntries) {
			if(typeid({ return e.value; }()) is typeid(DefaultInitializer)) {
				if(previous) {
					e.value = new AddExpression(e.location, new SymbolExpression(e.location, previous), makeLiteral(e.location, 1));
				} else {
					e.value = makeLiteral(e.location, 0);
				}
			}
			
			e.value = explicitCast(e.location, type, pass.evaluate(pass.visit(e.value)));
			e.type = type;
			
			scheduler.register(e, e, Step.Processed);
			
			previous = e;
		}
			
		return d;
	}
	
	Symbol visit(AliasDeclaration d) {
		d.type = pass.visit(d.type);
		
		return d;
	}
	
	Symbol visit(TemplateDeclaration d) {
		d.mangle = manglePrefix;
		
		return d;
	}
	
	Symbol visit(StaticIfElse!Declaration d) {
		d.condition = evaluate(explicitCast(d.condition.location, new BooleanType(d.condition.location), pass.visit(d.condition)));
		
		if((cast(BooleanLiteral) d.condition).value) {
			assert(d.items.length == 1, "static if must have one and only one item");
			
			return scheduler.register(d.items[0], visit(d.items[0]), Step.Processed);
		} else {
			assert(d.elseItems.length == 1, "static else must have one and only one item");
			
			return scheduler.register(d.elseItems[0], visit(d.elseItems[0]), Step.Processed);
		}
	}
}

