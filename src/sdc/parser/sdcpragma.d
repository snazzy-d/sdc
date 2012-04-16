/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.sdcpragma;

import sdc.tokenstream;
import sdc.ast.sdcpragma;
import sdc.parser.base;
import sdc.parser.expression;


Pragma parsePragma(TokenStream tstream)
{
    auto thePragma = new Pragma();
    thePragma.location = tstream.peek.location;
    
    match(tstream, TokenType.Pragma);
    match(tstream, TokenType.OpenParen);
    thePragma.identifier = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Comma) {
        thePragma.argumentList = parseArgumentList(tstream, TokenType.Comma, TokenType.CloseParen);
    }
    return thePragma;
}
