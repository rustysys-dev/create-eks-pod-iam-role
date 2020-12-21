#!/bin/bash

function create_eks_pod_iam_role() {
    local CLUSTER_NAME ROLE_NAME ROLE_DESCRIPTION CONTAINER_POLICY_ARN SERVICE_ACCOUNT_NAME
    local ISSUER_ADDRESS ISSUER_ID ISSUER_DOMAIN PROVIDER_ARN ROLE_ARN NAMESPACE
    function usage() {
        echo "Outputs rendered files for specified chart into current directory.
           ${FUNCNAME[0]} -
                   [-h] print this help
                   -c   Name of the EKS Cluster
                   -r   Name of the IAM role to create
                   -d   Description for IAM role
                   -p   IAM policy ARN of to attach to the role
                   -s   Name of the service account
                   -n   Namespace of the service account";
    }

    function check_policy_exists() {
        local POLICY_LIST POLICY
        POLICY_LIST="$(aws iam list-policies --query Policies[].Arn --output text)"
        for POLICY in ${POLICY_LIST}; do
            if [[ "${POLICY}" == "${1}" ]]; then
                return 0
            fi
        done
        echo "INVALID: your policy arn seems to be invalid please verify"
        return 1
    }

    function create_provider_if_not_exists() {
        local PROVIDER_LIST PROVIDER_ARN THUMBPRINT
        PROVIDER_LIST=$(aws iam list-open-id-connect-providers --query OpenIDConnectProviderList --output text)
        PROVIDER_ARN=$(for PROVIDER in ${PROVIDER_LIST}; do
            if [[ "${PROVIDER}" == *"${2}"* ]]; then
                echo "${PROVIDER}"
                return
            fi
        done)
        if ! [ "${PROVIDER_ARN}" ]; then
            FOOTPRINT=$(echo | openssl s_client -servername "${3}" -showcerts -connect "${3}":443 2>&- \
                | tac | sed -n '/-----END CERTIFICATE-----/,/-----BEGIN CERTIFICATE-----/p; /-----BEGIN CERTIFICATE-----/q' \
                | tac | openssl x509 -fingerprint -sha1 -noout \
                | sed 's/://g' | awk -F= '{print tolower($2)}')
            aws iam create-open-id-connect-provider \
                --url "${1}" \
                --client-id-list "sts.amazonaws.com" \
                --thumbprint-list "${FOOTPRINT}" \
                --query OpenIDConnectProviderArn
        else
            echo "${PROVIDER_ARN}"
        fi
    }

    function create_trust_relationship_file() {
        local TRUST_RELATIONSHIP
        read -r -d '' TRUST_RELATIONSHIP <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${1}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${1#*/}:sub": "system:serviceaccount:${3}:${2}"
        }
      }
    }
  ]
}
EOF
        echo "${TRUST_RELATIONSHIP}" > trust.json
    }

    function delete_trust_relationship_file() {
        rm -f trust.json
    }

    # Set options
    while getopts ':c:r:d:p:s:n:' OPTION; do
        case "$OPTION" in
            c)
                CLUSTER_NAME="${OPTARG}"
            ;;
            r)
                ROLE_NAME="${OPTARG}"
            ;;
            d)
                ROLE_DESCRIPTION="${OPTARG}"
            ;;
            p)
                CONTAINER_POLICY_ARN="${OPTARG}"
            ;;
            s)
                SERVICE_ACCOUNT_NAME="${OPTARG}"
            ;;
            n)
                NAMESPACE="${OPTARG}"
            ;;
            *)
                usage;
                return 1;
            ;;
        esac;
    done;

    [ "${CLUSTER_NAME}" ] && \
    [ "${ROLE_NAME}" ] && \
    [ "${ROLE_DESCRIPTION}" ] && \
    [ "${CONTAINER_POLICY_ARN}" ] && \
    [ "${SERVICE_ACCOUNT_NAME}" ] && \
    [ "${NAMESPACE}" ] \
    || { usage; return 1; }

    if ! check_policy_exists "${CONTAINER_POLICY_ARN}"; then
        return 1
    fi

    ISSUER_ADDRESS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.identity.oidc.issuer" --output text)
    ISSUER_ID="${ISSUER_ADDRESS#https://}"
    ISSUER_DOMAIN="${ISSUER_ID%%/*}"
    PROVIDER_ARN=$(create_provider_if_not_exists "${ISSUER_ADDRESS}" "${ISSUER_ID}" "${ISSUER_DOMAIN}")
    create_trust_relationship_file "${PROVIDER_ARN}" "${SERVICE_ACCOUNT_NAME}" "${NAMESPACE}"
    ROLE_ARN="$(aws iam create-role --role-name "${ROLE_NAME}" \
                        --assume-role-policy-document file://trust.json \
                        --description "${ROLE_DESCRIPTION}" \
                        --output text --query Role.Arn)"
    delete_trust_relationship_file
    aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn="${CONTAINER_POLICY_ARN}"
    echo "コンテナーのサービスアカウントの annotations に下記を追加"
    echo "    eks.amazonaws.com/role-arn: ${ROLE_ARN}"
}
