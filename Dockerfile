FROM public.ecr.aws/lambda/python:3.13

# Copy requirements.txt
COPY pyproject.toml ${LAMBDA_TASK_ROOT}

# Install the specified packages
RUN pip install --upgrade pip
RUN pip install .

# Copy function code
COPY src/s3_teardown_lambda/main.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "main.lambda_handler" ]
