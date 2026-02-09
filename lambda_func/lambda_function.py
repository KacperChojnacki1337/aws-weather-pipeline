import json
import urllib3
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    http = urllib3.PoolManager()
    s3 = boto3.client('s3')
    bucket_name = os.environ.get('MY_DATA_BUCKET')
    
    cities = [
        {"name": "Bialystok", "lat": 53.1325, "lon": 23.1688},
        {"name": "Bydgoszcz", "lat": 53.1235, "lon": 18.0084},
        {"name": "Gdansk", "lat": 54.3520, "lon": 18.6466},
        {"name": "Gorzow_Wielkopolski", "lat": 52.7368, "lon": 15.2288},
        {"name": "Katowice", "lat": 50.2649, "lon": 19.0238},
        {"name": "Kielce", "lat": 50.8661, "lon": 20.6286},
        {"name": "Krakow", "lat": 50.0647, "lon": 19.9450},
        {"name": "Lublin", "lat": 51.2465, "lon": 22.5684},
        {"name": "Lodz", "lat": 51.7592, "lon": 19.4560},
        {"name": "Olsztyn", "lat": 53.7784, "lon": 20.4801},
        {"name": "Opole", "lat": 50.6668, "lon": 17.9237},
        {"name": "Poznan", "lat": 52.4064, "lon": 16.9252},
        {"name": "Rzeszow", "lat": 50.0413, "lon": 21.9990},
        {"name": "Szczecin", "lat": 53.4285, "lon": 14.5528},
        {"name": "Torun", "lat": 53.0138, "lon": 18.5984},
        {"name": "Warszawa", "lat": 52.2297, "lon": 21.0122},
        {"name": "Wroclaw", "lat": 51.1079, "lon": 17.0385},
        {"name": "Zielona_Gora", "lat": 51.9355, "lon": 15.5062}
    ]
    
    execution_results = []
    current_time = datetime.now()

    for city in cities:
        url = f"https://api.open-meteo.com/v1/forecast?latitude={city['lat']}&longitude={city['lon']}&current_weather=true"
        try:
            # API Request
            response = http.request('GET', url)
            weather_data = json.loads(response.data.decode('utf-8'))
            weather_data['ingested_at'] = current_time.isoformat()
            weather_data['city_name'] = city['name']
            
            # S3 Path Construction
            s3_key = f"raw/city={city['name']}/year={current_time.year}/month={current_time.month:02d}/day={current_time.day:02d}/weather_{current_time.strftime('%H%M%S')}.json"
            
            # Upload to S3
            s3.put_object(Bucket=bucket_name, Key=s3_key, Body=json.dumps(weather_data))
            execution_results.append(f"Success: {city['name']}")
        except Exception as e:
            print(f"Error for {city['name']}: {str(e)}")
            execution_results.append(f"Error: {city['name']}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(execution_results)
    }