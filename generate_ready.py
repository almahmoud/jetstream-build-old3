#!/bin/usr/python3

from argparse import ArgumentParser
import json
import os
import time
import shutil

parser = ArgumentParser()
parser.add_argument("-j", "--json-file", dest="inputjson",
                    help="Input JSON file")
parser.add_argument("-r", "--ready-file", dest="readyfile",
                    help="File listing packages ready to be built")
parser.add_argument("-b", "--built-file", dest="builtfile",
                    help="File listing packages to be built")
parser.add_argument("-f", "--failed-file", dest="failedfile",
                    help="File listing packages that failed")
parser.add_argument("-s", "--skipped-file", dest="skippedfile",
                    help="File listing packages that failed")


args = parser.parse_args()


skipped = []
built = []
ready = []
failed = []
newdeps = {}

with open(args.inputjson, 'r') as f:
    deps = json.load(f)

if os.path.exists(args.builtfile):
    os.rename(args.builtfile, 'tmpupdbuilt.txt')
    with open('tmpupdbuilt.txt', 'r') as f:
        built = f.read().splitlines()
    os.remove('tmpupdbuilt.txt')

if os.path.exists(args.failedfile):
    shutil.copy(args.failedfile, 'tmpupdfailed.txt')
    with open('tmpupdfailed.txt', 'r') as f:
        failed = f.read().splitlines()
    os.remove('tmpupdfailed.txt')

if os.path.exists(args.skippedfile):
    os.rename(args.skippedfile, 'tmpupdskipped.txt')
    with open('tmpupdskipped.txt', 'r') as f:
        skipped = f.read().splitlines()
    os.remove('tmpupdskipped.txt')

print(f'original %d' % len(deps))

for pkg in deps.keys():
    for b in built:
        if b in deps[pkg]:
            deps[pkg].remove(b)
    if len(deps[pkg]) == 0:
        ready.append(pkg)
    else:
        skip = False
        for each in failed + skipped:
            if each in deps[pkg]:
                print(f'skipping {pkg} because of {each}. in failed {each in failed}. in skipped {each in skipped}')
                skipped.append(pkg)
                skip = True
        if not skip:
            newdeps[pkg] = deps[pkg]


print(f'new %d' % len(newdeps))

with open(args.skippedfile, 'w') as f:
    f.write("\n".join([each for each in set(skipped) if each]) + "\n")

with open(args.inputjson, 'w') as f:
    f.writelines(json.dumps(newdeps, indent=4))

with open(args.readyfile, 'w') as f:
    f.write("\n".join([each for each in set(ready) if each]) + "\n")

