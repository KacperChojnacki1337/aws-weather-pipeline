import pytest
from lambda_func.transformer import flatten_weather_data

def test_flatten_weather_data():
    mock_input = {
        "main": {"temp": 280.15, "humidity": 80},
        "name": "Gdansk",
        "dt": 1700000000
    }
    
    result = flatten_weather_data(mock_input)
    
    assert result['city'] == "Gdansk"
    assert result['temp_celsius'] == 7.0 # 280.15K - 273.15
    assert "humidity" in result