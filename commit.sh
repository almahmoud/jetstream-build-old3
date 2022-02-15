#!/bin/bash

git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

while true; do
    rm .git/index.lock || true && sleep 1;
    git add packages.json || true && sleep 1;
    git add lists || true && sleep 1;
    git add manifests || true && sleep 1;
    git commit -m "Periodic commit" || true && sleep 1;
    git push || true;
    sleep 300
done

