#!/usr/bin/env zsh
bad=0
function diaf() {
    bad=1
    exit
}
export LANG=en-US.utf-8
zle -N diaf
bindkey '^D' diaf

line=
vared -p "$1" line
test "$bad" = "1" && exit 1
echo "$line"
