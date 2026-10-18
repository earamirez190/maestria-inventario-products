param(
    [string]$Region = 'us-east-1',
    [string]$VpcId = 'vpc-086fa0287f12fa3ca',
    [string[]]$Subnets = @('subnet-04203e5b1994505b2', 'subnet-058969041c2da3066'),
    [string]$ImageTag = 'latest',
    [ValidateRange(2, 50)][int]$ProductsDesiredCount = 2,
    [ValidateRange(2, 50)][int]$AuditDesiredCount = 2
)

$ErrorActionPreference = 'Stop'
$Aws = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'
$AccountId = (& $Aws sts get-caller-identity --query Account --output text).Trim()
$Name = 'maestria-observabilidad'
$ClusterName = "$Name-cluster"
$ProductsServiceName = "$Name-service"
$AuditServiceName = "$Name-audit-service"
$ProductsTaskFamily = "$Name-products-task"
$AuditTaskFamily = "$Name-audit-task"
$ServiceConnectNamespaceName = "$Name.local"
$DbIdentifier = 'maestria-inventario-mysql'
$DbName = 'maestria_inventario_products'
$DbSecretName = "$Name/rds/mysql"
$LogGroup = "/ecs/$Name"
$EcrBase = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$ProductsImage = "$EcrBase/maestria-inventario-products:$ImageTag"
$AuditImage = "$EcrBase/maestria-inventario-audit:$ImageTag"
$CollectorImage = "$EcrBase/maestria-observability-collector:$ImageTag"

function AwsText {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = & $Aws @Arguments
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI falló: aws $($Arguments -join ' ')" }
    return ($result | Out-String).Trim()
}

function ExistingId {
    param([string]$Command, [string[]]$Arguments)
    try { return (AwsText $Command @Arguments) } catch { return $null }
}

function IgnoreAws {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Aws @Arguments 2>$null | Out-Null
    $ErrorActionPreference = $previousPreference
}

Write-Host "Cuenta AWS: $AccountId"
Write-Host "Región: $Region"

# Security groups
$AlbSgName = "$Name-alb-sg"
$EcsSgName = "$Name-ecs-sg"
$RdsSgName = "$Name-rds-sg"
$AlbSg = ExistingId 'ec2' @('describe-security-groups', '--filters', "Name=group-name,Values=$AlbSgName", "Name=vpc-id,Values=$VpcId", '--query', 'SecurityGroups[0].GroupId', '--output', 'text')
if (-not $AlbSg -or $AlbSg -eq 'None') { $AlbSg = AwsText ec2 create-security-group --group-name $AlbSgName --description 'ALB for maestria observabilidad' --vpc-id $VpcId --query GroupId --output text }
$EcsSg = ExistingId 'ec2' @('describe-security-groups', '--filters', "Name=group-name,Values=$EcsSgName", "Name=vpc-id,Values=$VpcId", '--query', 'SecurityGroups[0].GroupId', '--output', 'text')
if (-not $EcsSg -or $EcsSg -eq 'None') { $EcsSg = AwsText ec2 create-security-group --group-name $EcsSgName --description 'ECS tasks for maestria observabilidad' --vpc-id $VpcId --query GroupId --output text }
$RdsSg = ExistingId 'ec2' @('describe-security-groups', '--filters', "Name=group-name,Values=$RdsSgName", "Name=vpc-id,Values=$VpcId", '--query', 'SecurityGroups[0].GroupId', '--output', 'text')
if (-not $RdsSg -or $RdsSg -eq 'None') { $RdsSg = AwsText ec2 create-security-group --group-name $RdsSgName --description 'RDS for maestria observabilidad' --vpc-id $VpcId --query GroupId --output text }
IgnoreAws ec2 authorize-security-group-ingress --group-id $AlbSg --protocol tcp --port 80 --cidr 0.0.0.0/0
IgnoreAws ec2 authorize-security-group-ingress --group-id $EcsSg --protocol tcp --port 9090 --source-group $AlbSg
IgnoreAws ec2 authorize-security-group-ingress --group-id $EcsSg --protocol tcp --port 9090 --source-group $EcsSg
IgnoreAws ec2 authorize-security-group-ingress --group-id $RdsSg --protocol tcp --port 3306 --source-group $EcsSg

# IAM roles
$TrustFile = Join-Path $PSScriptRoot 'ecs-task-trust.json'
$XrayPolicyFile = Join-Path $PSScriptRoot 'xray-policy.json'
$ExecutionRoleName = "$Name-execution-role"
$TaskRoleName = "$Name-task-role"
$ManagedInstanceRoleName = "$Name-fis-managed-instance-role"
$FisExperimentRoleName = "$Name-fis-experiment-role"
$SsmManagedTrustFile = Join-Path $PSScriptRoot 'ssm-managed-instance-trust.json'
$ExecutionRoleArn = ExistingId 'iam' @('get-role', '--role-name', $ExecutionRoleName, '--query', 'Role.Arn', '--output', 'text')
if (-not $ExecutionRoleArn -or $ExecutionRoleArn -eq 'None') { $ExecutionRoleArn = AwsText iam create-role --role-name $ExecutionRoleName --assume-role-policy-document "file://$TrustFile" --query Role.Arn --output text }
IgnoreAws iam attach-role-policy --role-name $ExecutionRoleName --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
$TaskRoleArn = ExistingId 'iam' @('get-role', '--role-name', $TaskRoleName, '--query', 'Role.Arn', '--output', 'text')
if (-not $TaskRoleArn -or $TaskRoleArn -eq 'None') { $TaskRoleArn = AwsText iam create-role --role-name $TaskRoleName --assume-role-policy-document "file://$TrustFile" --query Role.Arn --output text }
AwsText iam put-role-policy --role-name $TaskRoleName --policy-name XRayWriteAccess --policy-document "file://$XrayPolicyFile" | Out-Null

$ManagedInstanceRoleArn = ExistingId 'iam' @('get-role', '--role-name', $ManagedInstanceRoleName, '--query', 'Role.Arn', '--output', 'text')
if (-not $ManagedInstanceRoleArn -or $ManagedInstanceRoleArn -eq 'None') {
    $ManagedInstanceRoleArn = AwsText iam create-role --role-name $ManagedInstanceRoleName --assume-role-policy-document "file://$SsmManagedTrustFile" --query Role.Arn --output text
}
IgnoreAws iam attach-role-policy --role-name $ManagedInstanceRoleName --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
$ManagedInstanceCleanupPolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{ Effect = 'Allow'; Action = @('ssm:DeleteActivation'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ssm:DeregisterManagedInstance'); Resource = "arn:aws:ssm:${Region}:${AccountId}:managed-instance/*" }
    )
} | ConvertTo-Json -Depth 5 -Compress
AwsText iam put-role-policy --role-name $ManagedInstanceRoleName --policy-name FisManagedInstanceCleanup --policy-document $ManagedInstanceCleanupPolicy | Out-Null

$TaskFisPolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{ Effect = 'Allow'; Action = @('ssm:CreateActivation', 'ssm:AddTagsToResource'); Resource = '*' },
        @{
            Effect = 'Allow'; Action = @('iam:PassRole'); Resource = $ManagedInstanceRoleArn
            Condition = @{ StringEquals = @{ 'iam:PassedToService' = 'ssm.amazonaws.com' } }
        }
    )
} | ConvertTo-Json -Depth 6 -Compress
AwsText iam put-role-policy --role-name $TaskRoleName --policy-name FisSsmRegistration --policy-document $TaskFisPolicy | Out-Null

$FisTrustFile = Join-Path $PSScriptRoot 'fis-experiment-trust.json'
$FisExperimentRoleArn = ExistingId 'iam' @('get-role', '--role-name', $FisExperimentRoleName, '--query', 'Role.Arn', '--output', 'text')
if (-not $FisExperimentRoleArn -or $FisExperimentRoleArn -eq 'None') {
    $FisExperimentRoleArn = AwsText iam create-role --role-name $FisExperimentRoleName --assume-role-policy-document "file://$FisTrustFile" --query Role.Arn --output text
}
$FisExperimentPolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{ Effect = 'Allow'; Action = @('ecs:DescribeTasks'); Resource = "arn:aws:ecs:${Region}:${AccountId}:task/$ClusterName/*" },
        @{ Effect = 'Allow'; Action = @('ecs:ListTasks'); Resource = "arn:aws:ecs:${Region}:${AccountId}:cluster/$ClusterName" },
        @{ Effect = 'Allow'; Action = @('ecs:DescribeContainerInstances'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ecs:StopTask'); Resource = "arn:aws:ecs:${Region}:${AccountId}:task/$ClusterName/*" },
        @{ Effect = 'Allow'; Action = @('ec2:DescribeInstances', 'ec2:DescribeSubnets', 'tag:GetResources'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('cloudwatch:DescribeAlarms'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ssm:ListCommands'); Resource = '*' },
        @{
            Effect = 'Allow'; Action = @('ssm:SendCommand')
            Resource = "arn:aws:ssm:${Region}::document/AWSFIS-*"
        },
        @{
            Effect = 'Allow'; Action = @('ssm:SendCommand')
            Resource = "arn:aws:ssm:${Region}:${AccountId}:managed-instance/*"
            Condition = @{ StringEquals = @{ 'ssm:resourceTag/FAULT_INJECTION_SIDECAR' = 'true' } }
        },
        @{ Effect = 'Allow'; Action = @('ssm:CancelCommand'); Resource = "arn:aws:ssm:${Region}:${AccountId}:command/*" }
    )
} | ConvertTo-Json -Depth 6 -Compress
AwsText iam put-role-policy --role-name $FisExperimentRoleName --policy-name FisEcsTaskFaultInjection --policy-document $FisExperimentPolicy | Out-Null
Start-Sleep -Seconds 10

# Database secret and subnet group
$SecretArn = ExistingId 'secretsmanager' @('describe-secret', '--secret-id', $DbSecretName, '--query', 'ARN', '--output', 'text')
$SecretPayloadFile = Join-Path ([IO.Path]::GetTempPath()) "$Name-db-secret.json"
if (-not $SecretArn -or $SecretArn -eq 'None') {
    $PasswordAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#$%&*+-_=.?'
    $DbPassword = -join (1..32 | ForEach-Object { $PasswordAlphabet[(Get-Random -Minimum 0 -Maximum $PasswordAlphabet.Length)] })
    $SecretPayload = @{ username = 'maestria_admin'; password = $DbPassword; engine = 'mysql'; dbname = $DbName } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($SecretPayloadFile, $SecretPayload, (New-Object Text.UTF8Encoding($false)))
    $SecretArn = AwsText secretsmanager create-secret --name $DbSecretName --description 'Credentials for maestria observabilidad RDS' --secret-string "file://$SecretPayloadFile" --query ARN --output text
} else {
    $SecretPayload = AwsText secretsmanager get-secret-value --secret-id $DbSecretName --query SecretString --output text
}
try {
    $Secret = $SecretPayload | ConvertFrom-Json
    if (-not $Secret.username -or -not $Secret.password) { throw 'El secreto no contiene username/password' }
} catch {
    Write-Host 'El secreto existente tiene formato inválido; se reemplazará por JSON válido.'
    $PasswordAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#$%&*+-_=.?'
    $DbPassword = -join (1..32 | ForEach-Object { $PasswordAlphabet[(Get-Random -Minimum 0 -Maximum $PasswordAlphabet.Length)] })
    $SecretPayload = @{ username = 'maestria_admin'; password = $DbPassword; engine = 'mysql'; dbname = $DbName } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($SecretPayloadFile, $SecretPayload, (New-Object Text.UTF8Encoding($false)))
    AwsText secretsmanager put-secret-value --secret-id $DbSecretName --secret-string "file://$SecretPayloadFile" | Out-Null
    $Secret = $SecretPayload | ConvertFrom-Json
}
$ExecutionSecretPolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{
            Effect = 'Allow'
            Action = @('secretsmanager:GetSecretValue')
            Resource = $SecretArn
        }
    )
} | ConvertTo-Json -Depth 5 -Compress
$ExecutionSecretPolicyFile = Join-Path ([IO.Path]::GetTempPath()) "$Name-secret-policy.json"
[IO.File]::WriteAllText($ExecutionSecretPolicyFile, $ExecutionSecretPolicy, (New-Object Text.UTF8Encoding($false)))
AwsText iam put-role-policy --role-name $ExecutionRoleName --policy-name ReadDatabaseSecret --policy-document "file://$ExecutionSecretPolicyFile" | Out-Null

$DbSubnetGroup = "$Name-db-subnet-group"
$ExistingDbSubnet = ExistingId 'rds' @('describe-db-subnet-groups', '--db-subnet-group-name', $DbSubnetGroup, '--query', 'DBSubnetGroups[0].DBSubnetGroupName', '--output', 'text')
if (-not $ExistingDbSubnet -or $ExistingDbSubnet -eq 'None') { AwsText rds create-db-subnet-group --db-subnet-group-name $DbSubnetGroup --db-subnet-group-description 'Subnets for maestria RDS' --subnet-ids $Subnets[0] $Subnets[1] | Out-Null }
$DbStatus = ExistingId 'rds' @('describe-db-instances', '--db-instance-identifier', $DbIdentifier, '--query', 'DBInstances[0].DBInstanceStatus', '--output', 'text')
if (-not $DbStatus -or $DbStatus -eq 'None') {
    AwsText rds create-db-instance --db-instance-identifier $DbIdentifier --engine mysql --db-instance-class db.t3.micro --allocated-storage 20 --storage-type gp3 --db-name $DbName --master-username $Secret.username --master-user-password $Secret.password --db-subnet-group-name $DbSubnetGroup --vpc-security-group-ids $RdsSg --no-publicly-accessible --backup-retention-period 1 --no-multi-az --no-deletion-protection | Out-Null
}
Write-Host 'Esperando a que RDS esté disponible...'
AwsText rds wait db-instance-available --db-instance-identifier $DbIdentifier | Out-Null
$DbEndpoint = AwsText rds describe-db-instances --db-instance-identifier $DbIdentifier --query 'DBInstances[0].Endpoint.Address' --output text

# ECR repositories and images
foreach ($repo in @('maestria-inventario-products', 'maestria-inventario-audit', 'maestria-observabilidad-collector')) {
    $exists = ExistingId 'ecr' @('describe-repositories', '--repository-names', $repo, '--query', 'repositories[0].repositoryName', '--output', 'text')
    if (-not $exists -or $exists -eq 'None') { AwsText ecr create-repository --repository-name $repo --image-scanning-configuration scanOnPush=true | Out-Null }
}
$EcrPassword = AwsText ecr get-login-password --region $Region
$EcrPassword | docker login --username AWS --password-stdin $EcrBase | Out-Null
docker build -t $ProductsImage .
docker build -f services/service-b/Dockerfile -t $AuditImage .
docker build -f deploy/aws/Dockerfile.otel-collector -t $CollectorImage .
docker push $ProductsImage
docker push $AuditImage
docker push $CollectorImage
$CollectorDigest = AwsText ecr describe-images --repository-name maestria-observabilidad-collector --image-ids "imageTag=$ImageTag" --query 'imageDetails[0].imageDigest' --output text
$CollectorRuntimeImage = "$EcrBase/maestria-observabilidad-collector@$CollectorDigest"

# ECS and CloudWatch
$LogExists = ExistingId 'logs' @('describe-log-groups', '--log-group-name-prefix', $LogGroup, '--query', "logGroups[?logGroupName=='$LogGroup'].logGroupName", '--output', 'text')
if (-not $LogExists -or $LogExists -eq 'None') { AwsText logs create-log-group --log-group-name $LogGroup | Out-Null }
$ClusterArn = ExistingId 'ecs' @('describe-clusters', '--clusters', $ClusterName, '--query', 'clusters[0].clusterArn', '--output', 'text')
if (-not $ClusterArn -or $ClusterArn -eq 'None') { $ClusterArn = AwsText ecs create-cluster --cluster-name $ClusterName --query cluster.clusterArn --output text }

$NamespaceId = ExistingId 'servicediscovery' @('list-namespaces', '--query', "Namespaces[?Name=='$ServiceConnectNamespaceName'].Id | [0]", '--output', 'text')
if (-not $NamespaceId -or $NamespaceId -eq 'None') {
    $NamespaceOperationId = AwsText servicediscovery create-private-dns-namespace --name $ServiceConnectNamespaceName --vpc $VpcId --description 'Private Service Connect namespace for maestria lab services' --query OperationId --output text
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $NamespaceOperationStatus = AwsText servicediscovery get-operation --operation-id $NamespaceOperationId --query Operation.Status --output text
        if ($NamespaceOperationStatus -eq 'SUCCESS') { break }
        if ($NamespaceOperationStatus -eq 'FAIL') { throw 'Cloud Map private DNS namespace creation failed.' }
        Start-Sleep -Seconds 5
    }
    if ($NamespaceOperationStatus -ne 'SUCCESS') { throw 'Timed out waiting for Cloud Map private DNS namespace creation.' }
    $NamespaceId = AwsText servicediscovery list-namespaces --query "Namespaces[?Name=='$ServiceConnectNamespaceName'].Id | [0]" --output text
}
$NamespaceArn = AwsText servicediscovery get-namespace --id $NamespaceId --query Namespace.Arn --output text
$LogConfig = @{ logDriver = 'awslogs'; options = @{ 'awslogs-group' = $LogGroup; 'awslogs-region' = $Region; 'awslogs-stream-prefix' = 'ecs'; 'awslogs-create-group' = 'true' } }

$SsmAgentCommand = @'
set -e
dnf upgrade -y
dnf install jq procps awscli -y
term_handler() {
  echo "Deleting SSM activation $ACTIVATION_ID"
  if ! aws ssm delete-activation --activation-id "$ACTIVATION_ID" --region "$ECS_TASK_REGION"; then echo "SSM activation cleanup failed" 1>&2; fi
  MANAGED_INSTANCE_ID=$(jq -e -r .ManagedInstanceID /var/lib/amazon/ssm/registration)
  echo "Deregistering SSM Managed Instance $MANAGED_INSTANCE_ID"
  if ! aws ssm deregister-managed-instance --instance-id "$MANAGED_INSTANCE_ID" --region "$ECS_TASK_REGION"; then echo "SSM managed instance cleanup failed" 1>&2; fi
  kill -SIGTERM "$SSM_AGENT_PID"
}
trap term_handler SIGTERM SIGINT
if [[ -z "$MANAGED_INSTANCE_ROLE_NAME" ]]; then echo "MANAGED_INSTANCE_ROLE_NAME is required" 1>&2; exit 1; fi
if ps ax | grep amazon-ssm-agent | grep -v grep > /dev/null; then echo "SSM agent already running" 1>&2; exit 1; fi
if [[ -z "$ECS_CONTAINER_METADATA_URI_V4" ]]; then echo "ECS task metadata is unavailable" 1>&2; exit 1; fi
TASK_METADATA=$(curl "${ECS_CONTAINER_METADATA_URI_V4}/task")
ECS_TASK_AVAILABILITY_ZONE=$(echo "$TASK_METADATA" | jq -e -r '.AvailabilityZone')
ECS_TASK_ARN=$(echo "$TASK_METADATA" | jq -e -r '.TaskARN')
ECS_TASK_REGION=$(echo "$ECS_TASK_AVAILABILITY_ZONE" | sed 's/.$//')
ECS_TASK_AVAILABILITY_ZONE_REGEX='^(af|ap|ca|cn|eu|me|sa|us|us-gov)-(central|north|(north(east|west))|south|south(east|west)|east|west)-[0-9]{1}[a-z]{1}$'
if ! [[ "$ECS_TASK_AVAILABILITY_ZONE" =~ $ECS_TASK_AVAILABILITY_ZONE_REGEX ]]; then echo "Invalid task availability zone" 1>&2; exit 1; fi
ECS_TASK_ARN_REGEX='^arn:(aws|aws-cn|aws-us-gov):ecs:[a-z0-9-]+:[0-9]{12}:task/[a-zA-Z0-9_-]+/[a-zA-Z0-9]+$'
if ! [[ "$ECS_TASK_ARN" =~ $ECS_TASK_ARN_REGEX ]]; then echo "Invalid ECS task ARN" 1>&2; exit 1; fi
CREATE_ACTIVATION_OUTPUT=$(aws ssm create-activation --iam-role "$MANAGED_INSTANCE_ROLE_NAME" --tags "Key=ECS_TASK_AVAILABILITY_ZONE,Value=$ECS_TASK_AVAILABILITY_ZONE" "Key=ECS_TASK_ARN,Value=$ECS_TASK_ARN" "Key=FAULT_INJECTION_SIDECAR,Value=true" --region "$ECS_TASK_REGION")
ACTIVATION_CODE=$(echo "$CREATE_ACTIVATION_OUTPUT" | jq -e -r .ActivationCode)
ACTIVATION_ID=$(echo "$CREATE_ACTIVATION_OUTPUT" | jq -e -r .ActivationId)
amazon-ssm-agent -register -code "$ACTIVATION_CODE" -id "$ACTIVATION_ID" -region "$ECS_TASK_REGION"
amazon-ssm-agent &
SSM_AGENT_PID=$!
wait "$SSM_AGENT_PID"
'@
$SsmAgentContainer = @{
    name = 'amazon-ssm-agent'; image = 'public.ecr.aws/amazon-ssm-agent/amazon-ssm-agent:latest'; essential = $false
    entryPoint = @(); command = @('/bin/bash', '-c', $SsmAgentCommand)
    environment = @(@{ name = 'MANAGED_INSTANCE_ROLE_NAME'; value = $ManagedInstanceRoleName })
    logConfiguration = $LogConfig
}
$CollectorContainer = @{
    name = 'otel-collector'; image = $CollectorRuntimeImage; essential = $true
    portMappings = @(@{ containerPort = 4318; hostPort = 4318; protocol = 'tcp' }, @{ containerPort = 13133; hostPort = 13133; protocol = 'tcp' })
    logConfiguration = $LogConfig
}
$ProductsContainer = @{
    name = 'products'; image = $ProductsImage; essential = $true
    portMappings = @(@{ name = 'products'; containerPort = 9090; hostPort = 9090; protocol = 'tcp' })
    environment = @(
        @{ name = 'SERVER_PORT'; value = '9090' },
        @{ name = 'SPRING_DATASOURCE_URL'; value = "jdbc:mysql://$($DbEndpoint):3306/$DbName" },
        @{ name = 'SPRING_JPA_HIBERNATE_DDL_AUTO'; value = 'update' },
        @{ name = 'PRODUCT_AUDIT_ENABLED'; value = 'true' },
        @{ name = 'PRODUCT_AUDIT_URL'; value = 'http://audit:9090' },
        @{ name = 'OTEL_SERVICE_NAME'; value = 'maestria-inventario-products' },
        @{ name = 'OTEL_EXPORTER_OTLP_ENDPOINT'; value = 'http://127.0.0.1:4318' },
        @{ name = 'OTEL_EXPORTER_OTLP_PROTOCOL'; value = 'http/protobuf' },
        @{ name = 'OTEL_RESOURCE_ATTRIBUTES'; value = 'deployment.environment=aws-ecs,service.namespace=maestria' }
    )
    secrets = @(
        @{ name = 'SPRING_DATASOURCE_USERNAME'; valueFrom = "$($SecretArn):username::" },
        @{ name = 'SPRING_DATASOURCE_PASSWORD'; valueFrom = "$($SecretArn):password::" }
    )
    healthCheck = @{ command = @('CMD-SHELL', 'wget -q --spider http://localhost:9090/actuator/health || exit 1'); interval = 30; timeout = 5; retries = 3; startPeriod = 60 }
    logConfiguration = $LogConfig
}
$AuditContainer = @{
    name = 'audit'; image = $AuditImage; essential = $true
    portMappings = @(@{ name = 'audit'; containerPort = 9090; hostPort = 9090; protocol = 'tcp'; appProtocol = 'http' })
    environment = @(
        @{ name = 'SERVER_PORT'; value = '9090' },
        @{ name = 'SPRING_DATASOURCE_URL'; value = "jdbc:mysql://$($DbEndpoint):3306/$DbName" },
        @{ name = 'SPRING_JPA_HIBERNATE_DDL_AUTO'; value = 'update' },
        @{ name = 'OTEL_SERVICE_NAME'; value = 'maestria-inventario-audit' },
        @{ name = 'OTEL_EXPORTER_OTLP_ENDPOINT'; value = 'http://127.0.0.1:4318' },
        @{ name = 'OTEL_EXPORTER_OTLP_PROTOCOL'; value = 'http/protobuf' },
        @{ name = 'OTEL_RESOURCE_ATTRIBUTES'; value = 'deployment.environment=aws-ecs,service.namespace=maestria' }
    )
    secrets = @(
        @{ name = 'SPRING_DATASOURCE_USERNAME'; valueFrom = "$($SecretArn):username::" },
        @{ name = 'SPRING_DATASOURCE_PASSWORD'; valueFrom = "$($SecretArn):password::" }
    )
    healthCheck = @{ command = @('CMD-SHELL', 'wget -q --spider http://localhost:9090/actuator/health || exit 1'); interval = 30; timeout = 5; retries = 3; startPeriod = 60 }
    logConfiguration = $LogConfig
}
function RegisterLabTaskDefinition {
    param([string]$Family, [hashtable]$ApplicationContainer)
    $Definition = @{
        family = $Family; networkMode = 'awsvpc'; pidMode = 'task'; enableFaultInjection = $true
        requiresCompatibilities = @('FARGATE'); cpu = '1024'; memory = '2048'
        executionRoleArn = $ExecutionRoleArn; taskRoleArn = $TaskRoleArn
        containerDefinitions = @($ApplicationContainer, $CollectorContainer, $SsmAgentContainer)
    }
    $Json = $Definition | ConvertTo-Json -Depth 20 -Compress
    return (AwsText ecs register-task-definition --cli-input-json $Json --query 'taskDefinition.taskDefinitionArn' --output text)
}
$ProductsTaskDefinitionArn = RegisterLabTaskDefinition $ProductsTaskFamily $ProductsContainer
$AuditTaskDefinitionArn = RegisterLabTaskDefinition $AuditTaskFamily $AuditContainer

# ALB and ECS service
$AlbArn = ExistingId 'elbv2' @('describe-load-balancers', '--names', "$Name-alb", '--query', 'LoadBalancers[0].LoadBalancerArn', '--output', 'text')
if (-not $AlbArn -or $AlbArn -eq 'None') { $AlbArn = AwsText elbv2 create-load-balancer --name "$Name-alb" --subnets $Subnets[0] $Subnets[1] --security-groups $AlbSg --scheme internet-facing --type application --query 'LoadBalancers[0].LoadBalancerArn' --output text }
$TargetGroupArn = ExistingId 'elbv2' @('describe-target-groups', '--names', "$Name-tg", '--query', 'TargetGroups[0].TargetGroupArn', '--output', 'text')
if (-not $TargetGroupArn -or $TargetGroupArn -eq 'None') { $TargetGroupArn = AwsText elbv2 create-target-group --name "$Name-tg" --protocol HTTP --port 9090 --vpc-id $VpcId --target-type ip --health-check-path /actuator/health --health-check-interval-seconds 30 --query 'TargetGroups[0].TargetGroupArn' --output text }
$ListenerArn = ExistingId 'elbv2' @('describe-listeners', '--load-balancer-arn', $AlbArn, '--query', 'Listeners[0].ListenerArn', '--output', 'text')
if (-not $ListenerArn -or $ListenerArn -eq 'None') { AwsText elbv2 create-listener --load-balancer-arn $AlbArn --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=$TargetGroupArn" --query 'Listeners[0].ListenerArn' --output text | Out-Null }
$LoadBalancerDimension = ($AlbArn -split ':loadbalancer/')[1]
$TargetGroupDimension = ($TargetGroupArn -split ':targetgroup/')[1]
$ChaosStopAlarm5xxName = "$Name-chaos-stop-target-5xx"
$ChaosStopAlarmUnhealthyName = "$Name-chaos-stop-products-unhealthy"
AwsText cloudwatch put-metric-alarm --alarm-name $ChaosStopAlarm5xxName --alarm-description 'Stop AWS FIS chaos if the products ALB target returns 5xx.' --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count --statistic Sum --period 60 --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=LoadBalancer,Value=$LoadBalancerDimension" "Name=TargetGroup,Value=$TargetGroupDimension" --treat-missing-data notBreaching | Out-Null
AwsText cloudwatch put-metric-alarm --alarm-name $ChaosStopAlarmUnhealthyName --alarm-description 'Stop AWS FIS chaos if a products ALB target becomes unhealthy.' --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount --statistic Maximum --period 60 --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=LoadBalancer,Value=$LoadBalancerDimension" "Name=TargetGroup,Value=$TargetGroupDimension" --treat-missing-data notBreaching | Out-Null
$ChaosStopAlarm5xxArn = AwsText cloudwatch describe-alarms --alarm-names $ChaosStopAlarm5xxName --query 'MetricAlarms[0].AlarmArn' --output text
$ChaosStopAlarmUnhealthyArn = AwsText cloudwatch describe-alarms --alarm-names $ChaosStopAlarmUnhealthyName --query 'MetricAlarms[0].AlarmArn' --output text
$ProductsConnect = @{ enabled = $true; namespace = $NamespaceArn }
$AuditConnect = @{
    enabled = $true; namespace = $NamespaceArn
    services = @(@{ portName = 'audit'; discoveryName = 'audit'; clientAliases = @(@{ port = 9090; dnsName = 'audit' }) })
}
function EnsureLabEcsService {
    param(
        [string]$ServiceName,
        [string]$TaskArn,
        [int]$DesiredCount,
        [string]$ChaosTarget,
        [hashtable]$ServiceConnectConfiguration,
        [switch]$ExposeOnAlb
    )
    $Status = ExistingId 'ecs' @('describe-services', '--cluster', $ClusterName, '--services', $ServiceName, '--query', 'services[0].status', '--output', 'text')
    if ($Status -and $Status -ne 'None') {
        $ExistingServiceArn = AwsText ecs describe-services --cluster $ClusterName --services $ServiceName --query 'services[0].serviceArn' --output text
        AwsText ecs tag-resource --resource-arn $ExistingServiceArn --tags "key=ChaosTarget,value=$ChaosTarget" "key=Service,value=$ServiceName" | Out-Null
    }
    if (-not $Status -or $Status -eq 'None') {
        $Service = @{
            cluster = $ClusterName; serviceName = $ServiceName; taskDefinition = $TaskArn
            desiredCount = $DesiredCount; launchType = 'FARGATE'; platformVersion = 'LATEST'
            networkConfiguration = @{ awsvpcConfiguration = @{ subnets = $Subnets; securityGroups = @($EcsSg); assignPublicIp = 'ENABLED' } }
            enableECSManagedTags = $true; propagateTags = 'SERVICE'
            deploymentConfiguration = @{ maximumPercent = 200; minimumHealthyPercent = 50 }
            serviceConnectConfiguration = $ServiceConnectConfiguration
            tags = @(@{ key = 'ChaosTarget'; value = $ChaosTarget }, @{ key = 'Service'; value = $ServiceName })
        }
        if ($ExposeOnAlb) { $Service.loadBalancers = @(@{ targetGroupArn = $TargetGroupArn; containerName = 'products'; containerPort = 9090 }) }
        $ServiceJson = $Service | ConvertTo-Json -Depth 20 -Compress
        AwsText ecs create-service --cli-input-json $ServiceJson | Out-Null
    } else {
        $ConnectJson = $ServiceConnectConfiguration | ConvertTo-Json -Depth 10 -Compress
        $UpdateArgs = @(
            'ecs', 'update-service', '--cluster', $ClusterName, '--service', $ServiceName,
            '--task-definition', $TaskArn, '--desired-count', "$DesiredCount",
            '--enable-ecs-managed-tags', '--propagate-tags', 'SERVICE',
            '--service-connect-configuration', $ConnectJson, '--force-new-deployment'
        )
        AwsText @UpdateArgs | Out-Null
    }
}
EnsureLabEcsService $ProductsServiceName $ProductsTaskDefinitionArn $ProductsDesiredCount 'products' $ProductsConnect -ExposeOnAlb
EnsureLabEcsService $AuditServiceName $AuditTaskDefinitionArn $AuditDesiredCount 'audit' $AuditConnect
Write-Host 'Esperando a que ECS quede estable...'
AwsText ecs wait services-stable --cluster $ClusterName --services $ProductsServiceName $AuditServiceName | Out-Null
$AlbDns = AwsText elbv2 describe-load-balancers --load-balancer-arns $AlbArn --query 'LoadBalancers[0].DNSName' --output text
Write-Host "DESPLEGADO"
Write-Host "URL pública: http://$AlbDns"
Write-Host "RDS endpoint: $DbEndpoint"
Write-Host "ECS cluster: $ClusterName"
Write-Host "ECS cluster ARN: $ClusterArn"
Write-Host "Products service: $ProductsServiceName ($ProductsDesiredCount tasks)"
Write-Host "Audit service: $AuditServiceName ($AuditDesiredCount tasks)"
Write-Host "Service Connect namespace: $ServiceConnectNamespaceName"
Write-Host "FIS experiment role: $FisExperimentRoleArn"
Write-Host "FIS stop alarms: $ChaosStopAlarm5xxArn; $ChaosStopAlarmUnhealthyArn"
