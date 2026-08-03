# This script needs to be sourced

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
MAGENTA="\e[0;35m"
NC="\e[0m"

echo "Checking environment readiness to deploy a cluster..."

if [[ -d "/Applications" ]] && [[ -d "/Library" ]] ; then
    echo -e "- ${MAGENTA}Detected MacOS terminal${NC}"
elif  [ "$AWS_EXECUTION_ENV" = "CloudShell" ] ; then
    echo -e "- ${MAGENTA}Detected AWS CloudShell terminal${NC}"
elif [ "$(netstat -ptn 2>&1 | grep '^tcp.*ttyd' | awk '{ split($4, a, ":"); split($7, b, "/"); printf "%s:%s\n", a[2], b[2] }')" = "8080:ttyd" ] ; then
    echo -e "- ${MAGENTA}Detected KodeKloud lab terminal${NC}"
else
    {
    source /etc/os-release
    echo -e "- ${MAGENTA}Detected Linux terminal: ${NAME}${NC}"
    }
fi

if ! command -v aws > /dev/null ; then
    echo -e "${RED}aws cli is not installed. Please install it.${NC}"
    return
fi

if ! command -v terraform > /dev/null ; then
    echo -e "${YELLOW}WARN: terraform is not installed. If you intend to use it, please install it first.${NC}"
fi

if ! command -v jq > /dev/null ; then
    echo -e "${RED}jq is not installed. Please install it.${NC}"
    return
fi

# Verify correct region
current_region=$AWS_REGION

if [[ -z "$current_region" ]]; then
    current_region=$(aws configure get region)
fi

if [[ -z "$current_region" ]]; then
    current_region=$AWS_DEFAULT_REGION
fi

if [[ "$current_region" != "us-east-1" ]]; then
    if [[ -n "$current_region" ]]; then
        echo -e "${RED}The current region is ${current_region}. This must be deployed in us-east-1.${NC}"
        return
    fi
    echo "${RED}Unable to determine the current region. Use "aws configure" to set the default region to us-east-1.${NC}"
    return
fi

echo -e "- ${GREEN}Running in correct region: us-east-1${NC}"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_ID" == "None" ]; then
  echo "${RED}Error: No default VPC found.${NC}"
  return
fi

echo -e "${GREEN}- Using default VPC: ${VPC_ID}${NC}"

IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[0].InternetGatewayId" --output text)

if [ "$IGW_ID" == "None" ]; then
    echo -e "${RED}Error: Default VPC $VPC_ID does not have an Internet Gateway attached.${NC}"
    return
fi

echo -e "${GREEN}- Default VPC $VPC_ID has an Internet Gateway: ${IGW_ID}${NC}"

# Check for the cluster service role being present and flag terraform accordingly.
if aws iam get-role --role-name Monesh-Eks-Cluster-Role > /dev/null 2>&1 ; then
    echo -e "${GREEN}- Using pre-existing role Monesh-Eks-Cluster-Role${NC}"
    export TF_VAR_use_predefined_role=true
else
    echo -e "${YELLOW}- Cluster role Monesh-Eks-Cluster-Role not present; Terraform will create it.${NC}"
    export TF_VAR_use_predefined_role=false
fi

echo -e "${GREEN}Good to go!${NC}"