/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.util;

import std.stdio;

bool contains(T)(const(T)[] l, const T a)
{
    foreach (e; l) {
        if (e == a) {
            return true;
        }
    }
    return false;
}

void debugPrint(lazy string msg)
{
    debug writeln("DEBUG: ", msg);
}

enum Status
{
    Failure,
    Success,
}
