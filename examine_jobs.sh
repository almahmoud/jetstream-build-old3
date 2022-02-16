#!/bin/bash
while getopts "n:b:f:" flag
do
    case "${flag}" in
        n) namespace=${OPTARG};;
        b) built=${OPTARG};;
        f) failed=${OPTARG};;
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


echo "successful deletions:"
kubectl get jobs -n $namespace --no-headers | grep 1/1 | awk '{print $1}' > tmpexbuiltlist &&\
    grep -q '[^[:space:]]' < tmpexbuiltlist &&\
    cat tmpexbuiltlist | xargs kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job |\
    awk -F'\"' '{print $2}' >> $built &&\
    cat tmpexbuiltlist | xargs kubectl delete -n $namespace job;

sleep 5;

echo "failure deletions:"
kubectl get jobs -n $namespace -o custom-columns=':metadata.name,:status.conditions[0].type' | grep -w Failed | awk '{print $1}' > tmpexfailist &&\
    grep -q '[^[:space:]]' < tmpexfailist &&\
    cat tmpexfailist | xargs kubectl get -n $namespace --no-headers -o custom-columns=':spec.template.spec.containers[0].args' job |\
    awk -F'\"' '{print $2}' >> $failed &&\
    cat tmpexfailist | xargs -i kubectl logs -n $namespace job/{} > logs/{} &&\
    cat tmpexfailist | xargs kubectl delete -n $namespace job;
