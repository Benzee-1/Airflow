#!/usr/bin/env python3
import json, os, tempfile, sys
# Entrée JSON: [{"ip":"10.0.0.1","hostname":"W1","environment":"production"}]
workers=json.load(open(sys.argv[1],encoding="utf-8"))
out=sys.argv[2]
groups=[]
for w in workers:
    groups.append({"targets":[f"{w['ip']}:9100"],"labels":{"hostname":w['hostname'],"environment":w['environment'],"role":"celery-worker"}})
os.makedirs(os.path.dirname(out),exist_ok=True)
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(out),prefix='.workers-',text=True)
with os.fdopen(fd,'w') as f: json.dump(groups,f,indent=2)
os.replace(tmp,out)
