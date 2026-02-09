import json
import boto3
import pandas as pd
import awswrangler as wr
import urllib.parse

def flatten_weather_data(data):
    return {
        "city": data["name"],
        "temp_celsius": data["main"]["temp"] - 273.15,
        "humidity": data["main"]["humidity"],
        "timestamp": data["dt"]
    }

def validate_data(df):
    """
    Returns True if data is valid, False otherwise.
    Add your quality business rules here.
    """
    if df.empty:
        return False, "Empty DataFrame"
    
    # Rule 1: Temperature check (reasonable Earth limits)
    if 'current_weather_temperature' in df.columns:
        temp = df['current_weather_temperature'].iloc[0]
        if temp < -60 or temp > 60:
            return False, f"Invalid temperature: {temp}"
    
    # Rule 2: Mandatory fields check
    required_cols = ['latitude', 'longitude', 'current_weather_time']
    for col in required_cols:
        if col not in df.columns or pd.isna(df[col].iloc[0]):
            return False, f"Missing required column: {col}"
            
    return True, "Success"

def lambda_handler(event, context):
    s3_client = boto3.client('s3')
    bucket = event['Records'][0]['s3']['bucket']['name']
    raw_key = event['Records'][0]['s3']['object']['key']
    key = urllib.parse.unquote_plus(raw_key)
    
    try:
        # Load and Flatten
        response = s3_client.get_object(Bucket=bucket, Key=key)
        json_data = json.loads(response['Body'].read().decode('utf-8'))
        df = pd.json_normalize(json_data, sep='_')

        # DATA QUALITY CHECK
        is_valid, message = validate_data(df)
        
        if not is_valid:
            print(f"Data Quality Failed for {key}: {message}")
            # Move to quarantine
            quarantine_key = key.replace('raw/', 'quarantine/')
            s3_client.copy_object(
                Bucket=bucket,
                CopySource={'Bucket': bucket, 'Key': key},
                Key=quarantine_key
            )
            return {'statusCode': 400, 'body': f"Data quarantined: {message}"}

        # If valid, proceed with existing transformation logic
        target_schema = {
            'latitude': 'float64', 'longitude': 'float64',
            'current_weather_temperature': 'float64',
            'current_weather_time': 'string'
            # ... (reszta Twojego schematu)
        }
        
        for col, dtype in target_schema.items():
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce').astype(dtype)

        df['processing_timestamp'] = pd.Timestamp.now()
        output_key = key.replace('raw/', 'transformed/').replace('.json', '.parquet')
        
        wr.s3.to_parquet(df=df, path=f"s3://{bucket}/{output_key}", dataset=False)
        
        return {'statusCode': 200, 'body': "Validated and Transformed"}

    except Exception as e:
        print(f"Error: {str(e)}")
        raise e