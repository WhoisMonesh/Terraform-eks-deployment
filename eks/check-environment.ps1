Write-Host "Checking environment readiness to deploy a cluster..."

# Check if AWS CLI is installed
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "aws cli is not installed. Please install it." -ForegroundColor Red
    return
}

# Check if Terraform is installed
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "WARN: terraform is not installed. If you intend to use it, please install it first." -ForegroundColor Yellow
}

# Check if jq is installed
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Host "jq is not installed. Please install it." -ForegroundColor Red
    return
}

# Verify correct region
$current_region = $Env:AWS_REGION
if (-not $current_region) {
    $current_region = aws configure get region
}

if (-not $current_region) {
    $current_region = $Env:AWS_DEFAULT_REGION
}

if ($current_region -ne "us-east-1") {
    if ($current_region) {
        Write-Host "The current region is $current_region. This must be deployed in us-east-1." -ForegroundColor Red
        return
    }
    Write-Host "Unable to determine the current region. Use `aws configure` to set the default region to us-east-1." -ForegroundColor Red
    return
}

Write-Host "- Running in correct region: us-east-1" -ForegroundColor Green

# Get default VPC
$VPC_ID = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text

if ($VPC_ID -eq "None") {
    Write-Host "Error: No default VPC found." -ForegroundColor Red
    return
}

Write-Host "- Using default VPC: $VPC_ID" -ForegroundColor Green

# Check for Internet Gateway
$IGW_ID = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[0].InternetGatewayId" --output text

if ($IGW_ID -eq "None") {
    Write-Host "Error: Default VPC $VPC_ID does not have an Internet Gateway attached." -ForegroundColor Red
    return
}

Write-Host "- Default VPC $VPC_ID has an Internet Gateway: $IGW_ID" -ForegroundColor Green

# Check for the cluster service role being present and flag terraform accordingly.
if (aws iam get-role --role-name "Monesh-Eks-Cluster-Role" 2>$null) {
    Write-Host "- Using pre-existing role Monesh-Eks-Cluster-Role" -ForegroundColor Green
    $env:TF_VAR_use_predefined_role = "true"
} else {
    Write-Host "- Cluster role Monesh-Eks-Cluster-Role not present; Terraform will create it." -ForegroundColor Yellow
    $env:TF_VAR_use_predefined_role = "false"
}

Write-Host "Good to go!" -ForegroundColor Green