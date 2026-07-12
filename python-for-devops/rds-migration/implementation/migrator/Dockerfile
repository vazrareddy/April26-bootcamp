FROM ubuntu:22.04

# Add the official PostgreSQL (PGDG) apt repo so we can install
# postgresql-client-16 instead of Ubuntu 22.04's default v14
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
        gnupg \
        lsb-release && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list

# Update package lists and install necessary dependencies
RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        ruby-dev \
        libpq-dev \
        build-essential \
        postgresql-client-16

# Install pgsync gem
RUN gem install pgsync

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy the Python application code into the container
COPY main.py main.py

# Set the command to run the Python application
CMD ["python3", "main.py"]