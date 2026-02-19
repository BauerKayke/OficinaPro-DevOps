"""
Lambda Function: K3s Master Auto Stop
=======================================

Para automaticamente a K3s Master Spot Instance quando:
1. CloudWatch Alarm detecta baixa atividade no ALB
2. SNS aciona esta Lambda
3. Lambda ajusta ASG desired_capacity para 0
4. ASG para/termina a Spot Instance

Critérios de inatividade:
- Menos de 1 request em 30 minutos (3x 10 minutos)
- Configurável via CloudWatch Alarm

Economia estimada: ~$18/mês (assuming 6h/dia de uso)
"""

import json
import boto3
import os
from datetime import datetime

# Clientes AWS
ec2 = boto3.client('ec2')
asg = boto3.client('autoscaling')
cloudwatch = boto3.client('cloudwatch')

# Variáveis de ambiente
ASG_NAME = os.environ['ASG_NAME']
INSTANCE_TAG_NAME = os.environ['INSTANCE_TAG_NAME']

def handler(event, context):
    """
    Handler principal da Lambda
    
    Event sources:
    - SNS (CloudWatch Alarm)
    - Manual invocation
    """
    
    print(f"[{datetime.now().isoformat()}] K3s Auto Stop Lambda acionada")
    print(f"Event: {json.dumps(event)}")
    
    try:
        # Parse SNS message se vier do CloudWatch Alarm
        if 'Records' in event and event['Records']:
            sns_message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = sns_message.get('AlarmName', 'Unknown')
            state_value = sns_message.get('NewStateValue', 'Unknown')
            
            print(f"📢 CloudWatch Alarm: {alarm_name}")
            print(f"📢 State: {state_value}")
            
            # Só parar se o alarme estiver em ALARM
            if state_value != 'ALARM':
                print(f"⏭️ Alarme não está em ALARM, ignorando (state: {state_value})")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Alarme não está em ALARM, nenhuma ação necessária',
                        'alarm_state': state_value
                    })
                }
        
        # 1. Verificar ASG
        asg_info = get_asg_info()
        current_desired = asg_info['DesiredCapacity']
        current_instances = asg_info['Instances']
        
        print(f"📊 ASG Status:")
        print(f"  - Desired Capacity: {current_desired}")
        print(f"  - Current Instances: {len(current_instances)}")
        
        # 2. Se desired capacity já é 0, nada a fazer
        if current_desired == 0:
            print("✅ K3s Master já está parado (desired capacity = 0)")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'K3s Master já está parado',
                    'desired_capacity': 0
                })
            }
        
        # 3. Listar instâncias rodando
        running_instances = [i for i in current_instances if i['LifecycleState'] == 'InService']
        
        if running_instances:
            print(f"🔍 {len(running_instances)} instância(s) rodando:")
            for inst in running_instances:
                print(f"  - {inst['InstanceId']}: {inst['LifecycleState']}")
        
        # 4. Parar K3s (ajustar desired capacity para 0)
        print(f"🛑 Parando K3s Master (ajustando ASG desired capacity para 0)...")
        
        asg.set_desired_capacity(
            AutoScalingGroupName=ASG_NAME,
            DesiredCapacity=0,
            HonorCooldown=False
        )
        
        # Enviar métrica customizada para CloudWatch
        cloudwatch.put_metric_data(
            Namespace='OficinaPro/K3s',
            MetricData=[
                {
                    'MetricName': 'AutoStopInvocations',
                    'Value': 1.0,
                    'Unit': 'Count',
                    'Timestamp': datetime.now()
                }
            ]
        )
        
        print("✅ ASG desired capacity ajustado para 0")
        print("⏳ ASG irá parar/terminar a(s) instância(s)")
        print("💰 Economia ativada! Instância não consumirá custos até próxima requisição")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'K3s Master parado com sucesso',
                'asg_name': ASG_NAME,
                'desired_capacity': 0,
                'stopped_instances': len(running_instances)
            })
        }
    
    except Exception as e:
        print(f"❌ Erro: {str(e)}")
        import traceback
        traceback.print_exc()
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Erro ao parar K3s Master',
                'error': str(e)
            })
        }

def get_asg_info():
    """Obtém informações do Auto Scaling Group"""
    response = asg.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_NAME]
    )
    
    if not response['AutoScalingGroups']:
        raise Exception(f"ASG {ASG_NAME} não encontrado")
    
    return response['AutoScalingGroups'][0]
