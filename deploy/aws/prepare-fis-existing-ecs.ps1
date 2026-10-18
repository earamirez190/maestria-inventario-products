param(
    [string]$Region = 'us-east-2',
    [string]$ClusterName = 'prd-maestriainventario-ecs',
    [string]$ProductsServiceName = 'td-maestriainventario-inventario-products-api-prd-service-wkkqqol1',
    [string]$ProductsContainerName = 'maestria-inventario-products-api',
    [string]$AuditServiceName = 'td-maestriainventario-audi-api-prd-service-4c4nxx0x',
    [string]$AuditContainerName = 'maestria-inventario-audi-api',
    [string]$DataServiceName = 'td-maestria-inventario-service-api-prod-service-onouq3k1',
    [string]$DataContainerName = 'maestria-inventario-service-api',
    [ValidateRange(2, 50)][int]$DesiredCount = 2,
    [string]$FisExperimentRoleName = 'maestria-inventario-fis-experiment-role',
    [string]$ManagedInstanceRoleName = 'maestria-inventario-fis-managed-instance-role',
    [string]$ProductsAlarmPrefix = 'maestria-inventario-chaos-products',
    [string]$LogGroup
)

$ErrorActionPreference = 'Stop'
$AwsCommand = Get-Command aws -ErrorAction Stop
$Aws = $AwsCommand.Source
$AccountId = (& $Aws sts get-caller-identity --query Account --output text).Trim()
if ($LASTEXITCODE -ne 0 -or -not $AccountId) {
    throw 'No se pudo identificar la cuenta AWS actual.'
}

function Invoke-AwsText {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = & $Aws @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI falló: aws $($Arguments -join ' ')"
    }
    return ($result | Out-String).Trim()
}

function Get-ServiceDetails {
    param([string]$Name)
    $json = Invoke-AwsText ecs describe-services --region $Region --cluster $ClusterName --services $Name --output json
    $response = $json | ConvertFrom-Json
    if ($response.failures.Count -gt 0 -or $response.services.Count -ne 1 -or $response.services[0].status -ne 'ACTIVE') {
        throw "No se encontró el servicio ECS activo '$Name' en '$ClusterName' ($Region)."
    }
    return $response.services[0]
}

function Get-TaskDefinition {
    param([string]$Arn)
    $json = Invoke-AwsText ecs describe-task-definition --region $Region --task-definition $Arn --query taskDefinition --output json
    $definition = $json | ConvertFrom-Json
    foreach ($property in @('taskDefinitionArn', 'revision', 'status', 'requiresAttributes', 'compatibilities', 'registeredAt', 'registeredBy', 'deregisteredAt')) {
        $definition.PSObject.Properties.Remove($property)
    }
    if ($definition.requiresCompatibilities -notcontains 'FARGATE' -or $definition.networkMode -ne 'awsvpc') {
        throw "La task definition '$Arn' no es compatible con Fargate/awsvpc."
    }
    if (-not $definition.taskRoleArn -or -not $definition.executionRoleArn) {
        throw "La task definition '$Arn' debe tener taskRoleArn y executionRoleArn."
    }
    return $definition
}

function Add-PolicyToRole {
    param([string]$RoleName, [string]$PolicyName, [object]$Policy)
    $policyJson = $Policy | ConvertTo-Json -Depth 12 -Compress
    $policyFile = Join-Path ([IO.Path]::GetTempPath()) "$PolicyName-$([guid]::NewGuid().ToString('N')).json"
    try {
        [IO.File]::WriteAllText($policyFile, $policyJson, (New-Object Text.UTF8Encoding($false)))
        Invoke-AwsText iam put-role-policy --role-name $RoleName --policy-name $PolicyName --policy-document "file://$policyFile" | Out-Null
    } finally {
        if (Test-Path -LiteralPath $policyFile) {
            Remove-Item -LiteralPath $policyFile -Force
        }
    }
}

function Ensure-IamRole {
    param([string]$RoleName, [string]$TrustPolicyPath)
    $roleArn = $null
    try {
        $roleArn = Invoke-AwsText iam get-role --role-name $RoleName --query 'Role.Arn' --output text
    } catch {
        $roleArn = Invoke-AwsText iam create-role --role-name $RoleName --assume-role-policy-document "file://$TrustPolicyPath" --query Role.Arn --output text
    }
    return $roleArn
}

function Add-FisAgentContainer {
    param([object]$Definition, [string]$TaskLogGroup)

    $Definition.pidMode = 'task'
    $Definition.enableFaultInjection = $true
    $existing = @($Definition.containerDefinitions | Where-Object { $_.name -eq 'amazon-ssm-agent' })
    if ($existing.Count -gt 0) {
        return
    }
    if ($Definition.containerDefinitions | Where-Object { $_.name -eq 'amazon-ssm-agent' -or $_.name -eq 'aws-fis-ssm-agent' }) {
        throw "La task definition '$($Definition.family)' contiene un nombre de sidecar FIS no esperado."
    }

    $agentCommand = @'
set -e
dnf upgrade -y
dnf install jq procps awscli -y
term_handler() {
  if [[ -n "$ACTIVATION_ID" ]]; then aws ssm delete-activation --activation-id "$ACTIVATION_ID" --region "$ECS_TASK_REGION" || true; fi
  if [[ -n "$MANAGED_INSTANCE_ID" ]]; then aws ssm deregister-managed-instance --instance-id "$MANAGED_INSTANCE_ID" --region "$ECS_TASK_REGION" || true; fi
  if [[ -n "$SSM_AGENT_PID" ]]; then kill -SIGTERM "$SSM_AGENT_PID" 2>/dev/null || true; fi
}
trap term_handler SIGTERM SIGINT
if [[ -z "$MANAGED_INSTANCE_ROLE_NAME" || -z "$ECS_CONTAINER_METADATA_URI_V4" ]]; then
  echo "MANAGED_INSTANCE_ROLE_NAME and ECS task metadata are required" >&2
  exit 1
fi
TASK_METADATA=$(curl "${ECS_CONTAINER_METADATA_URI_V4}/task")
ECS_TASK_AVAILABILITY_ZONE=$(echo "$TASK_METADATA" | jq -e -r '.AvailabilityZone')
ECS_TASK_ARN=$(echo "$TASK_METADATA" | jq -e -r '.TaskARN')
ECS_TASK_REGION=$(echo "$ECS_TASK_AVAILABILITY_ZONE" | sed 's/.$//')
CREATE_ACTIVATION_OUTPUT=$(aws ssm create-activation --iam-role "$MANAGED_INSTANCE_ROLE_NAME" --tags "Key=ECS_TASK_AVAILABILITY_ZONE,Value=$ECS_TASK_AVAILABILITY_ZONE" "Key=ECS_TASK_ARN,Value=$ECS_TASK_ARN" "Key=FAULT_INJECTION_SIDECAR,Value=true" --region "$ECS_TASK_REGION")
ACTIVATION_CODE=$(echo "$CREATE_ACTIVATION_OUTPUT" | jq -e -r .ActivationCode)
ACTIVATION_ID=$(echo "$CREATE_ACTIVATION_OUTPUT" | jq -e -r .ActivationId)
amazon-ssm-agent -register -code "$ACTIVATION_CODE" -id "$ACTIVATION_ID" -region "$ECS_TASK_REGION"
MANAGED_INSTANCE_ID=$(jq -e -r .ManagedInstanceID /var/lib/amazon/ssm/registration)
amazon-ssm-agent &
SSM_AGENT_PID=$!
wait "$SSM_AGENT_PID"
'@
    $logOptions = @{
        'awslogs-group' = $TaskLogGroup
        'awslogs-region' = $Region
        'awslogs-stream-prefix' = 'ecs'
        'awslogs-create-group' = 'true'
    }
    $Definition.containerDefinitions += @{
        name = 'amazon-ssm-agent'
        image = 'public.ecr.aws/amazon-ssm-agent/amazon-ssm-agent:latest'
        essential = $false
        entryPoint = @()
        command = @('/bin/bash', '-c', $agentCommand)
        environment = @(@{ name = 'MANAGED_INSTANCE_ROLE_NAME'; value = $ManagedInstanceRoleName })
        logConfiguration = @{ logDriver = 'awslogs'; options = $logOptions }
    }
}

function Register-UpdatedTaskDefinition {
    param([object]$Definition, [string]$ContainerName, [string]$ServiceName)
    $container = @($Definition.containerDefinitions | Where-Object { $_.name -eq $ContainerName })
    if ($container.Count -ne 1) {
        throw "No se encontró exactamente un contenedor '$ContainerName' en la task definition de '$ServiceName'."
    }
    $json = $Definition | ConvertTo-Json -Depth 30 -Compress
    $file = Join-Path ([IO.Path]::GetTempPath()) "$($Definition.family)-$([guid]::NewGuid().ToString('N')).json"
    try {
        [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))
        return (Invoke-AwsText ecs register-task-definition --region $Region --cli-input-json "file://$file" --query 'taskDefinition.taskDefinitionArn' --output text)
    } finally {
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force
        }
    }
}

$ClusterArn = Invoke-AwsText ecs describe-clusters --region $Region --clusters $ClusterName --query 'clusters[0].clusterArn' --output text
if (-not $ClusterArn -or $ClusterArn -eq 'None') {
    throw "No se encontró el cluster '$ClusterName' en la región '$Region'."
}
$ProductsService = Get-ServiceDetails $ProductsServiceName
$AuditService = Get-ServiceDetails $AuditServiceName
$DataService = Get-ServiceDetails $DataServiceName
$allServiceArns = @($ProductsService.serviceArn, $AuditService.serviceArn, $DataService.serviceArn)
$serviceArns = @($allServiceArns | Select-Object -Unique)
if ($serviceArns.Count -ne 3) {
    throw 'Productos, auditoría y data-service deben ser servicios ECS independientes.'
}
$allServices = @($ProductsService, $AuditService, $DataService)
if (@($allServices | Where-Object { $_.desiredCount -lt $DesiredCount }).Count -gt 0) {
    Write-Warning "La preparación elevará desiredCount a $DesiredCount para los servicios que estén por debajo; esto incrementa el coste de Fargate."
}
$ProductsDefinition = Get-TaskDefinition $ProductsService.taskDefinition
$AuditDefinition = Get-TaskDefinition $AuditService.taskDefinition
$DataDefinition = Get-TaskDefinition $DataService.taskDefinition
foreach ($item in @(
    @{ Definition = $ProductsDefinition; Container = $ProductsContainerName; Service = $ProductsServiceName },
    @{ Definition = $AuditDefinition; Container = $AuditContainerName; Service = $AuditServiceName },
    @{ Definition = $DataDefinition; Container = $DataContainerName; Service = $DataServiceName }
)) {
    if (@($item.Definition.containerDefinitions | Where-Object { $_.name -eq $item.Container }).Count -ne 1) {
        throw "No se encontró exactamente el contenedor '$($item.Container)' en la task definition de '$($item.Service)'. No se aplicaron cambios."
    }
}
$productsContainer = $ProductsDefinition.containerDefinitions | Where-Object { $_.name -eq $ProductsContainerName }
$auditUrl = $productsContainer.environment | Where-Object { $_.name -eq 'PRODUCT_AUDIT_URL' } | Select-Object -First 1 -ExpandProperty value
if (-not $auditUrl -or $auditUrl -match 'localhost|127\.0\.0\.1') {
    throw "PRODUCT_AUDIT_URL en '$ProductsServiceName' debe apuntar a un endpoint privado alcanzable del servicio audit, no a localhost."
}
$dataServiceUrl = $productsContainer.environment | Where-Object { $_.name -eq 'DATA_SERVICE_URL' } | Select-Object -First 1 -ExpandProperty value
if (-not $dataServiceUrl -or $dataServiceUrl -match 'localhost|127\.0\.0\.1') {
    throw "DATA_SERVICE_URL en '$ProductsServiceName' debe apuntar a un endpoint privado alcanzable del data-service, no a localhost."
}
$dataContainer = $DataDefinition.containerDefinitions | Where-Object { $_.name -eq $DataContainerName }
$dataProfile = $dataContainer.environment | Where-Object { $_.name -eq 'SPRING_PROFILES_ACTIVE' } | Select-Object -First 1 -ExpandProperty value
if ($dataProfile -ne 'data-service') {
    throw "El contenedor '$DataContainerName' debe ejecutarse con SPRING_PROFILES_ACTIVE=data-service antes de preparar FIS."
}
$ProductsTargetGroupArn = $ProductsService.loadBalancers | Select-Object -First 1 -ExpandProperty targetGroupArn
if (-not $ProductsTargetGroupArn) {
    throw "El servicio de productos '$ProductsServiceName' no está conectado a un ALB target group; no se pueden preparar alarmas de parada."
}
$targetGroupJson = Invoke-AwsText elbv2 describe-target-groups --region $Region --target-group-arns $ProductsTargetGroupArn --output json
$targetGroup = ($targetGroupJson | ConvertFrom-Json).TargetGroups | Select-Object -First 1
if (-not $targetGroup.LoadBalancerArns -or $targetGroup.LoadBalancerArns.Count -eq 0) {
    throw 'El target group de productos no está asociado a un load balancer.'
}
$loadBalancerDimension = ($targetGroup.LoadBalancerArns[0] -split ':loadbalancer/')[1]
$targetGroupDimension = ($ProductsTargetGroupArn -split ':targetgroup/')[1]
if (-not $LogGroup) {
    $LogGroup = $ProductsDefinition.containerDefinitions |
        Where-Object { $_.logConfiguration.logDriver -eq 'awslogs' } |
        Select-Object -First 1 -ExpandProperty logConfiguration |
        ForEach-Object { $_.options.'awslogs-group' }
}
if (-not $LogGroup) {
    throw 'No se pudo detectar el grupo CloudWatch Logs; proporciónalo con -LogGroup.'
}
$taskRoleArns = @($ProductsDefinition.taskRoleArn, $AuditDefinition.taskRoleArn, $DataDefinition.taskRoleArn) | Select-Object -Unique
foreach ($taskRoleArn in $taskRoleArns) {
    if (($taskRoleArn -split ':')[4] -ne $AccountId) {
        throw "El task role '$taskRoleArn' no pertenece a la cuenta actual; no se aplicaron cambios."
    }
}

$FisTrustFile = Join-Path $PSScriptRoot 'fis-experiment-trust.json'
$SsmTrustFile = Join-Path $PSScriptRoot 'ssm-managed-instance-trust.json'
$ManagedRoleArn = Ensure-IamRole $ManagedInstanceRoleName $SsmTrustFile
$FisRoleArn = Ensure-IamRole $FisExperimentRoleName $FisTrustFile
Invoke-AwsText iam attach-role-policy --role-name $ManagedInstanceRoleName --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore | Out-Null

$ManagedRolePolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{ Effect = 'Allow'; Action = @('ssm:DeleteActivation'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ssm:DeregisterManagedInstance'); Resource = "arn:aws:ssm:${Region}:${AccountId}:managed-instance/*" }
    )
}
Add-PolicyToRole $ManagedInstanceRoleName 'FisManagedInstanceCleanup' $ManagedRolePolicy

$TaskRolePolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{ Effect = 'Allow'; Action = @('ssm:CreateActivation', 'ssm:AddTagsToResource'); Resource = '*' },
        @{
            Effect = 'Allow'; Action = @('iam:PassRole'); Resource = $ManagedRoleArn
            Condition = @{ StringEquals = @{ 'iam:PassedToService' = 'ssm.amazonaws.com' } }
        }
    )
}
foreach ($taskRoleArn in $taskRoleArns) {
    $taskRoleName = ($taskRoleArn -split '/')[-1]
    Add-PolicyToRole $taskRoleName 'FisSsmRegistration' $TaskRolePolicy
}

$FisRolePolicy = @{
    Version = '2012-10-17'
    Statement = @(
        @{ Effect = 'Allow'; Action = @('ecs:DescribeTasks', 'ecs:StopTask'); Resource = "arn:aws:ecs:${Region}:${AccountId}:task/$ClusterName/*" },
        @{ Effect = 'Allow'; Action = @('ecs:ListTasks'); Resource = $ClusterArn },
        @{ Effect = 'Allow'; Action = @('ecs:DescribeContainerInstances'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ec2:DescribeInstances', 'ec2:DescribeSubnets', 'tag:GetResources', 'cloudwatch:DescribeAlarms'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ssm:ListCommands'); Resource = '*' },
        @{ Effect = 'Allow'; Action = @('ssm:SendCommand'); Resource = "arn:aws:ssm:${Region}::document/AWSFIS-*" },
        @{
            Effect = 'Allow'; Action = @('ssm:SendCommand')
            Resource = "arn:aws:ssm:${Region}:${AccountId}:managed-instance/*"
            Condition = @{ StringEquals = @{ 'ssm:resourceTag/FAULT_INJECTION_SIDECAR' = 'true' } }
        },
        @{ Effect = 'Allow'; Action = @('ssm:CancelCommand'); Resource = "arn:aws:ssm:${Region}:${AccountId}:command/*" }
    )
}
Add-PolicyToRole $FisExperimentRoleName 'FisEcsTaskFaultInjection' $FisRolePolicy

$Alarm5xxName = "$ProductsAlarmPrefix-5xx"
$AlarmUnhealthyName = "$ProductsAlarmPrefix-unhealthy"
Invoke-AwsText cloudwatch put-metric-alarm --region $Region --alarm-name $Alarm5xxName --alarm-description 'Stop AWS FIS if products ALB target returns 5xx.' --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count --statistic Sum --period 60 --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=LoadBalancer,Value=$loadBalancerDimension" "Name=TargetGroup,Value=$targetGroupDimension" --treat-missing-data notBreaching | Out-Null
Invoke-AwsText cloudwatch put-metric-alarm --region $Region --alarm-name $AlarmUnhealthyName --alarm-description 'Stop AWS FIS if a products ALB target becomes unhealthy.' --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount --statistic Maximum --period 60 --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=LoadBalancer,Value=$loadBalancerDimension" "Name=TargetGroup,Value=$targetGroupDimension" --treat-missing-data notBreaching | Out-Null
$Alarm5xxArn = Invoke-AwsText cloudwatch describe-alarms --region $Region --alarm-names $Alarm5xxName --query 'MetricAlarms[0].AlarmArn' --output text
$AlarmUnhealthyArn = Invoke-AwsText cloudwatch describe-alarms --region $Region --alarm-names $AlarmUnhealthyName --query 'MetricAlarms[0].AlarmArn' --output text

foreach ($service in @(
    @{ Details = $ProductsService; Target = 'products' },
    @{ Details = $AuditService; Target = 'audit' },
    @{ Details = $DataService; Target = 'data-service' }
)) {
    Invoke-AwsText ecs tag-resource --region $Region --resource-arn $service.Details.serviceArn --tags "key=ChaosTarget,value=$($service.Target)" | Out-Null
}

Add-FisAgentContainer $ProductsDefinition $LogGroup
Add-FisAgentContainer $AuditDefinition $LogGroup
$DataDefinition.enableFaultInjection = $true
Add-FisAgentContainer $DataDefinition $LogGroup
$ProductsTaskDefinitionArn = Register-UpdatedTaskDefinition $ProductsDefinition $ProductsContainerName $ProductsServiceName
$AuditTaskDefinitionArn = Register-UpdatedTaskDefinition $AuditDefinition $AuditContainerName $AuditServiceName
$DataTaskDefinitionArn = Register-UpdatedTaskDefinition $DataDefinition $DataContainerName $DataServiceName

Invoke-AwsText ecs update-service --region $Region --cluster $ClusterName --service $ProductsServiceName --task-definition $ProductsTaskDefinitionArn --desired-count ([Math]::Max($DesiredCount, $ProductsService.desiredCount)) --enable-ecs-managed-tags --propagate-tags SERVICE --force-new-deployment | Out-Null
Invoke-AwsText ecs update-service --region $Region --cluster $ClusterName --service $AuditServiceName --task-definition $AuditTaskDefinitionArn --desired-count ([Math]::Max($DesiredCount, $AuditService.desiredCount)) --enable-ecs-managed-tags --propagate-tags SERVICE --force-new-deployment | Out-Null
Invoke-AwsText ecs update-service --region $Region --cluster $ClusterName --service $DataServiceName --task-definition $DataTaskDefinitionArn --desired-count ([Math]::Max($DesiredCount, $DataService.desiredCount)) --enable-ecs-managed-tags --propagate-tags SERVICE --force-new-deployment | Out-Null

Write-Host 'Esperando a que los tres servicios ECS queden estables...'
Invoke-AwsText ecs wait services-stable --region $Region --cluster $ClusterName --services $ProductsServiceName $AuditServiceName $DataServiceName | Out-Null

Write-Host 'Preparación de FIS completada; no se ha iniciado ningún experimento.'
Write-Host "Cuenta: $AccountId"
Write-Host "Región: $Region"
Write-Host "Cluster ARN: $ClusterArn"
Write-Host "Products: $ProductsServiceName / $ProductsContainerName / $ProductsTaskDefinitionArn"
Write-Host "Audit: $AuditServiceName / $AuditContainerName / $AuditTaskDefinitionArn"
Write-Host "Data service: $DataServiceName / $DataContainerName / $DataTaskDefinitionArn"
Write-Host "FIS role ARN: $FisRoleArn"
Write-Host "Alarm 5xx ARN: $Alarm5xxArn"
Write-Host "Alarm unhealthy ARN: $AlarmUnhealthyArn"
