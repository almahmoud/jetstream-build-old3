#!/bin/bash

set -x

while getopts "n:i:o:l:" flag
do
    case "${flag}" in
        n) namespace=${OPTARG};;
        i) inputlist=${OPTARG};;
        o) outputlist=${OPTARG};;
    esac
done

if [ -z "$namespace" ];
    then echo "Needed: -n myinitials-mynamespace";
    exit;
fi

if [ -z "$inputlist" ];
    then echo "Needed: -i input.list";
    exit;
fi


if [ -z "$outputlist" ];
    then echo "Needed: -o output.list";
    exit;
fi

cat $inputlist | xargs -i sh -c "job_name=\$(echo {} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')-build; kubectl get -n $namespace -o yaml job/\$job_name > manifests/{}/job.yaml && kubectl logs -n $namespace job/\$job_name -c build > manifests/{}/log && kubectl delete -n $namespace job/\$job_name";
cat $inputlist >> $outputlist;
rm $inputlist
