/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.sdctemplate;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.util;
import sdc.ast.sdctemplate;
import sdc.parser.base;
import sdc.parser.declaration;
import sdc.parser.expression;


TemplateDeclaration parseTemplateDeclaration(TokenStream tstream)
{
    auto decl = new TemplateDeclaration();
    decl.location = tstream.peek.location;
    
    match(tstream, TokenType.Template);
    decl.templateIdentifier = parseIdentifier(tstream);
    match(tstream, TokenType.OpenParen);
    if (tstream.peek.type != TokenType.CloseParen) {
        decl.parameterList = parseTemplateParameterList(tstream);
    }
    match(tstream, TokenType.CloseParen);
    if (tstream.peek.type == TokenType.If) {
        decl.constraint = parseConstraint(tstream);
    }
    match(tstream, TokenType.OpenBrace);
    while (tstream.peek.type != TokenType.CloseBrace) {
        decl.declDefs ~= parseDeclarationDefinition(tstream);
    }
    match(tstream, TokenType.CloseBrace);
    return decl;
}

TemplateParameterList parseTemplateParameterList(TokenStream tstream)
{
    auto list = new TemplateParameterList();
    list.location = tstream.peek.location;
    
    list.parameters ~= parseTemplateParameter(tstream);
    while (tstream.peek.type == TokenType.Comma) {
        match(tstream, TokenType.Comma);
        list.parameters ~= parseTemplateParameter(tstream);
    }
    
    return list;
}

TemplateParameter parseTemplateParameter(TokenStream tstream)
{
    auto parameter = new TemplateParameter();
    parameter.location = tstream.peek.location;
    
    if (startsLikeDeclaration(tstream)) {
        parameter.type = TemplateParameterType.Value;
        parameter.node = parseTemplateValueParameter(tstream);
    } else switch (tstream.peek.type) {
    case TokenType.Identifier:
        if (tstream.lookahead(1).type == TokenType.TripleDot) {
            parameter.type = TemplateParameterType.Tuple;
            parameter.node = parseTemplateTupleParameter(tstream);
        } else {
            parameter.type = TemplateParameterType.Type;
            parameter.node = parseTemplateTypeParameter(tstream);
        }
        break;
    case TokenType.Alias:
        parameter.type = TemplateParameterType.Alias;
        parameter.node = parseTemplateAliasParameter(tstream);
        break;
    case TokenType.This:
        parameter.type = TemplateParameterType.This;
        parameter.node = parseTemplateThisParameter(tstream);
        break;
    default:
        throw new CompilerError(tstream.peek.location, "expected template parameter.");
    }
    
    return parameter;
}

TemplateTypeParameter parseTemplateTypeParameter(TokenStream tstream)
{
    auto parameter = new TemplateTypeParameter();
    parameter.location = tstream.peek.location;
    
    parameter.identifier = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        parameter.specialisation = parseType(tstream);
    }
    if (tstream.peek.type == TokenType.Assign) {
        match(tstream, TokenType.Assign);
        parameter.parameterDefault = parseType(tstream);
    }
    return parameter;
}

TemplateValueParameter parseTemplateValueParameter(TokenStream tstream)
{
    auto parameter = new TemplateValueParameter();
    parameter.location = tstream.peek.location;
    
    parameter.declaration = parseVariableDeclaration(tstream, true);
    if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        parameter.specialisation = parseConditionalExpression(tstream);
    }
    if (tstream.peek.type == TokenType.Assign) {
        match(tstream, TokenType.Assign);
        parameter.parameterDefault = parseTemplateValueParameterDefault(tstream);
    }
    return parameter;
}

TemplateValueParameterDefault parseTemplateValueParameterDefault(TokenStream tstream)
{
    auto parameterDefault = new TemplateValueParameterDefault();
    parameterDefault.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.__File__) {
        match(tstream, TokenType.__File__);
        parameterDefault.type = TemplateValueParameterDefaultType.__File__;
    } else if (tstream.peek.type == TokenType.__Line__) {
        match(tstream, TokenType.__Line__);
        parameterDefault.type = TemplateValueParameterDefaultType.__Line__;
    } else {
        parameterDefault.type = TemplateValueParameterDefaultType.ConditionalExpression;
        parameterDefault.expression = parseConditionalExpression(tstream);
    }
    return parameterDefault;
}

TemplateAliasParameter parseTemplateAliasParameter(TokenStream tstream)
{
    auto parameter = new TemplateAliasParameter();
    parameter.location = tstream.peek.location;
    
    match(tstream, TokenType.Alias);
    parameter.identifier = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        parameter.specialisation = parseType(tstream);
    }
    if (tstream.peek.type == TokenType.Assign) {
        match(tstream, TokenType.Assign);
        parameter.parameterDefault = parseType(tstream);
    }
    return parameter;
}

TemplateTupleParameter parseTemplateTupleParameter(TokenStream tstream)
{
    auto parameter = new TemplateTupleParameter();
    parameter.location = tstream.peek.location;
    
    parameter.identifier = parseIdentifier(tstream);
    match(tstream, TokenType.TripleDot);
    return parameter;
}

TemplateThisParameter parseTemplateThisParameter(TokenStream tstream)
{
    auto parameter = new TemplateThisParameter();
    parameter.location = tstream.peek.location;
    
    match(tstream, TokenType.This);
    parameter.templateTypeParameter = parseTemplateTypeParameter(tstream);
    return parameter;
}

Constraint parseConstraint(TokenStream tstream)
{
    auto constraint = new Constraint();
    constraint.location = tstream.peek.location;
    
    match(tstream, TokenType.If);
    match(tstream, TokenType.OpenParen);
    constraint.expression = parseExpression(tstream);
    match(tstream, TokenType.CloseParen);
    return constraint;
}
