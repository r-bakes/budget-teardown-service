import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")


def lambda_handler(event, context):
    message = event["Records"][0]["Sns"]["Message"]
    print("From SNS: " + message)

    response = s3.list_buckets()
    buckets = [bucket_data["Name"] for bucket_data in response["Buckets"]]

    for bucket in buckets:
        try:
            tagging = s3.get_bucket_tagging(Bucket=bucket)
            tag_set = tagging["TagSet"]
            is_public = any(
                tag["Key"] == "access" and tag["Value"] == "public" for tag in tag_set
            )

            if is_public:
                enable_public_access_block(bucket)
                delete_bucket_website(bucket)

        except ClientError as e:
            # Buckets with no tags will cause NoSuchTagSet error
            if e.response["Error"]["Code"] == "NoSuchTagSet":
                print(f"No tags found for bucket: {bucket}")
            else:
                print(f"Error checking tags for {bucket}: {e}")

    return {"statusCode": 200, "body": "Completed public bucket cleanup"}


def enable_public_access_block(bucket: str):
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


def delete_bucket_website(bucket: str):
    try:
        s3.delete_bucket_website(Bucket=bucket)
        print(f"Removed website hosting from: {bucket}")
    except s3.exceptions.NoSuchWebsiteConfiguration:
        print(f"No website hosting found for: {bucket}")
