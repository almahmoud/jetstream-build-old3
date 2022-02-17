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


echo "successful deletions:"
kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | grep -w Complete | awk '{print $1}' > lists/tmpbuildlist$UNIQUE &&\
    grep -q '[^[:space:]]' < "lists/tmpbuildlist$UNIQUE" &&\
    cat lists/tmpbuildlist$UNIQUE | xargs -i sh -c "grep -ir {} manifests | gawk -F'/' '{print \$2}'" > lists/cleanup$UNIQUE;


if [ -s lists/cleanup$UNIQUE ]
then
    sed -i "/        \"$(cat lists/cleanup$UNIQUE | sed 's/\./\\\./' | awk '{print $1"\\"}' | paste -sd'|' - | awk '{print "\\("$0")"}')\"\(,\)\{0,1\}/d" packages.json &&\
    sed -i '/^$/d' packages.json &&\
    sed -i ':a;N;$!ba;s/\[\n    \]/\[ \]/g' packages.json &&\
    cat lists/cleanup$UNIQUE | xargs -i sh -c "kubectl get -n $namespace -o yaml job/\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build -o yaml > manifests/{}/job.yaml && kubectl logs -n $namespace job/\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build > manifests/{}/log" &&\
    cat lists/cleanup$UNIQUE >> $built;
    cat lists/tmpbuildlist$UNIQUE | xargs kubectl delete -n $namespace job;
fi

rm lists/tmpbuildlist$UNIQUE;

echo "failure deletions:"

kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | grep -w Failed | awk '{print $1}' > lists/tmpexfailist$UNIQUE &&\
    grep -q '[^[:space:]]' < "lists/tmpexfailist$UNIQUE" &&\
    cat lists/tmpexfailist$UNIQUE | xargs -i sh -c "grep -ir {} manifests | gawk -F'/' '{print \$2}'" > lists/tmpfld$UNIQUE && cat lists/tmpfld$UNIQUE >> $failed &&\
    cat lists/tmpexfailist$UNIQUE | xargs -i sh -c "kubectl logs -n $namespace job/{} > $logs/{}.log; kubectl get job/{} -n $namespace -o yaml > $logs/{}.yaml && xargs kubectl delete -n $namespace job;"

rm lists/tmpexfailist$UNIQUE

export WORKERS=$(kubectl get nodes | grep $(kubectl get nodes | grep etcd | awk '{print $1}')- | awk '{print "\""$1"\""}' | paste -sd, -)


export TMPDISPATCH=$(echo "lists/dispatch$(date '+%s')");
export TMPMANIFEST=$(echo "lists/manifests$(date '+%s')");


function dispatch_job {
    if [ ! -f "manifests/$pkg/$pkg.yaml" ]
    then
        export lowerpkgname=$(echo $pkg | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
        mkdir -p "manifests/$pkg";
        sed """s/PACKAGENAMELOWER/$lowerpkgname/g
                  s/PACKAGENAME/$pkg/g
                  s/LIBRARIESCLAIM/$claim/g
                  s/NAMESPACE/$namespace/g
                  s/WORKERNODES/$WORKERS/g""" job-template.yaml > manifests/$pkg/$lowerpkgname-build.yaml
        cat manifests/$pkg/$lowerpkgname-build.yaml >> $TMPMANIFEST;
        echo "Created manifest: $pkg";
    fi
}

grep -Pzo "(?s)\s*\"\N*\":\s*\[\s*\]" packages.json | awk -F'"' '{print $2}' | grep -v '^$' > $TMPDISPATCH;


if [ ! -s $TMPDISPATCH ]
then
    rm $TMPDISPATCH;
else
    while IFS= read -r pkg; do
        dispatch_job;
    done < $TMPDISPATCH &&\
    kubectl apply -f $TMPMANIFEST &&\
    sed -i '/^$/d' packages.json &&\
    sed -i ':a;N;$!ba;s/\[\n    \]/\[ \]/g' packages.json &&\
    sed -i "/    \"$(cat $TMPDISPATCH | sed 's/\./\\\./' | awk '{print $1"\\"}' | paste -sd'|' - | awk '{print "\\("$0")"}')\"\: \[ \]\(,\)\{0,1\}/d" packages.json
fi


