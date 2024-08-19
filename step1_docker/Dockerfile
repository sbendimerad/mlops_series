# Use Miniconda as the base image
FROM continuumio/miniconda3

# Set the working directory in the container
WORKDIR /home/app

# Update the package lists
RUN apt-get update

# Upgrade pip to the latest version
RUN pip install --upgrade pip

# Copy the requirements.txt file into the container
COPY requirements.txt /dependencies/requirements.txt

# Install Python dependencies
RUN pip install -r /dependencies/requirements.txt

# Copy the contents of the current directory into the container
COPY . /home/app

# Specify the entry point for the container to run the app.py script
CMD python app.py
