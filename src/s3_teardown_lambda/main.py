import boto3
from botocore.exceptions import ClientError
from mypy_boto3_s3.client import S3Client

s3: S3Client = boto3.client("s3")


def lambda_handler(event, context):
    message = event["Records"][0]["Sns"]["Message"]
    print("From SNS: " + message)

    response = s3.list_buckets()
    buckets = [
        bucket_data["Name"]
        for bucket_data in response["Buckets"]
        if "Name" in bucket_data
    ]

    for bucket in buckets:
        if _is_public(bucket):
            _enable_public_access_block(bucket)
            _delete_bucket_website(bucket)

    return {"statusCode": 200, "body": "Completed public bucket cleanup"}


def _is_public(bucket: str) -> bool:
    try:
        tagging = s3.get_bucket_tagging(Bucket=bucket)
        tag_set = tagging["TagSet"]

        return any(
            tag["Key"] == "access" and tag["Value"] == "public" for tag in tag_set
        )
    except ClientError as e:
        if _is_no_such_tag_error(e):
            print(f"No tags found for bucket: {bucket}")
        else:
            print(f"Error checking tags for {bucket}: {e}")

    return True  # Just in case of error, assume public access


def _enable_public_access_block(bucket: str) -> None:
    s3.put_public_access_block(
        Bucket=bucket,
        PublicAccessBlockConfiguration={
            "BlockPublicAcls": True,
            "IgnorePublicAcls": True,
            "BlockPublicPolicy": True,
            "RestrictPublicBuckets": True,
        },
    )
    print(f"Blocked all public access for: {bucket}")


def _delete_bucket_website(bucket: str) -> None:
    try:
        s3.delete_bucket_website(Bucket=bucket)
        print(f"Removed website hosting from: {bucket}")
    except ClientError as _:
        print(f"No website hosting found for: {bucket}")


def _is_no_such_tag_error(e: ClientError) -> bool:
    if e.response and "Error" in e.response:
        error_code = e.response["Error"].get("Code")
        return error_code == "NoSuchTagSet"
    return False
