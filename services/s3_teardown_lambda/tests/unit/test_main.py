import pytest
import boto3
from moto import mock_aws
from botocore.exceptions import ClientError

with mock_aws():
    from s3_teardown_lambda.main import lambda_handler


@pytest.fixture
def sns_event():
    """
    A minimal SNS event payload, as if triggered by AWS Budgets.
    """
    return {"Records": [{"Sns": {"Message": "Budget threshold exceeded"}}]}


@mock_aws
@pytest.mark.parametrize("region", ["us-east-1"])
def test_public_bucket_cleanup(sns_event, region):
    """
    Test that a bucket tagged with access=public has its public access blocked
    and its website configuration removed.
    """
    # Create the bucket
    s3 = boto3.client("s3", region_name=region)
    bucket_name = "my-public-bucket"
    s3.create_bucket(Bucket=bucket_name)

    # Assign public tags
    s3.put_bucket_tagging(
        Bucket=bucket_name,
        Tagging={
            "TagSet": [
                {"Key": "access", "Value": "public"},
            ]
        },
    )

    # Set up bucket website configuration
    s3.put_bucket_website(
        Bucket=bucket_name,
        WebsiteConfiguration={
            "IndexDocument": {"Suffix": "index.html"},
            "ErrorDocument": {"Key": "error.html"},
        },
    )

    # Invoke the lambda
    response = lambda_handler(sns_event, {})
    assert response["statusCode"] == 200
    assert "Completed public bucket cleanup" in response["body"]

    # Confirm that website configuration was removed
    with pytest.raises(ClientError) as exc:
        s3.get_bucket_website(Bucket=bucket_name)
        assert (
            exc.value.response.get("Error", {}).get("Code")
            == "NoSuchWebsiteConfiguration"
        )

    # Confirm that public access block is in place
    pab = s3.get_public_access_block(Bucket=bucket_name)
    config = pab["PublicAccessBlockConfiguration"]
    assert config.get("BlockPublicAcls") is True
    assert config.get("IgnorePublicAcls") is True
    assert config.get("BlockPublicPolicy") is True
    assert config.get("RestrictPublicBuckets") is True


@mock_aws
@pytest.mark.parametrize("region", ["us-east-1"])
def test_private_bucket_no_action(sns_event, region):
    """
    Test that a bucket with no 'access=public' tag is not modified.
    """
    # Create the bucket
    s3 = boto3.client("s3", region_name=region)
    bucket_name = "my-private-bucket"
    s3.create_bucket(Bucket=bucket_name)

    # Assign non-public tags
    s3.put_bucket_tagging(
        Bucket=bucket_name,
        Tagging={
            "TagSet": [
                {"Key": "environment", "Value": "dev"},
            ]
        },
    )

    # Set up bucket website configuration
    s3.put_bucket_website(
        Bucket=bucket_name,
        WebsiteConfiguration={
            "IndexDocument": {"Suffix": "index.html"},
        },
    )

    # Invoke the lambda
    response = lambda_handler(sns_event, {})
    assert response["statusCode"] == 200
    assert "Completed public bucket cleanup" in response["body"]

    # Confirm that the website configuration is *still* there
    website_config = s3.get_bucket_website(Bucket=bucket_name)
    assert website_config["IndexDocument"]["Suffix"] == "index.html"

    # Confirm no public access block was created
    # We expect this call to fail because the Lambda shouldn't have applied a block.
    with pytest.raises(ClientError) as exc:
        s3.get_public_access_block(Bucket=bucket_name)
    assert (
        exc.value.response.get("Error", {}).get("Code")
        == "NoSuchPublicAccessBlockConfiguration"
    )
