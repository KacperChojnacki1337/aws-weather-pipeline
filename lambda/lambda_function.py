import json
import urllib3
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    http = urllib3.PoolManager()
    s3 = boto3.client('s3')
    
    # Get bucket name from environment variable (defined in Terraform)
    BUCKET_NAME = os.environ['MY_DATA_BUCKET']
    
    # Open-Meteo API (Warsaw coordinates)
    url = "https://api.open-meteo.com/v1/forecast?latitude=52.2297&longitude=21.0122&current_weather=true"
    
    try:
        # Fetching data from the API
        response = http.request('GET', url)
        data = json.loads(response.data.decode('utf-8'))
        
        # Add a timestamp to the data to track when it was ingested
        data['ingested_at'] = datetime.now().isoformat()
        
        # File path: raw/year/month/day/weather_timestamp.json (good partitioning practice)
        now = datetime.now()
        file_path = f"raw/{now.year}/{now.month:02d}/{now.day:02d}/weather_{now.strftime('%H%M%S')}.json"
        
        # Uploading the JSON data to S3
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=file_path,
            Body=json.dumps(data)
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'File {file_path} uploaded successfully!')
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps('Error uploading to S3')
        }