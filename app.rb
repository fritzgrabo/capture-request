require 'aws-sdk-s3'
require 'base64'
require 'json'
require 'rack'
require 'securerandom'
require 'time'

class App
  MAX_BODY_SIZE = 1_048_576 # 1MB in bytes

  def initialize
    @s3_client = Aws::S3::Client.new(
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      region: ENV['AWS_REGION'] || 'us-east-1',
      endpoint: ENV['AWS_ENDPOINT_URL']
    )
    @bucket_name = ENV['S3_BUCKET']
  end

  def call(env)
    request = Rack::Request.new(env)

    return build_error_response(405, message: 'Method not allowed. Use POST /') unless valid_route?(request)
    return build_error_response(413, message: 'Payload too large. Maximum 1MB allowed.') unless valid_size?(request)

    handle_capture(request)
  end

  private

  def valid_route?(request)
    request.post? && request.path == '/'
  end

  def valid_size?(request)
    request.content_length.to_i <= MAX_BODY_SIZE
  end

  def handle_capture(request)
    captured_data = capture_request(request)
    file_id = generate_file_id

    upload_to_s3(file_id, captured_data)

    build_success_response(file_id)
  rescue => e
    log_error(e)
    build_error_response(500, message: "Failed to capture request: #{e.message}")
  end

  def build_success_response(file_id)
    response = {
      status: 'captured',
      file_id: file_id,
      url: generate_url(file_id)
    }

    [200, {'content-type' => 'application/json'}, [JSON.generate(response)]]
  end

  def build_error_response(status_code, message:)
    [status_code, {'content-type' => 'application/json'}, [JSON.generate({error: message})]]
  end

  def log_error(error)
    puts "Error capturing request: #{error.message}"
    puts error.backtrace.join("\n")
  end

  def capture_request(request)
    body_content = request.body.read
    is_binary = is_binary?(body_content, request.content_type)

    body = parse_body_content(body_content) unless is_binary || body_content.empty?
    body_base64 = Base64.strict_encode64(body_content) if is_binary

    {
      timestamp: generate_timestamp,
      method: request.request_method,
      path: request.path,
      query_string: request.query_string,
      headers: extract_headers(request.env),
      source_ip: request.ip,
      body: body,
      body_base64: body_base64
    }
  end

  def parse_body_content(content)
    JSON.parse(content)
  rescue JSON::ParserError
    content
  end

  def generate_timestamp
    Time.now.utc.iso8601(3)
  end

  def is_binary?(content, content_type)
    return true if content_type&.match?(%r{image|audio|video|application/octet-stream})
    return false if content.empty?

    test_content = content.force_encoding('UTF-8')
    !test_content.valid_encoding?
  rescue
    true
  end

  def extract_headers(env)
    headers = {}

    env.each do |key, value|
      if key.start_with?('HTTP_')
        header_name = format_http_header(key)
        headers[header_name] = value
      elsif ['CONTENT_TYPE', 'CONTENT_LENGTH'].include?(key)
        header_name = format_standard_header(key)
        headers[header_name] = value
      end
    end

    headers
  end

  def format_http_header(key)
    key.sub(/^HTTP_/, '').then(&method(:format_standard_header))
  end

  def format_standard_header(key)
    key.split('_').map(&:capitalize).join('-')
  end

  def generate_file_id
    timestamp = Time.now.utc.strftime('%Y-%m-%dT%H-%M-%S-%3N')
    uuid = SecureRandom.uuid.split('-').first

    "#{timestamp}_#{uuid}.json"
  end

  def upload_to_s3(file_id, data)
    @s3_client.put_object(
      bucket: @bucket_name,
      key: file_id,
      body: JSON.generate(data),
      content_type: 'application/json'
    )
  end

  def generate_url(file_id)
    signer = Aws::S3::Presigner.new(client: @s3_client)

    signer.presigned_url(
      :get_object,
      bucket: @bucket_name,
      key: file_id,
      expires_in: 604800 # 7 days
    )
  end
end
