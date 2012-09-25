/**
 * This module put the correct mangling to AST nodes.
 */
module d.pass.mangle;

import d.pass.base;

import d.pass.dscope;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.identifier;

import std.algorithm;
import std.array;
import std.conv;

auto mangle(Module m) {
	auto pass = new ManglePass();
	
	return pass.visit(m);
}

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class ManglePass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	private TypeMangler typeMangler;
	
	private string manglePrefix;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		typeMangler			= new TypeMangler(this);
	}
	
final:
	Module visit(Module m) {
		auto name = m.moduleDeclaration.name;
		
		manglePrefix = m.moduleDeclaration.packages.map!(s => to!string(s.length) ~ s).join() ~ to!string(name.length) ~ name;
		
		m.declarations = m.declarations.map!(d => visit(d)).array();
		
		return m;
	}
	
	auto visit(Declaration decl) {
		return declarationVisitor.visit(decl);
	}
	
	auto visit(Statement stmt) {
		return statementVisitor.visit(stmt);
	}
	
	auto visit(Type t) {
		return typeMangler.visit(t);
	}
	
	auto visit(TemplateInstance tpl) {
		tpl.declarations = tpl.declarations.map!(d => visit(d)).array();
		
		return tpl;
	}
}

import d.ast.adt;
import d.ast.dfunction;
import d.ast.dtemplate;

class DeclarationVisitor {
	private ManglePass pass;
	alias pass this;
	
	this(ManglePass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Symbol visit(FunctionDeclaration d) {
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		auto paramsToMangle = d.isStatic?d.parameters:d.parameters[1 .. $];
		d.mangle = "_D" ~ manglePrefix ~ (d.isStatic?"F":"FM") ~ paramsToMangle.map!(p => p.type.mangle()).join() ~ "Z" ~ d.returnType.mangle();
		
		return d;
	}
	
	Symbol visit(FunctionDefinition d) {
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		auto paramsToMangle = d.isStatic?d.parameters:d.parameters[1 .. $];
		d.mangle = "_D" ~ manglePrefix ~ (d.isStatic?"F":"FM") ~ paramsToMangle.map!(p => p.type.mangle()).join() ~ "Z" ~ d.returnType.mangle();
		
		// And visit.
		pass.visit(d.fbody);
		
		return d;
	}
	
	Symbol visit(VariableDeclaration d) {
		if(d.isStatic) {
			d.mangle = "_D" ~ manglePrefix ~ to!string(d.name.length) ~ d.name ~ d.type.mangle();
		}
		
		return d;
	}
	
	Declaration visit(FieldDeclaration f) {
		return visit(cast(VariableDeclaration) f);
	}
	
	Symbol visit(StructDefinition d) {
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		d.mangle = "S" ~ manglePrefix;
		
		d.members = d.members.map!(m => visit(m)).array();
		
		return d;
	}
	
	Symbol visit(AliasDeclaration d) {
		d.mangle = d.type.mangle();
		
		return d;
	}
	
	Symbol visit(TemplateDeclaration d) {
		auto tplMangleBase = "__T" ~ to!string(d.name.length) ~ d.name;
		
		foreach(key; d.instances.byKey()) {
			auto oldManglePrefix = manglePrefix;
			scope(exit) manglePrefix = oldManglePrefix;
			
			auto tplMangle = tplMangleBase ~ key ~ "Z";
			
			manglePrefix = manglePrefix ~ to!string(tplMangle.length) ~ tplMangle;
			
			d.instances[key] = pass.visit(d.instances[key]);
		}
		
		return d;
	}
}

import d.ast.statement;

class StatementVisitor {
	private ManglePass pass;
	alias pass this;
	
	this(ManglePass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(ExpressionStatement e) {
	}
	
	void visit(DeclarationStatement d) {
		d.declaration = pass.visit(d.declaration);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		visit(f.initialize);
		
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
	}
}

import d.ast.type;

class TypeMangler {
	private ManglePass pass;
	alias pass this;
	
	this(ManglePass pass) {
		this.pass = pass;
	}
	
final:
	string visit(Type t) {
		return this.dispatch(t);
	}
	
	string visit(SymbolType t) {
		return t.symbol.mangle;
	}
/*	
	Type visit(BooleanType t) {
		return t;
	}
	
	Type visit(IntegerType t) {
		return t;
	}
	
	Type visit(FloatType t) {
		return t;
	}
	
	Type visit(CharacterType t) {
		return t;
	}
	
	Type visit(VoidType t) {
		return t;
	}
	
	Type visit(PointerType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(SliceType t) {
		t.type = visit(t.type);
		
		return t;
	}
*/
}

