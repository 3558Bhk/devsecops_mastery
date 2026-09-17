# This file is zipped by Terraform (data.archive_file) and deployed to Lambda.
# It runs EVERY TIME a file is uploaded to the bucket.


def handler(event, context):  # entry point: Lambda calls this function (name must match `handler` in main.tf)
    key = event["Records"][0]["s3"]["object"]["key"]  # dig the uploaded file's name out of the S3 event JSON
    print(f"Hello! I saw a new file: {key}")  # print = write to CloudWatch Logs (that's how we see output)
    return {"statusCode": 200}  # tell Lambda the invocation succeeded (any return value is fine)
