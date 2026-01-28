import urllib.parse
import pytest

def test_s3_key_decoding():
    # Simulate what S3 sends in the event
    incoming_key = "raw/city%3DBialystok/year%3D2026/month%3D01/weather_123.json"
    
    # The logic from your lambda_handler
    decoded_key = urllib.parse.unquote_plus(incoming_key)
    
    # Verification
    expected_key = "raw/city=Bialystok/year=2026/month=01/weather_123.json"
    
    assert decoded_key == expected_key
    print(f"\n✅ Decoded correctly: {decoded_key}")


def test_output_path_generation():
    key = "raw/city=Warszawa/year=2026/weather.json"
    
    # The logic from your lambda_handler
    output_key = key.replace('raw/', 'transformed/').replace('.json', '.parquet')
    
    assert "transformed/" in output_key
    assert output_key.endswith(".parquet")
    assert "raw/" not in output_key
    print(f"✅ Path generated correctly: {output_key}")

def test_flattening_logic():
    import pandas as pd
    nested_data = {
        "city": "Lodz",
        "current_weather": {"temp": 15, "wind": 5}
    }
    df = pd.json_normalize(nested_data, sep='_')
    
    assert 'current_weather_temp' in df.columns
    assert df['current_weather_temp'][0] == 15
    print("\n✅ Flattening works: 'current_weather_temp' created.")