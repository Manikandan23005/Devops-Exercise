FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV PORT=5000
ENV AWS_REGION=ap-south-1
ENV SECRET_NAME=payment-service-secret

EXPOSE 5000

CMD ["python", "app.py"]
