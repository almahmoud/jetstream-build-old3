#!/bin/bash

set -x

# alias ggrep=gggrep
# alias gxargs=ggxargs
# alias gsed=ggsed
# alias gawk=ggawk

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
kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | ggrep -w Complete | gawk '{print $1}' > lists/tmpbuildlist$UNIQUE &&\
    ggrep -q '[^[:space:]]' < "lists/tmpbuildlist$UNIQUE" &&\
    cat lists/tmpbuildlist$UNIQUE | gxargs -i sh -c "kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job/{} |\
    gawk -F'\"' '{print $2}'" > lists/cleanup$UNIQUE;


if [ -s lists/cleanup$UNIQUE ]
then
    cat lists/cleanup$UNIQUE | gxargs -i sh -c "gsed -i '/        \"{}\"\(,\)\{0,1\}/d' packages.json" &&\
    gsed -i '/^$/d' packages.json &&\
    gsed -i ':a;N;$!ba;s/\[\n    \]/\[ \]/g' packages.json &&\
    cat lists/cleanup$UNIQUE | gxargs -i sh -c "kubectl get -n $namespace -o yaml job/\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build -o yaml > manifests/{}/job.yaml && kubectl logs -n $namespace job/\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build > manifests/{}/log" &&\
    cat lists/cleanup$UNIQUE >> $built;
    cat lists/tmpbuildlist$UNIQUE | gxargs kubectl delete -n $namespace job;
else
    rm lists/cleanup$UNIQUE;
fi

rm lists/tmpbuildlist$UNIQUE;

echo "failure deletions:"

kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | ggrep -w Failed | gawk '{print $1}' > lists/tmpexfailist$UNIQUE &&\
    ggrep -q '[^[:space:]]' < "lists/tmpexfailist$UNIQUE" &&\
    cat lists/tmpexfailist$UNIQUE | gxargs -i sh -c "kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job/{}" |\
    gawk -F'\"' '{print $2}' > lists/tmpfld$UNIQUE && cat lists/tmpfld$UNIQUE >> $failed &&\
    cat lists/tmpexfailist$UNIQUE | gxargs -i sh -c "kubectl logs -n $namespace job/{} > $logs/{}.log; kubectl get job/{} -n $namespace -o yaml > $logs/{}.yaml && gxargs kubectl delete -n $namespace job;"

rm lists/tmpexfailist$UNIQUE

export WORKERS=$(kubectl get nodes | ggrep $(kubectl get nodes | ggrep etcd | gawk '{print $1}')- | gawk '{print "\""$1"\""}' | paste -sd, -)


export TMPDISPATCH=$(echo "lists/dispatch$(date '+%s')");
export TMPMANIFEST=$(echo "lists/manifests$(date '+%s')");


function dispatch_job {
    if [ ! -f "manifests/$pkg/$pkg.yaml" ]
    then
        mkdir -p "manifests/$pkg";
        gsed """s/PACKAGENAMELOWER/$(echo $pkg | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')/g
                  s/PACKAGENAME/$pkg/g
                  s/LIBRARIESCLAIM/$claim/g
                  s/NAMESPACE/$namespace/g
                  s/WORKERNODES/$WORKERS/g""" job-template.yaml > manifests/$pkg/$pkg.yaml
        cat manifests/$pkg/$pkg.yaml >> $TMPMANIFEST;
        echo "Created manifest: $pkg";
    fi
}

ggrep -Pzo "(?s)\s*\"\N*\":\s*\[\s*\]" packages.json | gawk -F'"' '{print $2}' | ggrep -v '^$' > $TMPDISPATCH;


if [ ! -s $TMPDISPATCH ]
then
    rm $TMPDISPATCH;
else
    while IFS= read -r pkg; do
        dispatch_job;
    done < $TMPDISPATCH &&\
    kubectl apply -f $TMPMANIFEST &&\
    cat $TMPDISPATCH | gxargs -i sh -c "gsed -i '/    \"{}\"\: \[ \]\(,\)\{0,1\}/d' packages.json"
fi


