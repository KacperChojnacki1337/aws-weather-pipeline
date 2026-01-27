import json
import boto3
import pandas as pd
import awswrangler as wr
import os

def lambda_handler(event, context):
    """
    Silver Layer Transformer:
    Triggered by S3 events when a new JSON arrives in the 'raw/' folder.
    Cleans the data and saves it as an optimized Apache Parquet file.
    """
    
    # 1. Get the bucket name and file key from the S3 event trigger
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    print(f"Processing new file: s3://{bucket}/{key}")

    try:
        # 2. Read the JSON file from S3 directly into a Pandas DataFrame
        # awswrangler handles the S3 connection and parsing automatically
        df_raw = wr.s3.read_json(path=[f"s3://{bucket}/{key}"])
        
        # 3. Data Transformation & Cleaning
        # Flatten the nested JSON structure if necessary and select relevant columns
        # We assume the API response has 'current' and 'location' data
        
        # Adding processing metadata
        df_raw['processing_timestamp'] = pd.Timestamp.now()
        df_raw['source_file'] = key

        # 4. Define the output path for the Silver Layer (Parquet format)
        # We replace 'raw/' with 'transformed/' in the path
        output_key = key.replace('raw/', 'transformed/').replace('.json', '.parquet')
        output_path = f"s3://{bucket}/{output_key}"

        # 5. Write the DataFrame to S3 as a Parquet file
        # Parquet is columnar, compressed, and much faster for analytics
        wr.s3.to_parquet(
            df=df_raw,
            path=output_path,
            dataset=False # We save single files to match the Bronze structure for now
        )

        print(f"Successfully transformed and saved to: {output_path}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f"Transformed {key} to Parquet successfully.")
        }

    except Exception as e:
        print(f"Error processing {key}: {str(e)}")
        raise e