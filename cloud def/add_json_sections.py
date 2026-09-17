# -*- coding: utf-8 -*-
"""Remove all architecture images from the service files and insert a
"JSON File Format" section describing the JSON used by each AWS/Azure service."""
import os, re, shutil

ROOT = "/home/user"

# =====================================================================
# Per-service JSON sections: key -> markdown section (after ## JSON File Format)
# =====================================================================
SECTIONS = {

# ---------------------------- AWS CORE ----------------------------
"aws-vpc-peering": """VPC Peering is defined in **Infrastructure-as-Code** and CLI input as JSON. The most common form is the CloudFormation `AWS::EC2::VPCPeeringConnection` resource (JSON or YAML). Routes and route-table entries are separate JSON resources.

```json
{
  "Type": "AWS::EC2::VPCPeeringConnection",
  "Properties": {
    "VpcId": "vpc-0abc123",
    "PeerVpcId": "vpc-0def456",
    "PeerRegion": "us-west-2",
    "PeerOwnerId": "111122223333"
  }
}
```

**Key fields:** `VpcId` (requester VPC) · `PeerVpcId` (accepter VPC) · `PeerRegion` (cross-region) · `PeerOwnerId` (cross-account). The CLI also accepts `--cli-input-json` for `create-vpc-peering-connection` / `accept-vpc-peering-connection`.
""",

"aws-transit-gateway": """Transit Gateway (TGW) attachments and route tables are modelled as JSON in CloudFormation (`AWS::EC2::TransitGateway`, `AWS::EC2::TransitGatewayAttachment`, `AWS::EC2::TransitGatewayRouteTable`).

```json
{
  "Type": "AWS::EC2::TransitGateway",
  "Properties": {
    "Description": "Shared network hub",
    "AmazonSideAsn": 64512,
    "AutoAcceptSharedAttachments": "disable",
    "DefaultRouteTableAssociation": "enable",
    "DefaultRouteTablePropagation": "enable"
  }
}
```

**Key fields:** `AmazonSideAsn` (BGP ASN used for VPN/DX) · `AutoAcceptSharedAttachments` (shared-via-RAM behaviour) · `DefaultRouteTableAssociation` / `DefaultRouteTablePropagation` (routing policy defaults).
""",

"aws-security-groups": """Security Group rules are JSON when created via CLI/CloudFormation — the classic form is an **ingress/egress rule object** inside `AWS::EC2::SecurityGroup` or the `authorize-security-group-ingress` API.

```json
{
  "IpProtocol": "tcp",
  "FromPort": 443,
  "ToPort": 443,
  "IpRanges": [{ "CidrIp": "0.0.0.0/0", "Description": "HTTPS from anywhere" }],
  "UserIdGroupPairs": [{ "GroupId": "sg-0abc123", "Description": "from app tier SG" }]
}
```

**Key fields:** `IpProtocol` (tcp/udp/icmp/-1) · `FromPort`/`ToPort` · `IpRanges` (CIDRs) · `Ipv6Ranges` · `UserIdGroupPairs` (SG-to-SG reference) · `PrefixListIds` (managed prefix lists).
""",

"aws-network-acls": """NACL entries are JSON in CloudFormation (`AWS::EC2::NetworkAcl` + `AWS::EC2::NetworkAclEntry`) or `create-network-acl-entry`. Because NACLs are stateless, you model **both** directions.

```json
{
  "Type": "AWS::EC2::NetworkAclEntry",
  "Properties": {
    "NetworkAclId": "acl-0abc123",
    "RuleNumber": 100,
    "Protocol": "6",
    "RuleAction": "allow",
    "Egress": false,
    "CidrBlock": "0.0.0.0/0",
    "PortRange": { "From": 443, "To": 443 }
  }
}
```

**Key fields:** `RuleNumber` (1–32766, evaluated in order) · `RuleAction` (allow/deny) · `Egress` (false = inbound, true = outbound) · `Protocol` (IANA number, e.g. 6 = TCP) · `PortRange`.
""",

"aws-nat-gateway": """A NAT Gateway is declared in JSON via CloudFormation `AWS::EC2::NatGateway` (and the Elastic IP via `AWS::EC2::EIP`).

```json
{
  "Type": "AWS::EC2::NatGateway",
  "Properties": {
    "SubnetId": "subnet-public-1",
    "AllocationId": { "Fn::GetAtt": ["MyEIP", "AllocationId"] },
    "ConnectivityType": "public"
  }
}
```

**Key fields:** `SubnetId` (must be a **public** subnet) · `AllocationId` (the Elastic IP) · `ConnectivityType` (public / private for private-NAT). Route tables reference the NAT via `AWS::EC2::Route` with `NatGatewayId`.
""",

"aws-vpc-endpoints": """VPC Endpoints are JSON in CloudFormation (`AWS::EC2::VPCEndpoint`). The **endpoint policy** (an IAM-style policy document) is the important JSON payload inside it.

```json
{
  "Type": "AWS::EC2::VPCEndpoint",
  "Properties": {
    "VpcEndpointType": "Interface",
    "ServiceName": "com.amazonaws.us-east-1.ssm",
    "VpcId": "vpc-0abc123",
    "SubnetIds": ["subnet-1", "subnet-2"],
    "PrivateDnsEnabled": true,
    "SecurityGroupIds": ["sg-0abc123"],
    "PolicyDocument": { "Statement": [ { "Effect": "Allow", "Action": "*", "Resource": "*" } ] }
  }
}
```

**Key fields:** `VpcEndpointType` (Interface / Gateway) · `ServiceName` · `PrivateDnsEnabled` · `PolicyDocument` (endpoint policy — extra gate on top of IAM).
""",

"aws-application-load-balancer": """ALB listener rules and target groups are JSON in CloudFormation (`AWS::ElasticLoadBalancingV2::ListenerRule`, `AWS::ElasticLoadBalancingV2::TargetGroup`). The rule **conditions/actions** JSON is the interesting part.

```json
{
  "Type": "AWS::ElasticLoadBalancingV2::ListenerRule",
  "Properties": {
    "ListenerArn": "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/my-alb/abc/def",
    "Priority": 10,
    "Conditions": [{ "Field": "path-pattern", "Values": ["/api/*"] }],
    "Actions": [{ "Type": "forward", "TargetGroupArn": "arn:aws:elasticloadbalancing:...:targetgroup/api/xyz" }]
  }
}
```

**Key fields:** `Conditions` (path-pattern, host-header, http-header, query-string, source-ip, http-request-method) · `Actions` (forward, redirect, fixed-response, authenticate-oidc/cognito) · `Priority` (lower = evaluated first).
""",

"aws-network-load-balancer": """NLB is JSON via CloudFormation `AWS::ElasticLoadBalancingV2::LoadBalancer` with `Type: network`. Static IPs are expressed as per-subnet **mappings** with Elastic IP allocations.

```json
{
  "Type": "AWS::ElasticLoadBalancingV2::LoadBalancer",
  "Properties": {
    "Type": "network",
    "Scheme": "internal",
    "SubnetMappings": [
      { "SubnetId": "subnet-a", "AllocationId": "eipalloc-0aaa" },
      { "SubnetId": "subnet-b", "AllocationId": "eipalloc-0bbb" }
    ]
  }
}
```

**Key fields:** `Type` (network) · `Scheme` (internet-facing / internal) · `SubnetMappings` (one entry per AZ; `AllocationId` = static EIP) · listeners (`TLS`/`TCP`/`UDP`) and target groups (`Protocol: TCP_UDP`).
""",

"aws-global-accelerator": """Global Accelerator resources are JSON in CloudFormation: `AWS::GlobalAccelerator::Accelerator`, `::Listener`, `::EndpointGroup`, `::Endpoint`.

```json
{
  "Type": "AWS::GlobalAccelerator::Accelerator",
  "Properties": {
    "Name": "my-accelerator",
    "IpAddressType": "IPV4",
    "Enabled": true
  }
}
```

**Key fields:** `IpAddressType` (IPV4 / DUAL_STACK) · `IpAddresses` (BYOIP) · Listener `PortRanges` + `Protocol` (TCP/UDP) · EndpointGroup `EndpointGroupRegion` + `TrafficDialPercentage` (0–100) · Endpoint `Weight`.
""",

"aws-s3-bucket": """S3's flagship JSON is the **bucket policy** (resource-based policy) and the **CORS/notification/lifecycle** configuration. Bucket policies use the IAM policy language.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::111122223333:role/app-role" },
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
    "Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0abc123" } }
  }]
}
```

**Key fields:** `Principal` (who) · `Action` / `Resource` (ARNs) · `Condition` (e.g. `aws:SourceVpce`, `s3:prefix`). Also relevant: Lifecycle rules, Event Notification config, and CORS config are all JSON documents.
""",

"aws-ebs-volumes": """EBS volumes are declared in JSON via CloudFormation `AWS::EC2::Volume` (or inside `BlockDeviceMappings` of an instance/AMI).

```json
{
  "Type": "AWS::EC2::Volume",
  "Properties": {
    "AvailabilityZone": "us-east-1a",
    "Size": 100,
    "VolumeType": "gp3",
    "Iops": 3000,
    "Throughput": 250,
    "Encrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"
  }
}
```

**Key fields:** `VolumeType` (gp2/gp3/io2/st1/sc1) · `Size` (GiB) · `Iops` / `Throughput` (gp3/io2 are provisionable) · `Encrypted` + `KmsKeyId` · `AvailabilityZone` (volumes are AZ-scoped).
""",

"aws-mysql": """RDS instances are declared in JSON via CloudFormation `AWS::RDS::DBInstance` (and `AWS::RDS::DBParameterGroup` / `DBSubnetGroup`).

```json
{
  "Type": "AWS::RDS::DBInstance",
  "Properties": {
    "Engine": "mysql",
    "EngineVersion": "8.0",
    "DBInstanceClass": "db.t3.medium",
    "AllocatedStorage": 100,
    "MultiAZ": true,
    "StorageEncrypted": true,
    "DBParameterGroupName": "my-param-group",
    "DBSubnetGroupName": "my-subnet-group"
  }
}
```

**Key fields:** `Engine` / `EngineVersion` · `DBInstanceClass` · `MultiAZ` (synchronous standby = HA) · `StorageEncrypted` · `DBParameterGroupName` / `DBSubnetGroupName`. Parameter-group values themselves are name/value JSON.
""",

"aws-dynamodb": """DynamoDB uses JSON for **items** (documents) and for **table definitions** (`CreateTable`). Attribute values are typed with single-letter tags (S/N/B/M/L/SS/NS/BOOL).

```json
{
  "UserID": { "S": "u-123" },
  "OrderID": { "N": "1001" },
  "Total": { "N": "42.50" },
  "Tags": { "SS": ["new", "priority"] },
  "Metadata": { "M": { "region": { "S": "ap-south-1" } } }
}
```

**Key fields:** attribute type tags — `S` string · `N` number · `B` binary · `BOOL` · `M` map · `L` list · `SS/NS/BS` sets. Table JSON carries `KeySchema` (partition + optional sort key), `AttributeDefinitions`, `ProvisionedThroughput` (RCU/WCU) or `BillingMode: PAY_PER_REQUEST`.
""",

"aws-iam-policies": """IAM policies are the canonical **JSON policy document** — the format every other AWS policy (bucket, endpoint, key) reuses.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowS3Read",
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
    "Condition": { "StringEquals": { "aws:PrincipalTag/team": "data" } }
  }]
}
```

**Key fields:** `Version` (2012-10-17) · `Statement[]` · `Sid` · `Effect` (Allow/Deny — **explicit Deny always wins**) · `Action`/`NotAction` · `Resource`/`NotResource` · `Condition` (operators like `StringEquals`, `IpAddress`, `ArnLike`).
""",

"aws-inline-policies": """An inline policy uses the **same JSON document structure** as a managed policy, but it is embedded in exactly one principal (via `put-user-policy` / `put-role-policy` / `put-group-policy`) and deleted with it.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::my-bucket/*"]
  }]
}
```

**Key fields:** identical to a managed policy (`Version`, `Statement`, `Effect`, `Action`, `Resource`, `Condition`). Differences are **behavioural, not structural**: no versioning, no reuse, and it counts toward the principal's total policy-size quota.
""",

"aws-ami": """AMIs are represented in JSON through EC2 launch/block-device mapping (`AWS::EC2::Instance`, `AWS::EC2::LaunchTemplate`) and EC2 Image Builder pipelines (`AWS::ImageBuilder::ImagePipeline`).

```json
{
  "Type": "AWS::EC2::Instance",
  "Properties": {
    "ImageId": "ami-0abc123",
    "InstanceType": "t3.medium",
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": { "VolumeSize": 30, "VolumeType": "gp3", "DeleteOnTermination": true }
    }],
    "UserData": { "Fn::Base64": "#!/bin/bash ..." }
  }
}
```

**Key fields:** `ImageId` (the AMI) · `BlockDeviceMappings` (`Ebs` size/type/`DeleteOnTermination`) · `UserData` (base64 bootstrap script). An AMI itself = snapshot + block device mapping + launch permissions.
""",

"aws-auto-scaling": """Auto Scaling groups are JSON via CloudFormation (`AWS::AutoScaling::AutoScalingGroup`, `::ScalingPolicy`, `::LaunchConfiguration`) and via `create-auto-scaling-group` CLI JSON.

```json
{
  "Type": "AWS::AutoScaling::AutoScalingGroup",
  "Properties": {
    "MinSize": "2",
    "MaxSize": "10",
    "DesiredCapacity": "3",
    "VPCZoneIdentifier": ["subnet-a", "subnet-b"],
    "TargetGroupARNs": ["arn:aws:elasticloadbalancing:...:targetgroup/app/xyz"],
    "LaunchTemplate": { "LaunchTemplateId": "lt-0abc123", "Version": "$Latest" }
  }
}
```

**Key fields:** `MinSize` / `MaxSize` / `DesiredCapacity` · `VPCZoneIdentifier` (subnets across AZs) · `TargetGroupARNs` (LB integration) · `LaunchTemplate`. Scaling-policy JSON adds `PolicyType` (TargetTrackingScaling etc.) + `TargetValue`.
""",

"aws-cloudwatch": """CloudWatch alarms, dashboards, and metric data are JSON (e.g. `put-metric-alarm`, `AWS::CloudWatch::Alarm`, and the metric-data format for custom metrics).

```json
{
  "AlarmName": "high-cpu",
  "MetricName": "CPUUtilization",
  "Namespace": "AWS/EC2",
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 2,
  "Threshold": 85,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": ["arn:aws:sns:us-east-1:111122223333:oncall"]
}
```

**Key fields:** `MetricName` / `Namespace` / `Dimensions` · `Statistic` (Average/Sum/Maximum/p99…) · `Period` × `EvaluationPeriods` (datapoints to alarm) · `ComparisonOperator` + `Threshold` · `AlarmActions` (SNS/ASG targets).
""",

"aws-cloudtrail": """CloudTrail **events** are JSON records (the raw log files in S3 and the EventBridge payload are both JSON).

```json
{
  "eventVersion": "1.08",
  "eventTime": "2026-09-13T10:30:00Z",
  "eventSource": "ec2.amazonaws.com",
  "eventName": "RunInstances",
  "userIdentity": { "type": "AssumedRole", "arn": "arn:aws:sts::111122223333:assumed-role/admin/jdoe" },
  "sourceIPAddress": "203.0.113.10",
  "requestParameters": { "instanceType": "t3.micro" },
  "responseElements": { "instancesSet": { "items": [{ "instanceId": "i-0abc123" }] } }
}
```

**Key fields:** `eventName` + `eventSource` (what happened) · `userIdentity` (who — includes assumed-role chains) · `sourceIPAddress` / `userAgent` · `requestParameters` / `responseElements` · `errorCode` (failures). Management vs **data events** (S3/Lambda/DynamoDB) are both JSON.
""",

"aws-config": """AWS Config stores **configuration items** and rule results as JSON (the S3 delivery and `get-resource-config-history` output are JSON).

```json
{
  "configurationItemVersion": "1.3",
  "resourceType": "AWS::EC2::SecurityGroup",
  "resourceId": "sg-0abc123",
  "configurationItemCaptureTime": "2026-09-13T10:00:00Z",
  "configurationState": "OK",
  "configuration": { "groupName": "web-sg" },
  "relationships": [],
  "tags": { "env": "prod" }
}
```

**Key fields:** `resourceType` / `resourceId` · `configuration` (the actual snapshot) · `relationships` (linked resources) · `configurationItemCaptureTime` (timeline). Config **rules** (custom Lambda) report via `PutEvaluations` JSON.
""",

# ---------------------------- AWS OTHER ----------------------------
"aws-route-53": """Route 53 records are JSON in CloudFormation (`AWS::Route53::RecordSet`) and via `change-resource-record-sets` (a `ChangeBatch` JSON with `Action: UPSERT/DELETE`).

```json
{
  "Type": "AWS::Route53::RecordSet",
  "Properties": {
    "HostedZoneId": "Z123456",
    "Name": "app.example.com.",
    "Type": "A",
    "AliasTarget": {
      "HostedZoneId": "Z35SXDOTRQ7X7K",
      "DNSName": "my-alb-123.us-east-1.elb.amazonaws.com"
    }
  }
}
```

**Key fields:** `Name` + `Type` (A/CNAME/MX/TXT…) · `TTL` (plain records) vs `AliasTarget` (AWS resources — free + apex-capable) · routing-policy fields: `SetIdentifier`, `Weight`, `Region`, `GeoLocation`, `Failover` (PRIMARY/SECONDARY), `HealthCheckId`.
""",

"aws-cloudfront": """CloudFront distributions use a large **DistributionConfig** JSON (via CloudFormation `AWS::CloudFront::Distribution` or `create-distribution`).

```json
{
  "Origins": { "Items": [{
    "Id": "s3-origin",
    "DomainName": "my-bucket.s3.us-east-1.amazonaws.com",
    "S3OriginConfig": { "OriginAccessIdentity": "origin-access-identity/cloudfront/EXAMPLE" }
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "MinTTL": 0, "DefaultTTL": 86400, "MaxTTL": 31536000
  },
  "Enabled": true
}
```

**Key fields:** `Origins` · `DefaultCacheBehavior` (`TTLs`, `ViewerProtocolPolicy`, cache policy/origin-request policy IDs) · `CacheBehaviors` (path rules) · `ViewerCertificate` (TLS) · `PriceClass`. Cache policies / origin request policies are their own JSON documents.
""",

"aws-lambda": """Lambda uses JSON for **events** (the payload passed to the handler) and for function configuration (CloudFormation `AWS::Lambda::Function`). Events are source-specific JSON structures.

```json
{
  "Records": [{
    "eventSource": "aws:s3",
    "eventTime": "2026-09-13T10:30:00Z",
    "s3": {
      "bucket": { "name": "uploads" },
      "object": { "key": "img/photo.jpg", "size": 1048576 }
    }
  }]
}
```

**Key fields (event):** source wrapper (`Records` for S3/SQS/DynamoDB, `detail` for EventBridge, `body` for API Gateway) + the event payload. **Config JSON:** `Runtime`, `Handler`, `MemorySize`, `Timeout`, `Role`, `Environment`, `VpcConfig`.
""",

"aws-sqs": """SQS messages are sent/received as JSON (via `send-message` / `receive-message`). The body is usually a JSON payload, with **message attributes** as structured metadata.

```json
{
  "MessageBody": "{\"orderId\": \"1001\", \"amount\": 42.5}",
  "MessageAttributes": {
    "eventType": { "DataType": "String", "StringValue": "order-created" }
  },
  "DelaySeconds": 0,
  "MessageGroupId": "user-123",
  "MessageDeduplicationId": "ord-1001"
}
```

**Key fields:** `MessageBody` (often JSON) · `MessageAttributes` (typed metadata) · `DelaySeconds` · FIFO-only: `MessageGroupId` (ordering) + `MessageDeduplicationId` (exactly-once). Received messages add `ReceiptHandle`, `MessageId`, `ApproximateReceiveCount`.
""",

"aws-sns": """SNS delivers a **notification envelope** JSON to subscribers (Lambda, HTTP, SQS); the actual payload sits in the `Message` field.

```json
{
  "Type": "Notification",
  "MessageId": "abc-123-xyz",
  "TopicArn": "arn:aws:sns:us-east-1:111122223333:orders",
  "Subject": "New order",
  "Message": "{\"orderId\": \"1001\"}",
  "Timestamp": "2026-09-13T10:00:00Z",
  "MessageAttributes": {
    "eventType": { "Type": "String", "Value": "order-created" }
  }
}
```

**Key fields:** `Message` (the payload — typically JSON) · `MessageAttributes` (used by **subscription filter policies**) · `TopicArn` / `Subject`. Filter policies are also JSON (`{\"eventType\": [\"order-created\"]}`).
""",

"aws-api-gateway": """API Gateway REST APIs are imported/exported as **OpenAPI (Swagger) JSON**, including AWS extensions that wire each path to a backend.

```json
{
  "openapi": "3.0.1",
  "info": { "title": "Orders API", "version": "1.0" },
  "paths": {
    "/orders": {
      "get": {
        "x-amazon-apigateway-integration": {
          "type": "aws_proxy",
          "httpMethod": "POST",
          "uri": "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:...:invocations"
        }
      }
    }
  }
}
```

**Key fields:** `paths` + methods · `x-amazon-apigateway-integration` (`aws_proxy` / `http` / `mock` backend mapping) · `securitySchemes` (auth) · `models` (request/response schemas) · `x-amazon-apigateway-request-validator` (validation).
""",

"aws-ecs": """ECS's signature JSON is the **task definition** — the blueprint for containers, networking, roles, and secrets.

```json
{
  "family": "web-app",
  "networkMode": "awsvpc",
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::111122223333:role/appRole",
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [{
    "name": "web",
    "image": "111122223333.dkr.ecr.us-east-1.amazonaws.com/web:1.0",
    "portMappings": [{ "containerPort": 8080, "protocol": "tcp" }],
    "secrets": [{ "name": "DB_PASSWORD", "valueFrom": "arn:aws:secretsmanager:us-east-1:111122223333:secret:db" }]
  }]
}
```

**Key fields:** `family` · `networkMode` (awsvpc/bridge/host) · `taskRoleArn` (app permissions) vs `executionRoleArn` (pull images/logs/secrets) · `containerDefinitions[]` (image, portMappings, environment, secrets) · `cpu`/`memory`.
""",

"aws-eks": """Kubernetes objects (used with EKS) are expressed as JSON — the API wire format — though manifests are usually written in YAML. A Deployment manifest in JSON:

```json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": { "name": "web", "namespace": "prod" },
  "spec": {
    "replicas": 3,
    "selector": { "matchLabels": { "app": "web" } },
    "template": {
      "metadata": { "labels": { "app": "web" } },
      "spec": { "containers": [{ "name": "web", "image": "repo/web:1.0" }] }
    }
  }
}
```

**Key fields:** `apiVersion` + `kind` · `metadata` (name/namespace/labels) · `spec` (replicas, selector, template, containers) · `status` (runtime state). ConfigMaps/Secrets, Services, and Ingresses follow the same JSON schema.
""",

"aws-kms": """KMS access is governed by the **key policy** — a resource-based JSON policy document (same language as IAM policies).

```json
{
  "Version": "2012-10-17",
  "Id": "key-policy",
  "Statement": [{
    "Sid": "Allow use of the key",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::111122223333:role/app-role" },
    "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
    "Resource": "*",
    "Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0abc123" } }
  }]
}
```

**Key fields:** `Principal` · `Action` (`kms:Encrypt/Decrypt/ReEncrypt*`, `kms:CreateGrant`, `kms:DescribeKey`…) · `Resource` (usually `*` = the key itself) · `Condition` (`aws:SourceVpce`, `kms:ViaService`, `aws:SourceAccount`). Both the **key policy and IAM policy** must allow.
""",

"aws-secrets-manager": """A Secrets Manager **secret value** is a JSON object of key-value pairs, retrieved via `GetSecretValue.SecretString`.

```json
{
  "username": "appuser",
  "password": "S3cr3t-Passw0rd!",
  "host": "db.example.internal",
  "port": "3306",
  "dbname": "orders"
}
```

**Key fields:** arbitrary key-value JSON (structured credentials) · **versioning** via staging labels `AWSCURRENT` / `AWSPENDING` / `AWSPREVIOUS` · rotation Lambdas receive/return this JSON in the rotation steps (createSecret → setSecret → testSecret → finishSecret).
""",

"aws-systems-manager": """SSM **documents** (Run Command, Automation, State Manager) are JSON (or YAML) files that define actions and parameters.

```json
{
  "schemaVersion": "0.3",
  "description": "Restart an unhealthy instance",
  "parameters": { "InstanceId": { "type": "String" } },
  "mainSteps": [{
    "name": "restart",
    "action": "aws:changeInstanceState",
    "inputs": { "InstanceIds": ["{{ InstanceId }}"], "DesiredState": "running" }
  }]
}
```

**Key fields:** `schemaVersion` (0.3) · `parameters` (typed, e.g. String/StringList/AWS::EC2::Instance::Id) · `mainSteps[]` with `action` (aws:runCommand, aws:invokeLambda, aws:approve…) + `inputs`. Parameter Store values also support JSON strings.
""",

"aws-elasticache": """ElastiCache clusters are declared in JSON via CloudFormation (`AWS::ElastiCache::CacheCluster`, `::ReplicationGroup`).

```json
{
  "Type": "AWS::ElastiCache::CacheCluster",
  "Properties": {
    "Engine": "redis",
    "CacheNodeType": "cache.r6g.large",
    "NumCacheNodes": 1,
    "VpcSecurityGroupIds": ["sg-0abc123"],
    "CacheSubnetGroupName": "cache-subnets"
  }
}
```

**Key fields:** `Engine` (redis / memcached) · `CacheNodeType` · `NumCacheNodes` · `CacheSubnetGroupName` (subnets across AZs) · `VpcSecurityGroupIds`. Redis **cluster mode** uses `AWS::ElastiCache::ReplicationGroup` with `NumNodeGroups` (shards) + `ReplicasPerNodeGroup`.
""",

# ---------------------------- AZURE CORE ----------------------------
"azure-basic-networking": """Azure VNets are deployed with **ARM templates** (JSON). Every Azure resource follows the same ARM JSON shape: `type`, `apiVersion`, `name`, `properties`.

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "resources": [{
    "type": "Microsoft.Network/virtualNetworks",
    "apiVersion": "2023-04-01",
    "name": "myVNet",
    "properties": {
      "addressSpace": { "addressPrefixes": ["10.0.0.0/16"] },
      "subnets": [
        { "name": "web", "properties": { "addressPrefix": "10.0.0.0/24" } },
        { "name": "db",  "properties": { "addressPrefix": "10.0.1.0/24" } }
      ]
    }
  }]
}
```

**Key fields:** `type` (resource provider path) · `apiVersion` · `name` · `properties.addressSpace` / `subnets[].addressPrefix`. Bicep compiles down to this same ARM JSON.
""",

"azure-nsg-introduction": """NSGs are defined in JSON as ARM resources (`Microsoft.Network/networkSecurityGroups`) whose `securityRules` array holds the rule objects.

```json
{
  "type": "Microsoft.Network/networkSecurityGroups",
  "apiVersion": "2023-04-01",
  "name": "web-nsg",
  "properties": {
    "securityRules": [{
      "name": "AllowHttps",
      "properties": {
        "priority": 100,
        "direction": "Inbound",
        "access": "Allow",
        "protocol": "Tcp",
        "sourcePortRange": "*",
        "destinationPortRange": "443",
        "sourceAddressPrefix": "*",
        "destinationAddressPrefix": "*"
      }
    }]
  }
}
```

**Key fields:** `securityRules[]` · `priority` (100–4096, lower wins) · `direction` (Inbound/Outbound) · `access` (Allow/Deny) · `protocol` · `sourceAddressPrefix` / `destinationAddressPrefix` (CIDR, service tag, or ASG id) · port ranges.
""",

"azure-nsg-inbound-rules": """Inbound NSG rules are the same JSON rule shape with `direction: "Inbound"`. The source can be a CIDR, a **service tag**, or an **ASG resource id**.

```json
{
  "name": "AllowSshFromOffice",
  "properties": {
    "priority": 110,
    "direction": "Inbound",
    "access": "Allow",
    "protocol": "Tcp",
    "sourceAddressPrefix": "203.0.113.0/24",
    "sourcePortRange": "*",
    "destinationAddressPrefix": "*",
    "destinationPortRange": "22"
  }
}
```

**Key fields:** `direction: "Inbound"` · `sourceAddressPrefix` (or `sourceAddressPrefixes[]`, `sourceApplicationSecurityGroups[]`) · `destinationPortRange` / `destinationPortRanges[]`. NSGs are stateful, so the return path is automatic; inbound evaluation order is subnet NSG → NIC NSG.
""",

"azure-nsg-outbound-rules": """Outbound NSG rules use `direction: "Outbound"`. Azure allows all outbound by default, so you add **Deny** rules to lock down egress.

```json
{
  "name": "DenyInternet",
  "properties": {
    "priority": 100,
    "direction": "Outbound",
    "access": "Deny",
    "protocol": "*",
    "sourceAddressPrefix": "*",
    "sourcePortRange": "*",
    "destinationAddressPrefix": "Internet",
    "destinationPortRange": "*"
  }
}
```

**Key fields:** `direction: "Outbound"` · `destinationAddressPrefix` (e.g. `Internet`, `VirtualNetwork`, service tags) · `access: "Deny"` (since outbound defaults to allow). Outbound evaluation order is **NIC NSG → subnet NSG** (reverse of inbound).
""",

"azure-asg": """Application Security Groups are JSON ARM resources (`Microsoft.Network/applicationSecurityGroups`), and NSG rules reference them by **resource id** as source/destination.

```json
{
  "type": "Microsoft.Network/applicationSecurityGroups",
  "apiVersion": "2023-04-01",
  "name": "web-asg",
  "location": "eastus",
  "properties": {}
}
```

Rule referencing an ASG:
```json
{
  "name": "AllowWebToDb",
  "properties": {
    "priority": 100,
    "direction": "Inbound",
    "access": "Allow",
    "protocol": "Tcp",
    "sourceApplicationSecurityGroups": [{ "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/web-asg" }],
    "destinationApplicationSecurityGroups": [{ "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/db-asg" }],
    "destinationPortRange": "1433"
  }
}
```

**Key fields:** `sourceApplicationSecurityGroups` / `destinationApplicationSecurityGroups` (full resource ids, VNet-scoped). NICs join an ASG via the NIC's `ipConfigurations[].applicationSecurityGroups`.
""",

"azure-hub-and-spoke": """Hub-spoke connectivity is expressed in JSON as **VNet peering** ARM resources (`Microsoft.Network/virtualNetworks/virtualNetworkPeerings`) plus route tables (`Microsoft.Network/routeTables`).

```json
{
  "type": "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
  "apiVersion": "2023-04-01",
  "name": "hub/spokeA-to-hub",
  "properties": {
    "remoteVirtualNetwork": { "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub" },
    "allowVirtualNetworkAccess": true,
    "allowForwardedTraffic": true,
    "useRemoteGateways": true
  }
}
```

**Key fields:** `remoteVirtualNetwork.id` · `allowVirtualNetworkAccess` (enable peering) · `allowForwardedTraffic` (NVA transit) · `allowGatewayTransit` / `useRemoteGateways` (share the hub's VPN/ER gateway). UDRs are `routeTables` with `routes[]` (nextHopType: VirtualAppliance/VirtualNetworkGateway).
""",

"azure-vpn": """Azure VPN Gateways are ARM JSON: `Microsoft.Network/virtualNetworkGateways`, `localNetworkGateways`, and `connections`.

```json
{
  "type": "Microsoft.Network/virtualNetworkGateways",
  "apiVersion": "2023-04-01",
  "name": "vpn-gw",
  "properties": {
    "gatewayType": "Vpn",
    "vpnType": "RouteBased",
    "sku": { "name": "VpnGw1", "tier": "VpnGw1" },
    "ipConfigurations": [{
      "name": "gw-ip",
      "properties": { "subnet": { "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/GatewaySubnet" } }
    }]
  }
}
```

**Key fields:** `gatewayType` (Vpn / ExpressRoute) · `vpnType` (RouteBased / PolicyBased) · `sku` (VpnGw1–5) · `ipConfigurations[].subnet` (must be **GatewaySubnet**). `localNetworkGateways` JSON holds the on-prem public IP + `localNetworkAddressSpace`; `connections` JSON holds the shared key (`sharedKey`).
""",

"azure-load-balancer": """Azure Load Balancers are ARM JSON (`Microsoft.Network/loadBalancers`) with frontends, backend pools, rules, and probes.

```json
{
  "type": "Microsoft.Network/loadBalancers",
  "apiVersion": "2023-04-01",
  "name": "myLB",
  "sku": { "name": "Standard" },
  "properties": {
    "frontendIPConfigurations": [{ "name": "fe", "properties": { "publicIPAddress": { "id": "/subscriptions/<sub>/.../publicIPAddresses/pip" } } }],
    "backendAddressPools": [{ "name": "pool1" }],
    "probes": [{ "name": "http", "properties": { "protocol": "Tcp", "port": 80 } }],
    "loadBalancingRules": [{
      "name": "http",
      "properties": {
        "frontendIPConfiguration": { "id": "[resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations','myLB','fe')]" },
        "backendAddressPool": { "id": "[resourceId('Microsoft.Network/loadBalancers/backendAddressPools','myLB','pool1')]" },
        "protocol": "Tcp", "frontendPort": 80, "backendPort": 80
      }
    }]
  }
}
```

**Key fields:** `sku` (Standard/Basic) · `frontendIPConfigurations` · `backendAddressPools` · `probes` · `loadBalancingRules` (`frontendPort`→`backendPort`) · `inboundNatRules` (per-VM NAT) · `outboundRules` (SNAT).
""",

"azure-application-gateway": """Application Gateway is ARM JSON (`Microsoft.Network/applicationGateways`): listeners, backend pools, HTTP settings, path maps, and routing rules.

```json
{
  "type": "Microsoft.Network/applicationGateways",
  "apiVersion": "2023-04-01",
  "name": "appgw",
  "properties": {
    "sku": { "name": "WAF_v2", "tier": "WAF_v2" },
    "backendAddressPools": [{ "name": "api-pool", "properties": { "backendAddresses": [{ "fqdn": "api.internal" }] } }],
    "backendHttpSettingsCollection": [{ "name": "api-settings", "properties": { "port": 8080, "protocol": "Http" } }],
    "httpListeners": [{ "name": "https", "properties": { "frontendIPConfiguration": { "id": "[...]" }, "protocol": "Https", "sslCertificate": { "id": "[...]" } } }],
    "requestRoutingRules": [{ "name": "api-route", "properties": { "httpListener": { "id": "[...]" }, "backendAddressPool": { "id": "[...]" }, "backendHttpSettings": { "id": "[...]" } } }]
  }
}
```

**Key fields:** `sku` (Standard_v2 / WAF_v2) · `httpListeners` (SNI/TLS) · `backendAddressPools` · `backendHttpSettingsCollection` · `requestRoutingRules` + `urlPathMaps` (path routing) · `probes`. WAF policies (`Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies`) are separate JSON.
""",

"azure-traffic-manager": """Traffic Manager profiles are ARM JSON (`Microsoft.Network/trafficManagerProfiles`) with DNS config, routing method, monitor config, and endpoints.

```json
{
  "type": "Microsoft.Network/trafficManagerProfiles",
  "apiVersion": "2022-04-01",
  "name": "tmprofile",
  "properties": {
    "profileStatus": "Enabled",
    "trafficRoutingMethod": "Performance",
    "dnsConfig": { "relativeName": "myapp", "ttl": 60 },
    "monitorConfig": { "protocol": "HTTPS", "port": 443, "path": "/health", "intervalInSeconds": 30, "toleratedNumberOfFailures": 3 },
    "endpoints": [{
      "name": "us",
      "type": "Microsoft.Network/trafficManagerProfiles/azureEndpoints",
      "properties": { "endpointStatus": "Enabled", "target": "app-us.azurewebsites.net" }
    }]
  }
}
```

**Key fields:** `trafficRoutingMethod` (Priority/Weighted/Performance/Geographic/Multivalue/Subnet) · `dnsConfig` (relativeName + TTL) · `monitorConfig` (health probes) · `endpoints[].properties` (`priority`, `weight`, `geoMapping`, `target`).
""",

"azure-front-door": """Azure Front Door (Standard/Premium) is ARM JSON under `Microsoft.Cdn/profiles` (or the Classic `Microsoft.Network/frontDoors`): origins, origin groups, and routes.

```json
{
  "type": "Microsoft.Cdn/profiles",
  "apiVersion": "2023-05-01",
  "name": "fd-profile",
  "sku": { "name": "Premium_AzureFrontDoor" },
  "properties": {
    "originGroups": [{
      "name": "default",
      "properties": {
        "loadBalancing": { "sampleSize": 4 },
        "healthProbeSettings": { "probePath": "/health", "probeProtocol": "Https" }
      }
    }],
    "origins": [{ "name": "app", "properties": { "hostName": "app.azurewebsites.net" } }],
    "routes": [{ "name": "api", "properties": { "originGroup": { "id": "[...]" }, "patternsToMatch": ["/api/*"] } }]
  }
}
```

**Key fields:** `originGroups` (health probes + load balancing) · `origins` (backends) · `routes` (`patternsToMatch`) · `endpoints` (frontend domains) · `securityPolicies` (WAF) · `ruleSets` (rules engine). Classic Front Door uses `frontendEndpoints`/`routingRules` instead.
""",

"azure-virtual-machines": """Azure VMs are ARM JSON (`Microsoft.Compute/virtualMachines`) combining hardware, storage, OS, and network profiles.

```json
{
  "type": "Microsoft.Compute/virtualMachines",
  "apiVersion": "2023-03-01",
  "name": "myVM",
  "properties": {
    "hardwareProfile": { "vmSize": "Standard_D2s_v3" },
    "storageProfile": {
      "imageReference": { "publisher": "Canonical", "offer": "0001-com-ubuntu-server-jammy", "sku": "22_04-lts-gen2", "version": "latest" },
      "osDisk": { "createOption": "FromImage", "managedDisk": { "storageAccountType": "Premium_LRS" } }
    },
    "osProfile": { "computerName": "myvm", "adminUsername": "azureuser" },
    "networkProfile": { "networkInterfaces": [{ "id": "/subscriptions/<sub>/.../networkInterfaces/myvm-nic" }] }
  }
}
```

**Key fields:** `hardwareProfile.vmSize` · `storageProfile` (`imageReference`, `osDisk`/`dataDisks`) · `osProfile` · `networkProfile.networkInterfaces` · `zones` (availability zones) / `availabilitySet.id`.
""",

"azure-image-creation": """Azure image building is **JSON-native**: an Azure VM Image Builder template (`Microsoft.VirtualMachineImages/imageTemplates`) defines source → customize → distribute.

```json
{
  "type": "Microsoft.VirtualMachineImages/imageTemplates",
  "apiVersion": "2022-07-01",
  "name": "goldenImage",
  "properties": {
    "source": { "type": "PlatformImage", "publisher": "Canonical", "offer": "0001-com-ubuntu-server-jammy", "sku": "22_04-lts-gen2" },
    "customize": [
      { "type": "Shell", "name": "installAgent", "inline": ["curl -sL https://example.com/agent.sh | bash"] }
    ],
    "distribute": [{
      "type": "SharedImage",
      "galleryImageId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Compute/galleries/g/images/web/versions/1.0.0",
      "runOutputName": "web",
      "artifactTags": { "source": "CI" },
      "replicationRegions": ["eastus", "westeurope"]
    }]
  }
}
```

**Key fields:** `source` (PlatformImage / ManagedImage / SharedImageVersion) · `customize[]` steps (Shell, PowerShell, File, WindowsRestart) · `distribute[]` (`SharedImage` gallery id + `replicationRegions`, or `ManagedImage`). This is the JSON file format for image creation.
""",

"azure-storage-accounts": """Storage accounts are ARM JSON (`Microsoft.Storage/storageAccounts`) — SKU (redundancy), kind, and security flags.

```json
{
  "type": "Microsoft.Storage/storageAccounts",
  "apiVersion": "2023-01-01",
  "name": "mystoreacct",
  "sku": { "name": "Standard_LRS" },
  "kind": "StorageV2",
  "properties": {
    "allowBlobPublicAccess": false,
    "minimumTlsVersion": "TLS1_2",
    "accessTier": "Hot",
    "encryption": { "keySource": "Microsoft.Storage", "services": { "blob": { "enabled": true } } }
  }
}
```

**Key fields:** `sku.name` (Standard_LRS/ZRS/GRS/GZRS or Premium_*) · `kind` (StorageV2) · `allowBlobPublicAccess` · `minimumTlsVersion` · `accessTier` (Hot/Cool). Containers are `Microsoft.Storage/storageAccounts/blobServices/containers`.
""",

"azure-identity-management-storage": """Storage identity management uses **RBAC role assignments** (JSON) on the storage account, referencing Entra ID identities and data-plane role definitions.

```json
{
  "properties": {
    "roleDefinitionId": "/subscriptions/<sub>/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe",
    "principalId": "6f2b...-managed-identity-objectId",
    "principalType": "ServicePrincipal",
    "scope": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/mystoreacct"
  }
}
```

**Key fields:** `roleDefinitionId` (e.g. **Storage Blob Data Contributor** = `ba92f5b4-2d11-453d-a403-e96b0029c9fe`) · `principalId`/`principalType` (User/Group/ServicePrincipal) · `scope`. Role **definitions** themselves are JSON (`Microsoft.Authorization/roleDefinitions` with `permissions[].actions`).
""",

"azure-recovery-services-vault-backup": """Recovery Services Vaults and backup policies are ARM JSON: `Microsoft.RecoveryServices/vaults` and `.../backupPolicies` (schedule + retention).

```json
{
  "type": "Microsoft.RecoveryServices/vaults",
  "apiVersion": "2023-01-01",
  "name": "backupVault",
  "sku": { "name": "RS0", "tier": "Standard" },
  "properties": {}
}
```

Policy:
```json
{
  "name": "dailyPolicy",
  "properties": {
    "backupManagementType": "AzureIaasVM",
    "schedulePolicy": {
      "schedulePolicyType": "SimpleSchedulePolicy",
      "scheduleRunFrequency": "Daily",
      "scheduleRunTimes": ["2026-09-13T02:00:00Z"]
    },
    "retentionPolicy": {
      "retentionPolicyType": "LongTermRetentionPolicy",
      "dailySchedule": { "retentionDuration": { "count": 30, "durationType": "Days" } }
    }
  }
}
```

**Key fields:** `backupManagementType` (AzureIaasVM / AzureWorkload / AzureFileShare) · `schedulePolicy` (frequency + run times) · `retentionPolicy` (daily/weekly/monthly/yearly durations). Protected items register via `backupProtectedItems` JSON.
""",

"azure-recovery-services-vault-restore": """Restore operations are triggered with a **REST request JSON** (`IaasVMRestoreRequest` and variants) against the recovery point.

```json
{
  "properties": {
    "objectType": "IaasVMRestoreRequest",
    "recoveryPointId": "1234567890",
    "recoveryType": "OriginalLocation",
    "sourceResourceId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/myVM",
    "createNewCloudService": false,
    "restoreDiskLunList": [0]
  }
}
```

**Key fields:** `objectType` (IaasVMRestoreRequest) · `recoveryPointId` · `recoveryType` (OriginalLocation / AlternateLocation / RestoreDisks) · `sourceResourceId`. Alternate-location restores add `targetVirtualNetworkId`, `targetSubnetId`, and `targetResourceGroupId`.
""",

"azure-active-directory": """Entra ID (Azure AD) objects are JSON via **Microsoft Graph** (users, groups, apps) and app registration manifests.

```json
{
  "displayName": "Jane Doe",
  "userPrincipalName": "jane.doe@corp.com",
  "mail": "jane.doe@corp.com",
  "accountEnabled": true,
  "usageLocation": "IN",
  "extension_abc123_Department": "Engineering"
}
```

**Key fields:** `displayName`, `userPrincipalName`, `accountEnabled`, `extension_*` (directory extensions), `identities`. **App registrations** JSON: `displayName`, `signInAudience`, `requiredResourceAccess` (delegated/app permissions), `web.redirectUris`, `keyCredentials`/`passwordCredentials`. Conditional Access policies are also JSON documents.
""",

"azure-sql": """Azure SQL servers and databases are ARM JSON (`Microsoft.Sql/servers`, `Microsoft.Sql/servers/databases`) with the service tier in `sku`.

```json
{
  "type": "Microsoft.Sql/servers/databases",
  "apiVersion": "2022-05-01-preview",
  "name": "sqlsrv/ordersdb",
  "sku": { "name": "GP_Gen5", "tier": "GeneralPurpose" },
  "properties": {
    "maxSizeBytes": 268435456000,
    "zoneRedundant": false,
    "minCapacity": 0.5,
    "readScaleOut": "Enabled"
  }
}
```

**Key fields:** `sku.name/tier` (GP_Gen5, BC_Gen5, HS_Gen5; or DTU tiers Basic/S0/P1…) · `maxSizeBytes` · `zoneRedundant` (HA) · `minCapacity` (serverless auto-pause) · `readScaleOut` (readable replicas). Firewall rules and failover groups are also JSON.
""",

"azure-monitoring": """Azure Monitor config uses JSON **Data Collection Rules (DCR)** and **alert rules** (ARM `Microsoft.Insights/...`).

```json
{
  "type": "Microsoft.Insights/dataCollectionRules",
  "apiVersion": "2022-06-01",
  "name": "dcr-vm-logs",
  "properties": {
    "dataSources": {
      "performanceCounters": [{
        "name": "cpu",
        "counterSpecifiers": ["Processor(_Total) Percent Processor Time"],
        "samplingFrequencyInSeconds": 60
      }]
    },
    "destinations": {
      "logAnalytics": [{ "workspaceResourceId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law", "name": "law" }]
    },
    "dataFlows": [{ "streams": ["Microsoft-Perf"], "destinations": ["law"] }]
  }
}
```

**Key fields:** `dataSources` (what to collect) · `destinations` (Log Analytics workspace) · `dataFlows` (stream → destination mapping) · `streams` (Microsoft-Perf, Microsoft-Syslog…). Alert rules are JSON too (`Microsoft.Insights/metricAlerts` or `scheduledQueryRules`).
""",

"azure-log-analytics": """Log Analytics **saved searches** (and the query API) are JSON; the workspace itself is ARM JSON (`Microsoft.OperationalInsights/workspaces`). Queries are KQL strings stored in JSON.

```json
{
  "type": "Microsoft.OperationalInsights/workspaces/savedSearches",
  "apiVersion": "2020-08-01",
  "name": "law/errors-last-hour",
  "properties": {
    "category": "Ops",
    "displayName": "Errors in the last hour",
    "query": "Event | where TimeGenerated > ago(1h) | where EventLevelName == 'Error' | summarize count() by Source"
  }
}
```

**Key fields:** `query` (the KQL string) · `category` / `displayName`. The **query API response** is also JSON (`tables[].rows`). Workspace JSON carries `retentionInDays`, `sku`, and `publicNetworkAccessForIngestion`.
""",

"azure-nsg-flow-logs": """NSG flow logs are stored as **JSON blobs** — the record structure (Version 1/2) with flows and the matched rule.

```json
{
  "records": [{
    "time": "2026-09-13T10:00:00.0000000Z",
    "category": "NetworkSecurityGroupFlowEvent",
    "properties": {
      "Version": 2,
      "flows": [{
        "rule": "UserRule_AllowHttps",
        "flows": [{
          "mac": "000D3A123456",
          "flowTuples": ["172.16.1.4,203.0.113.9,55910,443,T,I,D,B,1024,2048,120,300"]
        }]
      }]
    }
  }]
}
```

**Key fields:** `category` · `Version` (1 or 2 — v2 adds bytes/packets) · `flows[].rule` (the NSG rule that matched) · `flowTuples[]` — a comma string: `srcIP,dstIP,srcPort,dstPort,protocol,TrafficFlow(I/O),TrafficDecision(A/D),FlowState(B/E),bytesSent,bytesReceived,…`.
""",

"azure-app-service": """App Service apps are ARM JSON (`Microsoft.Web/sites`), with slots as `Microsoft.Web/sites/slots`.

```json
{
  "type": "Microsoft.Web/sites",
  "apiVersion": "2022-09-01",
  "name": "myapp",
  "kind": "app,linux",
  "properties": {
    "serverFarmId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Web/serverfarms/plan1",
    "httpsOnly": true,
    "siteConfig": {
      "linuxFxVersion": "DOCKER|myreg.azurecr.io/web:1.0",
      "minTlsVersion": "1.2",
      "appSettings": [{ "name": "KEY", "value": "val" }]
    }
  }
}
```

**Key fields:** `serverFarmId` (App Service Plan) · `httpsOnly` · `siteConfig` (`linuxFxVersion`/`windowsFxVersion`, `appSettings`, `minTlsVersion`) · `kind`. App settings can be **Key Vault references** (`@Microsoft.KeyVault(SecretUri=...)`), which are JSON-encoded values.
""",

"azure-api-services": """Azure API Management APIs are defined in **OpenAPI (Swagger) JSON**, imported to auto-generate the API and operations.

```json
{
  "openapi": "3.0.1",
  "info": { "title": "Orders API", "version": "1.0.0" },
  "servers": [{ "url": "https://apim.azure-api.net/orders/v1" }],
  "paths": {
    "/orders": {
      "get": {
        "summary": "List orders",
        "responses": { "200": { "description": "OK" } }
      }
    }
  }
}
```

**Key fields:** `openapi` version · `paths` (operations → APIM operations) · `info`/`servers`. Note: APIM **policies are XML** (not JSON) — the exception to the JSON rule in APIM. The APIM service itself is ARM JSON (`Microsoft.ApiManagement/service`).
""",

# ---------------------------- AZURE OTHER ----------------------------
"azure-functions": """Azure Functions bindings are declared in **function.json** (per function) — the core JSON file format of Functions. `host.json` (runtime config) and `local.settings.json` (local dev) are also JSON.

```json
{
  "bindings": [
    { "name": "myBlob", "type": "blobTrigger", "direction": "in",  "path": "uploads/{name}", "connection": "AzureWebJobsStorage" },
    { "name": "outBlob", "type": "blob", "direction": "out", "path": "thumbs/{name}.png", "connection": "AzureWebJobsStorage" }
  ]
}
```

**Key fields:** `bindings[]` with `name`, `type` (httpTrigger, timerTrigger, queueTrigger, blobTrigger, serviceBusTrigger…) · `direction` (in/out) · `path` / `connection` / `queueName`. `host.json` holds `version`, `extensions`, and `logging` config.
""",

"azure-logic-apps": """A Logic Apps workflow is **entirely JSON** — the workflow definition (triggers + actions) is a JSON document (Consumption and Standard both use it).

```json
{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "triggers": {
      "When_a_HTTP_request_is_received": {
        "type": "Request",
        "kind": "Http",
        "inputs": { "method": "POST", "schema": {} }
      }
    },
    "actions": {
      "Send_an_email": {
        "type": "ApiConnection",
        "inputs": {
          "host": { "connection": { "name": "@parameters('$connections')['office365']['connectionId']" } },
          "method": "post",
          "path": "/v2/Mail"
        }
      }
    },
    "outputs": {}
  },
  "parameters": { "$connections": { "type": "Object", "defaultValue": {} } }
}
```

**Key fields:** `definition` (the workflow) · `triggers` / `actions` with `type` (Request, Recurrence, ApiConnection…) · `inputs` · `parameters` (`$connections` maps to API connections). Control actions (Condition, For_each) are JSON nodes too.
""",

"azure-key-vault": """Key Vaults are ARM JSON (`Microsoft.KeyVault/vaults`), and secret **values** are stored as JSON strings (key-value pairs), like Secrets Manager.

```json
{
  "type": "Microsoft.KeyVault/vaults",
  "apiVersion": "2022-07-01",
  "name": "myVault",
  "properties": {
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "sku": { "family": "A", "name": "standard" },
    "enableSoftDelete": true,
    "enablePurgeProtection": true,
    "networkAcls": { "defaultAction": "Deny", "bypass": "AzureServices" }
  }
}
```

**Key fields:** `tenantId` · `sku` (standard / premium) · `enableSoftDelete` / `enablePurgeProtection` · `networkAcls` (private access). Secret value example: `{ "username": "appuser", "password": "S3cr3t!" }` — retrieved as `value` via REST/SDK.
""",

"azure-cosmos-db": """Cosmos DB stores **items as JSON documents** — schema-less, with system properties added by the engine. Account/container config is ARM JSON (`Microsoft.DocumentDB/databaseAccounts`).

```json
{
  "id": "order-1001",
  "userId": "user-123",
  "items": [ { "sku": "A-1", "qty": 2, "price": 9.99 } ],
  "total": 19.98,
  "status": "placed",
  "_rid": "AAAAAA==",
  "_etag": "0000abcd-0000-0000-0000-000000000000",
  "_ts": 1750000000
}
```

**Key fields:** `id` (unique **within a partition**) · the **partition key** property (e.g. `userId`) · system fields `_rid`/`_etag`/`_ts` · any JSON structure (arrays, nested objects). Indexing and throughput (RU/s) live in the container JSON.
""",

"azure-aks": """AKS workloads are Kubernetes objects, expressed as JSON (the API wire format; manifests are usually written in YAML).

```json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": { "name": "web", "namespace": "prod" },
  "spec": {
    "replicas": 3,
    "selector": { "matchLabels": { "app": "web" } },
    "template": {
      "metadata": { "labels": { "app": "web" } },
      "spec": {
        "containers": [{
          "name": "web",
          "image": "myacr.azurecr.io/web:1.0",
          "ports": [{ "containerPort": 80 }]
        }]
      }
    }
  }
}
```

**Key fields:** `apiVersion` + `kind` · `metadata` · `spec` (replicas, selector, template, containers) · `status`. Secrets/ConfigMaps, Services, and Ingresses use the same JSON schema; Helm charts render to this JSON/YAML.
""",

"azure-service-bus": """Service Bus **message bodies** are typically JSON payloads; the queue/topic resources themselves are ARM JSON (`Microsoft.ServiceBus/namespaces/queues`, `.../topics`).

```json
{
  "orderId": "1001",
  "customerId": "cust-9",
  "amount": 42.5,
  "currency": "USD"
}
```

Queue ARM JSON (key settings):
```json
{
  "type": "Microsoft.ServiceBus/namespaces/queues",
  "apiVersion": "2022-10-01-preview",
  "name": "sbns/orders",
  "properties": {
    "maxDeliveryCount": 10,
    "requiresSession": false,
    "enablePartitioning": true,
    "lockDuration": "PT1M"
  }
}
```

**Key fields (message):** body (JSON) + broker properties `MessageId`, `SessionId`, `TimeToLive`, `Label`. **Key fields (entity):** `maxDeliveryCount` (→ DLQ), `requiresSession` (FIFO), `enablePartitioning`, `lockDuration`.
""",

"azure-devops": """Azure DevOps **pipelines are YAML**, but the REST API and extensions use JSON — e.g. **task.json** (custom task manifest) and pipeline/build definitions exported via REST.

```json
{
  "id": "00000000-0000-0000-0000-000000000000",
  "name": "MyBuildTask",
  "friendlyName": "My Build Task",
  "description": "A custom pipeline task",
  "category": "Build",
  "execution": {
    "Node10": { "target": "index.js", "argumentFormat": "" }
  },
  "inputs": [
    { "name": "apiKey", "type": "string", "label": "API Key", "required": true }
  ]
}
```

**Key fields:** `id` / `name` · `execution` (runtime + entry point) · `inputs[]` (task parameters). Pipeline definitions fetched via the REST API (`GET .../build/definitions/{id}`) are JSON; `azure-pipelines.yml` is YAML.
""",

"azure-defender-for-cloud": """Defender for Cloud recommendations are backed by **Azure Policy definitions** (JSON), and security **alerts** are JSON payloads.

```json
{
  "type": "Microsoft.Authorization/policyDefinitions",
  "apiVersion": "2021-06-01",
  "name": "deny-public-blob",
  "properties": {
    "displayName": "Storage accounts should restrict public access",
    "mode": "All",
    "policyRule": {
      "if": { "allOf": [ { "field": "type", "equals": "Microsoft.Storage/storageAccounts" } ] },
      "then": { "effect": "audit" }
    }
  }
}
```

**Key fields:** `policyRule` (`if` / `then` / `effect` — audit/deny) · `displayName` · `mode`. Security alert JSON: `alertDisplayName`, `severity`, `entities`, `startTimeUtc`, `remediationSteps`. Workflow automation (Logic Apps) is also JSON.
""",
}

# =====================================================================
# Apply: remove architecture images, insert JSON section
# =====================================================================
IMG_RE = re.compile(
    r"\n## Architecture\n\n!\[[^\n]*\]\(data:image/png;base64,[^)]*\)\n\n\*.*?\*\n",
    flags=re.S,
)

updated = 0
for cloud in ("aws", "azure"):
    for dirpath, _dirs, fnames in os.walk(os.path.join(ROOT, cloud)):
        for f in sorted(fnames):
            if not f.endswith(".md") or f == "README.md":
                continue
            md_path = os.path.join(dirpath, f)
            stem = os.path.splitext(f)[0]
            if stem.startswith(cloud + "-"):
                stem = stem[len(cloud) + 1:]
            key = f"{cloud}-{stem}"

            with open(md_path) as fh:
                text = fh.read()

            # 1. strip the architecture image block
            text, n = IMG_RE.subn("\n", text)
            # collapse any triple blank lines left behind
            text = re.sub(r"\n{3,}", "\n\n", text)

            # 2. insert the JSON section right after the intro separator
            section = SECTIONS.get(key)
            if section is None:
                print("NO JSON SECTION for", key)
                continue
            idx = text.index("---") + 3
            block = "\n\n## JSON File Format\n\n" + section.strip() + "\n"
            text = text[:idx] + block + text[idx:]

            with open(md_path, "w") as fh:
                fh.write(text)
            updated += 1

print(f"Updated {updated} files")

# =====================================================================
# Delete images + helper scripts
# =====================================================================
for p in ["images", "gen_diagrams.py", "convert_embed_png.py", "__pycache__"]:
    fp = os.path.join(ROOT, p)
    if os.path.isdir(fp):
        shutil.rmtree(fp)
        print("deleted dir:", p)
    elif os.path.isfile(fp):
        os.remove(fp)
        print("deleted file:", p)
