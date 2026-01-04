import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('visitor_counter')

def lambda_handler(event, context):
    # Atomic update of the 'count' attribute
    response = table.update_item(
        Key={'id': 'visitors'},
        UpdateExpression='ADD #c :val',
        ExpressionAttributeNames={'#c': 'count'},
        ExpressionAttributeValues={':val': 1},
        ReturnValues="UPDATED_NEW"
    )
    
    count = response['Attributes']['count']
    
    # Return response with CORS headers (so your website can talk to it)
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET'
        },
        'body': json.dumps({'count': int(count)})
    }