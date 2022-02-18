#!/bin/bash

set -x

while getopts "n:b:f:c:l:" flag
do
    case "${flag}" in
        n) namespace=${OPTARG};;
        b) built=${OPTARG};;
        f) failed=${OPTARG};;
        c) claim=${OPTARG};;
        l) logs=${OPTARG};;
    esac
done

if [ -z "$namespace" ];
    then echo "Needed: -n myinitials-mynamespace";
    exit;
fi

if [ -z "$built" ];
    then echo "Needed: -b built.list";
    exit;
fi


if [ -z "$failed" ];
    then echo "Needed: -f failed.list";
    exit;
fi

if [ -z "$claim" ];
    then echo "Needed pvc name: -c my-pvc";
    exit;
fi


if [ -z "$logs" ];
    then echo "Needed log-dir: -l logs";
    exit;
fi

mkdir -p lists

export UNIQUE=$(date '+%s');

export WORKERS=$(kubectl get nodes | grep $(kubectl get nodes | grep etcd | awk '{print $1}')- | awk '{print "\""$1"\""}' | paste -sd, -)

function dispatch_job {
    export lowerpkgname=$(echo $pkg | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    mkdir -p "manifests/$pkg";
    sed """s/PACKAGENAMELOWER/$lowerpkgname/g
              s/PACKAGENAME/$pkg/g
              s/LIBRARIESCLAIM/$claim/g
              s/NAMESPACE/$namespace/g
              s/WORKERNODES/$WORKERS/g""" job-template.yaml > manifests/$pkg/$lowerpkgname-build.yaml
    cat manifests/$pkg/$lowerpkgname-build.yaml >> lists/manifest$UNIQUE;
    echo "Created manifest: $pkg";
}



while IFS= read -r pkg; do
    dispatch_job;
done < $failed &&\
kubectl apply -f lists/manifest$UNIQUE

