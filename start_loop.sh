#!/bin/bash
while getopts "n:c:j:b:f:" flag
do
    case "${flag}" in
        n) namespace=${OPTARG};;
        c) claim=${OPTARG};;
        j) json=${OPTARG};;
        b) built=${OPTARG};;
        f) failed=${OPTARG};;
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

if [ -z "$json" ];
    then echo "Needed: -j packages.json";
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

# Start dispatch loop
sleep 10 && bash -c "while true; do bash dispatch_list.sh -n $namespace -c $claim && sleep 30; done" &

# Mark done jobs
sleep 20 && bash -c "while true; do bash examine_jobs.sh -n $namespace -b $built -f $failed && sleep 30; done" &

sleep 300 && bash commit.sh &

# Loop until no more jobs in the namespace for 30 seconds
while (( $(kubectl get jobs -n $namespace | grep 'build' | wc -l && sleep 10) + $(kubectl get jobs -n $namespace | grep 'build' | wc -l && sleep 10) + $(kubectl get jobs -n $namespace | grep 'build' | wc -l) > 0 )); do
    echo "$(date) pods running: $(($(kubectl get pods -n $namespace | grep "build" | grep -i running | wc -l)))"
    echo "$(date) total jobs: $(($(kubectl get jobs -n $namespace | grep "build" | wc -l)))"
    sleep 5;
done
