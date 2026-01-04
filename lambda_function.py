import json
import boto3
import os

# Initialize the DynamoDB resource
dynamodb = boto3.resource('dynamodb')
# THIS NAME MUST MATCH YOUR main.tf EXACTLY
table = dynamodb.Table('visitor_counter_v2')

def lambda_handler(event, context):
    try:
        # 1. Update the 'count' for the item with id 'visitors'
        response = table.update_item(
            Key={'id': 'visitors'},
            UpdateExpression='ADD #c :val',
            ExpressionAttributeNames={'#c': 'count'},
            ExpressionAttributeValues={':val': 1},
            ReturnValues='UPDATED_NEW'
        )
        
        # 2. Extract the new count
        new_count = response['Attributes']['count']

        # 3. Return the count with headers to prevent CORS issues
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'count': int(new_count)})
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }