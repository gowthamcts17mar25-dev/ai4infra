import base64
import boto3
import json
import os
from datetime import datetime

ec2_client = boto3.client('ec2', region_name=os.environ['REGION'])

def lambda_handler(event, context):
    """
    Lambda function to stop EC2 instances at scheduled time.
    Instance IDs are provided via environment variables.
    """
    
    instance_ids = os.environ['INSTANCE_IDS'].split(',')
    
    try:
        print(f"Stopping instances: {instance_ids}")
        
        response = ec2_client.stop_instances(InstanceIds=instance_ids)
        
        stopped_instances = [inst['InstanceId'] for inst in response['StoppingInstances']]
        
        print(f"Successfully stopped instances: {stopped_instances}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Instances stopped successfully',
                'instances': stopped_instances,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
    except Exception as e:
        print(f"Error stopping instances: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error stopping instances',
                'error': str(e)
            })
        }
