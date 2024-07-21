#!/bin/bash
#
# Copyright 2024 Tech Equity Cloud Services Ltd
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#       http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# 
#################################################################################
####  Explore ASM Dual Control Plane Hybrid Cloud Microservice Application  #####
#################################################################################

# User prompt function
function ask_yes_or_no() {
    read -p "$1 ([y]yes to preview, [n]o to create, [d]del to delete): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        n|no)  echo "no" ;;
        d|del) echo "del" ;;
        *)     echo "yes" ;;
    esac
}

function ask_yes_or_no_proj() {
    read -p "$1 ([y]es to change, or any key to skip): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

function join_by { local IFS="$1"; shift; echo "$*"; }

clear
MODE=1
export TRAINING_ORG_ID=1 # $(gcloud organizations list --format 'value(ID)' --filter="displayName:techequity.training" 2>/dev/null)
export ORG_ID=1 # $(gcloud projects get-ancestors $GCP_PROJECT --format 'value(ID)' 2>/dev/null | tail -1 )
export GCP_PROJECT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)  

echo
echo
echo -e "                        👋  Welcome to Cloud Sandbox! 💻"
echo 
echo -e "              *** PLEASE WAIT WHILE LAB UTILITIES ARE INSTALLED ***"
sudo apt-get -qq install pv > /dev/null 2>&1
echo 
export SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p `pwd`/gcp-csm-mcp
export PROJDIR=`pwd`/gcp-csm-mcp
export SCRIPTNAME=gcp-csm-mcp.sh

if [ -f "$PROJDIR/.env" ]; then
    source $PROJDIR/.env
else
cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_PROJECT_1=$GCP_PROJECT
export GCP_CLUSTER_1=hipster-dcp-1
export GCP_REGION_1=europe-west2
export GCP_ZONE_1=europe-west2-a
export GCP_MACHINE_1=e2-standard-2
export GCP_PROJECT_2=$GCP_PROJECT
export GCP_CLUSTER_2=hipster-dcp-2
export GCP_REGION_2=europe-west3
export GCP_ZONE_2=europe-west3-a
export GCP_MACHINE_2=e2-standard-2
export APPLICATION_NAME=dual-control-plane
export ISTIO_VERSION=1.21.4 # https://github.com/istio/istio/releases
export ASM_VERSION=1.21.4-asm.5 # https://cloud.google.com/service-mesh/docs/release-notes
export ASM_INSTALL_SCRIPT_VERSION=1.21 
EOF
source $PROJDIR/.env
fi

export GCP_SUBNET_1=10.164.0.0/20
export GCP_SUBNET_2=10.128.0.0/20

# Display menu options
while :
do
clear
cat<<EOF
==============================================================
Menu for Dual Control Plane Anthos Service Mesh Configuration  
--------------------------------------------------------------
Please enter number to select your choice:
 (1) Install tools
 (2) Enable APIs
 (3) Create network
 (4) Create Kubernetes cluster
 (5) Create firewall rules
 (6) Install ASM components
 (7) Configure application
 (Q) Quit
--------------------------------------------------------------
EOF
echo "Steps performed${STEP}"
echo
echo "What additional step do you want to perform, e.g. enter 0 to select the execution mode?"
read
clear
case "${REPLY^^}" in

"0")
start=`date +%s`
source $PROJDIR/.env
echo
echo "Do you want to run script in preview mode?"
export ANSWER=$(ask_yes_or_no "Are you sure?")
cd $HOME
if [[ ! -z "$TRAINING_ORG_ID" ]]  &&  [[ $ORG_ID == "$TRAINING_ORG_ID" ]]; then
    export STEP="${STEP},0"
    MODE=1
    if [[ "yes" == $ANSWER ]]; then
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    else 
        if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
            echo 
            echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
            echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
        else
            while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                echo 
                echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                gcloud auth login  --brief --quiet
                export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                if [[ $ACCOUNT != "" ]]; then
                    echo
                    echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                    read GCP_PROJECT
                    gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                    sleep 3
                    export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                fi
            done
            gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
            sleep 2
            gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
            gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
            gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
            gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
        fi
        export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
        cat <<EOF > $PROJDIR/.env
export GCP_PROJECT_1=$GCP_PROJECT
export GCP_CLUSTER_1=$GCP_CLUSTER_1
export GCP_REGION_1=$GCP_REGION_1
export GCP_ZONE_1=$GCP_ZONE_1
export GCP_MACHINE_1=$GCP_MACHINE_1
export GCP_PROJECT_2=$GCP_PROJECT
export GCP_CLUSTER_2=$GCP_CLUSTER_2
export GCP_REGION_2=$GCP_REGION_2
export GCP_ZONE_2=$GCP_ZONE_2
export GCP_MACHINE_2=$GCP_MACHINE_2
export APPLICATION_NAME=$APPLICATION_NAME
export ASM_VERSION=$ASM_VERSION
export ASM_INSTALL_SCRIPT_VERSION=$ASM_INSTALL_SCRIPT_VERSION
export ISTIO_VERSION=$ISTIO_VERSION
EOF
        gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
        echo
        echo "*** Google Cloud project 1 is $GCP_PROJECT_1 ***" | pv -qL 100
        echo "*** Google Cloud cluster 1 is $GCP_CLUSTER_1 ***" | pv -qL 100
        echo "*** Google Cloud region 1 is $GCP_REGION_1 ***" | pv -qL 100
        echo "*** Google Cloud zone 1 is $GCP_ZONE_1 ***" | pv -qL 100
        echo "*** Google Cloud machine type 1 is $GCP_MACHINE_1 ***" | pv -qL 100
        echo "*** Google Cloud project 2 is $GCP_PROJECT_2 ***" | pv -qL 100
        echo "*** Google Cloud cluster 2 is $GCP_CLUSTER_2 ***" | pv -qL 100
        echo "*** Google Cloud region 2 is $GCP_REGION_2 ***" | pv -qL 100
        echo "*** Google Cloud zone 2 is $GCP_ZONE_2 ***" | pv -qL 100
        echo "*** Google Cloud machine type 2 is $GCP_MACHINE_2 ***" | pv -qL 100
        echo "*** Application name is $APPLICATION_NAME ***" | pv -qL 100
        echo "*** Anthos Service Mesh version is $ASM_VERSION ***" | pv -qL 100
        echo "*** Anthos Service Mesh install script version is $ASM_INSTALL_SCRIPT_VERSION ***" | pv -qL 100
        echo "*** Istio version is $ISTIO_VERSION ***" | pv -qL 100
        echo
        echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
        echo "*** $PROJDIR/.env ***" | pv -qL 100
        if [[ "no" == $ANSWER ]]; then
            MODE=2
            echo
            echo "*** Create mode is active ***" | pv -qL 100
        elif [[ "del" == $ANSWER ]]; then
            export STEP="${STEP},0"
            MODE=3
            echo
            echo "*** Resource delete mode is active ***" | pv -qL 100
        fi
    fi
else 
    if [[ "no" == $ANSWER ]] || [[ "del" == $ANSWER ]] ; then
        export STEP="${STEP},0"
        if [[ -f $SCRIPTPATH/.${SCRIPTNAME}.secret ]]; then
            echo
            unset password
            unset pass_var
            echo -n "Enter access code: " | pv -qL 100
            while IFS= read -p "$pass_var" -r -s -n 1 letter
            do
                if [[ $letter == $'\0' ]]
                then
                    break
                fi
                password=$password"$letter"
                pass_var="*"
            done
            while [[ -z "${password// }" ]]; do
                unset password
                unset pass_var
                echo
                echo -n "You must enter an access code to proceed: " | pv -qL 100
                while IFS= read -p "$pass_var" -r -s -n 1 letter
                do
                    if [[ $letter == $'\0' ]]
                    then
                        break
                    fi
                    password=$password"$letter"
                    pass_var="*"
                done
            done
            export PASSCODE=$(cat $SCRIPTPATH/.${SCRIPTNAME}.secret | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass pass:$password 2> /dev/null)
            if [[ $PASSCODE == 'AccessVerified' ]]; then
                MODE=2
                echo && echo
                echo "*** Access code is valid ***" | pv -qL 100
                if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
                    echo 
                    echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
                    echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
                else
                    while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                        echo 
                        echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                        gcloud auth login  --brief --quiet
                        export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                        if [[ $ACCOUNT != "" ]]; then
                            echo
                            echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                            read GCP_PROJECT
                            gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                            sleep 3
                            export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                        fi
                    done
                    gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
                    sleep 2
                    gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
                    gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
                    gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
                    gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
                fi
                export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
                cat <<EOF > $PROJDIR/.env
export GCP_PROJECT_1=$GCP_PROJECT
export GCP_CLUSTER_1=$GCP_CLUSTER_1
export GCP_REGION_1=$GCP_REGION_1
export GCP_ZONE_1=$GCP_ZONE_1
export GCP_MACHINE_1=$GCP_MACHINE_1
export GCP_PROJECT_2=$GCP_PROJECT
export GCP_CLUSTER_2=$GCP_CLUSTER_2
export GCP_REGION_2=$GCP_REGION_2
export GCP_ZONE_2=$GCP_ZONE_2
export GCP_MACHINE_2=$GCP_MACHINE_2
export APPLICATION_NAME=$APPLICATION_NAME
export ASM_VERSION=$ASM_VERSION
export ASM_INSTALL_SCRIPT_VERSION=$ASM_INSTALL_SCRIPT_VERSION
export ISTIO_VERSION=$ISTIO_VERSION
EOF
                gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
                echo
                echo "*** Google Cloud project 1 is $GCP_PROJECT_1 ***" | pv -qL 100
                echo "*** Google Cloud cluster 1 is $GCP_CLUSTER_1 ***" | pv -qL 100
                echo "*** Google Cloud region 1 is $GCP_REGION_1 ***" | pv -qL 100
                echo "*** Google Cloud zone 1 is $GCP_ZONE_1 ***" | pv -qL 100
                echo "*** Google Cloud machine type 1 is $GCP_MACHINE_1 ***" | pv -qL 100
                echo "*** Google Cloud project 2 is $GCP_PROJECT_2 ***" | pv -qL 100
                echo "*** Google Cloud cluster 2 is $GCP_CLUSTER_2 ***" | pv -qL 100
                echo "*** Google Cloud region 2 is $GCP_REGION_2 ***" | pv -qL 100
                echo "*** Google Cloud zone 2 is $GCP_ZONE_2 ***" | pv -qL 100
                echo "*** Google Cloud machine type 2 is $GCP_MACHINE_2 ***" | pv -qL 100
                echo "*** Application name is $APPLICATION_NAME ***" | pv -qL 100
                echo "*** Anthos Service Mesh version is $ASM_VERSION ***" | pv -qL 100
                echo "*** Anthos Service Mesh install script version is $ASM_INSTALL_SCRIPT_VERSION ***" | pv -qL 100
                echo "*** Istio version is $ISTIO_VERSION ***" | pv -qL 100
                echo
                echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
                echo "*** $PROJDIR/.env ***" | pv -qL 100
                if [[ "no" == $ANSWER ]]; then
                    MODE=2
                    echo
                    echo "*** Create mode is active ***" | pv -qL 100
                elif [[ "del" == $ANSWER ]]; then
                    export STEP="${STEP},0"
                    MODE=3
                    echo
                    echo "*** Resource delete mode is active ***" | pv -qL 100
                fi
            else
                echo && echo
                echo "*** Access code is invalid ***" | pv -qL 100
                echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
                echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
                echo
                echo "*** Command preview mode is active ***" | pv -qL 100
            fi
        else
            echo
            echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
            echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
            echo
            echo "*** Command preview mode is active ***" | pv -qL 100
        fi
    else
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    fi
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"1")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},1i"
    echo
    echo "$ curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_\${ASM_INSTALL_SCRIPT_VERSION} > \$PROJDIR/asmcli # to download script" | pv -qL 100
    echo
    echo "$ curl -L \"https://github.com/istio/istio/releases/download/\${ISTIO_VERSION}/istio-\${ISTIO_VERSION}-linux-amd64.tar.gz\" | tar xz -C \$HOME # to download Istio" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},1"
    gcloud config set project $GCP_PROJECT > /dev/null 2>&1
    rm -rf $PROJDIR/asmcli 2> /dev/null
    cd $HOME > /dev/null 2>&1
    echo
    echo "$ curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_${ASM_INSTALL_SCRIPT_VERSION} > $PROJDIR/asmcli # to download script" | pv -qL 100
    curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_${ASM_INSTALL_SCRIPT_VERSION} > $PROJDIR/asmcli
    echo
    echo "$ chmod +x $PROJDIR/asmcli # to make the script executable" | pv -qL 100
    chmod +x $PROJDIR/asmcli
    echo
    export PATH=$PROJDIR/istio-${ASM_VERSION}/bin:$PATH > /dev/null 2>&1 # to set ASM path 
    echo "$ curl -L \"https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz\" | tar xz -C $HOME # to download Istio" | pv -qL 100
    curl -L "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz" | tar xz -C $HOME 
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},1x"
    gcloud config set project $GCP_PROJECT > /dev/null 2>&1
    echo
    echo "$ rm -rf $PROJDIR/asmcli # to delete script" | pv -qL 100
    rm -rf $PROJDIR/asmcli
else
export STEP="${STEP},1i"
    echo
    echo "1. Download ASM script" | pv -qL 100
    echo "4. Download Istio Service Mesh" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"2")
start=`date +%s`
source $PROJDIR/.env
for i in 1 
do
    if [ $MODE -eq 1 ]; then
       export STEP="${STEP},2i"   
       echo
       echo "$ gcloud --project \$GCP_PROJECT services enable container.googleapis.com compute.googleapis.com monitoring.googleapis.com logging.googleapis.com cloudtrace.googleapis.com meshca.googleapis.com mesh.googleapis.com meshconfig.googleapis.com iamcredentials.googleapis.com anthos.googleapis.com anthosgke.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com cloudresourcemanager.googleapis.com websecurityscanner.googleapis.com # to enable APIs" | pv -qL 100
    elif [ $MODE -eq 2 ]; then
       export STEP="${STEP},2"   
       export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
       export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
       export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
       export ZONE=${!GCP_ZONE} > /dev/null 2>&1
       echo
       echo "$ gcloud --project $PROJECT services enable container.googleapis.com compute.googleapis.com monitoring.googleapis.com logging.googleapis.com cloudtrace.googleapis.com meshca.googleapis.com mesh.googleapis.com meshconfig.googleapis.com iamcredentials.googleapis.com anthos.googleapis.com anthosgke.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com cloudresourcemanager.googleapis.com websecurityscanner.googleapis.com # to enable APIs" | pv -qL 100
       gcloud --project $PROJECT services enable container.googleapis.com compute.googleapis.com monitoring.googleapis.com logging.googleapis.com cloudtrace.googleapis.com meshca.googleapis.com mesh.googleapis.com meshconfig.googleapis.com iamcredentials.googleapis.com anthos.googleapis.com anthosgke.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com cloudresourcemanager.googleapis.com websecurityscanner.googleapis.com
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},2x"   
        echo
        echo "*** Nothing to delete ***" | pv -qL 100
    else
        export STEP="${STEP},2i"
        echo
        echo "1. Enable APIs" | pv -qL 100
    fi
done
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"3")
start=`date +%s`
source $PROJDIR/.env
for i in 1 2 
do
    if [ $MODE -eq 1 ]; then
        export STEP="${STEP},3i(${i})"   
        echo
        echo "$ gcloud --project \$PROJECT_ID compute networks create \$APPLICATION_NAME-net --subnet-mode custom # to create custom network" | pv -qL 100
        echo
        echo "$ gcloud --project \$PROJECT_ID compute networks subnets create \$APPLICATION_NAME-subnet-${i} --network \$APPLICATION_NAME-net --region \$REGION --range \$SUBNET --enable-flow-logs # to create  subnet" | pv -qL 100
    elif [ $MODE -eq 2 ]; then
        export STEP="${STEP},3(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export GCP_SUBNET=$(echo GCP_SUBNET_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export SUBNET=${!GCP_SUBNET} > /dev/null 2>&1
        echo
        echo "$ gcloud --project $PROJECT compute networks create $APPLICATION_NAME-net --subnet-mode custom # to create custom network" | pv -qL 100
        gcloud --project $PROJECT compute networks create $APPLICATION_NAME-net --subnet-mode custom 2>/dev/null
        echo
        echo "$ gcloud --project $PROJECT compute networks subnets create $APPLICATION_NAME-subnet-${i} --network $APPLICATION_NAME-net --region $REGION --range $SUBNET --enable-flow-logs # to create  subnet" | pv -qL 100
        gcloud --project $PROJECT compute networks subnets create $APPLICATION_NAME-subnet-${i} --network $APPLICATION_NAME-net --region $REGION --range $SUBNET --enable-flow-logs 2>/dev/null
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},3x(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export GCP_SUBNET=$(echo GCP_SUBNET_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export SUBNET=${!GCP_SUBNET} > /dev/null 2>&1
        echo
        echo "$ gcloud --project $PROJECT compute networks subnets delete $APPLICATION_NAME-subnet-${i} --region $REGION --quiet # to delete  subnet" | pv -qL 100
        gcloud --project $PROJECT compute networks subnets delete $APPLICATION_NAME-subnet-${i} --region $REGION --quiet 
        echo
        echo "$ gcloud --project $PROJECT compute networks delete $APPLICATION_NAME-net --quiet # to delete custom network" | pv -qL 100
        gcloud --project $PROJECT compute networks delete $APPLICATION_NAME-net --quiet 
    else
        export STEP="${STEP},3i"
        echo
        echo "1. Create custom network" | pv -qL 100
        echo "2. Create subnet" | pv -qL 100
    fi
done
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"4")
start=`date +%s`
source $PROJDIR/.env
for i in 1 2 
do
    if [ $MODE -eq 1 ]; then
        export STEP="${STEP},4i(${i})"   
        if [ "$i" -eq 1 ]; then
            echo
            echo "$ gcloud --project \$PROJECT_ID beta container clusters create --zone \$ZONE \$CLUSTER --machine-type=e2-standard-2 --num-nodes=3 --workload-pool=\${WORKLOAD_POOL} --network=\$APPLICATION_NAME-net --subnetwork=\$APPLICATION_NAME-subnet-${i} --labels=mesh_id=\${MESH_ID},location=\$REGION --spot # to create cluster" | pv -qL 100
        else
            echo
            echo "$ gcloud --project \$PROJECT_ID beta container clusters create --zone \$ZONE \$CLUSTER --machine-type=e2-standard-2 --num-nodes=3 --workload-pool=\${WORKLOAD_POOL} --network=\$APPLICATION_NAME-net --subnetwork=\$APPLICATION_NAME-subnet-${i} --labels=mesh_id=\${MESH_ID},location=\$REGION --spot # to create cluster" | pv -qL 100
        fi
        echo
        echo "$ kubectl config use-context \$CTX # to set context" | pv -qL 100
        echo      
        echo "$ kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=\$(gcloud config get-value core/account) # to enable current user to set RBAC rules for Istio" | pv -qL 100
    elif [ $MODE -eq 2 ]; then
        export STEP="${STEP},4(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export GCP_SUBNET=$(echo GCP_SUBNET_$(eval "echo $i")) > /dev/null 2>&1
        export SUBNET=${!GCP_SUBNET} > /dev/null 2>&1    
        export GCP_MACHINE=$(echo GCP_MACHINE_$(eval "echo $i")) > /dev/null 2>&1
        export MACHINE=${!GCP_MACHINE} > /dev/null 2>&1
        export GCP_NUMNODES=$(echo GCP_NUMNODES_$(eval "echo $i")) > /dev/null 2>&1
        export NUMNODES=${!GCP_NUMNODES} > /dev/null 2>&1
        export GCP_MINNODES=$(echo GCP_MINNODES_$(eval "echo $i")) > /dev/null 2>&1
        export MINNODES=${!GCP_MINNODES} > /dev/null 2>&1
        export GCP_MAXNODES=$(echo GCP_MAXNODES_$(eval "echo $i")) > /dev/null 2>&1
        export MAXNODES=${!GCP_MAXNODES} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        export PROJECT_NUMBER=$(gcloud projects describe $PROJECT --format="value(projectNumber)")
        export MESH_ID="proj-${PROJECT_NUMBER}" # sets the mesh_id label on the cluster
        export WORKLOAD_POOL=${PROJECT}.svc.id.goog
        if [ "$i" -eq 1 ]; then
            echo
            echo "$ gcloud --project $PROJECT beta container clusters create $CLUSTER --zone $ZONE --machine-type=e2-standard-2 --num-nodes=3 --workload-pool=${WORKLOAD_POOL} --network=$APPLICATION_NAME-net --subnetwork=$APPLICATION_NAME-subnet-${i} --labels=mesh_id=${MESH_ID},location=$REGION --spot # to create cluster" | pv -qL 100
            gcloud --project $PROJECT beta container clusters create $CLUSTER --zone $ZONE --machine-type=e2-standard-2 --num-nodes=3 --workload-pool=${WORKLOAD_POOL} --network=$APPLICATION_NAME-net --subnetwork=$APPLICATION_NAME-subnet-${i} --labels=mesh_id=${MESH_ID},location=$REGION --spot
        else
            echo
            echo "$ gcloud --project $PROJECT beta container clusters create $CLUSTER --zone $ZONE--machine-type=e2-standard-2 --num-nodes=3 --workload-pool=${WORKLOAD_POOL} --network=$APPLICATION_NAME-net --subnetwork=$APPLICATION_NAME-subnet-${i} --labels=mesh_id=${MESH_ID},location=$REGION --spot # to create cluster" | pv -qL 100
            gcloud --project $PROJECT beta container clusters create $CLUSTER --zone $ZONE --machine-type=e2-standard-2 --num-nodes=3 --workload-pool=${WORKLOAD_POOL} --network=$APPLICATION_NAME-net --subnetwork=$APPLICATION_NAME-subnet-${i} --labels=mesh_id=${MESH_ID},location=$REGION --spot
        fi
        echo
        echo "$ kubectl config use-context $CTX # to set context" | pv -qL 100
        kubectl config use-context $CTX
        echo      
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER --zone $ZONE > /dev/null 2>&1
        echo "$ kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=\$(gcloud config get-value core/account) # to enable current user to set RBAC rules for Istio" | pv -qL 100
        kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account) 2>/dev/null
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},4x(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export GCP_SUBNET=$(echo GCP_SUBNET_$(eval "echo $i")) > /dev/null 2>&1
        export SUBNET=${!GCP_SUBNET} > /dev/null 2>&1    
        export GCP_MACHINE=$(echo GCP_MACHINE_$(eval "echo $i")) > /dev/null 2>&1
        export MACHINE=${!GCP_MACHINE} > /dev/null 2>&1
        export GCP_NUMNODES=$(echo GCP_NUMNODES_$(eval "echo $i")) > /dev/null 2>&1
        export NUMNODES=${!GCP_NUMNODES} > /dev/null 2>&1
        export GCP_MINNODES=$(echo GCP_MINNODES_$(eval "echo $i")) > /dev/null 2>&1
        export MINNODES=${!GCP_MINNODES} > /dev/null 2>&1
        export GCP_MAXNODES=$(echo GCP_MAXNODES_$(eval "echo $i")) > /dev/null 2>&1
        export MAXNODES=${!GCP_MAXNODES} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        export PROJECT_NUMBER=$(gcloud projects describe $PROJECT --format="value(projectNumber)")
        export MESH_ID="proj-${PROJECT_NUMBER}" # sets the mesh_id label on the cluster
        export WORKLOAD_POOL=${PROJECT}.svc.id.goog
        if [ "$i" -eq 1 ]; then
            echo
            echo "$ gcloud --project $PROJECT beta container clusters delete $CLUSTER --zone $ZONE # to delete container cluster" | pv -qL 100
            gcloud --project $PROJECT beta container clusters delete $CLUSTER --zone $ZONE
        else
            echo
            echo "$ gcloud --project $PROJECT beta container clusters delete $CLUSTER --zone $ZONE # to delete cluster" | pv -qL 100
            gcloud --project $PROJECT beta container clusters delete $CLUSTER --zone $ZONE
        fi
    else
        export STEP="${STEP},4i"
        echo
        echo "1. Create cluster" | pv -qL 100
        echo "2. Retrieve credentials for cluster" | pv -qL 100
        echo "3. Ensure user has admin priviledges" | pv -qL 100
    fi
done
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"5")
start=`date +%s`
source $PROJDIR/.env
for i in 1 2 
do
    if [ $MODE -eq 1 ]; then
        export STEP="${STEP},5i(${i})"
        echo
        echo "$ gcloud --project \$GCP_PROJECT compute firewall-rules create \${APPLICATION_NAME}-net-firewall-rule-${i} --allow=tcp,udp,icmp,esp,ah,sctp --network=\$APPLICATION_NAME-net-${i} --direction=INGRESS --priority=900 --source-ranges=\"\${ALL_CLUSTER_CIDRS}\" --target-tags=\"\${ALL_CLUSTER_NETTAGS}\" --enable-logging --logging-metadata=include-all # to create firewall rule" | pv -qL 100
    elif [ $MODE -eq 2 ]; then
        export STEP="${STEP},5(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        gcloud config set project $PROJECT > /dev/null 2>&1 
        echo
        export ALL_CLUSTER_POD_CIDRS=$(gcloud --project $PROJECT container clusters list --format='value(clusterIpv4Cidr)' | sort | uniq) # to retrieve cluster pod CIDR ranges
        export ALL_CLUSTER_SERVICE_CIDRS=$(gcloud --project $PROJECT container clusters list --format='value(servicesIpv4Cidr)' | sort | uniq) # to retrieve cluster service CIDR ranges
        export ALL_CLUSTER_CIDRS=$(join_by , $(echo "${ALL_CLUSTER_POD_CIDRS} ${ALL_CLUSTER_SERVICE_CIDRS}")) # to create a list of all cluster CIDR ranges
        export ALL_CLUSTER_NETTAGS=$(gcloud --project $PROJECT compute instances list --format='value(tags.items.[0])' | sort | uniq) # to create a list of all compute instance tags
        export ALL_CLUSTER_NETTAGS=$(join_by , $(echo "${ALL_CLUSTER_NETTAGS}")) # to create a list of all compute instance tags
        gcloud --project $PROJECT compute firewall-rules delete ${APPLICATION_NAME}-net-firewall-rule-${i} --quiet > /dev/null 2>&1 # to delete firewall rule
        echo "$ gcloud --project $PROJECT compute firewall-rules create ${APPLICATION_NAME}-net-firewall-rule-${i} --allow=tcp,udp,icmp,esp,ah,sctp --network=$APPLICATION_NAME-net --direction=INGRESS --priority=900 --source-ranges=\"${ALL_CLUSTER_CIDRS}\" --target-tags=\"${ALL_CLUSTER_NETTAGS}\" --enable-logging --logging-metadata=include-all # to create firewall rule" | pv -qL 100
        gcloud --project $PROJECT compute firewall-rules create ${APPLICATION_NAME}-net-firewall-rule-${i} --allow=tcp,udp,icmp,esp,ah,sctp --network=$APPLICATION_NAME-net --direction=INGRESS --priority=900 --source-ranges="${ALL_CLUSTER_CIDRS}" --target-tags="${ALL_CLUSTER_NETTAGS}" --enable-logging --logging-metadata=include-all
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},5x(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        gcloud config set project $PROJECT > /dev/null 2>&1 
        echo
        echo "$ gcloud --project $PROJECT compute firewall-rules delete ${APPLICATION_NAME}-net-firewall-rule-${i} --quiet # to delete firewall rule" | pv -qL 100
        gcloud --project $PROJECT compute firewall-rules delete ${APPLICATION_NAME}-net-firewall-rule-${i} --quiet 
    else
        export STEP="${STEP},5i(${i})"
        echo
        echo "1. Create firewall rule" | pv -qL 100
    fi
done
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"6")
start=`date +%s`
source $PROJDIR/.env
for i in 1 2 
do
    if [ $MODE -eq 1 ]; then
        export STEP="${STEP},6i(${i})"   
        echo
        echo "$ kubectl config use-context \$CTX # to set context" | pv -qL 100
        echo      
        echo "$ kubectl create namespace istio-system # to create namespace" | pv -qL 100
        echo
        echo "$ kubectl get namespace istio-system && kubectl label namespace istio-system topology.istio.io/network=\$APPLICATION_NAME-net # to label namespace" | pv -qL 100
        echo
        echo "$ cat > \$PROJDIR/tracing.yaml <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    enableTracing: true
  values:
    global:
      proxy:
        tracer: stackdriver
EOF" | pv -qL 100
        echo
        echo "$ \$PROJDIR/asmcli install --project_id \$PROJECT --cluster_name \$CLUSTER --cluster_location \$ZONE --fleet_id \$PROJECT --output_dir \$PROJDIR --enable_all --ca mesh_ca --custom_overlay \$PROJDIR/tracing.yaml --custom_overlay --option legacy-default-ingressgateway # to install ASM" | pv -qL 100
        echo
        echo "$ kubectl annotate --overwrite namespace default mesh.cloud.google.com/proxy='{\"managed\":\"false\"}' # to enable Google to manage data plane" | pv -qL 100
    elif [ $MODE -eq 2 ]; then
        export STEP="${STEP},6(${i})"   
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export PROJECT_NUMBER=$(gcloud projects describe $PROJECT --format="value(projectNumber)")
        export MESH_ID="proj-${PROJECT_NUMBER}" # sets the mesh_id label on the cluster
        export WORKLOAD_POOL=${PROJECT}.svc.id.goog
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        rm $HOME/.kube/config
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER > /dev/null 2>&1 # to retrieve the credentials for cluster
        cp $HOME/.kube/config $HOME/.kube/${CLUSTER}-config
        cd $HOME/istio-${ISTIO_VERSION} > /dev/null 2>&1 # to change to Istio directory
        echo
        echo "$ kubectl delete namespace istio-system # to delete namespace" | pv -qL 100
        kubectl delete namespace istio-system 2> /dev/null
        echo
        echo "$ kubectl config use-context $CTX # to set context" | pv -qL 100
        kubectl config use-context $CTX
        echo      
        echo "$ kubectl create namespace istio-system # to create namespace" | pv -qL 100
        kubectl create namespace istio-system 2> /dev/null
        echo
        echo "$ kubectl get namespace istio-system && kubectl label namespace istio-system topology.istio.io/network=$APPLICATION_NAME-net # to label namespace" | pv -qL 100
        kubectl get namespace istio-system && kubectl label namespace istio-system topology.istio.io/network=$APPLICATION_NAME-net --overwrite
        echo
        echo "$ cat > $PROJDIR/tracing.yaml <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    enableTracing: true
  values:
    global:
      proxy:
        tracer: stackdriver
EOF" | pv -qL 100
cat > $PROJDIR/tracing.yaml <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    enableTracing: true
  values:
    global:
      proxy:
        tracer: stackdriver
EOF
        echo
        echo "$ $PROJDIR/asmcli install --project_id $PROJECT --cluster_name $CLUSTER --cluster_location $ZONE --fleet_id $PROJECT --output_dir $PROJDIR --enable_all --ca mesh_ca --custom_overlay $PROJDIR/tracing.yaml --option legacy-default-ingressgateway # to install ASM" | pv -qL 100
        $PROJDIR/asmcli install --project_id $PROJECT --cluster_name $CLUSTER --cluster_location $ZONE --fleet_id $PROJECT --output_dir $PROJDIR --enable_all --ca mesh_ca --custom_overlay $PROJDIR/tracing.yaml --option legacy-default-ingressgateway
        echo
        echo "$ kubectl annotate --overwrite namespace default mesh.cloud.google.com/proxy='{\"managed\":\"false\"}' # to enable Google to manage data plane" | pv -qL 100
        kubectl annotate --overwrite namespace default mesh.cloud.google.com/proxy='{"managed":"false"}'
        sleep 15
        echo
        echo "$ kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system # to wait for the deployment to finish" | pv -qL 100
        kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},6x(${i})"   
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export PROJECT_NUMBER=$(gcloud projects describe $PROJECT --format="value(projectNumber)")
        export MESH_ID="proj-${PROJECT_NUMBER}" # sets the mesh_id label on the cluster
        export WORKLOAD_POOL=${PROJECT}.svc.id.goog
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        rm $HOME/.kube/config
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER > /dev/null 2>&1 
        cp $HOME/.kube/config $HOME/.kube/${CLUSTER}-config
        cd $HOME/istio-${ISTIO_VERSION} > /dev/null 2>&1 # to change to Istio directory
        echo
        echo "$ kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot # to remove webhooks" | pv -qL 100
        kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot
        echo
        echo "$ $PROJDIR/istio-$ASM_VERSION/bin/istioctl uninstall --purge # to remove the in-cluster control plane" | pv -qL 100
        $PROJDIR/istio-$ASM_VERSION/bin/istioctl uninstall --purge
        echo && echo
        echo "$  kubectl delete namespace istio-system asm-system --ignore-not-found=true # to remove namespace" | pv -qL 100
        kubectl delete namespace istio-system asm-system --ignore-not-found=true
    else
        export STEP="${STEP},6i"
        echo
        echo "1. Retrieve the credentials for cluster" | pv -qL 100
        echo "2. Create and label namespace" | pv -qL 100
        echo "3. Configure Istio Operator" | pv -qL 100
        echo "4. Install Anthos Service Mesh" | pv -qL 100
        echo "5. Enable Google to manage data plane" | pv -qL 100
        echo "6. Install dedicated east-west gateway" | pv -qL 100
        echo "7. Expose services on east-west gateway" | pv -qL 100
    fi
done
for ((i=2;i>0;i--)); do 
    if [ $MODE -ne 1 ]; then
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        export HOST_CLUSTER=${CLUSTER} > /dev/null 2>&1
        export HOST_CTX="${CTX}" > /dev/null 2>&1
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $((3-i))")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $((3-i))")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $((3-i))")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        export REMOTE_CLUSTER=${CLUSTER} > /dev/null 2>&1
        export REMOTE_CTX="${CTX}" > /dev/null 2>&1
    fi
done 
if [ $MODE -eq 1 ]; then
    echo
    echo "$ \$PROJDIR/asmcli create-mesh \$PROJECT \$HOME/.kube/\${HOST_CLUSTER}-config \$HOME/.kube/\${REMOTE_CLUSTER}-config # to enable endpoint discovery" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    echo
    echo "$ $PROJDIR/asmcli create-mesh $PROJECT $HOME/.kube/${HOST_CLUSTER}-config $HOME/.kube/${REMOTE_CLUSTER}-config # to enable endpoint discovery" | pv -qL 100
    $PROJDIR/asmcli create-mesh $PROJECT $HOME/.kube/${HOST_CLUSTER}-config $HOME/.kube/${REMOTE_CLUSTER}-config
elif [ $MODE -eq 3 ]; then
    echo
else
    echo "8. Enable endpoint discovery" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"7B")
start=`date +%s`
source $PROJDIR/.env
mkdir -p $PROJDIR/cluster1 > /dev/null 2>&1
mkdir -p $PROJDIR/cluster2 > /dev/null 2>&1
cat <<EOF> $PROJDIR/cluster1/deployments.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: emailservice
spec:
  selector:
    matchLabels:
      app: emailservice
  template:
    metadata:
      labels:
        app: emailservice
    spec:
      serviceAccountName: default
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - all
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/emailservice:v0.3.9
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        - name: DISABLE_TRACING
          value: "1"
        - name: DISABLE_PROFILER
          value: "1"
        readinessProbe:
          periodSeconds: 5
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:8080"]
        livenessProbe:
          periodSeconds: 5
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:8080"]
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkoutservice
spec:
  selector:
    matchLabels:
      app: checkoutservice
  template:
    metadata:
      labels:
        app: checkoutservice
    spec:
      serviceAccountName: default
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: server
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - all
            privileged: false
            readOnlyRootFilesystem: true
          image: gcr.io/google-samples/microservices-demo/checkoutservice:v0.3.9
          ports:
          - containerPort: 5050
          readinessProbe:
            exec:
              command: ["/bin/grpc_health_probe", "-addr=:5050"]
          livenessProbe:
            exec:
              command: ["/bin/grpc_health_probe", "-addr=:5050"]
          env:
          - name: PORT
            value: "5050"
          - name: PRODUCT_CATALOG_SERVICE_ADDR
            value: "productcatalogservice:3550"
          - name: SHIPPING_SERVICE_ADDR
            value: "shippingservice:50051"
          - name: PAYMENT_SERVICE_ADDR
            value: "paymentservice:50051"
          - name: EMAIL_SERVICE_ADDR
            value: "emailservice:5000"
          - name: CURRENCY_SERVICE_ADDR
            value: "currencyservice:7000"
          - name: CART_SERVICE_ADDR
            value: "cartservice:7070"
          - name: DISABLE_STATS
            value: "1"
          - name: DISABLE_TRACING
            value: "1"
          - name: DISABLE_PROFILER
            value: "1"
          # - name: JAEGER_SERVICE_ADDR
          #   value: "jaeger-collector:14268"
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
      annotations:
        sidecar.istio.io/rewriteAppHTTPProbers: "true"
    spec:
      serviceAccountName: default
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: server
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - all
            privileged: false
            readOnlyRootFilesystem: true
          image: gcr.io/google-samples/microservices-demo/frontend:v0.3.9
          ports:
          - containerPort: 8080
          readinessProbe:
            initialDelaySeconds: 10
            httpGet:
              path: "/_healthz"
              port: 8080
              httpHeaders:
              - name: "Cookie"
                value: "shop_session-id=x-readiness-probe"
          livenessProbe:
            initialDelaySeconds: 10
            httpGet:
              path: "/_healthz"
              port: 8080
              httpHeaders:
              - name: "Cookie"
                value: "shop_session-id=x-liveness-probe"
          env:
          - name: PORT
            value: "8080"
          - name: PRODUCT_CATALOG_SERVICE_ADDR
            value: "productcatalogservice:3550"
          - name: CURRENCY_SERVICE_ADDR
            value: "currencyservice:7000"
          - name: CART_SERVICE_ADDR
            value: "cartservice:7070"
          - name: RECOMMENDATION_SERVICE_ADDR
            value: "recommendationservice:8080"
          - name: SHIPPING_SERVICE_ADDR
            value: "shippingservice:50051"
          - name: CHECKOUT_SERVICE_ADDR
            value: "checkoutservice:5050"
          - name: AD_SERVICE_ADDR
            value: "adservice:9555"
          # # ENV_PLATFORM: One of: local, gcp, aws, azure, onprem, alibaba
          # # When not set, defaults to "local" unless running in GKE, otherwies auto-sets to gcp 
          # - name: ENV_PLATFORM 
          #   value: "aws"
          - name: DISABLE_TRACING
            value: "1"
          - name: DISABLE_PROFILER
            value: "1"
          # - name: JAEGER_SERVICE_ADDR
          #   value: "jaeger-collector:14268"
          # - name: CYMBAL_BRANDING
          #   value: "true"
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: paymentservice
spec:
  selector:
    matchLabels:
      app: paymentservice
  template:
    metadata:
      labels:
        app: paymentservice
    spec:
      serviceAccountName: default
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - all
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/paymentservice:v0.3.9
        ports:
        - containerPort: 50051
        env:
        - name: PORT
          value: "50051"
        - name: DISABLE_TRACING
          value: "1"
        - name: DISABLE_PROFILER
          value: "1"
        - name: DISABLE_DEBUGGER
          value: "1"
        readinessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:50051"]
        livenessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:50051"]
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: productcatalogservice
spec:
  selector:
    matchLabels:
      app: productcatalogservice
  template:
    metadata:
      labels:
        app: productcatalogservice
    spec:
      serviceAccountName: default
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - all
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/productcatalogservice:v0.3.9
        ports:
        - containerPort: 3550
        env:
        - name: PORT
          value: "3550"
        - name: DISABLE_STATS
          value: "1"
        - name: DISABLE_TRACING
          value: "1"
        - name: DISABLE_PROFILER
          value: "1"
        # - name: JAEGER_SERVICE_ADDR
        #   value: "jaeger-collector:14268"
        readinessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:3550"]
        livenessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:3550"]
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: currencyservice
spec:
  selector:
    matchLabels:
      app: currencyservice
  template:
    metadata:
      labels:
        app: currencyservice
    spec:
      serviceAccountName: default
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - all
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/currencyservice:v0.3.9
        ports:
        - name: grpc
          containerPort: 7000
        env:
        - name: PORT
          value: "7000"
        - name: DISABLE_TRACING
          value: "1"
        - name: DISABLE_PROFILER
          value: "1"
        - name: DISABLE_DEBUGGER
          value: "1"
        readinessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:7000"]
        livenessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:7000"]
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shippingservice
spec:
  selector:
    matchLabels:
      app: shippingservice
  template:
    metadata:
      labels:
        app: shippingservice
    spec:
      serviceAccountName: default
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - all
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/shippingservice:v0.3.9
        ports:
        - containerPort: 50051
        env:
        - name: PORT
          value: "50051"
        - name: DISABLE_STATS
          value: "1"
        - name: DISABLE_TRACING
          value: "1"
        - name: DISABLE_PROFILER
          value: "1"
        # - name: JAEGER_SERVICE_ADDR
        #   value: "jaeger-collector:14268"
        readinessProbe:
          periodSeconds: 5
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:50051"]
        livenessProbe:
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:50051"]
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
EOF
cat <<EOF> $PROJDIR/cluster1/istio-manifests.yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: frontend-gateway
spec:
  selector:
    istio: ingressgateway # use Istio default gateway implementation
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: frontend-ingress
spec:
  hosts:
  - "*"
  gateways:
  - frontend-gateway
  http:
  - route:
    - destination:
        host: frontend
        port:
          number: 80
---
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: allow-egress-googleapis
spec:
  hosts:
  - "accounts.google.com" # Used to get token
  - "*.googleapis.com"
  ports:
  - number: 80
    protocol: HTTP
    name: http
  - number: 443
    protocol: HTTPS
    name: https
---
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: allow-egress-google-metadata
spec:
  hosts:
  - metadata.google.internal
  addresses:
  - 169.254.169.254 # GCE metadata server
  ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: HTTPS
---
EOF
cat <<EOF> $PROJDIR/cluster1/services-all.yaml
apiVersion: v1
kind: Service
metadata:
  name: emailservice
spec:
  type: ClusterIP
  selector:
    app: emailservice
  ports:
  - name: grpc
    port: 5000
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: checkoutservice
spec:
  type: ClusterIP
  selector:
    app: checkoutservice
  ports:
  - name: grpc
    port: 5050
    targetPort: 5050
---
apiVersion: v1
kind: Service
metadata:
  name: recommendationservice
spec:
  type: ClusterIP
  selector:
    app: recommendationservice
  ports:
  - name: grpc
    port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: paymentservice
spec:
  type: ClusterIP
  selector:
    app: paymentservice
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
---
apiVersion: v1
kind: Service
metadata:
  name: productcatalogservice
spec:
  type: ClusterIP
  selector:
    app: productcatalogservice
  ports:
  - name: grpc
    port: 3550
    targetPort: 3550
---
apiVersion: v1
kind: Service
metadata:
  name: cartservice
spec:
  type: ClusterIP
  selector:
    app: cartservice
  ports:
  - name: grpc
    port: 7070
    targetPort: 7070
---
apiVersion: v1
kind: Service
metadata:
  name: currencyservice
spec:
  type: ClusterIP
  selector:
    app: currencyservice
  ports:
  - name: grpc
    port: 7000
    targetPort: 7000
---
apiVersion: v1
kind: Service
metadata:
  name: shippingservice
spec:
  type: ClusterIP
  selector:
    app: shippingservice
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cart
spec:
  type: ClusterIP
  selector:
    app: redis-cart
  ports:
  - name: tls-redis
    port: 6379
    targetPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: adservice
spec:
  type: ClusterIP
  selector:
    app: adservice
  ports:
  - name: grpc
    port: 9555
    targetPort: 9555
---
EOF
cat <<EOF> $PROJDIR/cluster2/deployments.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: recommendationservice
spec:
  selector:
    matchLabels:
      app: recommendationservice
  template:
    metadata:
      labels:
        app: recommendationservice
    spec:
      terminationGracePeriodSeconds: 5
      containers:
      - name: server
        image: gcr.io/google-samples/microservices-demo/recommendationservice:v0.3.9
        ports:
        - containerPort: 8080
        readinessProbe:
          periodSeconds: 5
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:8080"]
        livenessProbe:
          periodSeconds: 5
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:8080"]
        env:
        - name: PORT
          value: "8080"
        - name: PRODUCT_CATALOG_SERVICE_ADDR
          value: "productcatalogservice:3550"
        resources:
          requests:
            cpu: 100m
            memory: 220Mi
          limits:
            cpu: 200m
            memory: 450Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cartservice
spec:
  selector:
    matchLabels:
      app: cartservice
  template:
    metadata:
      labels:
        app: cartservice
    spec:
      terminationGracePeriodSeconds: 5
      containers:
      - name: server
        image: gcr.io/google-samples/microservices-demo/cartservice:v0.3.9
        ports:
        - containerPort: 7070
        env:
        - name: REDIS_ADDR
          value: "redis-cart:6379"
        - name: PORT
          value: "7070"
        - name: LISTEN_ADDR
          value: "0.0.0.0"
        resources:
          requests:
            cpu: 200m
            memory: 64Mi
          limits:
            cpu: 300m
            memory: 128Mi
        readinessProbe:
          initialDelaySeconds: 15
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:7070", "-rpc-timeout=5s"]
        livenessProbe:
          initialDelaySeconds: 15
          periodSeconds: 10
          exec:
            command: ["/bin/grpc_health_probe", "-addr=:7070", "-rpc-timeout=5s"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cart
spec:
  selector:
    matchLabels:
      app: redis-cart
  template:
    metadata:
      labels:
        app: redis-cart
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
        readinessProbe:
          periodSeconds: 5
          tcpSocket:
            port: 6379
        livenessProbe:
          periodSeconds: 5
          tcpSocket:
            port: 6379
        volumeMounts:
        - mountPath: /data
          name: redis-data
        resources:
          limits:
            memory: 256Mi
            cpu: 125m
          requests:
            cpu: 70m
            memory: 200Mi
      volumes:
      - name: redis-data
        emptyDir: {}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgenerator
spec:
  selector:
    matchLabels:
      app: loadgenerator
  replicas: 1
  template:
    metadata:
      labels:
        app: loadgenerator
      annotations:
        sidecar.istio.io/rewriteAppHTTPProbers: "true"
    spec:
      terminationGracePeriodSeconds: 5
      restartPolicy: Always
      containers:
      - name: main
        image: gcr.io/google-samples/microservices-demo/loadgenerator:v0.3.9
        env:
        - name: FRONTEND_ADDR
          value: "frontend:80"
        - name: USERS
          value: "10"
        resources:
          requests:
            cpu: 300m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
EOF
cat <<EOF> $PROJDIR/cluster2/services-all.yaml
apiVersion: v1
kind: Service
metadata:
  name: emailservice
spec:
  type: ClusterIP
  selector:
    app: emailservice
  ports:
  - name: grpc
    port: 5000
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: checkoutservice
spec:
  type: ClusterIP
  selector:
    app: checkoutservice
  ports:
  - name: grpc
    port: 5050
    targetPort: 5050
---
apiVersion: v1
kind: Service
metadata:
  name: recommendationservice
spec:
  type: ClusterIP
  selector:
    app: recommendationservice
  ports:
  - name: grpc
    port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: paymentservice
spec:
  type: ClusterIP
  selector:
    app: paymentservice
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
---
apiVersion: v1
kind: Service
metadata:
  name: productcatalogservice
spec:
  type: ClusterIP
  selector:
    app: productcatalogservice
  ports:
  - name: grpc
    port: 3550
    targetPort: 3550
---
apiVersion: v1
kind: Service
metadata:
  name: cartservice
spec:
  type: ClusterIP
  selector:
    app: cartservice
  ports:
  - name: grpc
    port: 7070
    targetPort: 7070
---
apiVersion: v1
kind: Service
metadata:
  name: currencyservice
spec:
  type: ClusterIP
  selector:
    app: currencyservice
  ports:
  - name: grpc
    port: 7000
    targetPort: 7000
---
apiVersion: v1
kind: Service
metadata:
  name: shippingservice
spec:
  type: ClusterIP
  selector:
    app: shippingservice
  ports:
  - name: grpc
    port: 50051
    targetPort: 50051
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cart
spec:
  type: ClusterIP
  selector:
    app: redis-cart
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: adservice
spec:
  type: ClusterIP
  selector:
    app: adservice
  ports:
  - name: grpc
    port: 9555
    targetPort: 9555
---
EOF
for i in 1 2 
do
    if [ $MODE -eq 1 ]; then
        export STEP="${STEP},7Bi(${i})"   
        echo
        echo "$ kubectl config use-context \$CTX # to set context" | pv -qL 100
        echo
        echo "$ kubectl label namespace default istio.io/rev=\$ASM_REVISION --overwrite # to create ingress" | pv -qL 100
        echo
        echo "$ kubectl -n default apply -f \$PROJDIR/cluster${i} # to configure application" | pv -qL 100
    elif [ $MODE -eq 2 ]; then
        export STEP="${STEP},7B(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $GCP_PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        echo
        echo "$ gcloud --project $PROJECT container clusters get-credentials $CLUSTER # to get cluster credentials" | pv -qL 100
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER
        echo
        echo "$ kubectl config use-context $CTX # to set context" | pv -qL 100
        kubectl config use-context $CTX
        echo
        echo "$ export ASM_REVISION=\$(kubectl get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\\.io\\/rev'}'{\"\\n\"}') # to set revision" | pv -qL 100
        export ASM_REVISION=$(kubectl get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\.io\/rev'}'{"\n"}')
        echo
        echo "$ kubectl label namespace default istio.io/rev=$ASM_REVISION --overwrite # to label namespace" | pv -qL 100
        kubectl label namespace default istio.io/rev=$ASM_REVISION --overwrite
        echo
        echo "$ kubectl -n default apply -f $PROJDIR/cluster${i} # to configure application" | pv -qL 100
        kubectl -n default apply -f $PROJDIR/cluster${i}
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},7Bx(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $GCP_PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        echo
        echo "$ gcloud --project $PROJECT container clusters get-credentials $CLUSTER # to get cluster credentials" | pv -qL 100
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER
        echo
        echo "$ kubectl config use-context $CTX # to set context" | pv -qL 100
        kubectl config use-context $CTX
        echo
        echo "$ kubectl label namespace default istio.io/rev- # to delete label" | pv -qL 100
        kubectl label namespace default istio.io/rev- 
        echo
        echo "$ kubectl -n default delete -f $PROJDIR/cluster${i} # to delete application" | pv -qL 100
        kubectl -n default delete -f $PROJDIR/cluster${i}
    else
        export STEP="${STEP},7Bi"
        echo
        echo "1. Get cluster credentials" | pv -qL 100
        echo "2. Set context" | pv -qL 100
        echo "3. Label namespace" | pv -qL 100
        echo "4. Apply manifest" | pv -qL 100
    fi
done
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"7")
start=`date +%s`
source $PROJDIR/.env
for i in 1 2 
do
    if [ $MODE -eq 1 ]; then
        export STEP="${STEP},7i(${i})"   
        echo
        echo "$ gcloud --project \$PROJECT container clusters get-credentials \$CLUSTER # to get cluster credentials" | pv -qL 100
        echo
        echo "$ kubectl config use-context \$CTX # to set context" | pv -qL 100
        echo
        echo "$ kubectl create namespace bank-of-anthos # to create namespace" | pv -qL 100
        echo
        echo "$ kubectl label namespace default istio.io/rev=\$ASM_REVISION --overwrite # to label namespace" | pv -qL 100
        echo
        echo "$ kubectl label namespace bank-of-anthos istio.io/rev=\$ASM_REVISION --overwrite # to label namespace" | pv -qL 100
        echo
        echo "$ kubectl apply -f \$PROJDIR/bank-of-anthos/istio-manifests # to configure gateway" | pv -qL 100
        echo
        echo "$ kubectl -n bank-of-anthos apply -f \$PROJDIR/bank-of-anthos/extras/jwt/jwt-secret.yaml # to configure secret used for user account creation and authentication" | pv -qL 100
        echo
        echo "$ kubectl -n bank-of-anthos apply -f \$PROJDIR/bank-of-anthos/kubernetes-manifests # to deploy manifests to clusters" | pv -qL 100
        if [ "$i" -eq 2 ]; then
            echo
            echo "$ kubectl -n bank-of-anthos delete statefulset accounts-db # to delete DB statefulSets" | pv -qL 100
            echo
            echo "$ kubectl -n bank-of-anthos delete statefulset ledger-db # to delete DB statefulSets" | pv -qL 100
        fi
    elif [ $MODE -eq 2 ]; then
        export STEP="${STEP},7(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $GCP_PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        echo
        rm -rf /tmp/anthos-service-mesh-packages
        echo "$ git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git /tmp/bank-of-anthos # to clone repo" | pv -qL 100
        git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git /tmp/bank-of-anthos
        echo
        echo "$ cp -rf /tmp/bank-of-anthos $PROJDIR # to copy files" | pv -qL 100
        cp -rf /tmp/bank-of-anthos $PROJDIR
        rm -rf /tmp/bank-of-anthos
        echo
        rm -rf /tmp/anthos-service-mesh-packages
        echo "$ git clone https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages.git /tmp/anthos-service-mesh-packages # to clone repo" | pv -qL 100
        git clone https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages.git /tmp/anthos-service-mesh-packages
        echo
        echo "$ cp -rf /tmp/anthos-service-mesh-packages $PROJDIR # to copy files" | pv -qL 100
        cp -rf /tmp/anthos-service-mesh-packages $PROJDIR
        rm -rf /tmp/anthos-service-mesh-packages
        echo
        echo "$ gcloud --project $PROJECT container clusters get-credentials $CLUSTER # to get cluster credentials" | pv -qL 100
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER
        echo
        echo "$ kubectl config use-context $CTX # to set context" | pv -qL 100
        kubectl config use-context $CTX
        echo
        echo "$ export ASM_REVISION=\$(kubectl get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\\.io\\/rev'}'{\"\\n\"}') # to set revision" | pv -qL 100
        export ASM_REVISION=$(kubectl get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\.io\/rev'}'{"\n"}')
        echo
        echo "$ kubectl create namespace bank-of-anthos # to create namespace" | pv -qL 100
        kubectl create namespace bank-of-anthos
        echo
        echo "$ kubectl label namespace default istio.io/rev=$ASM_REVISION --overwrite # to label namespace" | pv -qL 100
        kubectl label namespace default istio.io/rev=$ASM_REVISION --overwrite
        echo
        echo "$ kubectl label namespace bank-of-anthos istio.io/rev=$ASM_REVISION --overwrite # to label namespace" | pv -qL 100
        kubectl label namespace bank-of-anthos istio.io/rev=$ASM_REVISION --overwrite
        echo
        echo "$ kubectl apply -f $PROJDIR/bank-of-anthos/istio-manifests # to configure gateway" | pv -qL 100
        kubectl apply -f $PROJDIR/bank-of-anthos/istio-manifests
        echo
        echo "$ kubectl -n bank-of-anthos apply -f $PROJDIR/bank-of-anthos/extras/jwt/jwt-secret.yaml # to configure secret used for user account creation and authentication" | pv -qL 100
        kubectl -n bank-of-anthos apply -f $PROJDIR/bank-of-anthos/extras/jwt/jwt-secret.yaml
        echo
        echo "$ kubectl -n bank-of-anthos apply -f $PROJDIR/bank-of-anthos/kubernetes-manifests # to deploy manifests to clusters" | pv -qL 100
        kubectl -n bank-of-anthos apply -f $PROJDIR/bank-of-anthos/kubernetes-manifests
        if [ "$i" -eq 2 ]; then
            echo
            echo "$ kubectl -n bank-of-anthos delete statefulset accounts-db # to delete DB statefulSets" | pv -qL 100
            kubectl -n bank-of-anthos delete statefulset accounts-db
            echo
            echo "$ kubectl -n bank-of-anthos delete statefulset ledger-db # to delete DB statefulSets" | pv -qL 100
            kubectl -n bank-of-anthos delete statefulset ledger-db
        fi
    elif [ $MODE -eq 3 ]; then
        export STEP="${STEP},7x(${i})"   
        export GCP_PROJECT=$(echo GCP_PROJECT_$(eval "echo $i")) > /dev/null 2>&1
        export PROJECT=${!GCP_PROJECT} > /dev/null 2>&1
        export GCP_CLUSTER=$(echo GCP_CLUSTER_$(eval "echo $i")) > /dev/null 2>&1
        export CLUSTER=${!GCP_CLUSTER} > /dev/null 2>&1
        export GCP_REGION=$(echo GCP_REGION_$(eval "echo $i")) > /dev/null 2>&1
        export REGION=${!GCP_REGION} > /dev/null 2>&1
        export GCP_ZONE=$(echo GCP_ZONE_$(eval "echo $i")) > /dev/null 2>&1
        export ZONE=${!GCP_ZONE} > /dev/null 2>&1
        export CTX="gke_${PROJECT}_${ZONE}_${CLUSTER}" > /dev/null 2>&1
        gcloud config set project $GCP_PROJECT > /dev/null 2>&1
        gcloud config set compute/zone $ZONE > /dev/null 2>&1
        echo
        echo "$ gcloud --project $PROJECT container clusters get-credentials $CLUSTER # to get cluster credentials" | pv -qL 100
        gcloud --project $PROJECT container clusters get-credentials $CLUSTER
        echo
        echo "$ kubectl config use-context $CTX # to set context" | pv -qL 100
        kubectl config use-context $CTX
        echo
        echo "$ kubectl delete namespace bank-of-anthos # to delete namespace" | pv -qL 100
        kubectl delete namespace bank-of-anthos
        echo
        echo "$ kubectl delete -f $PROJDIR/bank-of-anthos/istio-manifests # to delete gateway" | pv -qL 100
        kubectl delete -f $PROJDIR/bank-of-anthos/istio-manifests
        echo
        echo "$ rm -rf  $PROJDIR/anthos-service-mesh-packages # to remove repo" | pv -qL 100
        rm -rf $PROJDIR/anthos-service-mesh-packages
        echo
        echo "$ rm -rf $PROJDIR/bank-of-anthos # to remove files" | pv -qL 100
        rm -rf $PROJDIR/bank-of-anthos
    else
        export STEP="${STEP},7i"
        echo
        echo "1. Get cluster credentials" | pv -qL 100
        echo "2. Set context" | pv -qL 100
        echo "3. Label namespace" | pv -qL 100
        echo "4. Apply manifest" | pv -qL 100
    fi
done
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"R")
echo
echo "
  __                      __                              __                               
 /|            /         /              / /              /                 | /             
( |  ___  ___ (___      (___  ___        (___           (___  ___  ___  ___|(___  ___      
  | |___)|    |   )     |    |   )|   )| |    \   )         )|   )|   )|   )|   )|   )(_/_ 
  | |__  |__  |  /      |__  |__/||__/ | |__   \_/       __/ |__/||  / |__/ |__/ |__/  / / 
                                 |              /                                          
"
echo "
We are a group of information technology professionals committed to driving cloud 
adoption. We create cloud skills development assets during our client consulting 
engagements, and use these assets to build cloud skills independently or in partnership 
with training organizations.
 
You can access more resources from our iOS and Android mobile applications.

iOS App: https://apps.apple.com/us/app/tech-equity/id1627029775
Android App: https://play.google.com/store/apps/details?id=com.techequity.app

Email:support@techequity.cloud 
Web: https://techequity.cloud

Ⓒ Tech Equity 2022" | pv -qL 100
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"G")
cloudshell launch-tutorial $SCRIPTPATH/.tutorial.md
;;

"Q")
echo
exit
;;
"q")
echo
exit
;;
* )
echo
echo "Option not available"
;;
esac
sleep 1
done
