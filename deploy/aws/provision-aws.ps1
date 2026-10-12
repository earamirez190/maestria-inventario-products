param(
    [string]$Region = 'us-east-1',
    [string]$VpcId = 'vpc-086fa0287f12fa3ca',
    [string[]]$Subnets = @('subnet-04203e5b1994505b2', 'subnet-058969041c2da3066'),
    [string]$ImageTag = 'latest'
)

$ErrorActionPreference = 'Stop'
$Aws = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'
$AccountId = (& $Aws sts get-caller-identity --query Account --output text).Trim()
$Name = 'maestria-observabilidad'
$ClusterName = "$Name-cluster"
$ServiceName = "$Name-service"
$TaskFamily = "$Name-task"
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
IgnoreAws ec2 authorize-security-group-ingress --group-id $RdsSg --protocol tcp --port 3306 --source-group $EcsSg

# IAM roles
$TrustFile = Join-Path $PSScriptRoot 'ecs-task-trust.json'
$XrayPolicyFile = Join-Path $PSScriptRoot 'xray-policy.json'
$ExecutionRoleName = "$Name-execution-role"
$TaskRoleName = "$Name-task-role"
$ExecutionRoleArn = ExistingId 'iam' @('get-role', '--role-name', $ExecutionRoleName, '--query', 'Role.Arn', '--output', 'text')
if (-not $ExecutionRoleArn -or $ExecutionRoleArn -eq 'None') { $ExecutionRoleArn = AwsText iam create-role --role-name $ExecutionRoleName --assume-role-policy-document "file://$TrustFile" --query Role.Arn --output text }
IgnoreAws iam attach-role-policy --role-name $ExecutionRoleName --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
$TaskRoleArn = ExistingId 'iam' @('get-role', '--role-name', $TaskRoleName, '--query', 'Role.Arn', '--output', 'text')
if (-not $TaskRoleArn -or $TaskRoleArn -eq 'None') { $TaskRoleArn = AwsText iam create-role --role-name $TaskRoleName --assume-role-policy-document "file://$TrustFile" --query Role.Arn --output text }
AwsText iam put-role-policy --role-name $TaskRoleName --policy-name XRayWriteAccess --policy-document "file://$XrayPolicyFile" | Out-Null

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

$LogConfig = @{ logDriver = 'awslogs'; options = @{ 'awslogs-group' = $LogGroup; 'awslogs-region' = $Region; 'awslogs-stream-prefix' = 'ecs'; 'awslogs-create-group' = 'true' } }
$TaskDefinition = @{
    family = $TaskFamily
    networkMode = 'awsvpc'
    requiresCompatibilities = @('FARGATE')
    cpu = '1024'
    memory = '2048'
    executionRoleArn = $ExecutionRoleArn
    taskRoleArn = $TaskRoleArn
    containerDefinitions = @(
        @{
            name = 'products'; image = $ProductsImage; essential = $true
            portMappings = @(@{ containerPort = 9090; hostPort = 9090; protocol = 'tcp' })
            environment = @(
                @{ name = 'SERVER_PORT'; value = '9090' },
                @{ name = 'SPRING_DATASOURCE_URL'; value = "jdbc:mysql://$($DbEndpoint):3306/$DbName" },
                @{ name = 'SPRING_JPA_HIBERNATE_DDL_AUTO'; value = 'update' },
                @{ name = 'PRODUCT_AUDIT_ENABLED'; value = 'true' },
                @{ name = 'PRODUCT_AUDIT_URL'; value = 'http://127.0.0.1:9091' },
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
        },
        @{
            name = 'audit'; image = $AuditImage; essential = $true
            portMappings = @(@{ containerPort = 9091; hostPort = 9091; protocol = 'tcp' })
            environment = @(
                @{ name = 'SERVER_PORT'; value = '9091' },
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
            healthCheck = @{ command = @('CMD-SHELL', 'wget -q --spider http://localhost:9091/actuator/health || exit 1'); interval = 30; timeout = 5; retries = 3; startPeriod = 60 }
            logConfiguration = $LogConfig
        },
        @{
            name = 'otel-collector'; image = $CollectorRuntimeImage; essential = $true
            portMappings = @(@{ containerPort = 4318; hostPort = 4318; protocol = 'tcp' }, @{ containerPort = 13133; hostPort = 13133; protocol = 'tcp' })
            logConfiguration = $LogConfig
        }
    )
}
$TaskJson = $TaskDefinition | ConvertTo-Json -Depth 20
$TaskFile = Join-Path ([IO.Path]::GetTempPath()) "$TaskFamily.json"
[IO.File]::WriteAllText($TaskFile, $TaskJson, (New-Object Text.UTF8Encoding($false)))
$TaskDefinitionArn = AwsText ecs register-task-definition --cli-input-json "file://$TaskFile" --query 'taskDefinition.taskDefinitionArn' --output text

# ALB and ECS service
$AlbArn = ExistingId 'elbv2' @('describe-load-balancers', '--names', "$Name-alb", '--query', 'LoadBalancers[0].LoadBalancerArn', '--output', 'text')
if (-not $AlbArn -or $AlbArn -eq 'None') { $AlbArn = AwsText elbv2 create-load-balancer --name "$Name-alb" --subnets $Subnets[0] $Subnets[1] --security-groups $AlbSg --scheme internet-facing --type application --query 'LoadBalancers[0].LoadBalancerArn' --output text }
$TargetGroupArn = ExistingId 'elbv2' @('describe-target-groups', '--names', "$Name-tg", '--query', 'TargetGroups[0].TargetGroupArn', '--output', 'text')
if (-not $TargetGroupArn -or $TargetGroupArn -eq 'None') { $TargetGroupArn = AwsText elbv2 create-target-group --name "$Name-tg" --protocol HTTP --port 9090 --vpc-id $VpcId --target-type ip --health-check-path /actuator/health --health-check-interval-seconds 30 --query 'TargetGroups[0].TargetGroupArn' --output text }
$ListenerArn = ExistingId 'elbv2' @('describe-listeners', '--load-balancer-arn', $AlbArn, '--query', 'Listeners[0].ListenerArn', '--output', 'text')
if (-not $ListenerArn -or $ListenerArn -eq 'None') { AwsText elbv2 create-listener --load-balancer-arn $AlbArn --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=$TargetGroupArn" --query 'Listeners[0].ListenerArn' --output text | Out-Null }
$ServiceStatus = ExistingId 'ecs' @('describe-services', '--cluster', $ClusterName, '--services', $ServiceName, '--query', 'services[0].status', '--output', 'text')
$Network = "awsvpcConfiguration={subnets=[$($Subnets -join ',')],securityGroups=[$EcsSg],assignPublicIp=ENABLED}"
if (-not $ServiceStatus -or $ServiceStatus -eq 'None') {
    AwsText ecs create-service --cluster $ClusterName --service-name $ServiceName --task-definition $TaskDefinitionArn --desired-count 1 --launch-type FARGATE --platform-version LATEST --network-configuration $Network --load-balancers "targetGroupArn=$TargetGroupArn,containerName=products,containerPort=9090" --deployment-configuration "maximumPercent=200,minimumHealthyPercent=50" | Out-Null
} else {
    AwsText ecs update-service --cluster $ClusterName --service $ServiceName --task-definition $TaskDefinitionArn --force-new-deployment | Out-Null
}
Write-Host 'Esperando a que ECS quede estable...'
AwsText ecs wait services-stable --cluster $ClusterName --services $ServiceName | Out-Null
$AlbDns = AwsText elbv2 describe-load-balancers --load-balancer-arns $AlbArn --query 'LoadBalancers[0].DNSName' --output text
Write-Host "DESPLEGADO"
Write-Host "URL pública: http://$AlbDns"
Write-Host "RDS endpoint: $DbEndpoint"
Write-Host "ECS cluster: $ClusterName"
Write-Host "ECS service: $ServiceName"
