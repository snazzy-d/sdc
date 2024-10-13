module sys.posix.types;

alias c_long = long;
alias c_ulong = ulong;

alias ssize_t = c_long;

alias pid_t = int;
alias uid_t = uint;
alias gid_t = uint;

alias mode_t = uint;

alias clock_t = c_long;
alias useconds_t = uint;
