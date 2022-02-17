#!/bin/bash
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


export TMPCLEANUP=$(echo "lists/cleanup$(date '+%s')");

echo "successful deletions:"
kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | grep -w Complete | awk '{print $1}' > tmpexbuiltlist &&\
    cat tmpexbuiltlist | xargs kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job |\
    awk -F'\"' '{print $2}' > tmpblt && cat tmpblt > $TMPCLEANUP;


if [ -s $TMPCLEANUP ]
then
    cat $TMPCLEANUP | xargs -i sh -c "sed -i '/        \"{}\"\(,\)\{0,1\}/d' packages.json" &&\
    sed -i '/^$/d' packages.json &&\
    sed -i ':a;N;$!ba;s/\[\n    \]/\[ \]/g' packages.json &&\
    cat $TMPCLEANUP | xargs -i sh -c "kubectl get -n $namespace -o yaml job/\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build -o yaml > manifests/{}/job.yaml && kubectl logs -n $namespace job/\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build > manifests/{}/log" &&\
    cat $TMPCLEANUP >> $built;
    cat tmpexbuiltlist | sort | uniq | xargs kubectl delete -n $namespace job;
else
    rm $TMPCLEANUP;
fi

rm tmpexbuiltlist;
rm tmpblt;

echo "failure deletions:"
kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | grep -w Failed | awk '{print $1}' > tmpexfailist


if [ -s tmpexfailist ]
then
    cat tmpexfailist | xargs kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job |\
    awk -F'\"' '{print $2}' > tmpfld && cat tmpfld >> $failed &&\
    cat tmpexfailist | sort | uniq | xargs -i sh -c "kubectl logs -n $namespace job/{} > $logs/{}.log; kubectl get job/{} -n $namespace -o yaml > $logs/{}.yaml && xargs kubectl delete -n $namespace job;"
fi

rm tmpfld;
rm tmpexfailist

export WORKERS=$(kubectl get nodes | grep $(kubectl get nodes | grep etcd | awk '{print $1}')- | awk '{print "\""$1"\""}' | paste -sd, -)


export TMPDISPATCH=$(echo "lists/dispatch$(date '+%s')");
export TMPMANIFEST=$(echo "lists/manifests$(date '+%s')");


function dispatch_job {
    if [ ! -f "manifests/$pkg/$pkg.yaml" ]
    then
        mkdir -p "manifests/$pkg";
        sed """s/PACKAGENAMELOWER/$(echo $pkg | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')/g
                  s/PACKAGENAME/$pkg/g
                  s/LIBRARIESCLAIM/$claim/g
                  s/NAMESPACE/$namespace/g
                  s/WORKERNODES/$WORKERS/g""" job-template.yaml > manifests/$pkg/$pkg.yaml
        cat manifests/$pkg/$pkg.yaml >> $TMPMANIFEST;
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
    cat $TMPDISPATCH | xargs -i sh -c "sed -i '/    \"{}\"\: \[ \]\(,\)\{0,1\}/d' packages.json"
fi


