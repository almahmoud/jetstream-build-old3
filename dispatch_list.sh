#!/bin/bash
while getopts "n:c:r:" flag
do
    case "${flag}" in
        n) namespace=${OPTARG};;
        c) claim=${OPTARG};;
        r) ready=${OPTARG};;
    esac
done


if [ -z "$namespace" ];
    then echo "Needed: -n myinitials-mynamespace";
    exit;
fi

if [ -z "$claim" ];
    then echo "Needed: -c my-claim";
    exit;
fi


if [ -z "$ready" ];
    then echo "Needed: -r ready.list";
    exit;
fi

function dispatch_job {
    if [ ! -f "manifests/$pkg/$pkg.yaml" ]
    then
        mkdir -p "manifests/$pkg"
        cp job-template.yaml manifests/$pkg/$pkg.yaml
        sed -i """s/PACKAGENAMELOWER/$(echo $pkg | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')/g
                  s/PACKAGENAME/$pkg/g
                  s/LIBRARIESCLAIM/$claim/g
                  s/NAMESPACE/$namespace/g
                  s/WORKERNODES/$(kubectl get nodes | grep $(kubectl get nodes | grep etcd | awk '{print $1}')- | awk '{print "\""$1"\""}' | paste -sd, -)/g""" manifests/$pkg/$pkg.yaml
        kubectl apply -f manifests/$pkg/$pkg.yaml;
        echo "Dispatched pkg: $pkg";
    fi
}

export TMPDISPATCH=$(echo "lists/dispatch$(date '+%s')");

grep -Pzo "(?s)\s*\"\N*\":\s*\[\s*\]" packages.json | awk -F'"' '{print $2}' | grep -v '^$' > $TMPDISPATCH;

while IFS= read -r pkg; do
    dispatch_job;
done < $TMPDISPATCH
