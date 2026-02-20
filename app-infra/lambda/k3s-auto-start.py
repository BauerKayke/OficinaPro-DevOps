"""
Lambda Function: K3s Master Auto Start
========================================

Inicia automaticamente a K3s Master Spot Instance quando:
1. ALB detecta que não há targets saudáveis (503)
2. EventBridge aciona esta Lambda
3. Lambda verifica se instância está parada
4. Se parada, ajusta ASG desired_capacity para 1
5. ASG cria/inicia nova Spot Instance
6. Instância se registra automaticamente no Target Group via user-data

Custos:
- Lambda: ~$0.20 por milhão de invocações
- EC2 Spot: ~$0.024/hora (apenas quando rodando)

Economia estimada: ~60-70% comparado a instância 24/7
"""

import json
import boto3
import os
from datetime import datetime

# Clientes AWS
ec2 = boto3.client('ec2')
asg = boto3.client('autoscaling')
elbv2 = boto3.client('elbv2')
cloudwatch = boto3.client('cloudwatch')

# Variáveis de ambiente
ASG_NAME = os.environ['ASG_NAME']
TARGET_GROUP_ARN = os.environ['TARGET_GROUP_ARN']
INSTANCE_TAG_NAME = os.environ['INSTANCE_TAG_NAME']

def handler(event, context):
    """
    Handler principal da Lambda
    
    Event sources:
    - EventBridge (ALB target health change)
    - Manual invocation
    - API Gateway
    """
    
    print(f"[{datetime.now().isoformat()}] K3s Auto Start Lambda acionada")
    print(f"Event: {json.dumps(event)}")
    
    try:
        # 1. Verificar se já existe instância rodando
        instances = get_running_instances()
        if instances:
            print(f"✅ Instância já está rodando: {instances[0]['InstanceId']}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'K3s Master já está rodando',
                    'instance_id': instances[0]['InstanceId'],
                    'state': instances[0]['State']['Name']
                })
            }
        
        # 2. Verificar targets do ALB
        target_health = check_target_health()
        healthy_targets = [t for t in target_health if t['TargetHealth']['State'] == 'healthy']
        
        if healthy_targets:
            print(f"✅ ALB já tem {len(healthy_targets)} target(s) saudável(is)")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'ALB já tem targets saudáveis',
                    'healthy_targets': len(healthy_targets)
                })
            }
        
        # 3. Verificar ASG
        asg_info = get_asg_info()
        current_desired = asg_info['DesiredCapacity']
        current_instances = asg_info['Instances']
        
        print(f"📊 ASG Status:")
        print(f"  - Desired Capacity: {current_desired}")
        print(f"  - Current Instances: {len(current_instances)}")
        print(f"  - Min Size: {asg_info['MinSize']}")
        print(f"  - Max Size: {asg_info['MaxSize']}")
        
        # 4. Se desired capacity é 0, ajustar para 1
        if current_desired == 0:
            print(f"🚀 Iniciando K3s Master (ajustando ASG desired capacity para 1)...")
            
            asg.set_desired_capacity(
                AutoScalingGroupName=ASG_NAME,
                DesiredCapacity=1,
                HonorCooldown=False
            )
            
            # Enviar métrica customizada para CloudWatch
            cloudwatch.put_metric_data(
                Namespace='OficinaPro/K3s',
                MetricData=[
                    {
                        'MetricName': 'AutoStartInvocations',
                        'Value': 1.0,
                        'Unit': 'Count',
                        'Timestamp': datetime.now()
                    }
                ]
            )
            
            print("✅ ASG desired capacity ajustado para 1")
            print("⏳ Aguardando ASG criar/iniciar instância...")
            print("📌 A instância levará ~2-3 minutos para ficar saudável no Target Group")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'K3s Master iniciado com sucesso via ASG',
                    'asg_name': ASG_NAME,
                    'desired_capacity': 1,
                    'estimated_ready_time': '2-3 minutos'
                })
            }
        
        # 5. Se desired capacity já é 1, aguardar instância inicializar
        elif current_desired == 1:
            print("⏳ ASG já tem desired capacity = 1, aguardando instância inicializar...")
            
            # Verificar se há instância sendo lançada
            pending_instances = [i for i in current_instances if i['LifecycleState'] in ['Pending', 'Pending:Wait', 'Pending:Proceed']]
            
            if pending_instances:
                print(f"📌 {len(pending_instances)} instância(s) sendo lançada(s)")
                for inst in pending_instances:
                    print(f"  - {inst['InstanceId']}: {inst['LifecycleState']}")
            
            return {
                'statusCode': 202,
                'body': json.dumps({
                    'message': 'K3s Master já está sendo iniciado',
                    'asg_name': ASG_NAME,
                    'desired_capacity': current_desired,
                    'pending_instances': len(pending_instances)
                })
            }
        
        else:
            print(f"⚠️ Desired capacity inesperado: {current_desired}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'message': 'Desired capacity inesperado',
                    'desired_capacity': current_desired
                })
            }
    
    except Exception as e:
        print(f"❌ Erro: {str(e)}")
        import traceback
        traceback.print_exc()
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Erro ao iniciar K3s Master',
                'error': str(e)
            })
        }

def get_running_instances():
    """Busca instâncias K3s Master rodando"""
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': [INSTANCE_TAG_NAME]},
            {'Name': 'instance-state-name', 'Values': ['running', 'pending']}
        ]
    )
    
    instances = []
    for reservation in response['Reservations']:
        instances.extend(reservation['Instances'])
    
    return instances

def check_target_health():
    """Verifica saúde dos targets no Target Group"""
    response = elbv2.describe_target_health(
        TargetGroupArn=TARGET_GROUP_ARN
    )
    return response['TargetHealthDescriptions']

def get_asg_info():
    """Obtém informações do Auto Scaling Group"""
    response = asg.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_NAME]
    )
    
    if not response['AutoScalingGroups']:
        raise Exception(f"ASG {ASG_NAME} não encontrado")
    
    return response['AutoScalingGroups'][0]
