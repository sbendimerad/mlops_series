import requests

# Define the API endpoint
# Use this first URL if you are testing on local
#url = "http://localhost:8000/predict"

# Copy and paste your azure url after deployment
#url = "your url azure"

# Define the input data
data = {
    "sepal_length": 5.1,
    "sepal_width": 3.5,
    "petal_length": 1.4,
    "petal_width": 0.2
}

# Make a POST request to the API
response = requests.post(url, json=data)

# Check if the request was successful
if response.status_code == 200:
    # Print the prediction result
    prediction = response.json()
    print("Prediction:", prediction)
else:
    print(f"Failed to get a prediction. Status code: {response.status_code}")
    print("Response:", response.text)

