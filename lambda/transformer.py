import pandas as pd
import awswrangler as wr

def lambda_handler(event, context):
    print("Silver Transformer triggered!")
    return {"status": "ready"}