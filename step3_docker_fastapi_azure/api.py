import uvicorn
import pandas as pd
from fastapi import FastAPI
from pydantic import BaseModel
from azure.storage.blob import BlobClient
import joblib
import io



# Initialize FastAPI
app = FastAPI()


# Define the request body format for predictions
class PredictionFeatures(BaseModel):
    sepal_length: float
    sepal_width: float
    petal_length: float
    petal_width: float
# Global variable to store the loaded model
model = None

# Download the model from Azure Blob Storage directly into memory
def download_model():
    global model

    # If you want to follow the tutorial but don't have an azure account, just load the model directly from the local file
    # model = joblib.load("path_to_your_local_model/model.pkl")
    blob = BlobClient(account_url="https://mlflowtrackingstorage.blob.core.windows.net/",
                        container_name="mlflowexperiments",
                        blob_name="model/model.pkl",
                        credential="copy and past the storage account key")

    # Download the model as a stream of bytes
    stream = io.BytesIO()
    blob.download_blob().download_to_stream(stream)

    # Move the pointer back to the start of the stream
    stream.seek(0)

    # Load the model directly from the in-memory stream
    model = joblib.load(stream)
    print("Model loaded from Azure Blob Storage successfully!")

# Download the model immediately when the script runs
download_model()


# API Root endpoint
@app.get("/")
async def index():
    return {"message": "Welcome to the Iris classification API. Use `/predict` to classify a flower."}

# Prediction endpoint
@app.post("/predict")
async def predict(features: PredictionFeatures):
    # Create input DataFrame for prediction
    input_data = pd.DataFrame([{
        "sepal length (cm)": features.sepal_length,
        "sepal width (cm)": features.sepal_width,
        "petal length (cm)": features.petal_length,
        "petal width (cm)": features.petal_width
    }])

    # Predict using the loaded model
    prediction = model.predict(input_data)
    
    # Get the class number (0, 1, or 2)
    class_index = int(prediction[0])

    # Get the class name from the class index
    class_names = ['setosa' ,'versicolor' ,'virginica']
    class_name = class_names[class_index]

    return {
        "prediction": class_index,
        "class_name": class_name
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
