import boto3
import json
import subprocess

sqs_client = boto3.client('sqs')
s3_client = boto3.client('s3')

def get_message_from_queue(queue_url):
    try:
        response = sqs_client.receive_message(
            QueueUrl=queue_url,
        )
        message = response.get('Messages')[0]
        message_id = message.get('MessageId')
        message_body = json.loads(message.get('Body'))
        bucket_name = message_body.get("Records")[0].get("s3").get("bucket").get("name")
        key= message_body.get("Records")[0].get("s3").get("object").get("key")

        return message_id, bucket_name, key
    except Exception as e:
        print(e)
        return None

def download_file_from_s3(bucket_name, key, local_path):
    try:
        s3_client.download_file(bucket_name, key, local_path)
        return True
    except Exception as e:
        print(e)
        return False


def upload_file_to_s3(destination_bucket_name, key, local_path):
    try:
        s3_client.upload_file(local_path, destination_bucket_name, key)
        return True
    except Exception as e:
        print(e)
        return False




def scan_file_for_malware(file_path):
    result = subprocess.run(['clamscan', file_path], capture_output=True, text=True)
    if result.stdout.splitlines()[6].split()[2] == "0":
        return "CLEAN"
    else:
        return "DIRTY"