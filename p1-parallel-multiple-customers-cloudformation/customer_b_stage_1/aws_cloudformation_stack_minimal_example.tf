# 180424 Reza Farrahi (imriss@yahoo.com)
provider "aws" {
  region = "${var.aws_region}"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  name_regex = "^ubuntu.*ssd.*18.04.*amd64.*"
  #filter {name = "name" values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-18.04-amd64-server-*"]}
  # filter {name = "virtualization-type" values = ["hvm"]}
  filter {name = "virtualization-type" values = ["hvm"]}
  owners = ["099720109477"] # Canonical
}

data "aws_subnet_ids" "subnet" {
  vpc_id = "${var.vpc_id}"
#  id = "${var.subnet_id}"
  tags { Name = "${var.subnet_name}"}
}

data "aws_subnet_ids" "subnet2" {
  vpc_id = "${var.vpc_id}"
  tags { Name = "${var.subnet2_name}"}
}

data "aws_route53_zone" "target" {
  name = "${var.domain_name}."
}

resource "aws_acm_certificate" "rfcertificate" {
  domain_name = "${var.instance_name}-elb.${var.domain_name}"
  validation_method = "DNS"
  #subject_alternative_names = ["${var.instance_name}-elb.${var.domain_name}"]
  tags {
    Name = "rfcertificate"
  }
}

resource "aws_route53_record" "rfcertificate_validation" {
  #count = "${1 + length(var.cert_san_names)}"
  count = "${1}"
  zone_id = "${data.aws_route53_zone.target.zone_id}"
  #zone_id = "${var.zone_id}"
  name    = "${lookup(aws_acm_certificate.rfcertificate.domain_validation_options[count.index], "resource_record_name")}"
  type    = "${lookup(aws_acm_certificate.rfcertificate.domain_validation_options[count.index], "resource_record_type")}"
  ttl     = 60
  records = ["${lookup(aws_acm_certificate.rfcertificate.domain_validation_options[count.index], "resource_record_value")}"]
}

resource "aws_acm_certificate_validation" "rfcertificate" {
  certificate_arn = "${aws_acm_certificate.rfcertificate.arn}"
  validation_record_fqdns = ["${aws_route53_record.rfcertificate_validation.*.fqdn}"]
}

locals {
  securitygroup_name = "${var.instance_name}SG"
  subnet_id = "${join(",", data.aws_subnet_ids.subnet.ids)}"
  subnet2_id = "${join(",", data.aws_subnet_ids.subnet2.ids)}"
  rfeip = "${replace("${var.stack_name}-rfeip", "-", "")}"
  rftargetgroup = "${replace("${var.stack_name}-rftg", "-", "")}"
  rfelasticLoadbalancer = "${replace("${var.stack_name}-rfelb", "-", "")}"
  rfelasticLoadbalancerrecord = "${replace("${var.stack_name}-rfelbr", "-", "")}"
}

output "rfcertificate_arn" {
  value = "${aws_acm_certificate_validation.rfcertificate.certificate_arn}"
}

output "rfcertificate_id" {
  value = "${aws_acm_certificate.rfcertificate.id}"
}

output "rfroute53_id" {
  value = "${aws_route53_record.rfcertificate_validation.*.id}"
}

resource "aws_cloudformation_stack" "test-rf-customerb-stage1" {
  name = "${var.stack_name}"

  template_body = <<STACK
{
  "AWSTemplateFormatVersion":"2010-09-09",
  "Resources" : {
    "${var.instance_name}" : {
      "Type" : "AWS::EC2::Instance",
      "Properties" : {
        "ImageId" : "${data.aws_ami.ubuntu.id}",
        "DisableApiTermination" : "false",
        "InstanceType" : "${var.instance_type}",
        "KeyName" : "${var.aws_key_name}",
        "SubnetId" : "${local.subnet_id}",
        "SecurityGroupIds" : [{"Ref" : "${local.securitygroup_name}" }],
        "Tags" : [ {"Key":"Name", "Value":"${var.stack_name}-cloudformation"}],
        "BlockDeviceMappings" : [
          {
            "DeviceName" : "/dev/sda1",
            "Ebs" : { "VolumeSize" : "8" } 
          },{
            "DeviceName" : "/dev/sde",
            "Ebs" : { "VolumeSize" : "20" }
          }
        ]
      }
    },
    "${local.securitygroup_name}" : {
      "Type" : "AWS::EC2::SecurityGroup",
      "Properties" : {
        "GroupName" : {"Fn::Join" : [ "-", [ "${var.instance_name}", "sg", "${var.vpc_id}" ] ]},
        "GroupDescription" : "rf-test-cloudformation SG",
        "SecurityGroupEgress" : [ {
          "CidrIp" : "0.0.0.0/0",
          "Description" : "rf-test-cloudformation Egress",
          "FromPort" : -1,
          "IpProtocol" : -1,
          "ToPort" : -1
        } ],
        "SecurityGroupIngress" : [ 
          {"CidrIp" : "0.0.0.0/0",
          "Description" : "rf-test-cloudformation Ingress",
          "FromPort" : 443,
          "IpProtocol" : "tcp",
          "ToPort" : 443
          },
          {"CidrIp" : "111.111.222.222/32",
          "Description" : "rf-test-cloudformation Ingress ssh",
          "FromPort" : 22,
          "IpProtocol" : "tcp",
          "ToPort" : 22
          }
        ],
        "Tags" : [ {"Key":"Name", "Value":{"Fn::Join" : [ "-", [ "${var.instance_name}", "sg", "${var.vpc_id}" ] ]} }],
        "VpcId" : "${var.vpc_id}"
      }
    },
    "rftargetgroup" : {
      "Type" : "AWS::ElasticLoadBalancingV2::TargetGroup",
      "Properties" : {
        "HealthCheckIntervalSeconds": 30,
        "HealthCheckProtocol": "HTTPS",
        "HealthCheckTimeoutSeconds": 10,
        "HealthyThresholdCount": 4,
        "Matcher" : {
          "HttpCode" : "200"
        },
        "Name": "${local.rftargetgroup}",
        "Port": 443,
        "Protocol": "HTTPS",
        "TargetGroupAttributes": [{
          "Key": "deregistration_delay.timeout_seconds",
          "Value": "20"
        }],
        "Targets": [
          { "Id": {"Ref" : "${var.instance_name}"}, "Port": 443 }
        ],
        "UnhealthyThresholdCount": 3,
        "VpcId": "${var.vpc_id}",
        "Tags" : [ {"Key":"Name", "Value":{"Fn::Join" : [ "-", [ "${var.instance_name}", "tg", "${var.vpc_id}" ] ]} }]
      }
    },
    "rfelasticLoadbalancer": {
      "Type": "AWS::ElasticLoadBalancing::LoadBalancer",
      "Properties": {
        "SecurityGroups" : [ { "Ref" :"${local.securitygroup_name}" } ],
        "Instances": [ {"Ref" : "${var.instance_name}" } ],
        "Scheme" : "internet-facing",
        "Subnets" : [ "${local.subnet_id}", "${local.subnet2_id}" ],
        "Listeners": [ { 
          "LoadBalancerPort": "443",
          "InstancePort": "443",
          "InstanceProtocol": "HTTPS",
          "Protocol": "HTTPS",
          "SSLCertificateId" : "${aws_acm_certificate_validation.rfcertificate.certificate_arn}",
          "PolicyNames" : ["ELBSecurityPolicy", 
            "ELBAppCookieStickinessPolicyJSESSIONID"
          ]
        }],
        "LBCookieStickinessPolicy": [ {
          "PolicyName": "rfelb-cookie-policy", 
          "CookieExpirationPeriod": 1200
        }], 
        "Policies" : [
          { "PolicyName" : "ELBSecurityPolicy",
            "PolicyType" : "SSLNegotiationPolicyType",
            "Attributes" : [
              { "Name"  : "Reference-Security-Policy", "Value" : "ELBSecurityPolicy-TLS-1-2-2017-01" }
            ]},
          { "PolicyName" : "ELBAppCookieStickinessPolicyJSESSIONID",
            "PolicyType" : "AppCookieStickinessPolicyType",
            "Attributes" : [
              { "Name" : "CookieName", "Value" : "JSESSIONID"}
            ]}
        ]
      }
    },
    "rfelasticLoadbalancerrecord" : {
        "Type" : "AWS::Route53::RecordSetGroup",
        "Properties" : {
          "HostedZoneName" : "${var.domain_name}.",
          "RecordSets" : [
            {
              "Name" : "${var.instance_name}-elb.${var.domain_name}.",
              "Type" : "A",
              "AliasTarget" : {
                  "HostedZoneId" : { "Fn::GetAtt" : ["rfelasticLoadbalancer", "CanonicalHostedZoneNameID"] },
                  "DNSName" : { "Fn::GetAtt" : ["rfelasticLoadbalancer","DNSName"] } } } ] }
    },
    "${local.rfeip}" : {
      "Type" : "AWS::EC2::EIP",
      "Properties" : {
        "InstanceId" : { "Ref" : "${var.instance_name}" },
        "Domain" :  "vpc"
      }
    }
  },
  "Outputs" : {
    "rfeipallocid" : {
        "Description" : "Test-rf outputs",
        "Value": { "Fn::GetAtt" : [ "${local.rfeip}", "AllocationId" ] }
    },
    "rfeip" : {
        "Description" : "Test-rf outputs",
        "Value": { "Fn::GetAtt" : [ "${var.instance_name}", "PublicIp" ] }
    },
    "rfelb" : {
        "Description" : "Test-rf outputs",
        "Value": { "Fn::GetAtt" : [ "rfelasticLoadbalancer", "DNSName" ] }
    },
    "rfsubnet" : {
        "Description" : "Test-rf outputs",
        "Value": "${local.subnet_id}"
    }
  }
}
STACK
}

output "cf_outputs" {
  value = "${aws_cloudformation_stack.test-rf-customerb-stage1.outputs}"

}

# "${aws_cloudformation_stack.test-rf-customerb-stage1.outputs}"
