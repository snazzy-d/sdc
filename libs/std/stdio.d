/// Part of a 'mock' phobos used for testing. Not intended for real use.
module std.stdio;


void writeln(string s)
{
    printf(s);
    printf("\n");
}
