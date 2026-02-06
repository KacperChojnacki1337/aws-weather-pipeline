import json
import boto3
import pandas as pd
import awswrangler as wr
import urllib.parse
import os

def lambda_handler(event, context):
    """
    Silver Layer Transformer:
    1. Decodes S3 keys.
    2. Flattens nested JSON.
    3. Enforces STRICT data types to prevent HIVE_BAD_DATA (Double vs Long).
    """
    # 1. Extract and Decode the S3 Key
    bucket = event['Records'][0]['s3']['bucket']['name']
    raw_key = event['Records'][0]['s3']['object']['key']
    key = urllib.parse.unquote_plus(raw_key)
    
    print(f"Starting transformation for: s3://{bucket}/{key}")

    try:
        # 2. Load raw JSON content using boto3
        s3 = boto3.client('s3')
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        json_data = json.loads(content)

        # 3. Flattening: Nested dicts become separate columns
        df = pd.json_normalize(json_data, sep='_')

        # 4. ENFORCED SCHEMA (The Fix for Athena/Glue)
        # Defining exact types as seen in your Glue Catalog
        target_schema = {
            'latitude': 'float64',
            'longitude': 'float64',
            'generationtime_ms': 'float64',
            'utc_offset_seconds': 'int64',
            'timezone': 'string',
            'timezone_abbreviation': 'string',
            'elevation': 'float64',
            'current_weather_temperature': 'float64', # CRITICAL FIX
            'current_weather_windspeed': 'float64',
            'current_weather_winddirection': 'float64',
            'current_weather_is_day': 'int64',
            'current_weather_weathercode': 'int64',
            'current_weather_interval': 'int64',
            'current_weather_time': 'string'
        }

        # Apply schema and handle missing columns gracefully
        for col, dtype in target_schema.items():
            if col in df.columns:
                if dtype == 'float64':
                    df[col] = pd.to_numeric(df[col], errors='coerce').astype('float64')
                else:
                    df[col] = df[col].astype(dtype)

        # 5. Add Metadata
        df['processing_timestamp'] = pd.Timestamp.now()
        df['source_file'] = key

        # 6. Define Output Path (Partition-aware replacement)
        output_key = key.replace('raw/', 'transformed/').replace('.json', '.parquet')
        output_path = f"s3://{bucket}/{output_key}"

        # 7. Write to Parquet 
        # We set index=False to keep the schema clean in Athena
        wr.s3.to_parquet(
            df=df,
            path=output_path,
            dataset=False
        )

        print(f"Success! Schema-enforced Parquet saved to: {output_path}")
        
        return {
            'statusCode': 200,
            'body': json.dumps("File transformed with strict schema successfully.")
        }

    except Exception as e:
        print(f"Error processing {key}: {str(e)}")
        raise e