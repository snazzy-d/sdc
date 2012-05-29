module sdc.ast.visitor;

import sdc.ast.all;


interface AstVisitor
{
    // sdcmodule.d
    void visit(Module);
    void visit(ModuleDeclaration);
    void visit(DeclarationDefinition);
    void visit(StaticAssert);
    void visit(Unittest);

    // base.d
    void visit(QualifiedName);
    void visit(StringLiteral);
    void visit(Identifier);
    void visit(IntegerLiteral);
    void visit(FloatLiteral);
    void visit(CharacterLiteral);
    void visit(ArrayLiteral);
    void visit(AssocArrayLiteral);
    void visit(FunctionLiteral);

    // declaration.d
    void visit(Declaration);
    void visit(MixinDeclaration);
    void visit(VariableDeclaration);
    void visit(Declarator);
    void visit(ParameterList);
    void visit(FunctionDeclaration);
    void visit(FunctionBody);
    void visit(Type);
    void visit(TypeSuffix);
    void visit(PrimitiveType);
    void visit(UserDefinedType);
    void visit(IdentifierOrTemplateInstance);
    void visit(TypeofType);
    void visit(FunctionPointerType);
    void visit(DelegateType);
    void visit(Parameter);
    void visit(Initialiser);

    // sdcimport.d
    void visit(ImportDeclaration);
    void visit(ImportList);
    void visit(Import);
    void visit(ImportBinder);
    void visit(ImportBind);

    // enumeration.d
    void visit(EnumDeclaration);
    void visit(EnumMemberList);
    void visit(EnumMember);

    // sdcclass.d
    void visit(ClassDeclaration);
    void visit(BaseClassList);
    void visit(ClassBody);

    // aggregate.d
    void visit(AggregateDeclaration);
    void visit(StructBody);

    // attribute.d
    void visit(AttributeSpecifier);
    void visit(Attribute);
    void visit(AlignAttribute);
    void visit(DeclarationBlock);

    // conditional.d
    void visit(ConditionalDeclaration);
    void visit(ConditionalStatement);
    void visit(Condition);
    void visit(VersionCondition);
    void visit(VersionSpecification);
    void visit(DebugCondition);
    void visit(DebugSpecification);
    void visit(StaticIfCondition);

    // expression.d
    void visit(Expression);
    void visit(ConditionalExpression);
    void visit(BinaryExpression);
    void visit(UnaryExpression);
    void visit(NewExpression);
    void visit(CastExpression);
    void visit(PostfixExpression);
    void visit(ArgumentList);
    void visit(PrimaryExpression);
    void visit(ArrayExpression);
    void visit(AssocArrayExpression);
    void visit(KeyValuePair);
    void visit(AssertExpression);
    void visit(MixinExpression);
    void visit(ImportExpression);
    void visit(TypeofExpression);
    void visit(TypeidExpression);
    void visit(IsExpression);
    void visit(TraitsExpression);
    void visit(TraitsArguments);
    void visit(TraitsArgument);

    // sdcpragma.d
    void visit(Pragma);

    // sdctemplate.d
    void visit(TemplateDeclaration);
    void visit(TemplateParameterList);
    void visit(TemplateParameter);
    void visit(TemplateTypeParameter);
    void visit(TemplateValueParameter);
    void visit(TemplateValueParameterSpecialisation);
    void visit(TemplateValueParameterDefault);
    void visit(TemplateAliasParameter);
    void visit(TemplateTupleParameter);
    void visit(TemplateThisParameter);
    void visit(Constraint);
    void visit(TemplateInstance);
    void visit(TemplateArgument);
    void visit(Symbol);
    void visit(SymbolTail);
    void visit(TemplateSingleArgument);

    // statement.d
    void visit(Statement);
    void visit(BlockStatement);
    void visit(LabeledStatement);
    void visit(ExpressionStatement);
    void visit(DeclarationStatement);
    void visit(IfStatement);
    void visit(IfCondition);
    void visit(WhileStatement);
    void visit(DoStatement);
    void visit(ForStatement);
    void visit(ForeachStatement);
    void visit(ForeachType);
    void visit(SwitchStatement);
    void visit(SwitchSubStatement);
    void visit(CaseListStatement);
    void visit(CaseRangeStatement);
    void visit(ContinueStatement);
    void visit(BreakStatement);
    void visit(ReturnStatement);
    void visit(GotoStatement);
    void visit(WithStatement);
    void visit(SynchronizedStatement);
    void visit(TryStatement);
    void visit(Catches);
    void visit(Catch);
    void visit(CatchParameter);
    void visit(LastCatch);
    void visit(FinallyStatement);
    void visit(ThrowStatement);
    void visit(ScopeGuardStatement);
    void visit(PragmaStatement);
    void visit(MixinStatement);
    void visit(AsmStatement);
}

class NullAstVisitor : AstVisitor
{
    // sdcmodule.d
    void visit(Module) {}
    void visit(ModuleDeclaration) {}
    void visit(DeclarationDefinition) {}
    void visit(StaticAssert) {}
    void visit(Unittest) {}

    // base.d
    void visit(QualifiedName) {}
    void visit(StringLiteral) {}
    void visit(Identifier) {}
    void visit(IntegerLiteral) {}
    void visit(FloatLiteral) {}
    void visit(CharacterLiteral) {}
    void visit(ArrayLiteral) {}
    void visit(AssocArrayLiteral) {}
    void visit(FunctionLiteral) {}

    // declaration.d
    void visit(Declaration) {}
    void visit(MixinDeclaration) {}
    void visit(VariableDeclaration) {}
    void visit(Declarator) {}
    void visit(ParameterList) {}
    void visit(FunctionDeclaration) {}
    void visit(FunctionBody) {}
    void visit(Type) {}
    void visit(TypeSuffix) {}
    void visit(PrimitiveType) {}
    void visit(UserDefinedType) {}
    void visit(IdentifierOrTemplateInstance) {}
    void visit(TypeofType) {}
    void visit(FunctionPointerType) {}
    void visit(DelegateType) {}
    void visit(Parameter) {}
    void visit(Initialiser) {}

    // sdcimport.d
    void visit(ImportDeclaration) {}
    void visit(ImportList) {}
    void visit(Import) {}
    void visit(ImportBinder) {}
    void visit(ImportBind) {}

    // enumeration.d
    void visit(EnumDeclaration) {}
    void visit(EnumMemberList) {}
    void visit(EnumMember) {}

    // sdcclass.d
    void visit(ClassDeclaration) {}
    void visit(BaseClassList) {}
    void visit(ClassBody) {}

    // aggregate.d
    void visit(AggregateDeclaration) {}
    void visit(StructBody) {}

    // attribute.d
    void visit(AttributeSpecifier) {}
    void visit(Attribute) {}
    void visit(AlignAttribute) {}
    void visit(DeclarationBlock) {}

    // conditional.d
    void visit(ConditionalDeclaration) {}
    void visit(ConditionalStatement) {}
    void visit(Condition) {}
    void visit(VersionCondition) {}
    void visit(VersionSpecification) {}
    void visit(DebugCondition) {}
    void visit(DebugSpecification) {}
    void visit(StaticIfCondition) {}

    // expression.d
    void visit(Expression) {}
    void visit(ConditionalExpression) {}
    void visit(BinaryExpression) {}
    void visit(UnaryExpression) {}
    void visit(NewExpression) {}
    void visit(CastExpression) {}
    void visit(PostfixExpression) {}
    void visit(ArgumentList) {}
    void visit(PrimaryExpression) {}
    void visit(ArrayExpression) {}
    void visit(AssocArrayExpression) {}
    void visit(KeyValuePair) {}
    void visit(AssertExpression) {}
    void visit(MixinExpression) {}
    void visit(ImportExpression) {}
    void visit(TypeofExpression) {}
    void visit(TypeidExpression) {}
    void visit(IsExpression) {}
    void visit(TraitsExpression) {}
    void visit(TraitsArguments) {}
    void visit(TraitsArgument) {}

    // sdcpragma.d
    void visit(Pragma) {}

    // sdctemplate.d
    void visit(TemplateDeclaration) {}
    void visit(TemplateParameterList) {}
    void visit(TemplateParameter) {}
    void visit(TemplateTypeParameter) {}
    void visit(TemplateValueParameter) {}
    void visit(TemplateValueParameterSpecialisation) {}
    void visit(TemplateValueParameterDefault) {}
    void visit(TemplateAliasParameter) {}
    void visit(TemplateTupleParameter) {}
    void visit(TemplateThisParameter) {}
    void visit(Constraint) {}
    void visit(TemplateInstance) {}
    void visit(TemplateArgument) {}
    void visit(Symbol) {}
    void visit(SymbolTail) {}
    void visit(TemplateSingleArgument) {}

    // statement.d
    void visit(Statement) {}
    void visit(BlockStatement) {}
    void visit(LabeledStatement) {}
    void visit(ExpressionStatement) {}
    void visit(DeclarationStatement) {}
    void visit(IfStatement) {}
    void visit(IfCondition) {}
    void visit(WhileStatement) {}
    void visit(DoStatement) {}
    void visit(ForStatement) {}
    void visit(ForeachStatement) {}
    void visit(ForeachType) {}
    void visit(SwitchStatement) {}
    void visit(SwitchSubStatement) {}
    void visit(CaseListStatement) {}
    void visit(CaseRangeStatement) {}
    void visit(ContinueStatement) {}
    void visit(BreakStatement) {}
    void visit(ReturnStatement) {}
    void visit(GotoStatement) {}
    void visit(WithStatement) {}
    void visit(SynchronizedStatement) {}
    void visit(TryStatement) {}
    void visit(Catches) {}
    void visit(Catch) {}
    void visit(CatchParameter) {}
    void visit(LastCatch) {}
    void visit(FinallyStatement) {}
    void visit(ThrowStatement) {}
    void visit(ScopeGuardStatement) {}
    void visit(PragmaStatement) {}
    void visit(MixinStatement) {}
    void visit(AsmStatement) {}
}
