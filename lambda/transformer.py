import json
import boto3
import pandas as pd
import awswrangler as wr
import urllib.parse

def lambda_handler(event, context):
    """
    Silver Layer Transformer:
    1. Decodes S3 keys.
    2. Flattens nested JSON (crucial for Parquet/Athena).
    3. Enforces data types to prevent ArrowTypeError.
    """
    # 1. Extract and Decode the S3 Key
    bucket = event['Records'][0]['s3']['bucket']['name']
    raw_key = event['Records'][0]['s3']['object']['key']
    key = urllib.parse.unquote_plus(raw_key)
    
    print(f"Starting transformation for: s3://{bucket}/{key}")

    try:
        # 2. Load raw JSON content using boto3 
        # (Better control over flattening than direct wr.s3.read_json)
        s3 = boto3.client('s3')
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['body'].read().decode('utf-8')
        json_data = json.loads(content)

        # 3. Flattening: Nested dicts become separate columns
        # current_weather -> current_weather_temperature, etc.
        df = pd.json_normalize(json_data, sep='_')

        # 4. Data Cleaning & Metadata
        df['processing_timestamp'] = pd.Timestamp.now()
        df['source_file'] = key

        # 5. Type Enforcement (The "Parquet Guard")
        # Converts objects to strings and optimizes types to avoid ArrowTypeError
        df = df.convert_dtypes()
        for col in df.columns:
            if df[col].dtype == 'object':
                df[col] = df[col].astype(str)

        # 6. Define Output Path
        output_key = key.replace('raw/', 'transformed/').replace('.json', '.parquet')
        output_path = f"s3://{bucket}/{output_key}"

        # 7. Write to Parquet
        wr.s3.to_parquet(
            df=df,
            path=output_path,
            dataset=False 
        )

        print(f"Success! Flat Parquet saved to: {output_path}")
        
        return {
            'statusCode': 200,
            'body': json.dumps("File transformed and flattened successfully.")
        }

    except Exception as e:
        print(f"Error processing {key}: {str(e)}")
        raise e