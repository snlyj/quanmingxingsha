#!/usr/bin/env python3
# usage: rep.py <file> <<< "OLD\n===SEP===\nNEW" ; supports multiple blocks separated by ===NEXT===
import sys
path=sys.argv[1]
s=open(path).read()
data=sys.stdin.read()
for blk in data.split("===NEXT===\n"):
    if not blk.strip(): continue
    old,new=blk.split("===SEP===\n")
    if old.endswith("\n") and not new.endswith("\n"): new+="\n"
    c=s.count(old)
    if c!=1:
        print("MATCH COUNT",c,"for:\n",old[:300]); sys.exit(1)
    s=s.replace(old,new)
open(path,'w').write(s)
print("ok")
