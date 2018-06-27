# 180430: Reza Farrahi (imriss@yahoo.com)
# Reset the state of all the customers in the subdirs using the "customer_common" as default if not specified

# Function: Main Terraform Cycle of Deployment for one of customers
tf_single_cycle_deploy_cloudformation () {
  local customer_dir=$1
  echo $customer_dir
  rm -rd "${customer_dir}/.terraform"
  rm -rd "${customer_dir}/terraform.tfstate"
  rm -rd "${customer_dir}/terraform.tfstate.*"
}

# Main Prallel Loop
for customer in $(find -maxdepth 1 -type d -printf '%f\n' | grep -v "\."); do tf_single_cycle_deploy_cloudformation "$customer" & done
