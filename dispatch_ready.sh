#!/bin/bash
while getopts "n:b:f:c:" flag
do
    case "${flag}" in
        n) namespace=${OPTARG};;
        b) built=${OPTARG};;
        f) failed=${OPTARG};;
        c) claim=${OPTARG};;
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


export TMPCLEANUP=$(echo "lists/cleanup$(date '+%s')");

echo "successful deletions:"
kubectl get jobs -n $namespace --no-headers | grep 1/1 | awk '{print $1}' > tmpexbuiltlist &&\
    grep -q '[^[:space:]]' < tmpexbuiltlist &&\
    cat tmpexbuiltlist | xargs kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job |\
    awk -F'\"' '{print $2}' > tmpblt && cat tmpblt >> $TMPCLEANUP &&\
    cat tmpexbuiltlist | xargs kubectl delete -n $namespace job;

cat $TMPCLEANUP | xargs -i sh -c "sed -i '/        \"{}\"\(,\)\{0,1\}/d' packages.json";

# Remove all empty new lines
sed -i '/^$/d' packages.json > tmppkgs.json

# Remove last new line between brackets
sed -i ':a;N;$!ba;s/\[\n    \]/\[ \]/g' packages.json

cat $TMPCLEANUP | xargs -i sh -c "sed '/    \"{}\"\: \[ \]\(,\)\{0,1\}/d' packages.json > tmppkgs.json && mv tmppkgs.json packages.json"


cat $TMPCLEANUP >> $built && rm $TMPCLEANUP;

echo "failure deletions:"
kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | grep -w Failed | awk '{print $1}' > tmpexfailist &&\
    grep -q '[^[:space:]]' < tmpexfailist &&\
    cat tmpexfailist | xargs kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job |\
    awk -F'\"' '{print $2}' > tmpfld && cat tmpfld >> $failed &&\
    cat tmpexfailist | xargs -i kubectl logs -n $namespace job/{} > logs/{} &&\
    cat tmpexfailist | xargs kubectl delete -n $namespace job;

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