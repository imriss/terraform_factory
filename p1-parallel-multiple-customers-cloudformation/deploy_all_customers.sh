# 180430: Reza Farrahi (imriss@yahoo.com)
# Deploy all the customers' CloudFormation Stacks in the subdirs using the "customer_common" as the default source for paramters that might not be explicitly specified for some customers.

# Fucntion: Main Terraform Cycle of Deployment for one of customers
tf_single_cycle_deploy_cloudformation () {
  local customer_dir=$1
  sleep 1;
  echo $customer_dir
  cp customer_common/*.tf "${customer_dir}/"
  cd "${customer_dir}"
  TF_LOG_PATH="${customer_dir}/tf_deploy.log"
  TF_LOG="INFO"
  terraform init; terraform apply --refresh=true -auto-approve;
}

# Main Parallel Loop
for customer in $(find -maxdepth 1 -type d -printf '%f\n' | grep -v "\."); do tf_single_cycle_deploy_cloudformation "$customer" & done
