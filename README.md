# Request Capture Server

A minimalistic Ruby Rack server that captures incoming HTTP POST requests and stores them in S3-compatible object storage.

## Features

- Single POST endpoint at `/` that captures complete request data
- Stores requests in JSON format with smart binary detection
- Uploads to S3-compatible object storage (Tigris, AWS S3, Cloudflare R2, etc.)
- Returns presigned URL to access captured request
- 1MB request body size limit
- Minimal dependencies and lightweight

## Request Format

Captured requests are stored as JSON with the following structure:

```json
{
  "timestamp": "2025-10-14T10:30:00.123Z",
  "method": "POST",
  "path": "/",
  "query_string": "foo=bar",
  "headers": {
    "Content-Type": "application/json",
    "User-Agent": "curl/7.88.1"
  },
  "source_ip": "203.0.113.1",
  "body": {
    "key": "value"
  },
  "body_base64": null
}
```

**Body Handling**:
- **Binary data**: Stored base64-encoded in `body_base64` field, `body` is `null`
- **Valid JSON**: Parsed and stored as object/array in `body` field
- **Plain text**: Stored as string in `body` field

## Local Development

### Prerequisites

- Ruby 3.4+
- Bundler

### Setup

1. Install dependencies:
```bash
bundle install
```

2. Configure your S3-compatible storage:

Make a local copy of `.env`:

```bash
cp .env .env.local
```

Edit as needed:

```bash
S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=us-east-1
AWS_ENDPOINT_URL=https://s3.amazonaws.com
```

4. Run the server:
```bash
bundle exec puma
```

### Testing Locally

Send a test request:

```bash
# JSON request
curl -X POST http://localhost:8080/ \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "timestamp": 1234567890}'

# Form data
curl -X POST http://localhost:8080/ \
  -d "username=john&password=secret"

# Binary file
curl -X POST http://localhost:8080/ \
  -H "Content-Type: image/png" \
  --data-binary @image.png
```

Expected response:
```json
{
  "status": "captured",
  "file_id": "2025-10-14T10-30-00-123_550e8400.json",
  "url": "https://your-bucket.s3.amazonaws.com/..."
}
```

## Deployment

The application includes a Dockerfile for containerized deployment.

Make the below environment variables / secrets available in your `.env` file / deployment platform as needed.

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `S3_BUCKET` | Name of your S3 bucket | `my-capture-requests` |
| `AWS_ACCESS_KEY_ID` | S3 access key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | S3 secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | S3 region | `us-east-1` |
| `AWS_ENDPOINT_URL` | S3 endpoint URL (optional for AWS S3) | `https://s3.amazonaws.com` |
| `PORT` | Server port (optional) | `8080` |

## File Naming

Files are stored with timestamp-based names:
- Format: `YYYY-MM-DDTHH-MM-SS-mmm_uuid.json`
- Example: `2025-10-14T10-30-00-123_550e8400.json`

## Error Responses

| Status | Error | Description |
|--------|-------|-------------|
| 405 | Method not allowed | Only POST to / is accepted |
| 413 | Payload too large | Request body exceeds 1MB |
| 500 | Failed to capture request | Storage or processing error |
