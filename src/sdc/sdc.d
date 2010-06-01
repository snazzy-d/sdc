/**
 * Copyright 2010 Bernard Helyer
 * 
 * This file is part of SDC.
 * 
 * SDC is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
module sdc.sdc;

import std.stdio;

import sdc.source;
import sdc.tokenstream;
import sdc.lexer;
import sdc.compilererror;

int main(string[] args)
{
    try {
        return realmain(args);
    } catch (CompilerError) {
        return 1;
    }
}


int realmain(string[] args)
{
    auto source = new Source(args[1]);
    TokenStream tstream = lex(source);
    
    Token t;
    t = tstream.getToken();
    while (t.type != TokenType.End) {
        stdout.writefln("%s (%s)", t.value, t.location);
        t = tstream.getToken();
    }
            
    return 0;
}
