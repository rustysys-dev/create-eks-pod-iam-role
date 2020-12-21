# create-eks-pod-iam-role
bash function for creating an iam role for eks pods

Usage:

```bash
git clone https://github.com/rustysys-dev/create-eks-pod-iam-role.git
cd create-eks-pod-iam-role
source lib.sh

# Create IAM Role for EKS pod in your AWS default region.
create_eks_pod_iam_role \
    -c <cluster-name> \
    -r <desired-role-name> \
    -d <desired-role-description> \
    -p <policy-ARN-to-attach-to-role> \
    -s <name-of-related-service-account> \
    -n <namespace-of-service-account>

# Create IAM Role for EKS pod in a different region
AWS_DEFAULT_REGION=<your-EKS-cluster-region> create_eks_pod_iam_role \
    -c <cluster-name> \
    -r <desired-role-name> \
    -d <desired-role-description> \
    -p <policy-ARN-to-attach-to-role> \
    -s <name-of-related-service-account> \
    -n <namespace-of-service-account>
```
