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
import std.string;
import std.process;

import libdjson.json;

import sdc.lexer;
import sdc.tokenstream;
import sdc.ast.sdcmodule;


int main(string[] args)
{    
    if (args.length == 1) {
        return 0;
    }
    
    auto lexer = new Lexer(args[1]);
    lexer.lex();
        
    auto moduleNode = new ModuleNode();
    moduleNode.parse(lexer.tstream);
    
    auto parseTree = new JSONObject();
    moduleNode.prettyPrint(parseTree);
    writeln(parseTree.toString());
    return 0;
}
