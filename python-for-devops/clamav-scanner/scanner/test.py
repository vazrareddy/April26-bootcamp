import boto3
# import json
# queue_url = 'https://sqs.ap-south-1.amazonaws.com/879381241087/clamav-automation-queue'
# sqs_client = boto3.client('sqs')
# response = sqs_client.receive_message(
#     QueueUrl=queue_url,
# )

# # print(response.get('Messages')[0].get("MessageId"),
# # type(response.get('Messages')[0].get('Body')),
# # # response.get('Messages')[0].get('Body').get("Records")[0].get("s3").get("object").get("key")
# # )


# message = response.get('Messages')[0]
# message_id = message.get('MessageId')
# message_body = json.loads(message.get('Body'))
# print(message_body.get("Records")[0].get("s3").get("bucket").get("name"),
# message_body.get("Records")[0].get("s3").get("object").get("key"))



# scan file for malware
import subprocess
sns_client = boto3.client('sns')
file_path = 'eicar.txt'
result = subprocess.run(['clamscan', file_path], capture_output=True, text=True)

# print(result.stdout, type(result.stdout))
if result.stdout.splitlines()[6].split()[2] == "0":
    print("CLEAN")
else:
    print("DIRTY")
    response = sns_client.publish(
    TopicArn='arn:aws:sns:ap-south-1:879381241087:alarm-notification',
    Message='Malware found in file_path',
    Subject='ClamAV Scanner'
)
    print(response)


# send sns notification to topic alarm-notification
